# Agent class for deputy

clone_compaction_chat <- function(chat) {
  summary_chat <- chat$clone(deep = TRUE)
  if (identical(summary_chat, chat)) {
    cli::cli_abort("Chat cloning returned the original mutable object")
  }
  validate_chat(summary_chat)

  callback_names <- c(
    "callback_on_tool_request",
    "callback_on_tool_result"
  )
  live_private <- chat$.__enclos_env__$private
  summary_private <- summary_chat$.__enclos_env__$private

  for (callback_name in callback_names) {
    live_manager <- live_private[[callback_name]]
    summary_manager <- summary_private[[callback_name]]
    if (is.null(summary_manager) || !is.function(summary_manager$clear)) {
      cli::cli_abort(
        "The summary chat does not expose an isolated {callback_name} manager"
      )
    }
    if (identical(summary_manager, live_manager)) {
      cli::cli_abort(
        "The summary chat shares its {callback_name} manager with the live chat"
      )
    }
  }

  for (callback_name in callback_names) {
    summary_private[[callback_name]]$clear()
  }
  summary_chat$set_turns(list())
  summary_chat$set_system_prompt(NULL)
  summary_chat$set_tools(list())

  summary_chat
}

#' Agent R6 Class
#'
#' @description
#' The main class for creating AI agents that can use tools to accomplish tasks.
#' Agent wraps an ellmer Chat object and adds agentic capabilities including
#' multi-turn execution, permission enforcement, and streaming output.
#'
#' **Security Note:** Core agent fields are read-only from the public API after
#' construction. Internal lifecycle methods may update the underlying state
#' through private storage when required.
#'
#' @section Skill Methods:
#' The following methods manage skills:
#'
#' \describe{
#'   \item{`$load_skill(skill, allow_conflicts = FALSE)`}{Load a [Skill] into
#'     the agent. The `skill` parameter can be a Skill object or path to a
#'     skill directory. If `allow_conflicts` is FALSE (default), an error is
#'     thrown when skill tools conflict with existing tools. Set to TRUE to
#'     allow overwriting. Returns invisible self.}
#'   \item{`$skills()`}{Get a named list of loaded [Skill] objects.}
#' }
#'
#' @section MCP Methods:
#' The following methods manage MCP (Model Context Protocol) server tools:
#'
#' \describe{
#'   \item{`$load_mcp(config = NULL, servers = NULL)`}{Load tools from MCP
#'     servers. The `config` parameter specifies the path to the MCP config
#'     file (defaults to `~/.config/mcptools/config.json`). The `servers`
#'     parameter optionally filters to specific server names. Requires the
#'     mcptools package. Returns invisible self.}
#'   \item{`$mcp_tools()`}{Get names of loaded MCP tools.}
#' }
#'
#' @section File checkpoint methods:
#' When `enable_file_checkpointing = TRUE`, Deputy captures exact preimages for
#' writes made through its native file tools.
#'
#' \describe{
#'   \item{`$checkpoint(name = NULL, metadata = list())`}{Create a manual file
#'     checkpoint and return its checkpoint ID.}
#'   \item{`$list_checkpoints()`}{List available file checkpoints.}
#'   \item{`$rewind_files(checkpoint_id)`}{Restore files to a checkpoint and
#'     invalidate later file history. Conversation history is not changed.}
#' }
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Create an agent with file tools
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-4o"),
#'   tools = tools_file()
#' )
#'
#' # Run a task with streaming output
#' events <- agent$run("List files in the current directory")
#' repeat {
#'   event <- events()
#'   if (coro::is_exhausted(event)) break
#'   if (event$type == "text") cat(event$text)
#' }
#'
#' # Or use the blocking convenience method
#' result <- agent$run_sync("List files")
#' print(result$response)
#' }
Agent <- R6::R6Class(
  "Agent",

  public = list(
    #' @description
    #' Create a new Agent.
    #'
    #' @param chat An ellmer Chat object created by `ellmer::chat()` or
    #'   provider-specific functions like `ellmer::chat_openai()`.
    #' @param tools A list of tools created with `ellmer::tool()`. See
    #'   [tools_file()] and [tools_code()] for built-in tool bundles.
    #' @param system_prompt Optional system prompt. If provided, overrides the
    #'   chat object's existing system prompt.
    #' @param permissions A [Permissions] object controlling what the agent can do.
    #'   Defaults to [permissions_standard()].
    #' @param usage_limits [UsageLimits] applied independently to each run.
    #'   Defaults to 25 model requests. Use `UsageLimits()` for no limits.
    #' @param enable_file_checkpointing Whether to journal exact file preimages
    #'   for Deputy's mutating file tools. A checkpoint is created automatically
    #'   at the beginning of every run.
    #' @param file_checkpoint_max_file_bytes Maximum bytes captured for one
    #'   file preimage. Defaults to 50 MiB.
    #' @param file_checkpoint_max_journal_bytes Maximum aggregate serialized
    #'   bytes for checkpoint records, markers, metadata, and pending captures.
    #'   Defaults to 250 MiB.
    #' @param working_dir Working directory for file operations. Defaults to
    #'   current directory.
    #' @param session_id Optional stable session identifier used for correlation.
    #'   A unique identifier is generated by default.
    #' @param run_context Immutable canonical JSON-compatible product context
    #'   inherited by each run. Credential-like fields and runtime objects are
    #'   rejected.
    #' @param agent_id Optional stable identifier for this Agent instance.
    #'   A unique identifier is generated by default.
    #' @param agent_name Optional human-readable Agent name.
    #' @return A new `Agent` object
    initialize = function(
      chat,
      tools = list(),
      system_prompt = NULL,
      permissions = NULL,
      usage_limits = UsageLimits(max_requests = 25),
      enable_file_checkpointing = FALSE,
      file_checkpoint_max_file_bytes = 50 * 1024^2,
      file_checkpoint_max_journal_bytes = 250 * 1024^2,
      working_dir = getwd(),
      session_id = NULL,
      run_context = list(),
      agent_id = NULL,
      agent_name = NULL
    ) {
      validate_chat(chat)

      agent_id <- validate_deputy_id(
        agent_id %||% new_deputy_id("agent_"),
        argument = "agent_id"
      )
      session_id <- validate_deputy_id(
        session_id %||% new_deputy_id("session_"),
        argument = "session_id"
      )
      if (
        !is.null(agent_name) &&
          (!is.character(agent_name) ||
            length(agent_name) != 1L ||
            is.na(agent_name) ||
            !nzchar(trimws(agent_name)))
      ) {
        cli_abort("{.arg agent_name} must be one non-empty string or NULL")
      }

      if (
        !is.character(working_dir) ||
          length(working_dir) != 1L ||
          is.na(working_dir) ||
          !dir.exists(working_dir)
      ) {
        cli_abort("{.arg working_dir} must be an existing directory")
      }
      working_dir <- normalizePath(working_dir, mustWork = TRUE, winslash = "/")

      private$.chat <- chat
      private$.permissions <- permissions %||% permissions_standard(working_dir)
      private$.usage_limits <- normalize_usage_limits(usage_limits)
      private$.working_dir <- working_dir
      private$.hooks <- HookRegistry$new()
      private$.run_context <- normalize_run_context(run_context)
      private$.agent_id <- agent_id
      private$.agent_name <- agent_name
      private$.session_id <- session_id
      private$.file_checkpoint_config <- list(
        max_file_bytes = file_checkpoint_byte_limit(
          file_checkpoint_max_file_bytes,
          "file_checkpoint_max_file_bytes"
        ),
        max_journal_bytes = file_checkpoint_byte_limit(
          file_checkpoint_max_journal_bytes,
          "file_checkpoint_max_journal_bytes"
        )
      )
      if (
        !is.logical(enable_file_checkpointing) ||
          length(enable_file_checkpointing) != 1L ||
          is.na(enable_file_checkpointing)
      ) {
        cli_abort("{.arg enable_file_checkpointing} must be TRUE or FALSE")
      }
      if (isTRUE(enable_file_checkpointing)) {
        private$.file_checkpoints <- private$new_file_checkpoint_store()
      }

      # Override system prompt if provided
      if (!is.null(system_prompt)) {
        self$chat$set_system_prompt(system_prompt)
      }

      # Register tools
      if (length(tools) > 0) {
        self$chat$register_tools(tools)
      }

      # Wire up ellmer's callbacks for permission/hook enforcement
      self$chat$on_tool_request(private$on_tool_request)
      self$chat$on_tool_result(private$on_tool_result)

      invisible(self)
    },

    #' @description
    #' Run an agentic task with streaming output.
    #'
    #' Returns a generator that yields [AgentEvent] objects as the agent works.
    #' The agent will continue until the task is complete, a run limit is
    #' reached, or it is interrupted.
    #'
    #' @param task The task for the agent to perform
    #' @param usage_limits Optional [UsageLimits] override for this run.
    #' @param include_partial_messages If TRUE (default), yield partial text
    #'   chunks as they stream. If FALSE, only yield `text_complete`.
    #' @param output_format Optional output format spec (e.g. JSON schema) to
    #'   guide and validate structured responses.
    #' @param run_context Canonical JSON-compatible context to add to or narrow
    #'   for this run. Protected constructor identity fields cannot change.
    #' @return A generator yielding [AgentEvent] objects
    run = function(
      task,
      usage_limits = NULL,
      include_partial_messages = TRUE,
      output_format = NULL,
      run_context = list()
    ) {
      if (isTRUE(private$run_active)) {
        cli::cli_abort(
          "This agent already has an active run",
          class = c("deputy_run_active", "deputy_error")
        )
      }

      effective_run_context <- merge_run_context(
        private$.run_context,
        run_context
      )

      limits <- if (is.null(usage_limits)) {
        self$usage_limits
      } else {
        merge_usage_limits(usage_limits, self$usage_limits)
      }
      limits <- normalize_usage_limits(limits)

      # Native file tools resolve relative paths through the process working
      # directory. Wrap each generator step so provider callbacks and tool
      # execution consistently observe this Agent's immutable workspace while
      # leaving the caller's process working directory unchanged between
      # yields.
      run_owner <- new.env(parent = emptyenv())
      run_owner$active_run_id <- NULL
      run_owner$finished <- FALSE
      generator <- private$create_run_generator(
        task,
        limits,
        include_partial_messages = include_partial_messages,
        output_format = output_format,
        run_context = effective_run_context,
        run_owner = run_owner
      )
      private$wrap_generator_working_dir(generator, run_owner)
    },

    #' @description
    #' Run an agentic task and block until completion.
    #'
    #' Convenience wrapper around `run()` that collects all events and returns
    #' an [AgentResult].
    #'
    #' @param task The task for the agent to perform
    #' @param usage_limits Optional [UsageLimits] override for this run.
    #' @param include_partial_messages If TRUE (default), keep partial text
    #'   events. If FALSE, suppress partials.
    #' @param output_format Optional output format spec (e.g. JSON schema) to
    #'   guide and validate structured responses.
    #' @param run_context Canonical JSON-compatible context to add to or narrow
    #'   for this run. Protected constructor identity fields cannot change.
    #' @return An [AgentResult] object
    run_sync = function(
      task,
      usage_limits = NULL,
      include_partial_messages = TRUE,
      output_format = NULL,
      run_context = list()
    ) {
      start_time <- Sys.time()

      # Collect all events from the generator
      gen <- self$run(
        task = task,
        usage_limits = usage_limits,
        include_partial_messages = include_partial_messages,
        output_format = output_format,
        run_context = run_context
      )
      events <- list()

      # Iterate through the generator
      # Note: coro generators return coro::exhausted() when done, not NULL
      repeat {
        event <- tryCatch(
          gen(),
          error = function(e) {
            if (
              grepl("generator has been exhausted", e$message, fixed = TRUE)
            ) {
              return(coro::exhausted())
            }
            stop(e)
          }
        )

        # Check for exhaustion (coro returns special exhausted symbol, not NULL)
        if (coro::is_exhausted(event)) {
          break
        }

        events <- c(events, list(event))

        # Also break on stop event to avoid extra generator call
        if (inherits(event, "AgentEvent") && event$type == "stop") {
          break
        }
      }

      # Find the stop event for metadata
      stop_event <- Find(function(e) e$type == "stop", events)

      duration <- as.numeric(Sys.time() - start_time, units = "secs")

      complete_events <- Filter(
        function(event) identical(event$type, "text_complete"),
        events
      )
      if (length(complete_events) > 0L) {
        run_response <- complete_events[[length(complete_events)]]$text
      } else {
        text_events <- Filter(
          function(event) identical(event$type, "text"),
          events
        )
        run_response <- if (length(text_events) > 0L) {
          paste(
            vapply(text_events, function(event) event$text, character(1)),
            collapse = ""
          )
        } else {
          NULL
        }
      }

      structured_output <- NULL
      if (!is.null(output_format) && !is.null(run_response)) {
        structured_output <- parse_structured_output(
          run_response,
          output_format
        )
      }

      AgentResult$new(
        response = run_response,
        turns = self$chat$get_turns(),
        cost = stop_event$cost %||% self$cost(),
        events = events,
        duration = duration,
        stop_reason = stop_event$reason %||% "complete",
        structured_output = structured_output,
        session_id = private$.session_id,
        run_id = stop_event$run_id %||% private$current_run_id,
        agent_id = stop_event$agent_id %||% self$agent_id,
        agent_name = stop_event$agent_name %||% self$agent_name,
        parent_agent_id = stop_event$parent_agent_id,
        parent_run_id = stop_event$parent_run_id,
        delegation_id = stop_event$delegation_id,
        run_context = stop_event$run_context %||% private$.run_context,
        usage = stop_event$usage %||% private$last_run_usage
      )
    },

    #' @description
    #' Register a tool with the agent.
    #'
    #' @param tool A tool created with `ellmer::tool()`
    #' @return Invisible self for chaining
    register_tool = function(tool) {
      self$chat$register_tool(tool)
      invisible(self)
    },

    #' @description
    #' Register multiple tools with the agent.
    #'
    #' @param tools A list of tools created with `ellmer::tool()`
    #' @return Invisible self for chaining
    register_tools = function(tools) {
      self$chat$register_tools(tools)
      invisible(self)
    },

    #' @description
    #' Add a hook to the agent.
    #'
    #' Hooks are called at specific points during agent execution and can
    #' modify behavior (e.g., deny tool calls, log events).
    #'
    #' @param hook A [HookMatcher] object
    #' @return Invisible self for chaining
    #'
    #' @examples
    #' \dontrun{
    #' # Add a hook to block dangerous bash commands
    #' agent$add_hook(hook_block_dangerous_bash())
    #'
    #' # Add a custom PreToolUse hook
    #' agent$add_hook(HookMatcher$new(
    #'   event = "PreToolUse",
    #'   pattern = "^write_file$",
    #'   callback = function(tool_name, tool_input, context) {
    #'     cli::cli_alert_info("Writing to: {tool_input$path}")
    #'     HookResultPreToolUse(permission = "allow")
    #'   }
    #' ))
    #' }
    add_hook = function(hook) {
      if (!inherits(hook, "HookMatcher")) {
        cli_abort("{.arg hook} must be a HookMatcher object")
      }
      self$hooks$add(hook)
      invisible(self)
    },

    #' @description
    #' Get the conversation history.
    #'
    #' @return A list of Turn objects
    turns = function() {
      self$chat$get_turns()
    },

    #' @description
    #' Get the last turn in the conversation.
    #'
    #' @param role Role to filter by ("assistant", "user", or "system")
    #' @return A Turn object or NULL
    last_turn = function(role = "assistant") {
      self$chat$last_turn(role = role)
    },

    #' @description
    #' Get this agent's session identifier.
    #'
    #' @return Character session identifier
    session_id = function() {
      private$.session_id
    },

    #' @description
    #' Get the active permission mode.
    #'
    #' @return Character permission mode
    get_permission_mode = function() {
      self$permissions$mode
    },

    #' @description
    #' Preserve or narrow the active permission mode for subsequent tool calls.
    #' Reapplying the current mode is a no-op. Widening or incomparable mode
    #' changes require a newly configured `Agent` so custom restrictions remain
    #' an immutable authority ceiling.
    #'
    #' @param mode Permission mode, see [PermissionMode]
    #' @return Invisible self
    set_permission_mode = function(mode) {
      mode <- validate_permission_mode_value(mode)
      existing <- self$permissions
      old_mode <- existing$mode

      if (identical(mode, old_mode)) {
        return(invisible(self))
      }

      if (!mode %in% permission_mode_targets(old_mode)) {
        cli_abort(
          c(
            "Permission mode cannot widen or replace the current policy",
            "x" = paste0(
              "Mode ",
              old_mode,
              " cannot change to ",
              mode,
              "."
            ),
            "i" = paste0(
              "Create a new Agent with explicitly broader Permissions to ",
              "make this change."
            )
          ),
          class = c("deputy_permission_mode_widening", "deputy_error")
        )
      }

      capabilities <- intersect_permission_capabilities(
        permission_capabilities_from(existing),
        permission_mode_capabilities(mode, self$working_dir)
      )

      private$.permissions <- Permissions$new(
        mode = mode,
        file_read = capabilities$file_read,
        file_write = capabilities$file_write,
        bash = capabilities$bash,
        r_code = capabilities$r_code,
        web = capabilities$web,
        install_packages = capabilities$install_packages,
        can_use_tool = existing$can_use_tool,
        tool_allowlist = existing$tool_allowlist,
        tool_denylist = existing$tool_denylist,
        permission_prompt_tool_name = capabilities$permission_prompt_tool_name
      )

      self$hooks$fire(
        "ConfigChange",
        key = "permission_mode",
        old_value = old_mode,
        new_value = mode,
        context = private$hook_context()
      )

      private$notify(
        paste0("Permission mode changed from ", old_mode, " to ", mode, "."),
        level = "info",
        code = "permission_mode_changed",
        previous_mode = old_mode,
        permission_mode = mode
      )

      invisible(self)
    },

    #' @description
    #' Get cost information for the conversation.
    #'
    #' @return A list with input, output, cached, and total token costs
    cost = function() {
      tokens <- self$chat$get_tokens()
      list(
        input = sum(tokens$input, na.rm = TRUE),
        output = sum(tokens$output, na.rm = TRUE),
        cached = sum(tokens$cached_input, na.rm = TRUE),
        total = sum(tokens$cost, na.rm = TRUE)
      )
    },

    #' @description
    #' Get normalized usage for the complete in-memory conversation.
    #'
    #' Per-run usage is available on [AgentResult] and in the final `usage`
    #' event returned by `$run()`.
    #'
    #' @return An [AgentUsage] object
    usage = function() {
      agent_usage_snapshot(self$chat)
    },

    #' @description
    #' Request cancellation of the active stream.
    #'
    #' Cancellation is cooperative and takes effect at the next provider or tool
    #' boundary supported by ellmer.
    #'
    #' @param reason Stable reason stored on the terminal event
    #' @return Invisible logical indicating whether a run was active
    interrupt = function(reason = "interrupted") {
      if (!isTRUE(private$run_active)) {
        return(invisible(FALSE))
      }
      private$should_stop <- TRUE
      private$stop_reason_from_hook <- as.character(reason[[1]])
      controller <- private$current_stream_controller
      if (!is.null(controller)) {
        tryCatch(
          controller$cancel(reason = private$stop_reason_from_hook),
          error = function(e) controller$cancel()
        )
      }
      invisible(TRUE)
    },

    #' @description
    #' Get provider information.
    #'
    #' @return A list with provider name and model
    provider = function() {
      provider <- self$chat$get_provider()
      list(
        name = provider@name,
        model = self$chat$get_model()
      )
    },

    #' @description
    #' Save the current session to an RDS file.
    #'
    #' @param path Path to save the session
    #' @return Invisible path
    #'
    #' @details
    #' The session file contains:
    #' - Conversation turns
    #' - System prompt
    #' - Effective run context
    #' - File checkpoint state, when enabled
    #' - Metadata (timestamp, version, provider info)
    save_session = function(path) {
      session <- private$build_session_payload()

      tryCatch(
        {
          saveRDS(session, path)
          cli_alert_success("Session saved to {.path {path}}")
          invisible(path)
        },
        error = function(e) {
          abort_session_save(
            c(
              "Failed to save session file",
              "x" = e$message
            ),
            path = path,
            parent = e
          )
        }
      )
    },

    #' @description
    #' Load a session from an RDS file.
    #'
    #' @param path Path to the session file
    #' @return Invisible self
    #'
    #' @details
    #' Tools, permissions, hooks, and the working directory are runtime policy
    #' and are never restored from a session file. Saved run context is
    #' validated before conversation state changes and merged with constructor
    #' context; protected identity conflicts fail the load.
    load_session = function(path) {
      if (isTRUE(private$run_active)) {
        cli::cli_abort(
          "Cannot load session state while this agent has an active run",
          class = c("deputy_run_active", "deputy_error")
        )
      }
      # Validate file exists
      if (!file.exists(path)) {
        abort_session_load(
          "Session file not found: {.path {path}}",
          path = path
        )
      }

      # Load with error handling
      session <- tryCatch(
        readRDS(path),
        error = function(e) {
          abort_session_load(
            c(
              "Failed to load session file",
              "x" = e$message
            ),
            path = path,
            parent = e
          )
        }
      )

      private$restore_session_payload(
        session,
        source = path
      )
      cli_alert_success("Session loaded from {.path {path}}")
      invisible(self)
    },

    #' @description
    #' Create a reversible file checkpoint.
    #'
    #' @param name Optional checkpoint label.
    #' @param metadata Optional serializable metadata list.
    #' @return The checkpoint ID.
    checkpoint = function(name = NULL, metadata = list()) {
      store <- private$require_file_checkpoint_store()
      name <- name %||%
        paste0(
          "manual checkpoint ",
          format(Sys.time(), "%Y-%m-%d %H:%M:%S")
        )
      checkpoint_id <- store$checkpoint(name, metadata)
      private$notify(
        paste0("Created file checkpoint ", checkpoint_id, "."),
        level = "info",
        code = "file_checkpoint_created",
        checkpoint_id = checkpoint_id,
        checkpoint_name = name
      )
      checkpoint_id
    },

    #' @description
    #' List reversible file checkpoints.
    #'
    #' @return A data frame ordered from oldest to newest.
    list_checkpoints = function() {
      private$require_file_checkpoint_store()$list_checkpoints()
    },

    #' @description
    #' Rewind files to a checkpoint without changing conversation history.
    #'
    #' @param checkpoint_id ID returned by `$checkpoint()` or present in a
    #'   `file_checkpoint` run event.
    #' @return A list describing the restored checkpoint and change count.
    rewind_files = function(checkpoint_id) {
      if (isTRUE(private$run_active)) {
        cli::cli_abort(
          "Cannot rewind files while this agent has an active run",
          class = c("deputy_run_active", "deputy_error")
        )
      }
      result <- private$require_file_checkpoint_store()$rewind(checkpoint_id)
      private$notify(
        paste0(
          "Rewound ",
          result$restored_changes,
          " file change(s) to ",
          result$checkpoint_id,
          "."
        ),
        level = "info",
        code = "files_rewound",
        checkpoint_id = result$checkpoint_id,
        restored_changes = result$restored_changes
      )
      result
    },

    #' @description
    #' Compact the conversation history to reduce context size.
    #'
    #' This method uses the LLM to generate a meaningful summary of older
    #' conversation turns, then replaces them with the summary appended to
    #' the system prompt. This preserves important context while reducing
    #' token usage.
    #'
    #' @param keep_last Number of recent turns to keep uncompacted (default: 4)
    #' @param summary Optional custom summary to use instead of auto-generating.
    #'   If NULL, the LLM will generate a summary focusing on key decisions,
    #'   findings, files discussed, and task progress.
    #' @return Invisible self
    #'
    #' @details
    #' The compaction process:
    #' 1. Fires the PreCompact hook (can cancel or provide custom summary)
    #' 2. If no custom summary, uses LLM to summarize compacted turns
    #' 3. Appends summary to system prompt under "Previous Conversation Summary"
    #' 4. Keeps only the most recent `keep_last` turns
    #'
    #' If LLM summarization fails (e.g., no API key), falls back to a simple
    #' text-based summary with truncated turn contents.
    compact = function(keep_last = 4, summary = NULL) {
      if (isTRUE(private$run_active)) {
        cli::cli_abort(
          "Cannot compact conversation state while this agent has an active run",
          class = c("deputy_run_active", "deputy_error")
        )
      }
      turns <- self$chat$get_turns()

      if (length(turns) <= keep_last) {
        cli_alert_info(
          "Not enough turns to compact (have {length(turns)}, keep_last = {keep_last})"
        )
        return(invisible(self))
      }

      # Determine which turns to compact
      compact_count <- length(turns) - keep_last
      turns_to_compact <- turns[1:compact_count]
      turns_to_keep <- turns[(compact_count + 1):length(turns)]

      # Fire PreCompact hook
      hook_result <- self$hooks$fire(
        "PreCompact",
        turns_to_compact = turns_to_compact,
        turns_to_keep = turns_to_keep,
        context = private$hook_context(
          total_turns = length(turns),
          compact_count = compact_count
        )
      )

      # Check if hook wants to cancel compaction
      if (!is.null(hook_result) && isFALSE(hook_result$continue)) {
        cli_alert_info("Compaction cancelled by hook")
        return(invisible(self))
      }

      # Generate summary if not provided
      if (is.null(summary)) {
        # Check if hook provided a custom summary
        if (!is.null(hook_result) && !is.null(hook_result$summary)) {
          summary <- hook_result$summary
        } else {
          # Use LLM to generate a meaningful summary
          summary <- private$generate_compaction_summary(turns_to_compact)
        }
      }

      # Add summary to system prompt and keep only recent turns
      current_system <- self$chat$get_system_prompt() %||% ""
      new_system <- paste0(
        current_system,
        "\n\n## Previous Conversation Summary\n",
        summary
      )

      self$chat$set_system_prompt(new_system)
      self$chat$set_turns(turns_to_keep)

      cli_alert_success(
        "Compacted {compact_count} turns, keeping {length(turns_to_keep)}"
      )
      invisible(self)
    },

    #' @description
    #' Print the agent configuration.
    print = function() {
      provider_info <- self$provider()
      tools <- self$chat$get_tools()

      cat("<Agent>\n")
      cat("  agent_id:", self$agent_id, "\n")
      if (!is.null(self$agent_name)) {
        cat("  agent_name:", self$agent_name, "\n")
      }
      cat("  provider:", provider_info$name, "\n")
      cat("  model:", provider_info$model, "\n")
      cat("  tools:", length(tools), "registered\n")
      if (length(tools) > 0) {
        tool_names <- names(tools)
        if (length(tool_names) > 5) {
          tool_names <- c(tool_names[1:5], "...")
        }
        cat("    ", paste(tool_names, collapse = ", "), "\n")
      }
      cat("  working_dir:", self$working_dir, "\n")
      cat("  permissions:\n")
      cat("    mode:", self$permissions$mode, "\n")
      invisible(self)
    },

    #' @description
    #' Load a [Skill] into the agent.
    #'
    #' @param skill A [Skill] object or path to a skill directory.
    #' @param allow_conflicts If FALSE (default), error on tool name conflicts.
    #'   Set TRUE to allow overwriting existing tools.
    #' @return Invisible self for chaining.
    load_skill = function(skill, allow_conflicts = FALSE) {
      if (is.character(skill)) {
        # Load from path
        skill <- skill_load(skill)
      }

      if (!inherits(skill, "Skill")) {
        cli_abort(
          "{.arg skill} must be a Skill object or path to a skill directory"
        )
      }

      # Get current provider for validation
      current_provider <- tryCatch(
        {
          provider_info <- self$provider()
          # provider() returns a list with name and model
          provider_info$name
        },
        error = function(e) {
          # Log unexpected errors (not just "no provider configured")
          if (
            !grepl("no provider|not configured", e$message, ignore.case = TRUE)
          ) {
            cli_warn(c(
              "Could not determine provider for skill validation",
              "x" = e$message,
              "i" = "Provider compatibility check will be skipped"
            ))
          }
          NULL
        }
      )

      # Check requirements with provider
      req_check <- skill$check_requirements(current_provider)

      # Report missing packages
      if (length(req_check$missing) > 0) {
        cli_warn(c(
          "Loading skill with missing packages: {.val {skill$name}}",
          "x" = "Missing: {.val {req_check$missing}}"
        ))
      }

      # Report provider mismatch
      if (isTRUE(req_check$provider_mismatch)) {
        required <- paste(req_check$required_providers, collapse = ", ")
        cli_warn(c(
          "Skill {.val {skill$name}} may not work optimally with current provider",
          "i" = "Current provider: {.val {current_provider}}",
          "i" = "Skill requires: {.val {required}}",
          "!" = "Some features may not work as expected"
        ))
      }

      # Register tools with conflict detection
      if (length(skill$tools) > 0) {
        # Get current tool names to detect conflicts
        current_tools <- self$chat$get_tools()
        current_tool_names <- names(current_tools)

        # Get names of tools being registered
        new_tool_names <- vapply(
          skill$tools,
          function(tool) tool@name,
          character(1)
        )

        # Check for conflicts
        conflicts <- new_tool_names[new_tool_names %in% current_tool_names]
        if (length(conflicts) > 0) {
          if (isTRUE(allow_conflicts)) {
            cli_warn(c(
              "Skill {.val {skill$name}} overwrites existing tool(s)",
              "!" = "Conflicting tools: {.val {conflicts}}",
              "i" = "Previous definitions will be replaced"
            ))
          } else {
            cli_abort(c(
              "Skill {.val {skill$name}} conflicts with existing tool(s)",
              "!" = "Conflicting tools: {.val {conflicts}}",
              "i" = "Use {.code allow_conflicts = TRUE} to overwrite existing tools"
            ))
          }
        }

        self$chat$register_tools(skill$tools)
      }

      # Append prompt to system prompt
      if (!is.null(skill$prompt) && nchar(skill$prompt) > 0) {
        current_prompt <- self$chat$get_system_prompt() %||% ""
        new_prompt <- paste(
          current_prompt,
          "",
          paste0("# Skill: ", skill$name),
          skill$prompt,
          sep = "\n"
        )
        self$chat$set_system_prompt(new_prompt)
      }

      # Store reference to loaded skill
      if (is.null(private$loaded_skills)) {
        private$loaded_skills <- list()
      }
      private$loaded_skills[[skill$name]] <- skill

      cli_alert_success("Loaded skill: {.val {skill$name}}")
      invisible(self)
    },

    #' @description
    #' Get loaded skills.
    #'
    #' @return Named list of loaded [Skill] objects.
    skills = function() {
      if (is.null(private$loaded_skills)) {
        return(list())
      }
      private$loaded_skills
    },

    #' @description
    #' Load tools from MCP (Model Context Protocol) servers.
    #'
    #' Requires the mcptools package. Issues a warning if not installed or if
    #' tool fetching fails.
    #'
    #' @param config Path to MCP configuration file. If NULL (default), uses
    #'   the mcptools default location (`~/.config/mcptools/config.json`).
    #' @param servers Optional character vector of server names to load from.
    #'   If NULL, loads from all configured servers.
    #' @return Invisible self for chaining
    load_mcp = function(config = NULL, servers = NULL) {
      mcp_tools_list <- tools_mcp(config = config, servers = servers)
      loaded_at <- Sys.time()

      if (length(mcp_tools_list) > 0) {
        # Register tools with error handling
        tryCatch(
          {
            self$chat$register_tools(mcp_tools_list)
          },
          error = function(e) {
            cli::cli_abort(c(
              "Failed to register MCP tools",
              "x" = e$message,
              "i" = "Check for tool name conflicts with existing tools"
            ))
          }
        )

        # Track loaded MCP tools with warnings for extraction failures
        tool_names <- vapply(
          seq_along(mcp_tools_list),
          function(i) {
            t <- mcp_tools_list[[i]]
            tryCatch(
              t@name %||% paste0("<unnamed_", i, ">"),
              error = function(e) {
                cli::cli_warn(c(
                  "Could not read name from MCP tool {.val {i}}",
                  "x" = e$message
                ))
                paste0("<unknown_", i, ">")
              }
            )
          },
          character(1)
        )
        private$loaded_mcp_tools <- c(private$loaded_mcp_tools, tool_names)
        private$loaded_mcp_status <- c(
          private$loaded_mcp_status,
          list(list(
            status = "connected",
            config = config,
            servers = servers %||% character(),
            tools = tool_names,
            loaded_at = loaded_at,
            error = NULL
          ))
        )
      } else {
        private$loaded_mcp_status <- c(
          private$loaded_mcp_status,
          list(list(
            status = if (mcp_available()) "empty" else "unavailable",
            config = config,
            servers = servers %||% character(),
            tools = character(),
            loaded_at = loaded_at,
            error = NULL
          ))
        )
      }

      invisible(self)
    },

    #' @description
    #' Get names of loaded MCP tools.
    #'
    #' @return Character vector of MCP tool names
    mcp_tools = function() {
      private$loaded_mcp_tools
    },

    #' @description
    #' Get MCP runtime status records.
    #'
    #' @return Data frame describing MCP load attempts and registered tools
    mcp_status = function() {
      records <- private$loaded_mcp_status
      if (length(records) == 0) {
        return(data.frame(
          status = character(),
          config = character(),
          servers = character(),
          tools = character(),
          loaded_at = as.POSIXct(character()),
          error = character(),
          stringsAsFactors = FALSE
        ))
      }

      do.call(
        rbind,
        lapply(records, function(record) {
          data.frame(
            status = record$status,
            config = record$config %||% NA_character_,
            servers = paste(record$servers, collapse = ","),
            tools = paste(record$tools, collapse = ","),
            loaded_at = as.POSIXct(record$loaded_at, tz = "UTC"),
            error = record$error %||% NA_character_,
            stringsAsFactors = FALSE
          )
        })
      )
    },

    #' @description
    #' Run an agentic task for use in Shiny applications with shinychat.
    #'
    #' Returns an async content stream suitable for passing to
    #' `shinychat::chat_append()`. Unlike `run()` and `run_sync()`, the
    #' multi-turn loop is driven by ellmer's `stream_async()` rather than
    #' deputy's own generator. Deputy's permissions, hooks, and observable
    #' [UsageLimits] are still enforced via callbacks and terminal accounting.
    #' File tools must use absolute paths within `working_dir`; rejected calls
    #' still count toward tool usage.
    #'
    #' @param prompt The user message to send
    #' @param max_tool_calls Maximum number of tool calls before stopping.
    #'   Overrides `usage_limits$max_tool_calls`; otherwise falls back to that
    #'   value or 25. This counts individual tool call requests, not LLM turns
    #'   (one turn can have multiple parallel calls).
    #' @param run_context Canonical JSON-compatible context to add to or narrow
    #'   for this run. Protected constructor identity fields cannot change.
    #' @return An async content stream suitable for
    #'   `shinychat::chat_append()`.
    run_shiny = function(prompt, max_tool_calls = NULL, run_context = list()) {
      rlang::check_installed("promises", reason = "for run_shiny()")

      if (isTRUE(private$run_active)) {
        cli::cli_abort(
          "This agent already has an active run",
          class = c("deputy_run_active", "deputy_error")
        )
      }

      effective_run_context <- merge_run_context(
        private$.run_context,
        run_context
      )

      max_tool_calls <- max_tool_calls %||%
        self$usage_limits$max_tool_calls %||%
        25L
      max_tool_calls <- validate_usage_limit(
        max_tool_calls,
        "max_tool_calls",
        integer = TRUE
      )
      shiny_limits <- self$usage_limits
      shiny_limits$max_tool_calls <- max_tool_calls

      agent <- self
      stream_state <- private$new_callback_run_state()
      wrapped_stream <- private$callback_run_stream(
        prompt,
        limits = shiny_limits,
        run_context = effective_run_context,
        require_absolute_file_paths = TRUE,
        state = stream_state
      )
      reg.finalizer(
        environment(wrapped_stream),
        function(environment) {
          if (
            !isTRUE(stream_state$finished) &&
              !is.null(stream_state$active_run_id)
          ) {
            stream_state$reason <- "abandoned"
            try(
              agent$.__enclos_env__$private$request_stream_stop("abandoned"),
              silent = TRUE
            )
            try(
              agent$.__enclos_env__$private$finish_callback_run(stream_state),
              silent = TRUE
            )
          }
        },
        onexit = TRUE
      )
      wrapped_stream
    },

    #' @description
    #' Run an agentic task asynchronously and resolve to an [AgentResult].
    #'
    #' Like `run_shiny()`, the multi-turn loop is driven by ellmer's
    #' `stream_async()`, so the R process is never blocked while the model or
    #' tools work: other Shiny sessions, `later` callbacks, and promise chains
    #' keep running. Unlike `run_shiny()`, nothing is streamed to a UI. The
    #' returned promise resolves once the run stops and carries the final
    #' response, run-scoped usage, and stop reason. Permissions, hooks, and
    #' [UsageLimits] are enforced as in `run_shiny()` (callbacks plus terminal
    #' accounting). File tools may use relative paths resolved against
    #' `working_dir`, as in `run()`; the absolute-path rule is specific to
    #' `run_shiny()`.
    #'
    #' Use this when an Agent is a *worker* inside a larger async system, for
    #' example a delegated sub-agent executed from the tool of a parent chat
    #' that is itself streaming. `output_format` is not supported here;
    #' structured output still requires `run()` or `run_sync()`.
    #'
    #' @param task The task for the agent to perform
    #' @param usage_limits Optional [UsageLimits] override for this run. Unset
    #'   fields fall back to the Agent's limits. With `on_exceed = "error"`,
    #'   hitting a limit rejects the promise with the structured limit error
    #'   instead of resolving with a typed `stop_reason`.
    #' @param run_context Canonical JSON-compatible context to add to or narrow
    #'   for this run. Protected constructor identity fields cannot change.
    #' @return A `promises::promise` resolving to an [AgentResult]. It is
    #'   rejected if the provider stream fails or a limit configured with
    #'   `on_exceed = "error"` is reached.
    run_async = function(task, usage_limits = NULL, run_context = list()) {
      rlang::check_installed("promises", reason = "for run_async()")

      if (isTRUE(private$run_active)) {
        cli::cli_abort(
          "This agent already has an active run",
          class = c("deputy_run_active", "deputy_error")
        )
      }

      effective_run_context <- merge_run_context(
        private$.run_context,
        run_context
      )

      limits <- if (is.null(usage_limits)) {
        self$usage_limits
      } else {
        merge_usage_limits(usage_limits, self$usage_limits)
      }
      limits <- normalize_usage_limits(limits)

      agent <- self
      start_time <- Sys.time()
      stream_state <- private$new_callback_run_state()
      stream <- private$callback_run_stream(
        task,
        limits = limits,
        run_context = effective_run_context,
        require_absolute_file_paths = FALSE,
        state = stream_state
      )

      coro::async(function() {
        # Text emitted before a tool call is working narration, not the
        # answer. Reset on every tool result so `response` is the text of the
        # final assistant turn, matching `run_sync()`'s `text_complete`.
        response_parts <- character()
        repeat {
          chunk <- coro::await(stream())
          if (coro::is_exhausted(chunk)) {
            break
          }
          if (inherits(chunk, "ellmer::ContentToolResult")) {
            response_parts <- character()
          } else if (inherits(chunk, "ellmer::ContentText")) {
            response_parts <- c(response_parts, chunk@text)
          } else if (is.character(chunk)) {
            response_parts <- c(response_parts, chunk)
          }
        }

        # The stream's exit handler has finalized the run by now: hooks have
        # fired, run-scoped state is cleared, and `stream_state` carries the
        # terminal reason, usage, and cost. (Assembled outside the async body
        # because coro's state-machine parser rejects `x <- if (...)`.)
        agent$.__enclos_env__$private$callback_run_result(
          response_parts,
          limits = limits,
          state = stream_state,
          run_context = effective_run_context,
          start_time = start_time
        )
      })()
    }
  ),
  active = list(
    #' @field agent_id Stable Agent instance identifier. Read-only.
    agent_id = function(value) {
      if (missing(value)) {
        return(private$.agent_id)
      }
      cli_abort("Cannot modify agent: agent_id is immutable after construction")
    },

    #' @field agent_name Optional human-readable Agent name. Read-only.
    agent_name = function(value) {
      if (missing(value)) {
        return(private$.agent_name)
      }
      cli_abort(
        "Cannot modify agent: agent_name is immutable after construction"
      )
    },

    #' @field run_context Default canonical product context. Read-only.
    run_context = function(value) {
      if (missing(value)) {
        return(clone_run_context(private$.run_context))
      }
      cli_abort(
        "Cannot modify agent: run_context is immutable after construction"
      )
    },

    #' @field chat The wrapped ellmer Chat object. Read-only after construction.
    chat = function(value) {
      if (missing(value)) {
        return(private$.chat)
      }
      cli_abort("Cannot modify agent: chat is immutable after construction")
    },

    #' @field permissions Permission policy for the agent. Read-only after construction.
    permissions = function(value) {
      if (missing(value)) {
        return(private$.permissions)
      }
      cli_abort(
        "Cannot modify agent: permissions are immutable after construction"
      )
    },

    #' @field usage_limits Default per-run [UsageLimits]. Read-only after construction.
    usage_limits = function(value) {
      if (missing(value)) {
        return(private$.usage_limits)
      }
      cli_abort(
        "Cannot modify agent: usage_limits are immutable after construction"
      )
    },

    #' @field working_dir Working directory for file operations. Read-only after construction.
    working_dir = function(value) {
      if (missing(value)) {
        return(private$.working_dir)
      }
      cli_abort(
        "Cannot modify agent: working_dir is immutable after construction"
      )
    },

    #' @field hooks Hook registry for lifecycle events. Read-only after construction.
    hooks = function(value) {
      if (missing(value)) {
        return(private$.hooks)
      }
      cli_abort("Cannot modify agent: hooks are immutable after construction")
    }
  ),

  private = list(
    .chat = NULL,
    .permissions = NULL,
    .usage_limits = NULL,
    .working_dir = NULL,
    .hooks = NULL,
    .run_context = list(),
    .agent_id = NULL,
    .agent_name = NULL,
    .session_id = NULL,
    .parent_agent_id = NULL,
    .parent_run_id = NULL,
    .delegation_id = NULL,
    .file_checkpoints = NULL,
    .file_checkpoint_config = NULL,

    # Flag to signal stopping from hooks
    should_stop = FALSE,
    stop_reason_from_hook = NULL,

    # Run-scoped tracing and usage state.
    run_active = FALSE,
    current_run_id = NULL,
    current_run_context = NULL,
    last_run_context = NULL,
    current_usage_limits = NULL,
    current_usage_baseline = NULL,
    current_tool_calls = 0L,
    current_tool_results = 0L,
    current_outer_requests = 0L,
    current_external_usage = NULL,
    current_stream_controller = NULL,
    current_stream_content = FALSE,
    pending_events = list(),
    tool_started_at = list(),
    tool_event_overrides = list(),
    tool_call_records = list(),
    pending_delegations = list(),
    last_run_usage = NULL,
    last_limit_status = NULL,
    current_run_checkpoint_id = NULL,
    current_run_requires_absolute_file_paths = FALSE,

    new_file_checkpoint_store = function() {
      FileCheckpointStore$new(
        private$.working_dir,
        max_file_bytes = private$.file_checkpoint_config$max_file_bytes,
        max_journal_bytes = private$.file_checkpoint_config$max_journal_bytes
      )
    },

    wrap_generator_working_dir = function(generator, run_owner) {
      workspace <- private$.working_dir
      agent <- self
      wrapped <- function() {
        previous <- getwd()
        on.exit(setwd(previous), add = TRUE)
        setwd(workspace)
        generator()
      }
      class(wrapped) <- class(generator)
      reg.finalizer(
        environment(wrapped),
        function(environment) {
          active_run_id <- run_owner$active_run_id
          if (
            !isTRUE(run_owner$finished) &&
              !is.null(active_run_id) &&
              isTRUE(agent$.__enclos_env__$private$run_active) &&
              identical(
                agent$.__enclos_env__$private$current_run_id,
                active_run_id
              )
          ) {
            run_owner$finished <- TRUE
            try(
              agent$.__enclos_env__$private$request_stream_stop("abandoned"),
              silent = TRUE
            )
            try(
              agent$.__enclos_env__$private$finalize_pending_checkpoints(),
              silent = TRUE
            )
            try(
              agent$.__enclos_env__$private$finish_active_run(),
              silent = TRUE
            )
          }
        },
        onexit = TRUE
      )
      wrapped
    },

    start_async_stream = function(prompt) {
      stream_fun <- self$chat$stream_async
      stream_formals <- names(formals(stream_fun))
      args <- list(prompt)
      if ("stream" %in% stream_formals) {
        args$stream <- "content"
      }
      if (
        !is.null(private$current_stream_controller) &&
          "controller" %in% stream_formals
      ) {
        args$controller <- private$current_stream_controller
      }
      do.call(stream_fun, args)
    },

    file_tool_path_info = function(tool_name, tool_input) {
      if (is.null(tool_name) || length(tool_name) == 0L) {
        return(NULL)
      }
      tool_id <- normalize_native_tool_id(tool_name[[1L]])
      native_file_tools <- c(
        "read_file",
        "read_markdown",
        "read_csv",
        "write_file",
        "edit_file",
        "multi_edit",
        "list_files",
        "glob_files",
        "grep_files"
      )
      if (!tool_id %in% native_file_tools) {
        return(NULL)
      }

      default_path <- switch(
        tool_id,
        list_files = ".",
        glob_files = ".",
        grep_files = ".",
        NULL
      )
      tool_input <- tool_input %||% list()
      list(
        tool_id = tool_id,
        path = tool_input$path %||% default_path
      )
    },

    request_stream_stop = function(reason) {
      private$should_stop <- TRUE
      private$stop_reason_from_hook <- reason
      controller <- private$current_stream_controller
      if (!is.null(controller)) {
        tryCatch(
          controller$cancel(reason = reason),
          error = function(e) controller$cancel()
        )
      }
      invisible(reason)
    },

    finalize_pending_checkpoints = function() {
      if (is.null(private$.file_checkpoints)) {
        return(invisible(0L))
      }
      private$.file_checkpoints$finalize_pending()
    },

    # Shared state for one callback-driven run (`run_shiny()`/`run_async()`).
    # The stream body and its exit handler communicate through this env so a
    # consumer can read the terminal reason, usage, and cost after the stream
    # is exhausted and run-scoped private fields have been cleared.
    new_callback_run_state = function() {
      state <- new.env(parent = emptyenv())
      state$reason <- "complete"
      state$active_run_id <- NULL
      state$session_started <- FALSE
      state$finished <- FALSE
      state$usage <- NULL
      state$cost <- NULL
      state
    },

    # Assemble the `AgentResult` for a finished `run_async()` run. Honors
    # `on_exceed = "error"` by signalling the structured limit error when the
    # run stopped because of the recorded limit.
    callback_run_result = function(
      response_parts,
      limits,
      state,
      run_context,
      start_time
    ) {
      response <- if (length(response_parts) > 0L) {
        paste(response_parts, collapse = "")
      } else {
        tryCatch(private$get_last_response(), error = function(e) NULL)
      }

      limit_status <- private$last_limit_status
      if (
        !is.null(limit_status) &&
          identical(limits$on_exceed, "error") &&
          identical(state$reason, limit_status$reason)
      ) {
        private$abort_usage_limit(limit_status)
      }

      AgentResult$new(
        response = response,
        turns = self$chat$get_turns(),
        cost = state$cost %||% self$cost(),
        events = list(),
        duration = as.numeric(Sys.time() - start_time, units = "secs"),
        stop_reason = state$reason %||% "complete",
        structured_output = NULL,
        session_id = private$.session_id,
        run_id = state$active_run_id,
        agent_id = self$agent_id,
        agent_name = self$agent_name,
        parent_agent_id = private$.parent_agent_id,
        parent_run_id = private$.parent_run_id,
        delegation_id = private$.delegation_id,
        run_context = run_context,
        usage = state$usage %||% AgentUsage()
      )
    },

    # The engine behind `run_shiny()` and `run_async()`: a lazily-started
    # async generator that drives ellmer's `stream_async()` while deputy's
    # permissions, hooks, and usage limits are enforced through the
    # `on_tool_request`/`on_tool_result` callbacks. Yields whatever the
    # provider stream yields (content objects in content mode).
    callback_run_stream = function(
      prompt,
      limits,
      run_context,
      require_absolute_file_paths,
      state
    ) {
      agent <- self
      stream_state <- state
      effective_run_context <- run_context
      run_limits <- limits

      coro::async_generator(function() {
        if (isTRUE(agent$.__enclos_env__$private$run_active)) {
          cli::cli_abort(
            "This agent already has an active run",
            class = c("deputy_run_active", "deputy_error")
          )
        }

        agent$.__enclos_env__$private$run_active <- TRUE
        agent$.__enclos_env__$private$current_run_id <-
          agent$.__enclos_env__$private$new_run_id()
        agent$.__enclos_env__$private$current_run_context <-
          effective_run_context
        active_run_id <- agent$.__enclos_env__$private$current_run_id
        stream_state$active_run_id <- active_run_id
        on.exit(
          agent$.__enclos_env__$private$finish_callback_run(stream_state),
          add = TRUE
        )

        # Initialize lazily on first consumption. Merely constructing and
        # abandoning a stream must not reserve this Agent forever.
        agent$.__enclos_env__$private$tool_call_count <- 0L
        agent$.__enclos_env__$private$tool_call_limit <-
          run_limits$max_tool_calls
        agent$.__enclos_env__$private$should_stop <- FALSE
        agent$.__enclos_env__$private$stop_reason_from_hook <- NULL
        agent$.__enclos_env__$private$current_usage_limits <- run_limits
        agent$.__enclos_env__$private$current_usage_baseline <-
          agent_usage_snapshot(agent$chat)
        agent$.__enclos_env__$private$current_tool_calls <- 0L
        agent$.__enclos_env__$private$current_tool_results <- 0L
        agent$.__enclos_env__$private$current_outer_requests <- 0L
        agent$.__enclos_env__$private$current_external_usage <- AgentUsage()
        agent$.__enclos_env__$private$current_stream_controller <- tryCatch(
          ellmer::stream_controller(),
          error = function(e) NULL
        )
        agent$.__enclos_env__$private$current_stream_content <- TRUE
        agent$.__enclos_env__$private$pending_events <- list()
        agent$.__enclos_env__$private$tool_started_at <- list()
        agent$.__enclos_env__$private$tool_event_overrides <- list()
        agent$.__enclos_env__$private$tool_call_records <- list()
        agent$.__enclos_env__$private$pending_delegations <- list()
        agent$.__enclos_env__$private$last_limit_status <- NULL
        agent$.__enclos_env__$private$last_run_usage <- AgentUsage()
        agent$.__enclos_env__$private$current_run_checkpoint_id <- NULL
        agent$.__enclos_env__$private$current_run_requires_absolute_file_paths <-
          isTRUE(require_absolute_file_paths)

        if (!is.null(agent$.__enclos_env__$private$.file_checkpoints)) {
          checkpoint_id <- agent$.__enclos_env__$private$.file_checkpoints$checkpoint(
            paste0("run ", active_run_id),
            metadata = list(run_id = active_run_id, task = prompt)
          )
          agent$.__enclos_env__$private$current_run_checkpoint_id <-
            checkpoint_id
        }

        agent$hooks$fire(
          "SessionStart",
          context = agent$.__enclos_env__$private$hook_context(
            permissions = agent$permissions,
            provider = agent$provider(),
            tools_count = length(agent$chat$get_tools()),
            run_id = active_run_id
          )
        )
        stream_state$session_started <- TRUE
        agent$hooks$fire(
          "UserPromptSubmit",
          prompt = prompt,
          context = agent$.__enclos_env__$private$hook_context(
            run_id = active_run_id
          )
        )

        initial_limit_status <- usage_limit_status(
          agent$.__enclos_env__$private$current_run_usage(),
          agent$.__enclos_env__$private$current_usage_limits,
          require_followup = TRUE
        )
        if (!is.null(initial_limit_status)) {
          agent$.__enclos_env__$private$mark_usage_limit(initial_limit_status)
          stream_state$reason <- initial_limit_status$reason
        }

        if (agent$.__enclos_env__$private$should_stop) {
          stream <- coro::async_generator(function() {
            if (FALSE) coro::yield("unreachable")
          })()
        } else {
          stream <- tryCatch(
            agent$.__enclos_env__$private$start_async_stream(prompt),
            error = function(error) {
              stream_state$reason <- "error"
              stop(error)
            }
          )
        }
        is_generator <- inherits(stream, "coro_generator_instance")

        repeat {
          if (agent$.__enclos_env__$private$should_stop) {
            stream_state$reason <-
              agent$.__enclos_env__$private$stop_reason_from_hook %||%
              "interrupted"
            break
          }

          stream_error <- NULL
          chunk <- NULL
          if (isTRUE(is_generator)) {
            chunk <- tryCatch(
              stream(),
              error = function(error) {
                stream_error <<- error
                NULL
              }
            )
          } else {
            chunk <- stream
          }

          if (is.null(stream_error) && promises::is.promising(chunk)) {
            chunk <- tryCatch(
              coro::await(chunk),
              error = function(error) {
                stream_error <<- error
                NULL
              }
            )
          }

          if (!is.null(stream_error)) {
            if (agent$.__enclos_env__$private$should_stop) {
              stream_state$reason <-
                agent$.__enclos_env__$private$stop_reason_from_hook %||%
                "interrupted"
              break
            }
            stream_state$reason <- "error"
            stop(stream_error)
          }

          if (agent$.__enclos_env__$private$should_stop) {
            stream_state$reason <-
              agent$.__enclos_env__$private$stop_reason_from_hook %||%
              "interrupted"
            break
          }

          if (coro::is_exhausted(chunk)) {
            break
          }

          coro::yield(chunk)
          if (!isTRUE(is_generator)) {
            break
          }
        }
      })()
    },

    # Terminal accounting for a callback-driven run (`run_shiny()` /
    # `run_async()`): settles the stop reason, fires Stop/SessionEnd, records
    # run-scoped usage and cost on `state`, and releases the active run.
    finish_callback_run = function(state) {
      active_run_id <- state$active_run_id
      if (
        isTRUE(state$finished) ||
          is.null(active_run_id) ||
          !identical(private$current_run_id, active_run_id)
      ) {
        return(invisible(NULL))
      }
      state$finished <- TRUE

      cleanup_error <- NULL
      tryCatch(
        {
          incomplete_tool_call <-
            private$current_tool_calls > private$current_tool_results
          private$finalize_pending_checkpoints()
          usage <- private$current_run_usage()
          state$usage <- usage
          state$cost <- tryCatch(self$cost(), error = function(e) NULL)
          private$last_run_usage <- usage
          limits <- private$current_usage_limits
          if (
            identical(state$reason, "complete") &&
              isTRUE(incomplete_tool_call)
          ) {
            state$reason <- "provider_error"
            private$notify(
              "Provider stream ended before a tool result arrived.",
              level = "warning",
              code = "provider_error",
              usage = usage
            )
          }
          if (identical(state$reason, "complete") && !is.null(limits)) {
            limit_status <- usage_limit_status(usage, limits)
            if (!is.null(limit_status)) {
              private$last_limit_status <- limit_status
              state$reason <- limit_status$reason
              private$notify(
                usage_limit_message(limit_status),
                level = "warning",
                code = limit_status$reason,
                usage = usage,
                limit = limit_status$limit
              )
            }
          }
          if (isTRUE(state$session_started)) {
            self$hooks$fire(
              "Stop",
              reason = state$reason,
              context = private$hook_context(
                cost = self$cost(),
                usage = usage,
                run_id = active_run_id
              )
            )
            self$hooks$fire(
              "SessionEnd",
              reason = state$reason,
              context = private$hook_context(
                cost = self$cost(),
                usage = usage,
                run_id = active_run_id
              )
            )
          }
        },
        error = function(error) {
          cleanup_error <<- error
        }
      )

      private$tool_call_limit <- NULL
      private$tool_call_count <- 0L
      private$should_stop <- FALSE
      private$stop_reason_from_hook <- NULL
      tryCatch(
        private$finish_active_run(),
        error = function(error) {
          if (is.null(cleanup_error)) {
            cleanup_error <<- error
          }
        }
      )
      if (!is.null(cleanup_error)) {
        stop(cleanup_error)
      }
      invisible(NULL)
    },

    finish_active_run = function() {
      checkpoint_error <- NULL
      tryCatch(
        private$finalize_pending_checkpoints(),
        error = function(error) {
          checkpoint_error <<- error
        }
      )
      private$current_stream_controller <- NULL
      private$current_stream_content <- FALSE
      private$current_usage_limits <- NULL
      private$current_usage_baseline <- NULL
      private$current_tool_calls <- 0L
      private$current_tool_results <- 0L
      private$current_outer_requests <- 0L
      private$current_external_usage <- NULL
      private$pending_events <- list()
      private$tool_started_at <- list()
      private$tool_event_overrides <- list()
      private$tool_call_records <- list()
      private$pending_delegations <- list()
      if (!is.null(private$current_run_context)) {
        private$last_run_context <- clone_run_context(
          private$current_run_context
        )
      }
      private$current_run_context <- NULL
      private$current_run_requires_absolute_file_paths <- FALSE
      private$run_active <- FALSE
      if (!is.null(checkpoint_error)) {
        stop(checkpoint_error)
      }
      invisible(NULL)
    },

    # Track hashes of hook-supplied additional_context chunks already appended
    # to the system prompt so repeated hook returns don't grow it unboundedly.
    appended_hook_context_hashes = character(),

    build_session_payload = function() {
      list(
        schema_version = 1L,
        turns = self$chat$get_turns(),
        system_prompt = self$chat$get_system_prompt(),
        run_context = private$snapshot_run_context(),
        appended_hook_context_hashes = private$appended_hook_context_hashes,
        file_checkpoint_state = if (is.null(private$.file_checkpoints)) {
          NULL
        } else {
          private$.file_checkpoints$export_state()
        },
        metadata = list(
          saved_at = Sys.time(),
          deputy_version = as.character(utils::packageVersion("deputy")),
          provider = self$provider(),
          session_id = private$.session_id,
          agent_id = private$.agent_id,
          agent_name = private$.agent_name
        )
      )
    },

    restore_session_payload = function(session, source = NULL) {
      if (!is.list(session)) {
        abort_session_load(
          "Invalid session file - expected a named list",
          path = source
        )
      }

      required_fields <- c(
        "schema_version",
        "turns",
        "system_prompt",
        "run_context",
        "appended_hook_context_hashes",
        "file_checkpoint_state",
        "metadata"
      )
      missing <- setdiff(required_fields, names(session))
      if (length(missing) > 0) {
        abort_session_load(
          c(
            "Invalid session file - missing required fields",
            "x" = "Missing: {.val {missing}}"
          ),
          path = source
        )
      }

      if (!identical(session$schema_version, 1L)) {
        abort_session_load(
          "Unsupported session schema - expected version 1",
          path = source
        )
      }

      metadata <- session$metadata
      if (!is.list(metadata)) {
        abort_session_load(
          "Invalid session file - metadata must be a list",
          path = source
        )
      }
      if (!is.list(session$turns)) {
        abort_session_load(
          "Invalid session file - turns must be a list",
          path = source
        )
      }
      if (
        !is.null(session$system_prompt) &&
          (!is.character(session$system_prompt) ||
            length(session$system_prompt) != 1L ||
            is.na(session$system_prompt))
      ) {
        abort_session_load(
          "Invalid session file - system_prompt must be one string or NULL",
          path = source
        )
      }

      restored_run_context <- tryCatch(
        {
          saved_context <- normalize_run_context(
            session$run_context,
            argument = "session$run_context"
          )
          merge_run_context(private$.run_context, saved_context)
        },
        deputy_run_context_error = function(error) {
          abort_session_load(
            c(
              "Invalid session file - run_context is unsafe",
              "x" = error$message
            ),
            path = source,
            parent = error
          )
        }
      )

      restored_hashes <- tryCatch(
        {
          as.character(session$appended_hook_context_hashes)
        },
        error = function(error) {
          abort_session_load(
            c(
              "Invalid session file - hook context hashes are malformed",
              "x" = error$message
            ),
            path = source,
            parent = error
          )
        }
      )
      # Validate recoverable filesystem state before mutating any conversation
      # state so a rejected cross-root or oversized journal leaves the receiver
      # unchanged.
      restored_checkpoints <- NULL
      if (!is.null(private$.file_checkpoints)) {
        restored_checkpoints <- private$new_file_checkpoint_store()
        if (!is.null(session$file_checkpoint_state)) {
          restored_checkpoints$restore_state(session$file_checkpoint_state)
        }
      }

      previous_turns <- self$chat$get_turns()
      previous_prompt <- self$chat$get_system_prompt()
      tryCatch(
        {
          self$chat$set_turns(session$turns)
          self$chat$set_system_prompt(session$system_prompt)
        },
        error = function(error) {
          try(self$chat$set_turns(previous_turns), silent = TRUE)
          try(self$chat$set_system_prompt(previous_prompt), silent = TRUE)
          abort_session_load(
            c(
              "Failed to restore session conversation state",
              "x" = error$message
            ),
            path = source,
            parent = error
          )
        }
      )

      # Session data is conversational state, not control-plane authority.
      # Constructor permissions and the workspace root remain immutable even
      # when the payload came from outside the process. Checkpoint state is
      # restored only when the receiver explicitly enabled checkpointing;
      # FileCheckpointStore also requires an exact configured-root match.
      if (!is.null(restored_checkpoints)) {
        private$.file_checkpoints <- restored_checkpoints
      }

      private$.run_context <- restored_run_context
      private$last_run_context <- clone_run_context(restored_run_context)
      private$appended_hook_context_hashes <- restored_hashes
    },

    notify = function(message, level = "info", code = NULL, ...) {
      self$hooks$fire(
        "Notification",
        message = message,
        context = private$hook_context(
          level = level,
          code = code,
          ...
        )
      )
      invisible(NULL)
    },

    require_file_checkpoint_store = function() {
      if (is.null(private$.file_checkpoints)) {
        file_checkpoint_abort(c(
          "File checkpointing is not enabled for this agent.",
          "i" = "Create the agent with {.code enable_file_checkpointing = TRUE}."
        ))
      }
      private$.file_checkpoints
    },

    new_run_id = function() {
      new_deputy_id("run_")
    },

    active_run_id = function() {
      if (isTRUE(private$run_active)) {
        private$current_run_id
      } else {
        NULL
      }
    },

    effective_run_context = function() {
      clone_run_context(
        private$current_run_context %||% private$.run_context
      )
    },

    snapshot_run_context = function() {
      clone_run_context(
        private$current_run_context %||%
          private$last_run_context %||%
          private$.run_context
      )
    },

    event_correlation = function(delegation_id = NULL) {
      Filter(
        Negate(is.null),
        list(
          agent_id = private$.agent_id,
          agent_name = private$.agent_name,
          session_id = private$.session_id,
          run_id = private$active_run_id(),
          parent_agent_id = private$.parent_agent_id,
          parent_run_id = private$.parent_run_id,
          delegation_id = delegation_id %||% private$.delegation_id,
          run_context = private$effective_run_context()
        )
      )
    },

    agent_event = function(type, ..., delegation_id = NULL) {
      do.call(
        AgentEvent,
        c(
          list(type = type),
          private$event_correlation(delegation_id = delegation_id),
          list(...)
        )
      )
    },

    hook_context = function(..., delegation_id = NULL) {
      context <- utils::modifyList(
        list(working_dir = self$working_dir),
        list(...),
        keep.null = TRUE
      )
      correlation <- private$event_correlation(
        delegation_id = delegation_id
      )
      for (field in names(correlation)) {
        context[[field]] <- correlation[[field]]
      }
      context
    },

    tool_call_record = function(extracted, phase) {
      phase <- match.arg(phase, c("start", "request", "result", "end"))
      tool_name <- extracted$tool_name %||% "unknown"
      tool_name <- as.character(tool_name[[1L]])
      provider_tool_call_id <- extracted$provider_tool_call_id
      if (
        is.null(provider_tool_call_id) ||
          length(provider_tool_call_id) != 1L ||
          is.na(provider_tool_call_id) ||
          !nzchar(as.character(provider_tool_call_id))
      ) {
        provider_tool_call_id <- NULL
      } else {
        provider_tool_call_id <- as.character(provider_tool_call_id)
      }

      records <- private$tool_call_records
      index <- NULL
      if (!is.null(provider_tool_call_id)) {
        matches <- which(vapply(
          records,
          function(record) {
            identical(record$provider_tool_call_id, provider_tool_call_id)
          },
          logical(1)
        ))
        if (length(matches) > 0L) {
          index <- matches[[1L]]
        }
      } else if (length(records) > 0L) {
        phase_field <- paste0(phase, "_seen")
        matches <- which(vapply(
          records,
          function(record) {
            is.null(record$provider_tool_call_id) &&
              identical(record$tool_name, tool_name) &&
              !isTRUE(record[[phase_field]])
          },
          logical(1)
        ))
        if (length(matches) > 0L) {
          index <- matches[[1L]]
        }
      }

      if (is.null(index)) {
        if (is.null(provider_tool_call_id)) {
          ambiguous <- any(vapply(
            records,
            function(record) {
              is.null(record$provider_tool_call_id) &&
                identical(record$tool_name, tool_name) &&
                !isTRUE(record$end_seen)
            },
            logical(1)
          ))
          if (isTRUE(ambiguous)) {
            cli_abort(
              c(
                "Cannot correlate concurrent tool calls without provider IDs.",
                "i" = paste0(
                  "The provider must supply a non-empty tool request ID for ",
                  "concurrent calls to the same tool."
                )
              ),
              class = c(
                "deputy_tool_correlation_error",
                "deputy_error"
              )
            )
          }
        }
        index <- length(records) + 1L
        records[[index]] <- list(
          tool_call_id = provider_tool_call_id %||%
            new_deputy_id("tool_"),
          provider_tool_call_id = provider_tool_call_id,
          tool_name = tool_name,
          delegation_id = if (identical(tool_name, "delegate_to_agent")) {
            new_deputy_id("delegation_")
          } else {
            NULL
          },
          delegation_queued = FALSE,
          start_seen = FALSE,
          request_seen = FALSE,
          result_seen = FALSE,
          end_seen = FALSE
        )
      }

      record <- records[[index]]
      record[[paste0(phase, "_seen")]] <- TRUE
      records[[index]] <- record
      private$tool_call_records <- records
      record$record_index <- index
      record
    },

    queue_delegation = function(record) {
      if (
        is.null(record$delegation_id) ||
          isTRUE(record$delegation_queued)
      ) {
        return(invisible(record))
      }
      private$pending_delegations <- c(
        private$pending_delegations,
        list(list(
          tool_call_id = record$tool_call_id,
          delegation_id = record$delegation_id,
          parent_agent_id = private$.agent_id,
          parent_run_id = private$active_run_id(),
          run_context = private$effective_run_context()
        ))
      )
      index <- record$record_index
      private$tool_call_records[[index]]$delegation_queued <- TRUE
      record$delegation_queued <- TRUE
      invisible(record)
    },

    claim_delegation = function() {
      if (length(private$pending_delegations) > 0L) {
        correlation <- private$pending_delegations[[1L]]
        private$pending_delegations <- private$pending_delegations[-1L]
        return(correlation)
      }
      list(
        tool_call_id = NULL,
        delegation_id = new_deputy_id("delegation_"),
        parent_agent_id = private$.agent_id,
        parent_run_id = private$active_run_id(),
        run_context = private$effective_run_context()
      )
    },

    enqueue_event = function(event) {
      private$pending_events <- c(private$pending_events, list(event))
      invisible(event)
    },

    drain_events = function() {
      events <- private$pending_events
      private$pending_events <- list()
      events
    },

    fallback_chat = function(prompt) {
      # Non-streaming chat calls report tool lifecycle through callbacks, so
      # switch out of content-stream mode before invoking the provider.
      private$current_stream_content <- FALSE
      fallback_error <- NULL
      response <- tryCatch(
        self$chat$chat(prompt),
        error = function(error) {
          fallback_error <<- error
          NULL
        }
      )

      list(
        response = response,
        events = private$drain_events(),
        error = fallback_error
      )
    },

    current_run_usage = function() {
      baseline <- private$current_usage_baseline %||% AgentUsage()
      usage <- agent_usage_difference(
        agent_usage_snapshot(self$chat),
        baseline,
        tool_calls = private$current_tool_calls
      )
      usage$requests <- max(usage$requests, private$current_outer_requests)
      agent_usage_add(
        usage,
        private$current_external_usage %||% AgentUsage()
      )
    },

    add_external_usage = function(usage) {
      if (!inherits(usage, "AgentUsage")) {
        return(invisible(FALSE))
      }
      private$current_external_usage <- agent_usage_add(
        private$current_external_usage %||% AgentUsage(),
        usage
      )
      if (!is.null(private$current_usage_limits)) {
        limit_status <- usage_limit_status(
          private$current_run_usage(),
          private$current_usage_limits,
          require_followup = TRUE
        )
        if (!is.null(limit_status)) {
          private$mark_usage_limit(limit_status)
        }
      }
      invisible(TRUE)
    },

    mark_usage_limit = function(status) {
      if (is.null(status)) {
        return(invisible(NULL))
      }
      if (is.null(private$last_limit_status)) {
        private$last_limit_status <- status
      }
      private$should_stop <- TRUE
      private$stop_reason_from_hook <- status$reason

      message <- usage_limit_message(status)
      private$notify(
        message,
        level = "warning",
        code = status$reason,
        usage = private$current_run_usage(),
        limit = status$limit
      )

      private$request_stream_stop(status$reason)
      invisible(status)
    },

    abort_usage_limit = function(status) {
      if (is.null(status)) {
        return(invisible(NULL))
      }
      message <- usage_limit_message(status)
      if (identical(status$reason, "request_limit")) {
        abort_request_limit(
          message,
          current_requests = status$actual,
          max_requests = status$limit,
          run_id = private$current_run_id
        )
      }
      abort_budget_exceeded(
        message,
        current_cost = if (identical(status$reason, "cost_limit")) {
          status$actual
        } else {
          NULL
        },
        max_cost = if (identical(status$reason, "cost_limit")) {
          status$limit
        } else {
          NULL
        },
        budget_type = status$field,
        actual = status$actual,
        limit = status$limit,
        run_id = private$current_run_id
      )
    },

    start_stream = function(prompt) {
      stream_fun <- self$chat$stream
      stream_formals <- names(formals(stream_fun))
      args <- list(prompt)
      content_mode <- "stream" %in% stream_formals
      if (content_mode) {
        args$stream <- "content"
      }
      if (
        !is.null(private$current_stream_controller) &&
          "controller" %in% stream_formals
      ) {
        args$controller <- private$current_stream_controller
      }
      list(
        generator = do.call(stream_fun, args),
        content = content_mode
      )
    },

    tool_start_event = function(extracted) {
      record <- private$tool_call_record(extracted, "start")
      private$tool_started_at[[record$tool_call_id]] <- Sys.time()
      private$agent_event(
        "tool_start",
        delegation_id = record$delegation_id,
        tool_call_id = record$tool_call_id,
        tool_name = extracted$tool_name,
        tool_input = extracted$tool_input
      )
    },

    tool_end_event = function(extracted) {
      record <- private$tool_call_record(extracted, "end")
      key <- record$tool_call_id
      started_at <- private$tool_started_at[[key]]
      duration <- if (is.null(started_at)) {
        NA_real_
      } else {
        as.numeric(difftime(Sys.time(), started_at, units = "secs"))
      }
      private$tool_started_at[[key]] <- NULL

      override <- private$tool_event_overrides[[key]]
      private$tool_event_overrides[[key]] <- NULL
      suppressed <- isTRUE(override$suppress_output)
      event_result <- if (suppressed) {
        NULL
      } else {
        override$updated_tool_output %||% extracted$tool_result
      }

      private$agent_event(
        "tool_end",
        delegation_id = record$delegation_id,
        tool_call_id = record$tool_call_id,
        tool_name = extracted$tool_name,
        tool_result = event_result,
        tool_error = extracted$tool_error,
        suppressed = suppressed,
        duration = duration
      )
    },

    # Callback for tool requests (permission checking + hooks)
    on_tool_request = function(request) {
      # Validate and extract request data safely
      extracted <- private$extract_tool_request_data(request)
      tool_name <- extracted$tool_name
      tool_input <- extracted$tool_input
      tool_annotations <- extracted$tool_annotations
      provider_tool_call_id <- extracted$provider_tool_call_id

      private$current_tool_calls <- private$current_tool_calls + 1L
      record <- private$tool_call_record(extracted, "request")
      extracted$tool_call_id <- record$tool_call_id
      if (!isTRUE(private$current_stream_content)) {
        private$enqueue_event(private$tool_start_event(extracted))
      }

      usage <- private$current_run_usage()
      limits <- private$current_usage_limits %||% self$usage_limits
      limit_status <- usage_limit_status(
        usage,
        limits,
        require_followup = TRUE
      )
      if (!is.null(limit_status)) {
        private$mark_usage_limit(limit_status)
        ellmer::tool_reject(usage_limit_message(limit_status))
      }

      file_info <- private$file_tool_path_info(tool_name, tool_input)
      if (
        isTRUE(private$current_run_requires_absolute_file_paths) &&
          !is.null(file_info)
      ) {
        tool_path <- file_info$path
        if (is.null(tool_path) || !is_absolute_path(tool_path)) {
          ellmer::tool_reject(sprintf(
            paste0(
              "Relative or missing file paths are not safe in run_shiny(); ",
              "provide an absolute path within the Agent working_dir: %s"
            ),
            self$working_dir
          ))
        }
        if (!is_path_within(tool_path, self$working_dir)) {
          ellmer::tool_reject(sprintf(
            "File paths in run_shiny() must stay within: %s",
            self$working_dir
          ))
        }
      }

      context <- private$hook_context(
        tool_annotations = tool_annotations,
        tool_call_id = record$tool_call_id,
        permission_mode = self$permissions$mode,
        usage = usage,
        usage_limits = limits,
        delegation_id = record$delegation_id
      )

      # Check permissions first
      perm_result <- self$permissions$check(tool_name, tool_input, context)

      if (inherits(perm_result, "PermissionResultDeny")) {
        request_result <- self$hooks$fire(
          "PermissionRequest",
          tool_name = tool_name,
          tool_input = tool_input,
          permission_result = perm_result,
          context = context
        )

        if (inherits(request_result, "PermissionResultAllow")) {
          perm_result <- request_result
        } else if (inherits(request_result, "PermissionResultDeny")) {
          perm_result <- request_result
        } else if (
          inherits(request_result, "HookResultPreToolUse") &&
            identical(request_result$permission, "allow")
        ) {
          perm_result <- PermissionResultAllow()
        }
      }

      if (inherits(perm_result, "PermissionResultDeny")) {
        if (isTRUE(perm_result$interrupt)) {
          private$request_stream_stop("permission_denied")
        }
        private$notify(
          perm_result$reason,
          level = "warning",
          code = "permission_denied",
          tool_name = tool_name,
          tool_input = tool_input
        )
        ellmer::tool_reject(perm_result$reason)
      }

      # Fire PreToolUse hooks
      hook_result <- self$hooks$fire(
        "PreToolUse",
        tool_name = tool_name,
        tool_input = tool_input,
        context = context
      )

      # Check hook result
      if (inherits(hook_result, "HookResultPreToolUse")) {
        if (!is.null(hook_result$additional_context)) {
          private$append_hook_context(hook_result$additional_context)
        }
        # Check continue field - signal to stop after this tool
        if (!is.null(hook_result$continue) && !hook_result$continue) {
          private$request_stream_stop(
            hook_result$stop_reason %||% "hook_requested_stop"
          )
        }
        if (hook_result$permission == "deny") {
          ellmer::tool_reject(hook_result$reason %||% "Denied by hook")
        }
      }

      # Enforce callback-based limits (active during run_shiny; NULL during
      # run/run_sync which have their own turn-level loop controls)
      if (!is.null(private$tool_call_limit)) {
        private$tool_call_count <- private$tool_call_count + 1L
        if (private$tool_call_count > private$tool_call_limit) {
          private$request_stream_stop("tool_call_limit")
          private$notify(
            "Tool call limit reached. Please provide your final answer with the information gathered so far.",
            level = "warning",
            code = "tool_call_limit"
          )
          ellmer::tool_reject(
            "Tool call limit reached. Please provide your final answer with the information gathered so far."
          )
        }
      }

      if (!is.null(private$.file_checkpoints)) {
        tryCatch(
          private$.file_checkpoints$before_tool(
            tool_name,
            tool_input,
            provider_tool_call_id %||% record$tool_call_id
          ),
          deputy_file_checkpoint_error = function(e) {
            private$notify(
              conditionMessage(e),
              level = "warning",
              code = "file_checkpoint_capture_failed",
              tool_name = tool_name,
              tool_call_id = record$tool_call_id
            )
            ellmer::tool_reject(conditionMessage(e))
          }
        )
      }

      # Queue delegated-run correlation only after every gate has allowed the
      # request. A denied request never invokes the tool closure and therefore
      # must not leave correlation for a later delegation to claim.
      private$queue_delegation(record)

      # Allow the tool to proceed
      invisible(NULL)
    },

    # Callback for tool results (hooks)
    on_tool_result = function(result) {
      # Validate and extract tool result data safely
      # ContentToolResult (S7) has: value, error, extra, request
      # request is ContentToolRequest with: id, name, arguments, tool, extra
      extracted <- private$extract_tool_result_data(result)
      private$current_tool_results <- private$current_tool_results + 1L
      record <- private$tool_call_record(extracted, "result")
      extracted$tool_call_id <- record$tool_call_id

      if (!is.null(private$.file_checkpoints)) {
        tryCatch(
          private$.file_checkpoints$after_tool(
            extracted$provider_tool_call_id %||% record$tool_call_id,
            is.null(extracted$tool_error)
          ),
          deputy_file_checkpoint_error = function(e) {
            private$should_stop <- TRUE
            private$stop_reason_from_hook <- "file_checkpoint_error"
            private$notify(
              conditionMessage(e),
              level = "warning",
              code = "file_checkpoint_commit_failed",
              tool_name = extracted$tool_name,
              tool_call_id = record$tool_call_id
            )
            stop(e)
          }
        )
      }

      context <- private$hook_context(
        tool_call_id = record$tool_call_id,
        permission_mode = self$permissions$mode,
        usage = private$current_run_usage(),
        usage_limits = private$current_usage_limits,
        delegation_id = record$delegation_id
      )

      # Fire PostToolUse hooks
      hook_result <- self$hooks$fire(
        "PostToolUse",
        tool_name = extracted$tool_name,
        tool_result = extracted$tool_result,
        tool_error = extracted$tool_error,
        context = context
      )

      # Check continue field in PostToolUse result
      if (inherits(hook_result, "HookResultPostToolUse")) {
        private$tool_event_overrides[[record$tool_call_id]] <- list(
          suppress_output = hook_result$suppress_output,
          updated_tool_output = hook_result$updated_tool_output
        )
        if (!is.null(hook_result$additional_context)) {
          private$append_hook_context(hook_result$additional_context)
        }
        if (!is.null(hook_result$continue) && !hook_result$continue) {
          private$should_stop <- TRUE
          private$stop_reason_from_hook <- hook_result$stop_reason %||%
            "hook_requested_stop"
        }
      }

      if (!is.null(extracted$tool_error)) {
        self$hooks$fire(
          "PostToolUseFailure",
          tool_name = extracted$tool_name,
          tool_result = extracted$tool_result,
          tool_error = extracted$tool_error,
          context = context
        )
      }

      if (!isTRUE(private$current_stream_content)) {
        private$enqueue_event(private$tool_end_event(extracted))
      }

      invisible(NULL)
    },

    # Safely extract data from an ellmer tool request.
    extract_tool_request_data = function(request) {
      # Default values if extraction fails
      tool_name <- "unknown"
      tool_input <- list()
      tool_annotations <- NULL
      provider_tool_call_id <- NULL

      # Check if we have a valid request object
      if (is.null(request)) {
        cli_warn("Tool request callback received NULL request")
        return(list(
          tool_name = tool_name,
          tool_input = tool_input,
          tool_annotations = tool_annotations,
          provider_tool_call_id = provider_tool_call_id
        ))
      }

      # Check if it's a ContentToolRequest (S7 class)
      if (!inherits(request, "ellmer::ContentToolRequest")) {
        cli_warn(c(
          "Tool request is not a ContentToolRequest",
          "i" = "Got class: {.cls {class(request)}}"
        ))

        return(list(
          tool_name = tool_name,
          tool_input = tool_input,
          tool_annotations = tool_annotations,
          provider_tool_call_id = provider_tool_call_id
        ))
      }

      # Extract from S7 object with error handling
      # Tool name
      tool_name <- tryCatch(
        request@name %||% "unknown",
        error = function(e) {
          cli_warn("Failed to extract tool name from request: {e$message}")
          "unknown"
        }
      )

      # Tool arguments
      tool_input <- tryCatch(
        request@arguments %||% list(),
        error = function(e) {
          cli_warn("Failed to extract tool arguments from request: {e$message}")
          list()
        }
      )

      provider_tool_call_id <- read_provider_tool_call_id(
        function() request@id,
        source = "request",
        object = request
      )

      # Tool annotations
      tool_annotations <- tryCatch(
        {
          if (!is.null(request@tool)) {
            request@tool@annotations
          } else {
            NULL
          }
        },
        error = function(e) {
          # Annotations are optional, don't warn
          NULL
        }
      )

      list(
        tool_name = tool_name,
        tool_input = tool_input,
        tool_annotations = tool_annotations,
        provider_tool_call_id = provider_tool_call_id
      )
    },

    # Safely extract data from an ellmer tool result.
    extract_tool_result_data = function(result) {
      # Default values if extraction fails
      tool_name <- "unknown"
      tool_result <- NULL
      tool_error <- NULL
      provider_tool_call_id <- NULL

      # Check if we have a valid result object
      if (is.null(result)) {
        cli_warn("Tool result callback received NULL result")
        return(list(
          tool_name = tool_name,
          tool_result = tool_result,
          tool_error = "NULL result received",
          provider_tool_call_id = provider_tool_call_id
        ))
      }

      # Check if it's a ContentToolResult (S7 class)
      if (!inherits(result, "ellmer::ContentToolResult")) {
        cli_warn(c(
          "Tool result is not a ContentToolResult",
          "i" = "Got class: {.cls {class(result)}}"
        ))

        return(list(
          tool_name = tool_name,
          tool_result = tool_result,
          tool_error = tool_error,
          provider_tool_call_id = provider_tool_call_id
        ))
      }

      # Extract from S7 object with error handling
      # Tool name from request
      tool_name <- tryCatch(
        {
          if (!is.null(result@request)) {
            result@request@name %||% "unknown"
          } else {
            "unknown"
          }
        },
        error = function(e) {
          cli_warn("Failed to extract tool name from result: {e$message}")
          "unknown"
        }
      )

      # Tool result value
      tool_result <- tryCatch(
        result@value,
        error = function(e) {
          cli_warn("Failed to extract tool result value: {e$message}")
          NULL
        }
      )

      # Tool error
      tool_error <- tryCatch(
        result@error,
        error = function(e) {
          cli_warn("Failed to extract tool error: {e$message}")
          NULL
        }
      )

      provider_tool_call_id <- read_provider_tool_call_id(
        function() {
          if (!is.null(result@request)) {
            result@request@id
          } else {
            NULL
          }
        },
        source = "result",
        object = result
      )

      list(
        tool_name = tool_name,
        tool_result = tool_result,
        tool_error = tool_error,
        provider_tool_call_id = provider_tool_call_id
      )
    },

    append_hook_context = function(additional_context) {
      if (is.null(additional_context)) {
        return(invisible(NULL))
      }

      context_text <- paste(as.character(additional_context), collapse = "\n")
      if (!nzchar(trimws(context_text))) {
        return(invisible(NULL))
      }

      # De-duplicate by content hash. A hook that fires on every tool call
      # with the same context would otherwise grow the system prompt without
      # bound and inflate every subsequent persisted session payload.
      chunk_hash <- digest::digest(context_text, algo = "sha1")
      if (chunk_hash %in% private$appended_hook_context_hashes) {
        return(invisible(NULL))
      }
      private$appended_hook_context_hashes <- c(
        private$appended_hook_context_hashes,
        chunk_hash
      )

      current_prompt <- self$chat$get_system_prompt() %||% ""
      self$chat$set_system_prompt(paste(
        current_prompt,
        "",
        "# Hook Additional Context",
        context_text,
        sep = "\n"
      ))

      invisible(NULL)
    },

    # Create a true coro generator for streaming events
    create_run_generator = function(
      task,
      usage_limits,
      include_partial_messages = TRUE,
      output_format = NULL,
      run_context,
      run_owner
    ) {
      agent <- self

      # Note: We use .__enclos_env__$private access inside the generator because
      # coro's state machine parser doesn't support calling closure functions.
      # This is a known limitation - see https://github.com/r-lib/coro/issues

      # Create the generator using coro
      coro::generator(function() {
        if (isTRUE(agent$.__enclos_env__$private$run_active)) {
          cli::cli_abort(
            "This agent already has an active run",
            class = c("deputy_run_active", "deputy_error")
          )
        }
        agent$.__enclos_env__$private$run_active <- TRUE
        active_run_id <- NULL
        on.exit(
          {
            if (
              is.null(active_run_id) ||
                identical(
                  agent$.__enclos_env__$private$current_run_id,
                  active_run_id
                )
            ) {
              run_owner$finished <- TRUE
              agent$.__enclos_env__$private$finish_active_run()
            }
          },
          add = TRUE
        )

        agent$.__enclos_env__$private$should_stop <- FALSE
        agent$.__enclos_env__$private$stop_reason_from_hook <- NULL
        agent$.__enclos_env__$private$current_run_id <-
          agent$.__enclos_env__$private$new_run_id()
        agent$.__enclos_env__$private$current_run_context <- run_context
        active_run_id <- agent$.__enclos_env__$private$current_run_id
        run_owner$active_run_id <- active_run_id
        agent$.__enclos_env__$private$current_usage_limits <- usage_limits
        agent$.__enclos_env__$private$current_usage_baseline <-
          agent_usage_snapshot(agent$chat)
        agent$.__enclos_env__$private$current_tool_calls <- 0L
        agent$.__enclos_env__$private$current_tool_results <- 0L
        agent$.__enclos_env__$private$current_outer_requests <- 0L
        agent$.__enclos_env__$private$current_external_usage <- AgentUsage()
        agent$.__enclos_env__$private$current_stream_controller <- tryCatch(
          ellmer::stream_controller(),
          error = function(e) NULL
        )
        agent$.__enclos_env__$private$current_stream_content <- FALSE
        agent$.__enclos_env__$private$pending_events <- list()
        agent$.__enclos_env__$private$tool_started_at <- list()
        agent$.__enclos_env__$private$tool_event_overrides <- list()
        agent$.__enclos_env__$private$tool_call_records <- list()
        agent$.__enclos_env__$private$pending_delegations <- list()
        agent$.__enclos_env__$private$last_limit_status <- NULL
        agent$.__enclos_env__$private$last_run_usage <- AgentUsage()
        agent$.__enclos_env__$private$current_run_checkpoint_id <- NULL
        agent$.__enclos_env__$private$current_run_requires_absolute_file_paths <-
          FALSE

        # Apply output format instructions
        if (!is.null(output_format)) {
          task <- apply_output_format_instructions(task, output_format)
        }

        if (!is.null(agent$.__enclos_env__$private$.file_checkpoints)) {
          checkpoint_id <- agent$.__enclos_env__$private$.file_checkpoints$checkpoint(
            paste0("run ", agent$.__enclos_env__$private$current_run_id),
            metadata = list(
              run_id = agent$.__enclos_env__$private$current_run_id,
              task = task
            )
          )
          agent$.__enclos_env__$private$current_run_checkpoint_id <-
            checkpoint_id
        }

        # Yield start event
        coro::yield(agent$.__enclos_env__$private$agent_event(
          "start",
          task = task,
          usage_limits = usage_limits,
          checkpoint_id = agent$.__enclos_env__$private$current_run_checkpoint_id
        ))

        if (!is.null(agent$.__enclos_env__$private$current_run_checkpoint_id)) {
          coro::yield(agent$.__enclos_env__$private$agent_event(
            "file_checkpoint",
            checkpoint_id = agent$.__enclos_env__$private$current_run_checkpoint_id,
            name = paste0(
              "run ",
              agent$.__enclos_env__$private$current_run_id
            )
          ))
        }

        # Fire SessionStart hook (before first turn begins)
        agent$hooks$fire(
          "SessionStart",
          context = agent$.__enclos_env__$private$hook_context(
            permissions = agent$permissions,
            provider = agent$provider(),
            tools_count = length(agent$chat$get_tools()),
            run_id = agent$.__enclos_env__$private$current_run_id,
            usage_limits = usage_limits
          )
        )

        # Fire UserPromptSubmit hook
        agent$hooks$fire(
          "UserPromptSubmit",
          prompt = task,
          context = agent$.__enclos_env__$private$hook_context(
            run_id = agent$.__enclos_env__$private$current_run_id
          )
        )

        turn_num <- 0
        stop_reason <- "complete"
        last_response_hash <- NULL
        loop_cap <- usage_limits$max_requests

        if (identical(loop_cap, 0L)) {
          zero_status <- list(
            field = "max_requests",
            actual = 0L,
            reason = "request_limit",
            label = "model requests",
            reached = TRUE,
            limit = 0L
          )
          agent$.__enclos_env__$private$mark_usage_limit(zero_status)
          stop_reason <- "request_limit"
        }

        i <- 0L
        while (is.null(loop_cap) || i < loop_cap) {
          # Check if hook requested stop
          if (agent$.__enclos_env__$private$should_stop) {
            hook_reason <- agent$.__enclos_env__$private$stop_reason_from_hook
            if (is.null(hook_reason)) {
              stop_reason <- "hook_requested_stop"
            } else {
              stop_reason <- hook_reason
            }
            break
          }

          i <- i + 1L
          turn_num <- i
          agent$.__enclos_env__$private$current_outer_requests <- i

          # Determine the prompt for this turn
          if (i == 1) {
            prompt <- task
          } else {
            prompt <- NULL
          }

          # Use ellmer's stream() for true streaming text output
          text_chunks <- character()
          stream_error <- NULL
          saw_stream_output <- FALSE
          tool_calls_before_stream <-
            agent$.__enclos_env__$private$current_tool_calls
          tool_results_before_stream <-
            agent$.__enclos_env__$private$current_tool_results
          turns_before_stream <- tryCatch(
            length(agent$chat$get_turns()),
            error = function(e) 0L
          )

          # Try streaming first
          stream <- tryCatch(
            agent$.__enclos_env__$private$start_stream(prompt),
            error = function(e) {
              stream_error <<- e
              NULL
            }
          )

          if (!is.null(stream)) {
            stream_gen <- stream$generator
            agent$.__enclos_env__$private$current_stream_content <-
              isTRUE(stream$content)

            # Stream chunks as they arrive
            repeat {
              if (agent$.__enclos_env__$private$should_stop) {
                break
              }
              step <- tryCatch(
                list(chunk = stream_gen(), error = NULL),
                error = function(e) list(chunk = NULL, error = e)
              )
              if (!is.null(step$error)) {
                if (agent$.__enclos_env__$private$should_stop) {
                  break
                }
                stream_error <- step$error
                break
              }
              chunk <- step$chunk
              if (coro::is_exhausted(chunk)) {
                break
              }
              if (
                agent$.__enclos_env__$private$should_stop &&
                  !inherits(chunk, "ellmer::ContentToolResult")
              ) {
                break
              }
              saw_stream_output <- TRUE

              queued <- agent$.__enclos_env__$private$drain_events()
              for (event in queued) {
                coro::yield(event)
              }

              if (inherits(chunk, "ellmer::ContentToolRequest")) {
                extracted <- agent$.__enclos_env__$private$extract_tool_request_data(
                  chunk
                )
                coro::yield(
                  agent$.__enclos_env__$private$tool_start_event(extracted)
                )
              } else if (inherits(chunk, "ellmer::ContentToolResult")) {
                extracted <- agent$.__enclos_env__$private$extract_tool_result_data(
                  chunk
                )
                coro::yield(
                  agent$.__enclos_env__$private$tool_end_event(extracted)
                )
              } else if (inherits(chunk, "ellmer::ContentText")) {
                text <- chunk@text
                text_chunks <- c(text_chunks, text)
                if (isTRUE(include_partial_messages)) {
                  coro::yield(AgentEvent(
                    "text",
                    run_id = agent$.__enclos_env__$private$current_run_id,
                    text = text,
                    is_complete = FALSE
                  ))
                }
              } else if (is.character(chunk) && length(chunk) == 1) {
                if (nchar(chunk) > 0) {
                  text_chunks <- c(text_chunks, chunk)
                  if (isTRUE(include_partial_messages)) {
                    coro::yield(AgentEvent(
                      "text",
                      run_id = agent$.__enclos_env__$private$current_run_id,
                      text = chunk,
                      is_complete = FALSE
                    ))
                  }
                }
              } else {
                coro::yield(AgentEvent(
                  "content",
                  run_id = agent$.__enclos_env__$private$current_run_id,
                  content = chunk,
                  content_type = class(chunk)[[1]] %||% "unknown"
                ))
              }
            }

            queued <- agent$.__enclos_env__$private$drain_events()
            for (event in queued) {
              coro::yield(event)
            }
          } else {
            # Fallback to non-streaming if stream() failed
            if (!agent$.__enclos_env__$private$should_stop) {
              if (!is.null(stream_error)) {
                cli::cli_warn(c(
                  "Streaming failed, falling back to non-streaming",
                  "x" = stream_error$message
                ))
                agent$.__enclos_env__$private$notify(
                  "Streaming failed, falling back to non-streaming",
                  level = "warning",
                  code = "stream_fallback",
                  error = stream_error$message
                )
                # Emit warning event so applications can surface this to users
                coro::yield(AgentEvent(
                  "warning",
                  run_id = agent$.__enclos_env__$private$current_run_id,
                  message = "Streaming failed, falling back to non-streaming",
                  details = stream_error$message
                ))
              }
              fallback <- agent$.__enclos_env__$private$fallback_chat(prompt)
              for (event in fallback$events) {
                coro::yield(event)
              }
              if (
                !is.null(fallback$error) &&
                  !agent$.__enclos_env__$private$should_stop
              ) {
                stop(fallback$error)
              }
              response <- fallback$response
              if (
                !agent$.__enclos_env__$private$should_stop &&
                  !is.null(response) &&
                  nchar(response) > 0
              ) {
                text_chunks <- response
                if (isTRUE(include_partial_messages)) {
                  coro::yield(AgentEvent(
                    "text",
                    run_id = agent$.__enclos_env__$private$current_run_id,
                    text = response,
                    is_complete = TRUE
                  ))
                }
              }
            }
          }

          if (
            !is.null(stream_error) &&
              !is.null(stream) &&
              !isTRUE(saw_stream_output) &&
              !agent$.__enclos_env__$private$should_stop &&
              identical(
                agent$.__enclos_env__$private$current_tool_calls,
                tool_calls_before_stream
              )
          ) {
            cli::cli_warn(c(
              "Streaming failed, falling back to non-streaming",
              "x" = stream_error$message
            ))
            agent$.__enclos_env__$private$notify(
              "Streaming failed, falling back to non-streaming",
              level = "warning",
              code = "stream_fallback",
              error = stream_error$message
            )
            coro::yield(AgentEvent(
              "warning",
              run_id = agent$.__enclos_env__$private$current_run_id,
              message = "Streaming failed, falling back to non-streaming",
              details = stream_error$message
            ))
            fallback <- agent$.__enclos_env__$private$fallback_chat(prompt)
            for (event in fallback$events) {
              coro::yield(event)
            }
            if (
              !is.null(fallback$error) &&
                !agent$.__enclos_env__$private$should_stop
            ) {
              stop(fallback$error)
            }
            response <- fallback$response
            if (
              !agent$.__enclos_env__$private$should_stop &&
                !is.null(response) &&
                nchar(response) > 0
            ) {
              text_chunks <- response
              if (isTRUE(include_partial_messages)) {
                coro::yield(AgentEvent(
                  "text",
                  run_id = agent$.__enclos_env__$private$current_run_id,
                  text = response,
                  is_complete = TRUE
                ))
              }
            }
            stream_error <- NULL
          }

          if (
            !is.null(stream_error) &&
              !is.null(stream) &&
              (isTRUE(saw_stream_output) ||
                agent$.__enclos_env__$private$current_tool_calls >
                  tool_calls_before_stream)
          ) {
            if (!agent$.__enclos_env__$private$should_stop) {
              stop_reason <- "provider_error"
              coro::yield(AgentEvent(
                "warning",
                run_id = agent$.__enclos_env__$private$current_run_id,
                message = "Streaming stopped after a provider error",
                details = stream_error$message
              ))
            }
            break
          }

          # Yield complete text event with full response
          full_text <- paste(text_chunks, collapse = "")
          if (length(text_chunks) > 0 && nchar(full_text) > 0) {
            coro::yield(AgentEvent(
              "text_complete",
              run_id = agent$.__enclos_env__$private$current_run_id,
              text = full_text
            ))
          }

          # Stall detection
          if (nchar(full_text) > 0) {
            current_hash <- digest::digest(full_text, algo = "md5")
          } else {
            current_hash <- ""
          }
          if (
            !is.null(last_response_hash) &&
              identical(current_hash, last_response_hash) &&
              nchar(full_text) > 0
          ) {
            cli::cli_warn("Agent may be stalled - identical response detected")
          }
          last_response_hash <- current_hash

          incomplete_tool_call <-
            agent$.__enclos_env__$private$current_tool_calls -
              tool_calls_before_stream >
              agent$.__enclos_env__$private$current_tool_results -
                tool_results_before_stream
          agent$.__enclos_env__$private$finalize_pending_checkpoints()
          if (isTRUE(incomplete_tool_call)) {
            stop_reason <- "provider_error"
            coro::yield(AgentEvent(
              "warning",
              run_id = agent$.__enclos_env__$private$current_run_id,
              message = "Provider stream ended before a tool result arrived",
              details = "Pending tool calls were finalized for safe recovery."
            ))
          }

          # Attribute a turn only when this request produced fresh output or
          # advanced the conversation. Cancellation before the first chunk
          # must not re-emit a prior assistant turn as current-run state.
          turns_after_stream <- tryCatch(
            length(agent$chat$get_turns()),
            error = function(e) turns_before_stream
          )
          produced_current_turn <-
            isTRUE(saw_stream_output) ||
            length(text_chunks) > 0L ||
            agent$.__enclos_env__$private$current_tool_calls >
              tool_calls_before_stream ||
            turns_after_stream > turns_before_stream
          last_turn <- NULL
          if (isTRUE(produced_current_turn)) {
            last_turn <- agent$chat$last_turn()
            coro::yield(AgentEvent(
              "turn",
              run_id = agent$.__enclos_env__$private$current_run_id,
              turn = last_turn,
              turn_number = turn_num
            ))
          }

          if (isTRUE(incomplete_tool_call)) {
            break
          }

          # Check if hook requested stop (after tool execution)
          if (agent$.__enclos_env__$private$should_stop) {
            hook_reason <- agent$.__enclos_env__$private$stop_reason_from_hook
            if (is.null(hook_reason)) {
              stop_reason <- "hook_requested_stop"
            } else {
              stop_reason <- hook_reason
            }
            break
          }

          # Check if we're done (no tool requests in last turn)
          if (!agent$.__enclos_env__$private$has_tool_requests(last_turn)) {
            break
          }

          # Check if we hit max turns
          if (!is.null(loop_cap) && i >= loop_cap) {
            request_status <- list(
              field = "max_requests",
              actual = i,
              reason = "request_limit",
              label = "model requests",
              reached = TRUE,
              limit = loop_cap
            )
            agent$.__enclos_env__$private$mark_usage_limit(request_status)
            stop_reason <- "request_limit"
          }
        }

        # A provider can fail after the request callback but before returning a
        # tool result. Resolve those captures before ending the run.
        agent$.__enclos_env__$private$finalize_pending_checkpoints()

        usage <- agent$.__enclos_env__$private$current_run_usage()
        agent$.__enclos_env__$private$last_run_usage <- usage
        limit_status <- agent$.__enclos_env__$private$last_limit_status
        if (is.null(limit_status)) {
          limit_status <- usage_limit_status(usage, usage_limits)
          if (!is.null(limit_status)) {
            agent$.__enclos_env__$private$mark_usage_limit(limit_status)
            stop_reason <- limit_status$reason
          }
        }

        if (agent$.__enclos_env__$private$should_stop) {
          stop_reason <- agent$.__enclos_env__$private$stop_reason_from_hook %||%
            "hook_requested_stop"
        }
        external_requests <- (agent$.__enclos_env__$private$current_external_usage %||%
          AgentUsage())$requests
        parent_requests <- max(0L, usage$requests - external_requests)
        turn_num <- max(turn_num, parent_requests)

        if (
          is.null(limit_status) &&
            !is.null(usage_limits$max_cost_usd) &&
            usage$cost_usd >= usage_limits$max_cost_usd * 0.9
        ) {
          agent$.__enclos_env__$private$notify(
            paste0(
              "Approaching run cost limit: ",
              format_cost(usage$cost_usd),
              " / ",
              format_cost(usage_limits$max_cost_usd)
            ),
            level = "warning",
            code = "cost_limit_warning",
            usage = usage,
            max_cost_usd = usage_limits$max_cost_usd
          )
          cli::cli_warn(
            "Approaching run cost limit: {format_cost(usage$cost_usd)} / {format_cost(usage_limits$max_cost_usd)}"
          )
        }

        # Fire Stop hook
        agent$hooks$fire(
          "Stop",
          reason = stop_reason,
          context = agent$.__enclos_env__$private$hook_context(
            total_turns = turn_num,
            cost = agent$cost(),
            usage = usage,
            run_id = agent$.__enclos_env__$private$current_run_id
          )
        )

        # Fire SessionEnd hook (after agent stops for any reason)
        agent$hooks$fire(
          "SessionEnd",
          reason = stop_reason,
          context = agent$.__enclos_env__$private$hook_context(
            total_turns = turn_num,
            cost = agent$cost(),
            usage = usage,
            run_id = agent$.__enclos_env__$private$current_run_id
          )
        )

        coro::yield(agent$.__enclos_env__$private$agent_event(
          "usage",
          usage = usage,
          limits = usage_limits
        ))

        if (
          !is.null(limit_status) && identical(usage_limits$on_exceed, "error")
        ) {
          agent$.__enclos_env__$private$abort_usage_limit(limit_status)
        }

        stop_event <- agent$.__enclos_env__$private$agent_event(
          "stop",
          reason = stop_reason,
          total_turns = turn_num,
          cost = agent$cost(),
          usage = usage,
          limit = limit_status
        )
        run_owner$finished <- TRUE
        agent$.__enclos_env__$private$finish_active_run()

        # Yield stop event after run resources are released.
        coro::yield(stop_event)
      })()
    },

    # Check if a turn has tool requests
    has_tool_requests = function(turn) {
      if (is.null(turn)) {
        return(FALSE)
      }

      # Check contents for tool requests (with defensive error handling)
      contents <- tryCatch(
        turn@contents,
        error = function(e) {
          cli_warn(c(
            "Failed to access turn contents for tool request check",
            "i" = "Turn class: {.cls {class(turn)}}",
            "x" = e$message
          ))
          list()
        }
      )

      for (content in contents) {
        if (inherits(content, "ellmer::ContentToolRequest")) {
          return(TRUE)
        }
      }
      FALSE
    },

    # Get the last response text
    get_last_response = function() {
      last <- self$chat$last_turn()
      if (is.null(last)) {
        return(NULL)
      }
      last@text
    },

    # Generate a summary of turns using the LLM
    generate_compaction_summary = function(turns) {
      # Format turns for summarization
      turn_texts <- vapply(
        turns,
        function(turn) {
          role <- if (inherits(turn, "ellmer::UserTurn")) {
            "User"
          } else if (inherits(turn, "ellmer::AssistantTurn")) {
            "Assistant"
          } else {
            cli_warn(c(
              "Unknown turn type in compaction summary",
              "i" = "Got class: {.cls {class(turn)}}",
              "i" = "Defaulting to 'Unknown'"
            ))
            "Unknown"
          }
          text <- turn@text %||% "[no text]"

          # Include tool information if present
          tool_info <- ""
          if (inherits(turn, "ellmer::AssistantTurn")) {
            contents <- turn@contents %||% list()
            tool_requests <- Filter(
              function(c) inherits(c, "ellmer::ContentToolRequest"),
              contents
            )
            if (length(tool_requests) > 0) {
              tool_names <- vapply(
                tool_requests,
                function(tool) tool@name %||% "unknown",
                character(1)
              )
              tool_info <- paste0(
                " [Tools: ",
                paste(tool_names, collapse = ", "),
                "]"
              )
            }
          }

          paste0(role, tool_info, ": ", text)
        },
        character(1)
      )

      conversation_text <- paste(turn_texts, collapse = "\n\n")

      # Create summarization prompt
      summarization_prompt <- paste0(
        "Summarize the following conversation excerpt concisely. ",
        "Focus on:\n",
        "1. Key decisions made\n",
        "2. Important findings or results\n",
        "3. Files created, modified, or discussed\n",
        "4. Any errors encountered and how they were resolved\n",
        "5. Current state/progress of the task\n\n",
        "Keep the summary under 500 words. Be factual and specific.\n\n",
        "Conversation to summarize:\n",
        "---\n",
        conversation_text,
        "\n---\n\n",
        "Summary:"
      )

      # Try to use the LLM for summarization
      summary <- tryCatch(
        {
          # Create a temporary chat for summarization
          # Use the same provider as the main chat
          temp_chat <- tryCatch(
            {
              clone_compaction_chat(self$chat)
            },
            error = function(e) {
              cli_warn(c(
                "Could not create summarization chat",
                "i" = "Falling back to text-based summary",
                "x" = e$message
              ))
              private$notify(
                "Compaction fell back to text summary because a summarization chat could not be created.",
                level = "warning",
                code = "compact_fallback",
                error = e$message
              )
              NULL
            }
          )

          if (is.null(temp_chat)) {
            return(private$generate_fallback_summary(turns))
          }

          # Generate summary
          response <- temp_chat$chat(summarization_prompt, echo = "none")
          response
        },
        error = function(e) {
          cli_warn(c(
            "LLM summarization failed",
            "i" = "Falling back to text-based summary",
            "x" = e$message
          ))
          private$notify(
            "Compaction fell back to text summary because LLM summarization failed.",
            level = "warning",
            code = "compact_fallback",
            error = e$message
          )
          private$generate_fallback_summary(turns)
        }
      )

      summary
    },

    # Fallback summary when LLM is unavailable
    generate_fallback_summary = function(turns) {
      summary_parts <- vapply(
        turns,
        function(turn) {
          role <- if (inherits(turn, "ellmer::UserTurn")) {
            "User"
          } else if (inherits(turn, "ellmer::AssistantTurn")) {
            "Assistant"
          } else {
            cli_warn(c(
              "Unknown turn type in fallback summary",
              "i" = "Got class: {.cls {class(turn)}}",
              "i" = "Defaulting to 'Unknown'"
            ))
            "Unknown"
          }
          text <- turn@text %||% "[no text]"
          if (nchar(text) > 200) {
            text <- paste0(substr(text, 1, 197), "...")
          }
          paste0(role, ": ", text)
        },
        character(1)
      )

      paste0(
        "[Compacted ",
        length(turns),
        " earlier turns - LLM summary unavailable]\n\n",
        paste(summary_parts, collapse = "\n\n")
      )
    },

    # Storage for loaded skills
    loaded_skills = list(),

    # Storage for loaded MCP tool names
    loaded_mcp_tools = character(),
    loaded_mcp_status = list(),

    # Tool call counter for run_shiny() callback-based limits
    tool_call_count = 0L,

    # Tool call limit for run_shiny() -- NULL means inactive (run/run_sync path)
    tool_call_limit = NULL
  )
)
