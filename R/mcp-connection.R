#' Own an isolated MCP client connection
#'
#' @description
#' A host-owned connection to one configured server. A separate R worker keeps
#' mcptools' connection registry independent of other connections. mcptools owns
#' transport and authentication; the selected server owns execution.
#'
#' This temporary adapter is qualified for mcptools 1.0.2 and uses its internal
#' request and shutdown functions. Public replacements are tracked upstream in
#' issues 129 and 130. Other versions fail explicitly.
#'
#' @details
#' Construct an Agent first, then bind a connection to it. Tool, resource URI and
#' prompt allowlists are fixed at construction. Discovery never expands them.
#' Register the tools returned by `$tools()` to apply the Agent's normal
#' permissions, hooks and budgets. Direct host methods use the connection's
#' allowlists but do not constitute an Agent run.
#'
#' Calls return promises, with at most one active call per connection. A concurrent
#' call fails with a busy error; unrelated connections and the host event loop remain
#' available. The host must call `$close()` when its conversation ends.
#' `$cancel()` terminates the connection and its process tree, discarding server
#' session state. It does not promise a state-preserving interpreter interrupt.
#' Timeouts also close the connection; old tools cannot reconnect implicitly.
#'
#' Owner identifiers and run context prevent accidental cross-Agent reuse; the
#' host remains responsible for authentication and assigning those identifiers.
#' Connections and executable tools are not portable saved-session state.
#'
#' @export
McpConnection <- R6::R6Class(
  "McpConnection",
  cloneable = FALSE,
  public = list(
    #' @description Connect and discover tools from one exact server entry.
    #' @param config Path to an mcptools JSON configuration.
    #' @param server Exact configured server name.
    #' @param agent Agent whose identity, session and run context own this connection.
    #' @param tools Exact tool names the host allows. Empty by default.
    #' @param resources Exact resource URIs the host allows. Empty by default.
    #' @param prompts Exact prompt names the host allows. Empty by default.
    #' @param timeout Maximum seconds for each request.
    #' @param startup_timeout Maximum seconds for client and server startup.
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
          load_tools = length(tools) > 0L
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

    #' @description Inspect local connection state and fixed host allowances.
    #' @return A list. This is local process state, not a remote health probe.
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
        adapter_version = "mcptools 1.0.2"
      )
    },

    #' @description Inspect one catalogue page without registering or authorizing items.
    #' @param kind One of `"tools"`, `"resources"`, `"resource_templates"`, `"prompts"`.
    #' @param cursor Opaque cursor returned by a previous page, or NULL.
    #' @return A promise for one server result with connection provenance.
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

    #' @description Read one explicitly allowed resource URI.
    #' @param uri Exact allowed resource URI. Returned links are never fetched automatically.
    #' @return A promise for the upstream resource result and connection provenance.
    read_resource = function(uri) {
      private$check_allowed(uri, "resources")
      private$request("resources/read", list(uri = uri), provenance = TRUE)
    },

    #' @description Retrieve one explicitly allowed prompt without changing any Chat.
    #' @param name Exact allowed prompt name.
    #' @param arguments Named list of prompt argument strings.
    #' @return A promise for the upstream prompt result and connection provenance.
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

    #' @description Build allowed tool handles for explicit Agent registration.
    #' @return A named list of ellmer tools, bound to this connection and owner.
    tools = function() {
      private$check_current()
      result <- lapply(private$allowed$tools, function(name) {
        descriptor <- private$descriptors[[name]]
        invoke <- function(arguments) {
          private$check_allowed(name, "tools")
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
          description = descriptor$description,
          arguments = descriptor$arguments,
          convert = descriptor$convert,
          annotations = mcp_ellmer_annotations(descriptor$annotations, name)
        )
        private$decorate(tool, name)
      })
      names(result) <- private$allowed$tools
      result
    },

    #' @description Build resource and prompt tools restricted to the fixed host allowlists.
    #' @param prefix Tool name prefix. Use distinct prefixes when registering
    #'   capability tools from multiple connections. Must contain 1 to 50
    #'   letters, digits, underscores or hyphens.
    #' @return A named list of ellmer tools for explicit Agent registration.
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

    #' @description End the connection and discard its server session state.
    #' @return Invisibly, NULL. Repeated calls are harmless.
    cancel = function() {
      private$terminate("cancelled")
      invisible(NULL)
    },

    #' @description Close transport when idle, then terminate the client process tree.
    #' @return Invisibly, NULL. Closing an active call rejects its promise.
    close = function() {
      if (identical(private$state, "idle") && private$worker$is_alive()) {
        tryCatch(
          {
            private$worker$call(
              mcp_worker_function(mcp_worker_request),
              list(operation = "close", arguments = list())
            )
            deadline <- Sys.time() + min(private$timeout, 2)
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
      attr(tool, "deputy_mcp_connection_id") <- private$id
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
