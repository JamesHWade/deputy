#' MCP server connection
#'
#' @description
#' A connection to one MCP server, owned by one agent. Use it instead of
#' [tools_mcp()] when you need a fixed list of allowed tools, resources and
#' prompts, a request timeout, or control over when the server stops. Each
#' connection runs its own mcptools client in a separate R process. Requires
#' mcptools 1.0.2 or 1.0.3.
#'
#' @details
#' Create the [Agent] first, then the connection. The allowlists are fixed when
#' the connection is created; `$discover()` never adds to them. Register
#' `$tools()` on the agent so that calls go through its permissions, hooks and
#' limits. The other methods call the server directly, outside any agent run.
#'
#' Methods that contact the server return promises. A connection handles one
#' request at a time; a second request made meanwhile errors, but other
#' connections are not blocked. Call `$close()` when the conversation ends.
#' `$cancel()`, and any request that times out, stop the connection and
#' discard the server's session state; its tools then stop working.
#'
#' mcptools waits about 4 seconds for a stdio server's reply and doesn't match
#' replies to requests, so a late or mismatched reply fails the call with a
#' `deputy_mcp_desynchronized` error and closes the connection. Create a new
#' connection to continue.
#'
#' The connection is tied to the agent's ID, session and run context: its tools
#' can't be registered on another agent and stop working if the agent's session
#' changes. Connections are not saved with the agent's session.
#'
#' @export
McpConnection <- R6::R6Class(
  "McpConnection",
  cloneable = FALSE,
  public = list(
    #' @description Start the server and connect to it.
    #' @param config Path to an mcptools JSON configuration.
    #' @param server Name of the server in `config`.
    #' @param agent The agent that owns the connection. The server starts in its
    #'   working directory.
    #' @param tools Names of the server tools to allow. None by default. The
    #'   connection fails if the server doesn't offer all of them.
    #' @param resources Resource URIs to allow. None by default.
    #' @param prompts Prompt names to allow. None by default.
    #' @param timeout Maximum seconds for each request. A request that takes
    #'   longer closes the connection.
    #' @param startup_timeout Maximum seconds for the client and server to
    #'   start.
    initialize = function(
      config,
      server,
      agent,
      tools = character(),
      resources = character(),
      prompts = character(),
      timeout = 60,
      startup_timeout = 60
    ) {
      private$owner <- mcp_connection_owner(agent)
      private$agent <- agent
      private$allowed <- list(
        tools = mcp_connection_allowlist(tools, "tools"),
        resources = mcp_connection_allowlist(resources, "resources"),
        prompts = mcp_connection_allowlist(prompts, "prompts")
      )
      if (
        !is.numeric(timeout) ||
          length(timeout) != 1L ||
          is.na(timeout) ||
          !is.finite(timeout) ||
          timeout <= 0
      ) {
        abort_deputy(
          "{.arg timeout} must be positive and finite.",
          class = "mcp_connection"
        )
      }
      if (
        !is.numeric(startup_timeout) ||
          length(startup_timeout) != 1L ||
          is.na(startup_timeout) ||
          !is.finite(startup_timeout) ||
          startup_timeout <= 0
      ) {
        abort_deputy(
          "{.arg startup_timeout} must be positive and finite.",
          class = "mcp_connection"
        )
      }
      selected <- mcp_connection_config(config, server)
      rlang::check_installed("mcptools", reason = "to create an MCP connection")
      mcp_metadata_state()
      private$server <- server
      private$adapter_version <- paste(
        "mcptools",
        utils::packageVersion("mcptools")
      )
      private$timeout <- timeout
      private$id <- new_deputy_id("mcp_")
      private$worker <- callr::r_session$new(
        options = callr::r_session_options(
          libpath = .libPaths(),
          user_profile = FALSE
        ),
        wait = FALSE
      )
      ok <- FALSE
      on.exit(if (!ok) private$terminate("startup_failed"))
      started <- Sys.time()
      while (!identical(private$worker$get_state(), "idle")) {
        if (
          !private$worker$is_alive() ||
            as.numeric(difftime(Sys.time(), started, units = "secs")) >
              startup_timeout
        ) {
          abort_deputy(
            "MCP client worker did not start in time.",
            class = "mcp_connection"
          )
        }
        if (identical(private$worker$poll_process(20), "ready")) {
          private$worker$read()
        }
      }
      private$worker$call(
        mcp_worker_function(mcp_worker_start),
        list(
          config = selected,
          server = server,
          working_dir = agent$working_dir,
          load_tools = length(tools) > 0L,
          qualified_versions = mcptools_qualified_versions
        )
      )
      startup <- NULL
      while (is.null(startup)) {
        if (
          !private$worker$is_alive() ||
            as.numeric(difftime(Sys.time(), started, units = "secs")) >
              startup_timeout
        ) {
          abort_deputy(
            "MCP server did not initialize in time.",
            class = "mcp_connection"
          )
        }
        if (identical(private$worker$poll_process(20), "ready")) {
          startup <- mcp_worker_read_result(private$worker)
        }
      }
      if (startup$code != 200L) {
        abort_deputy(
          "MCP client worker exited during initialization.",
          class = "mcp_connection"
        )
      }
      if (!is.null(startup$error)) {
        rlang::cnd_signal(startup$error)
      }
      initialized <- startup$result
      if (!is.list(initialized) || !is.list(initialized$tools)) {
        abort_deputy(
          "MCP server initialization failed.",
          class = "mcp_connection"
        )
      }
      private$descriptors <- initialized$tools
      names(private$descriptors) <- vapply(
        private$descriptors,
        `[[`,
        character(1),
        "name"
      )
      if (!all(tools %in% names(private$descriptors))) {
        abort_deputy(
          "The MCP server did not supply every allowed tool.",
          class = "mcp_connection"
        )
      }
      # Validate metadata before making any executable handle available.
      for (descriptor in private$descriptors) {
        mcp_ellmer_annotations(descriptor$annotations, descriptor$name)
      }
      private$state <- "idle"
      ok <- TRUE
      invisible(self)
    },

    #' @description Report the connection's state and allowlists.
    #' @return A list with the connection's ID, server, owner, `state`, the
    #'   `reason` it closed, its allowlists and version details. It doesn't
    #'   contact the server.
    status = function() {
      if (private$state %in% c("idle", "busy") && !private$worker$is_alive()) {
        private$terminate("crashed")
      }
      list(
        connection_id = private$id,
        server = private$server,
        owner = private$owner,
        state = private$state,
        reason = private$reason,
        allowed = private$allowed,
        execution = attr(self, "deputy_mcp_adapter", exact = TRUE)$execution,
        adapter_version = private$adapter_version
      )
    },

    #' @description List one page of what the server offers. Listing an item
    #'   doesn't allow it.
    #' @param kind One of `"tools"`, `"resources"`, `"resource_templates"`, `"prompts"`.
    #' @param cursor Cursor from a previous page, or `NULL` for the first page.
    #' @return A promise for a list with `source` (the server and connection)
    #'   and the server's `result`.
    discover = function(
      kind = c("tools", "resources", "resource_templates", "prompts"),
      cursor = NULL
    ) {
      kind <- match.arg(kind)
      if (!is.null(cursor) && !rlang::is_string(cursor)) {
        abort_deputy(
          "{.arg cursor} must be NULL or one non-missing string.",
          class = "mcp_connection"
        )
      }
      methods <- c(
        tools = "tools/list",
        resources = "resources/list",
        resource_templates = "resources/templates/list",
        prompts = "prompts/list"
      )
      private$request(
        methods[[kind]],
        if (is.null(cursor)) {
          structure(list(), names = character())
        } else {
          list(cursor = cursor)
        },
        provenance = TRUE
      )
    },

    #' @description Read an allowed resource.
    #' @param uri An allowed resource URI. Links in the result are not followed.
    #' @return A promise for a list with `source` and the server's `result`.
    read_resource = function(uri) {
      private$check_allowed(uri, "resources")
      private$request("resources/read", list(uri = uri), provenance = TRUE)
    },

    #' @description Get an allowed prompt. The prompt is not added to any
    #'   conversation.
    #' @param name An allowed prompt name.
    #' @param arguments Named list of strings to fill in the prompt.
    #' @return A promise for a list with `source` and the server's `result`.
    get_prompt = function(name, arguments = list()) {
      private$check_allowed(name, "prompts")
      if (
        !is.list(arguments) ||
          (length(arguments) > 0L &&
            (is.null(names(arguments)) ||
              anyNA(names(arguments)) ||
              anyDuplicated(names(arguments)) ||
              !all(nzchar(names(arguments))) ||
              !all(vapply(arguments, rlang::is_string, logical(1)))))
      ) {
        abort_deputy(
          "Prompt arguments must be a named list of scalar, non-missing strings.",
          class = "mcp_connection"
        )
      }
      private$request(
        "prompts/get",
        list(
          name = name,
          arguments = if (length(arguments)) {
            arguments
          } else {
            structure(list(), names = character())
          }
        ),
        provenance = TRUE
      )
    },

    #' @description Create tools for the allowed server tools, to register on
    #'   the owning agent.
    #' @return A named list of ellmer tools.
    tools = function() {
      private$check_current()
      result <- lapply(private$allowed$tools, function(name) {
        descriptor <- private$descriptors[[name]]
        # A producer adapter (mcp-repl, MCP Console) governs its one tool's
        # arguments and description; other tools pass through unchanged.
        adapter <- attr(self, "deputy_mcp_adapter", exact = TRUE)
        if (!identical(adapter$tool, name)) {
          adapter <- NULL
        }
        invoke <- function(arguments) {
          private$check_allowed(name, "tools")
          if (!is.null(adapter)) {
            arguments <- adapter$arguments(arguments)
          }
          private$request("tool", list(name = name, arguments = arguments))
        }
        fun <- rlang::new_function(
          descriptor$formals,
          rlang::expr((!!invoke)(base::mget(
            base::as.character(base::names(base::as.list(base::match.call())[
              -1L
            ])),
            envir = base::environment(),
            inherits = FALSE
          )))
        )
        tool <- ellmer::tool(
          fun,
          name = name,
          description = if (!is.null(adapter)) {
            adapter$description(descriptor$description)
          } else {
            descriptor$description
          },
          arguments = descriptor$arguments,
          convert = descriptor$convert,
          annotations = mcp_ellmer_annotations(descriptor$annotations, name)
        )
        private$decorate(tool, name)
      })
      names(result) <- private$allowed$tools
      result
    },

    #' @description Create `<prefix>_read_resource` and `<prefix>_get_prompt`
    #'   tools that let the model read allowed resources and get allowed
    #'   prompts. Each is created only if its allowlist isn't empty. Prompts
    #'   that need arguments can't be fetched this way.
    #' @param prefix Prefix for the tool names: 1 to 50 letters, digits,
    #'   underscores or hyphens. Use a different prefix for each connection on
    #'   the same agent.
    #' @return A named list of ellmer tools, possibly empty.
    capability_tools = function(prefix = "mcp") {
      private$check_current()
      if (
        !is_nonempty_string(prefix) || !grepl("^[A-Za-z0-9_-]{1,50}$", prefix)
      ) {
        abort_deputy(
          "{.arg prefix} must contain 1 to 50 letters, digits, underscores or hyphens.",
          class = "mcp_connection"
        )
      }
      result <- list()
      annotations <- list(
        read_only_hint = TRUE,
        destructive_hint = FALSE,
        idempotent_hint = FALSE,
        open_world_hint = TRUE
      )
      if (length(private$allowed$resources)) {
        name <- paste0(prefix, "_read_resource")
        result[[name]] <- private$decorate(
          ellmer::tool(
            function(uri) self$read_resource(uri),
            name = name,
            description = "Read one host-allowed MCP resource. Returned links are not fetched.",
            arguments = list(
              uri = ellmer::type_enum(private$allowed$resources)
            ),
            annotations = annotations
          ),
          "resources/read"
        )
      }
      if (length(private$allowed$prompts)) {
        name <- paste0(prefix, "_get_prompt")
        result[[name]] <- private$decorate(
          ellmer::tool(
            function(name) self$get_prompt(name),
            name = name,
            description = "Retrieve one host-allowed MCP prompt without adding it to the conversation. Prompts requiring arguments must be retrieved by the host.",
            arguments = list(name = ellmer::type_enum(private$allowed$prompts)),
            annotations = annotations
          ),
          "prompts/get"
        )
      }
      result
    },

    #' @description Stop the connection at once and discard the server's
    #'   session state.
    #' @return `NULL`, invisibly. Safe to call more than once.
    cancel = function() {
      private$terminate("cancelled")
      invisible(NULL)
    },

    #' @description Close the connection. If no request is running, the server
    #'   is first asked to shut down; then its processes are stopped.
    #' @return `NULL`, invisibly. A request still running is rejected.
    close = function() {
      if (identical(private$state, "idle") && private$worker$is_alive()) {
        tryCatch(
          {
            grace <- attr(self, "deputy_mcp_adapter", exact = TRUE)$close_grace
            grace <- if (is.null(grace)) 0 else grace
            private$worker$call(
              mcp_worker_function(mcp_worker_request),
              list(operation = "close", arguments = list(grace = grace))
            )
            deadline <- Sys.time() + min(private$timeout, 2) + grace
            response <- NULL
            while (is.null(response) && Sys.time() < deadline) {
              if (identical(private$worker$poll_process(10), "ready")) {
                response <- mcp_worker_read_result(private$worker)
              }
            }
          },
          error = function(e) NULL
        )
      }
      private$terminate("closed")
      invisible(NULL)
    }
  ),
  private = list(
    worker = NULL,
    server = NULL,
    id = NULL,
    owner = NULL,
    agent = NULL,
    allowed = NULL,
    descriptors = NULL,
    timeout = NULL,
    adapter_version = NULL,
    state = "starting",
    reason = NULL,
    pending_reject = NULL,
    finalize = function() private$terminate("finalized"),
    terminate = function(reason) {
      if (identical(private$state, "closed")) {
        return(invisible(NULL))
      }
      private$state <- "closed"
      private$reason <- reason
      if (!is.null(private$worker)) {
        try(private$worker$kill_tree(), silent = TRUE)
      }
      reject <- private$pending_reject
      private$pending_reject <- NULL
      if (!is.null(reject)) {
        reject(rlang::error_cnd(
          c("deputy_mcp_connection", "deputy_error"),
          message = paste("MCP connection ended:", reason)
        ))
      }
      invisible(NULL)
    },
    check_current = function() {
      if (!identical(private$owner, mcp_connection_owner(private$agent))) {
        abort_deputy(
          "The Agent's session or run context changed; create a new MCP connection.",
          class = "mcp_connection"
        )
      }
      status <- self$status()
      if (identical(status$state, "closed")) {
        abort_deputy(
          "The MCP connection is closed ({status$reason}); create a new connection.",
          class = "mcp_connection"
        )
      }
    },
    check_allowed = function(name, kind) {
      private$check_current()
      if (!is_nonempty_string(name) || !name %in% private$allowed[[kind]]) {
        abort_permission_denied(
          "The MCP {kind} item is not in the connection's host allowlist."
        )
      }
    },
    decorate = function(tool, name) {
      attr(tool, "deputy_tool_source") <- list(
        type = "mcp",
        server = private$server,
        tool = tool@name,
        operation = if (identical(name, tool@name)) "tools/call" else name,
        connection_id = private$id
      )
      attr(tool, "deputy_mcp_owner") <- private$owner
      execution <- attr(self, "deputy_mcp_adapter", exact = TRUE)$execution
      if (!is.null(execution)) {
        attr(tool, "deputy_tool_source")$execution <- execution
      }
      attr(tool, "deputy_mcp_connection_id") <- private$id
      attr(tool, "deputy_mcp_cancel_active") <- function() {
        if (identical(self$status()$state, "busy")) {
          self$cancel()
        }
        invisible(NULL)
      }
      attr(tool, "deputy_mcp_connection_current") <- function() {
        !identical(self$status()$state, "closed") &&
          identical(private$owner, mcp_connection_owner(private$agent))
      }
      tool
    },
    request = function(operation, arguments, provenance = FALSE) {
      private$check_current()
      if (!identical(private$state, "idle")) {
        abort_deputy(
          "The MCP connection already has an active request.",
          class = "mcp_busy"
        )
      }
      private$state <- "busy"
      deadline <- Sys.time() + private$timeout
      promises::promise(function(resolve, reject) {
        private$pending_reject <- reject
        tryCatch(
          private$worker$call(
            mcp_worker_function(mcp_worker_request),
            list(operation = operation, arguments = arguments)
          ),
          error = function(e) {
            private$terminate("dispatch_failed")
          }
        )
        poll <- function() {
          if (!identical(private$state, "busy")) {
            return(invisible(NULL))
          }
          if (!private$worker$is_alive()) {
            private$terminate("crashed")
          } else if (Sys.time() >= deadline) {
            private$terminate("timeout")
          } else if (identical(private$worker$poll_process(0), "ready")) {
            tryCatch(
              {
                response <- mcp_worker_read_result(private$worker)
                if (is.null(response)) {
                  later::later(poll, 0.01)
                  return(invisible(NULL))
                }
                if (response$code != 200L) {
                  private$terminate("worker_exited")
                  return(invisible(NULL))
                }
                private$pending_reject <- NULL
                private$state <- "idle"
                if (!is.null(response$error)) {
                  rlang::cnd_signal(response$error)
                }
                value <- response$result
                if (provenance) {
                  value <- list(
                    source = list(
                      type = "mcp",
                      server = private$server,
                      connection_id = private$id,
                      operation = operation
                    ),
                    result = value
                  )
                }
                resolve(value)
              },
              error = function(e) {
                if (identical(private$state, "busy")) {
                  private$pending_reject <- NULL
                  private$terminate("response_failed")
                } else if (mcp_connection_server_exited(e)) {
                  private$terminate("server_exited")
                } else if (mcp_connection_desynchronized(e)) {
                  private$terminate("desynchronized")
                  e <- mcp_desynchronized_error(private$server, e)
                }
                reject(e)
              }
            )
          } else {
            later::later(poll, 0.01)
          }
          invisible(NULL)
        }
        poll()
      })
    }
  )
)
