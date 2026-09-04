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
#' @importFrom later run_now
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
    #' @param context_policy A [ContextPolicy] controlling automatic compaction
    #'   and durable offloading of large tool results.
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
      context_policy = ContextPolicy(),
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
      private$.context_policy <- normalize_context_policy(context_policy)
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
        private$.chat$set_system_prompt(system_prompt)
      }

      # Rebind all tools to this Agent's runtime authority, including tools
      # configured on the supplied Chat before Agent construction.
      backend_tools <- private$.chat$get_tools()
      backend_tools <- validate_tool_batch(
        backend_tools,
        preserve_reader = TRUE
      )
      tools <- validate_tool_batch(tools, existing = backend_tools)
      wrapped <- lapply(c(backend_tools, tools), private$adapt_tool)
      private$.chat$set_tools(wrapped)

      # Wire up ellmer's callbacks for permission/hook enforcement
      private$.chat$on_tool_request(private$handle_tool_request)
      private$.chat$on_tool_result(private$handle_tool_result)

      # shinychat uses the ellmer Chat protocol structurally. Agent supplies
      # that protocol while retaining ownership of the wrapped backend.
      class(self) <- unique(c(class(self), "Chat"))
      private$.r6_clone <- self$clone
      rlang::env_binding_unlock(self, "clone")
      self$clone <- private$clone_client
      rlang::env_binding_lock(self, "clone")

      invisible(self)
    },

    #' @description
    #' Run an agentic task with semantic streaming events.
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
      if (!is.null(output_format)) {
        task <- apply_output_format_instructions(task, output_format)
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

      governed_run <- private$start_governed_stream(
        messages = list(task),
        limits = limits,
        run_context = effective_run_context,
        stream = "content"
      )
      private$event_generator(
        governed_run,
        include_partial_messages = include_partial_messages
      )
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
      gen <- self$run(
        task = task,
        usage_limits = usage_limits,
        include_partial_messages = include_partial_messages,
        output_format = output_format,
        run_context = run_context
      )
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
      }

      result <- private$.last_run_result
      if (is.null(result)) {
        cli_abort("The governed run ended without an AgentResult")
      }
      if (!is.null(output_format) && !is.null(result$response)) {
        result$structured_output <- parse_structured_output(
          result$response,
          output_format
        )
      }
      result
    },

    #' @description
    #' Send messages synchronously using the ellmer Chat interface.
    #'
    #' All requests pass through Deputy's run kernel. The return value matches
    #' `ellmer::Chat$chat()`; inspect [AgentResult] metadata with `$last_run()`.
    #' @param ... User content accepted by ellmer.
    #' @param echo Accepted for ellmer compatibility.
    #' @param run_context Canonical JSON-compatible context to add to or narrow
    #'   for this run.
    #' @return The final assistant text.
    chat = function(..., echo = NULL, run_context = list()) {
      effective_run_context <- merge_run_context(
        private$.run_context,
        run_context
      )
      governed_run <- private$start_governed_stream(
        messages = list(...),
        limits = self$usage_limits,
        run_context = effective_run_context,
        stream = "content"
      )
      result <- private$resolve_promise(private$collect_governed_stream(
        governed_run
      ))
      private$echo_chat_result(result$response, echo)
      result$response
    },

    #' @description
    #' Send messages asynchronously using the ellmer Chat interface.
    #' @param ... User content accepted by ellmer.
    #' @param tool_mode Whether ellmer executes tool calls concurrently or
    #'   sequentially.
    #' @param run_context Canonical JSON-compatible context to add to or narrow
    #'   for this run.
    #' @return A promise resolving to the final assistant text.
    chat_async = function(
      ...,
      tool_mode = c("concurrent", "sequential"),
      run_context = list()
    ) {
      tool_mode <- match.arg(tool_mode)
      messages <- list(...)
      effective_run_context <- merge_run_context(
        private$.run_context,
        run_context
      )
      governed_run <- private$start_governed_stream(
        messages = messages,
        limits = self$usage_limits,
        run_context = effective_run_context,
        tool_mode = tool_mode,
        stream = "content"
      )
      private$collect_governed_stream(governed_run) |>
        promises::then(function(result) result$response)
    },

    #' @description Send a structured request through the governed run kernel.
    #' @param ... User content accepted by ellmer.
    #' @param type An ellmer structured-output type.
    #' @param echo Echo mode forwarded to ellmer.
    #' @param convert Whether ellmer converts the structured response.
    #' @param run_context Canonical JSON-compatible context to add to or narrow
    #'   for this run.
    #' @return Structured response data.
    chat_structured = function(
      ...,
      type,
      echo = "none",
      convert = TRUE,
      run_context = list()
    ) {
      private$resolve_promise(self$chat_structured_async(
        ...,
        type = type,
        echo = echo,
        convert = convert,
        run_context = run_context
      ))
    },

    #' @description Send an asynchronous structured request through Deputy.
    #' @param ... User content accepted by ellmer.
    #' @param type An ellmer structured-output type.
    #' @param echo Echo mode forwarded to ellmer.
    #' @param convert Whether ellmer converts the structured response.
    #' @param run_context Canonical JSON-compatible context to add to or narrow
    #'   for this run.
    #' @return A promise resolving to structured response data.
    chat_structured_async = function(
      ...,
      type,
      echo = "none",
      convert = TRUE,
      run_context = list()
    ) {
      effective_run_context <- merge_run_context(
        private$.run_context,
        run_context
      )
      governed_run <- private$start_governed_stream(
        messages = list(...),
        limits = self$usage_limits,
        run_context = effective_run_context,
        stream = "content",
        structured = list(type = type, echo = echo, convert = convert)
      )
      private$collect_governed_stream(governed_run) |>
        promises::then(function(...) governed_run$state$structured_output)
    },

    #' @description
    #' Stream synchronously using the ellmer Chat interface.
    #' @param ... User content accepted by ellmer.
    #' @param stream Yield text or semantic ellmer content.
    #' @param controller Optional ellmer stream controller.
    #' @param run_context Canonical JSON-compatible context to add to or narrow
    #'   for this run.
    #' @return A synchronous generator.
    stream = function(
      ...,
      stream = c("text", "content"),
      controller = NULL,
      run_context = list()
    ) {
      stream <- match.arg(stream)
      effective_run_context <- merge_run_context(
        private$.run_context,
        run_context
      )
      governed_run <- private$start_governed_stream(
        messages = list(...),
        limits = self$usage_limits,
        run_context = effective_run_context,
        stream = stream,
        controller = controller
      )
      private$sync_stream_generator(governed_run$stream)
    },

    #' @description
    #' Stream asynchronously using the ellmer Chat interface.
    #'
    #' This is the primary interface for shinychat. It returns the same content
    #' stream as ellmer while enforcing Deputy permissions, hooks, limits,
    #' workspace resolution, context management, and run accounting.
    #' @param ... User content accepted by ellmer, including shinychat's list of
    #'   attachment-enabled `Content` objects.
    #' @param tool_mode Whether ellmer executes tool calls concurrently or
    #'   sequentially.
    #' @param stream Yield text or semantic ellmer content.
    #' @param controller Optional ellmer stream controller.
    #' @param run_context Canonical JSON-compatible context to add to or narrow
    #'   for this run.
    #' @return An asynchronous generator suitable for `shinychat::chat_append()`.
    stream_async = function(
      ...,
      tool_mode = c("concurrent", "sequential"),
      stream = c("text", "content"),
      controller = NULL,
      run_context = list()
    ) {
      tool_mode <- match.arg(tool_mode)
      stream <- match.arg(stream)
      effective_run_context <- merge_run_context(
        private$.run_context,
        run_context
      )
      private$start_governed_stream(
        messages = list(...),
        limits = self$usage_limits,
        run_context = effective_run_context,
        tool_mode = tool_mode,
        stream = stream,
        controller = controller
      )$stream
    },

    #' @description
    #' Return the most recently completed governed run.
    #' @return An [AgentResult], or `NULL` before the first run completes.
    last_run = function() {
      private$.last_run_result
    },

    #' @description Return the most recent compaction outcome.
    #' @return A `DeputyCompaction`, or `NULL` before compaction occurs.
    last_compaction = function() {
      private$.last_compaction
    },

    #' @description Resolve a durable tool-result reference.
    #' @param reference A `deputy://tool-result/...` URI or reference text
    #'   emitted into model context.
    #' @return The complete original R value.
    resolve_tool_result = function(reference) {
      read_tool_result_envelope(
        reference,
        self$context_policy,
        private$.session_id
      )$value
    },

    #' @description Add a user/assistant turn pair, as in ellmer Chat.
    #' @param user User turn or content.
    #' @param assistant Assistant turn or content.
    #' @param log_tokens Whether ellmer should log token metadata.
    #' @return Invisible self.
    add_turn = function(user, assistant, log_tokens = TRUE) {
      private$.chat$add_turn(user, assistant, log_tokens = log_tokens)
      invisible(self)
    },

    #' @description Return conversation turns, as in ellmer Chat.
    #' @param include_system_prompt Include the system prompt as a turn.
    #' @return A list of ellmer turns.
    get_turns = function(include_system_prompt = FALSE) {
      if (
        "include_system_prompt" %in% names(formals(private$.chat$get_turns))
      ) {
        return(private$.chat$get_turns(
          include_system_prompt = include_system_prompt
        ))
      }
      private$.chat$get_turns()
    },

    #' @description Replace conversation turns, as in ellmer Chat.
    #' @param value A list of ellmer turns.
    #' @return Invisible self.
    set_turns = function(value) {
      private$.chat$set_turns(value)
      prompt <- private$.chat$get_system_prompt()
      prompt_without_compaction <- private$system_prompt_without_compaction()
      if (!identical(prompt, prompt_without_compaction)) {
        private$.chat$set_system_prompt(prompt_without_compaction)
      }
      private$.compaction_summary <- NULL
      invisible(self)
    },

    #' @description Return the system prompt, as in ellmer Chat.
    #' @return The system prompt or `NULL`.
    get_system_prompt = function() {
      private$.chat$get_system_prompt()
    },

    #' @description Replace the system prompt, as in ellmer Chat.
    #' @param value The new system prompt or `NULL`.
    #' @return Invisible self.
    set_system_prompt = function(value) {
      previous_summary <- private$.compaction_summary
      private$.chat$set_system_prompt(value)
      private$appended_hook_context_hashes <- character()
      parts <- private$compaction_prompt_parts(value)
      private$.compaction_summary <- if (
        is.null(previous_summary) ||
          is.null(parts) ||
          !identical(parts$summary, previous_summary)
      ) {
        NULL
      } else {
        parts$summary
      }
      invisible(self)
    },

    #' @description Return registered tools, as in ellmer Chat.
    #' @return A named list of ellmer tool definitions.
    get_tools = function() {
      private$.chat$get_tools()
    },

    #' @description Replace registered tools, preserving Deputy adaptation.
    #' @param tools A list of ellmer tool definitions.
    #' @return Invisible self.
    set_tools = function(tools) {
      had_result_reader <- isTRUE(private$.tool_result_reader_registered)
      tools <- validate_tool_batch(tools, preserve_reader = TRUE)
      wrapped <- lapply(tools, private$adapt_tool)
      if (had_result_reader) {
        wrapped[["deputy_read_tool_result"]] <-
          private$.chat$get_tools()[["deputy_read_tool_result"]]
      }
      private$.chat$set_tools(wrapped)
      invisible(self)
    },

    #' @description Return provider token records, as in ellmer Chat.
    #' @param include_system_prompt Deprecated ellmer compatibility argument.
    #' @return A token data frame.
    get_tokens = function(include_system_prompt = NULL) {
      if (is.null(include_system_prompt)) {
        return(private$.chat$get_tokens())
      }
      private$.chat$get_tokens(include_system_prompt = include_system_prompt)
    },

    #' @description Return provider cost records, as in ellmer Chat.
    #' @param include Return all costs or only the latest request.
    #' @return Provider cost information.
    get_cost = function(include = c("all", "last")) {
      private$.chat$get_cost(include = match.arg(include))
    },

    #' @description Estimate tokens, as in ellmer Chat.
    #' @param ... User content accepted by ellmer.
    #' @param include Count only new content or the complete context.
    #' @param type Optional provider content type.
    #' @return Estimated token count.
    token_count = function(
      ...,
      include = c("new", "complete"),
      type = NULL
    ) {
      private$.chat$token_count(
        ...,
        include = match.arg(include),
        type = type
      )
    },

    #' @description Return the ellmer provider.
    #' @return An ellmer provider object.
    get_provider = function() {
      private$.chat$get_provider()
    },

    #' @description Return the configured model name.
    #' @return Model identifier.
    get_model = function() {
      private$.chat$get_model()
    },

    #' @description Replace the configured model.
    #' @param model Model identifier.
    #' @return Invisible self.
    set_model = function(model) {
      private$.chat$set_model(model)
      invisible(self)
    },

    #' @description
    #' Register a tool with the agent.
    #'
    #' Function tools are wrapped with Deputy's runtime enforcement. Known
    #' provider-native web tools are authorized once, before registration,
    #' because their execution occurs inside the provider rather than R. Native
    #' tools therefore require static permissions and cannot be registered with
    #' a custom `can_use_tool` callback.
    #' Existing names require explicit replacement. Every tool in a batch is
    #' validated and adapted before the registry changes. List element names
    #' do not rename tools; each tool's own name is authoritative.
    #' @param tool A tool created with `ellmer::tool()` or a supported
    #'   provider-native web tool.
    #' @param replace Replace tools already registered under the same name?
    #'   Defaults to FALSE. Duplicate names within a batch always fail.
    #' @return Invisible self for chaining
    register_tool = function(tool, replace = FALSE) {
      self$register_tools(list(tool), replace = replace)
    },

    #' @description
    #' Register multiple tools with the agent.
    #'
    #' @param tools A list of function tools or supported provider-native web
    #'   tools.
    #' @param replace Replace tools already registered under the same name?
    #'   Defaults to FALSE. Duplicate names within a batch always fail.
    #' @return Invisible self for chaining
    register_tools = function(tools, replace = FALSE) {
      existing <- private$.chat$get_tools()
      tools <- validate_tool_batch(tools, existing, replace = replace)
      wrapped <- lapply(tools, private$adapt_tool)
      existing[names(wrapped)] <- wrapped
      private$.chat$set_tools(existing)
      invisible(self)
    },

    #' @description Register an additional ellmer tool-request observer.
    #' @param callback A function with one `request` argument.
    #' @return A function that removes the observer.
    on_tool_request = function(callback) {
      remove_backend <- private$.chat$on_tool_request(callback)
      if (!is.function(remove_backend)) {
        remove_backend <- function() invisible(NULL)
      }
      private$.tool_observer_id <- private$.tool_observer_id + 1L
      id <- as.character(private$.tool_observer_id)
      private$.tool_request_observers[[id]] <- callback
      rlang::new_function(
        alist(),
        quote({
          on.exit({
            agent_private$.tool_request_observers[[id]] <- NULL
          })
          remove_backend()
          invisible(NULL)
        }),
        rlang::env(
          remove_backend = remove_backend,
          agent_private = private,
          id = id
        )
      )
    },

    #' @description Register an additional ellmer tool-result observer.
    #' @param callback A function with one `result` argument.
    #' @return A function that removes the observer.
    on_tool_result = function(callback) {
      remove_backend <- private$.chat$on_tool_result(callback)
      if (!is.function(remove_backend)) {
        remove_backend <- function() invisible(NULL)
      }
      private$.tool_observer_id <- private$.tool_observer_id + 1L
      id <- as.character(private$.tool_observer_id)
      private$.tool_result_observers[[id]] <- callback
      rlang::new_function(
        alist(),
        quote({
          on.exit({
            agent_private$.tool_result_observers[[id]] <- NULL
          })
          remove_backend()
          invisible(NULL)
        }),
        rlang::env(
          remove_backend = remove_backend,
          agent_private = private,
          id = id
        )
      )
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
      private$.chat$get_turns()
    },

    #' @description
    #' Get the last turn in the conversation.
    #'
    #' @param role Role to filter by ("assistant", "user", or "system")
    #' @return A Turn object or NULL
    last_turn = function(role = c("assistant", "user", "system")) {
      private$.chat$last_turn(role = match.arg(role))
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
    #' an immutable authority ceiling. When narrowing removes web access,
    #' registered provider-native web tools are removed before the new policy
    #' becomes active because Deputy cannot interpose on provider-side calls.
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

      narrowed_permissions <- Permissions$new(
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

      registered_tools <- private$.chat$get_tools()
      provider_native <- vapply(
        registered_tools,
        inherits,
        logical(1),
        what = "ellmer::ToolBuiltIn"
      )
      removed_provider_tools <- character()
      if (!isTRUE(narrowed_permissions$web) && any(provider_native)) {
        removed_provider_tools <- vapply(
          registered_tools[provider_native],
          \(tool) tool@name,
          character(1)
        )
        private$.chat$set_tools(registered_tools[!provider_native])
      }

      private$.permissions <- narrowed_permissions

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
        permission_mode = mode,
        removed_provider_tools = removed_provider_tools
      )

      invisible(self)
    },

    #' @description
    #' Get cost information for the conversation.
    #'
    #' @return A list with input, output, and cached token counts; total
    #'   estimated cost; and `complete` and `missing` fields describing provider
    #'   cost coverage. An incomplete total is `NA_real_`.
    cost = function() {
      summary <- provider_usage_summary(private$.chat)
      summary[c("input", "output", "cached", "total", "complete", "missing")]
    },

    #' @description
    #' Get normalized usage for the complete in-memory conversation.
    #'
    #' Per-run usage is available on [AgentResult] and in the final `usage`
    #' event returned by `$run()`.
    #'
    #' @return An [AgentUsage] object
    usage = function() {
      agent_usage_snapshot(private$.chat)
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
      provider <- private$.chat$get_provider()
      list(
        name = provider@name,
        model = private$.chat$get_model()
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
    #' - The cumulative compaction summary
    #' - Portable copies of offloaded tool results
    #' - Effective run context
    #' - File checkpoint state, when enabled
    #' - Metadata (timestamp, version, provider info)
    save_session = function(path) {
      tryCatch(
        {
          session <- private$build_session_payload()
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
    #' context; protected identity conflicts fail the load. Compaction summaries
    #' and integrity-checked tool-result envelopes are restored as conversational
    #' state under the receiving Agent's session identity.
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
    #' @param keep_last Number of recent turns to retain. `NULL` chooses a
    #'   complete conversational boundary using the context policy's token
    #'   target.
    #' @param summary Optional custom summary to use instead of auto-generating.
    #'   If NULL, the LLM will generate a summary focusing on key decisions,
    #'   findings, files discussed, and task progress.
    #' @param fallback What to do when LLM summary generation fails.
    #' @param automatic Whether the run kernel triggered this compaction.
    #' @param estimated_tokens Optional pre-compaction token estimate.
    #' @return A `DeputyCompaction` describing the method and usage.
    #'
    #' @details
    #' The compaction process:
    #' 1. Fires the PreCompact hook (can cancel or provide custom summary)
    #' 2. If no custom summary, uses LLM to summarize compacted turns
    #' 3. Appends summary to system prompt under "Previous Conversation Summary"
    #' 4. Keeps only the most recent `keep_last` turns
    #'
    #' LLM summary-generation failures are errors by default. A deterministic
    #' truncated-text summary is used only when `fallback = "text"` is
    #' explicitly configured. The returned object records that degraded method.
    compact = function(
      keep_last = NULL,
      summary = NULL,
      fallback = self$context_policy$fallback,
      automatic = FALSE,
      estimated_tokens = NULL
    ) {
      if (isTRUE(private$run_active) && !isTRUE(automatic)) {
        cli::cli_abort(
          "Cannot compact conversation state while this agent has an active run",
          class = c("deputy_run_active", "deputy_error")
        )
      }
      turns <- private$.chat$get_turns()
      fallback <- match.arg(fallback, c("error", "text"))

      if (is.null(keep_last)) {
        max_tokens <- self$context_policy$max_tokens
        keep_last <- if (is.null(max_tokens)) {
          min(4L, length(turns))
        } else {
          private$compaction_keep_last(
            messages = list(),
            target_tokens = floor(
              max_tokens * self$context_policy$compact_to
            )
          )
        }
      }
      keep_last <- validate_usage_limit(keep_last, "keep_last", integer = TRUE)
      if (is.null(keep_last)) {
        keep_last <- 0L
      }

      if (length(turns) <= keep_last) {
        result <- new_compaction_result(
          method = "none",
          automatic = automatic,
          turns_compacted = 0L,
          turns_kept = length(turns),
          estimated_tokens = estimated_tokens
        )
        private$.last_compaction <- result
        return(result)
      }

      # Determine which turns to compact
      compact_count <- length(turns) - keep_last
      turns_to_compact <- turns[1:compact_count]
      turns_to_keep <- if (keep_last == 0L) {
        list()
      } else {
        tail(turns, keep_last)
      }

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
        result <- new_compaction_result(
          method = "cancelled",
          automatic = automatic,
          turns_compacted = 0L,
          turns_kept = length(turns),
          estimated_tokens = estimated_tokens
        )
        private$.last_compaction <- result
        return(result)
      }

      method <- "custom"
      summary_usage <- AgentUsage()
      if (is.null(summary)) {
        if (!is.null(hook_result) && !is.null(hook_result$summary)) {
          summary <- hook_result$summary
          method <- "hook"
        } else {
          generated <- private$generate_compaction_summary(
            turns_to_compact,
            fallback = fallback
          )
          summary <- generated$summary
          method <- generated$method
          summary_usage <- generated$usage
        }
      }

      summary <- paste(as.character(summary), collapse = "\n")
      current_system <- private$system_prompt_without_compaction()
      new_system <- paste0(
        current_system,
        private$compaction_prompt_block(summary)
      )

      private$.chat$set_system_prompt(new_system)
      private$.chat$set_turns(turns_to_keep)
      private$.compaction_summary <- summary

      result <- new_compaction_result(
        method = method,
        automatic = automatic,
        turns_compacted = compact_count,
        turns_kept = length(turns_to_keep),
        estimated_tokens = estimated_tokens,
        usage = summary_usage,
        summary = summary
      )
      private$.last_compaction <- result
      self$hooks$fire(
        "PostCompact",
        result = result,
        context = private$hook_context(
          total_turns = length(turns),
          compact_count = compact_count,
          automatic = isTRUE(automatic)
        )
      )
      result
    },

    #' @description
    #' Print the agent configuration.
    print = function() {
      provider_info <- self$provider()
      tools <- private$.chat$get_tools()

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
        current_tools <- private$.chat$get_tools()
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

        self$register_tools(skill$tools, replace = allow_conflicts)
      }

      # Append prompt to system prompt
      if (!is.null(skill$prompt) && nchar(skill$prompt) > 0) {
        current_prompt <- private$.chat$get_system_prompt() %||% ""
        new_prompt <- paste(
          current_prompt,
          "",
          paste0("# Skill: ", skill$name),
          skill$prompt,
          sep = "\n"
        )
        private$.chat$set_system_prompt(new_prompt)
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
    #' @param replace Refresh the selected servers' complete tool sets, removing
    #'   obsolete tools, and explicitly replace other matching names. On failure,
    #'   tools whose connections were invalidated are removed; working tools remain.
    #' @return Invisible self for chaining
    load_mcp = function(config = NULL, servers = NULL, replace = FALSE) {
      if (!rlang::is_bool(replace)) {
        tool_registration_error("{.arg replace} must be TRUE or FALSE.")
      }
      # mcptools closes old transports before replacement discovery/validation.
      # Clean up on errors and interrupts as well as normal returns, including
      # failures while publishing a successfully discovered batch.
      on.exit(private$discard_stale_mcp_tools(), add = TRUE)
      loaded <- load_mcp_tools_result(config, servers)
      mcp_tools_list <- loaded$tools
      loaded_at <- Sys.time()

      if (isTRUE(loaded$success)) {
        # Prepare the whole refreshed registry before publishing it. Successful
        # discovery can contain zero tools; working unrelated tools are retained.
        existing <- private$.chat$get_tools()
        removed <- character()
        tryCatch(
          {
            if (replace) {
              from_selected_server <- vapply(
                existing,
                function(tool) {
                  source <- tool_metadata(tool)$source
                  identical(source$type, "mcp") &&
                    source$server %in% loaded$servers
                },
                logical(1)
              )
              removed <- names(existing)[from_selected_server]
              retained <- existing[!from_selected_server]
              incoming <- validate_tool_batch(
                mcp_tools_list,
                retained,
                replace = TRUE
              )
              retained[names(incoming)] <- incoming
              self$set_tools(retained)
            } else {
              self$register_tools(mcp_tools_list)
            }
          },
          error = function(e) {
            private$loaded_mcp_status <- c(
              private$loaded_mcp_status,
              list(list(
                status = "failed",
                config = config,
                servers = loaded$servers,
                tools = character(),
                loaded_at = loaded_at,
                error = conditionMessage(e)
              ))
            )
            cli::cli_abort(c(
              "Failed to register MCP tools",
              "x" = e$message,
              "i" = "Check for tool name conflicts with existing tools"
            ))
          }
        )
        private$loaded_mcp_tools <- setdiff(private$loaded_mcp_tools, removed)
      }

      if (length(mcp_tools_list) > 0) {
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
        private$loaded_mcp_tools <- unique(c(
          private$loaded_mcp_tools,
          tool_names
        ))
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
            status = if (!mcp_available()) {
              "unavailable"
            } else if (loaded$success) {
              "empty"
            } else {
              "failed"
            },
            config = config,
            servers = servers %||% character(),
            tools = character(),
            loaded_at = loaded_at,
            error = loaded$error
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
    #' Run an agentic task asynchronously and resolve to an [AgentResult].
    #'
    #' Uses the same run kernel as `$stream_async()`, `$stream()`, `$chat()`,
    #' and `$run_sync()`. It collects the final response and run metadata rather
    #' than returning the content stream.
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

      governed_run <- private$start_governed_stream(
        messages = list(task),
        limits = limits,
        run_context = effective_run_context,
        stream = "content"
      )
      private$collect_governed_stream(governed_run)
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

    #' @field context_policy Automatic context-management policy. Read-only.
    context_policy = function(value) {
      if (missing(value)) {
        return(private$.context_policy)
      }
      cli_abort(
        "Cannot modify agent: context_policy is immutable after construction"
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
    .context_policy = NULL,
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
    current_run_state = NULL,
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
    original_tool_results = list(),
    last_run_usage = NULL,
    .last_run_result = NULL,
    last_limit_status = NULL,
    last_tool_cycle_signature = NULL,
    consecutive_tool_cycles = 0L,
    .last_compaction = NULL,
    .compaction_summary = NULL,
    .tool_result_reader_registered = FALSE,
    .tool_request_observers = list(),
    .tool_result_observers = list(),
    .tool_observer_id = 0L,
    .r6_clone = NULL,
    current_run_checkpoint_id = NULL,

    clone_client = function(deep = FALSE) {
      invisible(deep)
      cloned <- private$.r6_clone(deep = TRUE)
      cloned$.__enclos_env__$private$rewire_chat_runtime()
      cloned
    },

    deep_clone = function(name, value) {
      if (identical(name, ".chat") && is.function(value$clone)) {
        return(value$clone(deep = TRUE))
      }
      is_r6_object <- is.environment(value) &&
        !is.null(get0(".__enclos_env__", value, inherits = FALSE))
      if (is_r6_object) {
        return(value$clone(deep = TRUE))
      }
      value
    },

    rewire_chat_runtime = function() {
      chat_private <- tryCatch(
        private$.chat$.__enclos_env__$private,
        error = function(e) NULL
      )
      for (name in c("callback_on_tool_request", "callback_on_tool_result")) {
        manager <- chat_private[[name]]
        if (!is.null(manager) && is.function(manager$clear)) {
          manager$clear()
        }
      }

      tools <- private$.chat$get_tools()
      had_result_reader <- "deputy_read_tool_result" %in% names(tools)
      tools[["deputy_read_tool_result"]] <- NULL
      tools <- validate_tool_batch(tools)
      private$.chat$set_tools(lapply(tools, private$prepare_cloned_tool))
      private$.tool_result_reader_registered <- FALSE
      if (isTRUE(had_result_reader)) {
        private$ensure_tool_result_reader()
      }
      private$.chat$on_tool_request(private$handle_tool_request)
      private$.chat$on_tool_result(private$handle_tool_result)
      for (callback in private$.tool_request_observers) {
        private$.chat$on_tool_request(callback)
      }
      for (callback in private$.tool_result_observers) {
        private$.chat$on_tool_result(callback)
      }
      invisible(NULL)
    },

    prepare_cloned_tool = function(tool) {
      private$adapt_tool(tool)
    },

    discard_stale_mcp_tools = function() {
      tools <- private$.chat$get_tools()
      current <- vapply(tools, mcp_tool_is_current, logical(1))
      if (all(current)) {
        return(invisible(NULL))
      }
      removed <- names(tools)[!current]
      # These are already adapted tools; only remove invalidated handles.
      private$.chat$set_tools(tools[current])
      private$loaded_mcp_tools <- setdiff(private$loaded_mcp_tools, removed)
      invisible(NULL)
    },

    new_file_checkpoint_store = function() {
      FileCheckpointStore$new(
        private$.working_dir,
        max_file_bytes = private$.file_checkpoint_config$max_file_bytes,
        max_journal_bytes = private$.file_checkpoint_config$max_journal_bytes
      )
    },

    resolve_tool_arguments = function(tool_name, arguments) {
      resolve_runtime_tool_arguments(
        tool_name,
        arguments,
        private$.working_dir
      )
    },

    adapt_tool = function(tool) {
      if (inherits(tool, "ellmer::ToolBuiltIn")) {
        tool_name <- tryCatch(tool@name, error = function(error) NULL)
        tool_id <- normalize_native_tool_id(tool_name %||% "")
        if (!tool_id %in% c("web_search", "web_fetch")) {
          cli_abort(c(
            "Unsupported provider-native tool: {.val {tool_name %||% '<unknown>'}}",
            "x" = paste0(
              "Deputy cannot interpose on provider-side execution for this ",
              "tool."
            )
          ))
        }
        if (!isTRUE(self$permissions$web)) {
          cli_abort(c(
            "Provider-native web tool {.val {tool_name}} is not authorized.",
            "i" = "Set {.code web = TRUE} and explicitly allow the tool."
          ))
        }
        allowlist <- self$permissions$tool_allowlist %||% character()
        allowlist_ids <- unique(vapply(
          allowlist,
          normalize_native_tool_id,
          character(1)
        ))
        if (!tool_id %in% allowlist_ids) {
          cli_abort(c(
            "Provider-native web tool {.val {tool_name}} is not explicitly allowed.",
            "i" = "Add the tool name to {.arg tool_allowlist}."
          ))
        }
        if (!is.null(self$permissions$can_use_tool)) {
          cli_abort(c(
            "Provider-native tool {.val {tool_name}} cannot use a custom permission callback.",
            "x" = paste0(
              "Provider-side requests cannot be checked against request ",
              "arguments or run context."
            ),
            "i" = paste0(
              "Remove {.arg can_use_tool} or use Deputy's universal ",
              "function tool."
            )
          ))
        }
        permission <- self$permissions$check(
          tool_name,
          list(),
          list(
            working_dir = private$.working_dir,
            tool_annotations = tool@annotations
          )
        )
        if (inherits(permission, "PermissionResultDeny")) {
          cli_abort(c(
            "Provider-native tool {.val {tool_name}} was denied at registration.",
            "x" = permission$reason,
            "i" = paste0(
              "Provider-native tools are authorized before a request because ",
              "they execute inside the provider."
            )
          ))
        }
        return(tool)
      }
      runtime_wrap_tool(
        tool,
        resolve_arguments = if (
          identical(tool_metadata(tool)$source$type, "mcp")
        ) {
          function(tool_name, arguments) arguments
        } else {
          private$resolve_tool_arguments
        },
        process_result = private$offload_tool_result,
        begin_execution = private$begin_tool_execution,
        execute = private$execute_tool
      )
    },

    execute_tool = function(tool, arguments) {
      workspace_runner <- attr(
        tool,
        "deputy_workspace_runner",
        exact = TRUE
      )
      if (is.function(workspace_runner)) {
        return(workspace_runner(arguments, private$.working_dir))
      }
      do.call(tool, arguments)
    },

    offload_tool_result = function(tool_name, value, execution_id = NULL) {
      if (identical(tool_name, "deputy_read_tool_result")) {
        return(value)
      }
      record <- offload_tool_result(
        value = value,
        tool_name = tool_name,
        policy = private$.context_policy,
        session_id = private$.session_id,
        agent_id = private$.agent_id
      )
      if (is.null(record)) {
        return(value)
      }
      private$ensure_tool_result_reader()
      private$notify(
        paste0("Offloaded large result from ", tool_name, "."),
        level = "info",
        code = "tool_result_offloaded",
        tool_name = tool_name,
        result_reference = record$uri,
        result_bytes = record$bytes,
        result_sha256 = record$sha256
      )
      if (is_nonempty_string(execution_id)) {
        private$original_tool_results[[execution_id]] <- value
      }
      tool_result_reference_text(record)
    },

    ensure_tool_result_reader = function() {
      if (isTRUE(private$.tool_result_reader_registered)) {
        return(invisible(NULL))
      }
      private$.chat$register_tool(
        private$adapt_tool(tool_result_reader_tool(
          private$read_tool_result_chunk
        ))
      )
      private$.tool_result_reader_registered <- TRUE
      invisible(NULL)
    },

    read_tool_result_chunk = function(reference, offset, max_chars) {
      read_tool_result_chunk(
        reference = reference,
        offset = offset,
        max_chars = max_chars,
        policy = private$.context_policy,
        session_id = private$.session_id
      )
    },

    record_run_event = function(event) {
      state <- private$current_run_state
      if (!is.null(state)) {
        state$events[[length(state$events) + 1L]] <- event
      }
      invisible(event)
    },

    start_async_stream = function(
      messages,
      tool_mode,
      stream,
      controller,
      structured = NULL
    ) {
      if (!is.null(structured)) {
        return(do.call(
          private$.chat$chat_structured_async,
          c(messages, structured)
        ))
      }
      stream_fun <- private$.chat$stream_async
      stream_formals <- names(formals(stream_fun))
      args <- messages
      if ("tool_mode" %in% stream_formals) {
        args$tool_mode <- tool_mode
      }
      if ("stream" %in% stream_formals) {
        args$stream <- stream
      }
      if (
        !is.null(controller) &&
          "controller" %in% stream_formals
      ) {
        args$controller <- controller
      }
      do.call(stream_fun, args)
    },

    start_governed_stream = function(
      messages,
      limits,
      run_context,
      tool_mode = "concurrent",
      stream = "content",
      controller = NULL,
      structured = NULL
    ) {
      if (isTRUE(private$run_active)) {
        cli::cli_abort(
          "This agent already has an active run",
          class = c("deputy_run_active", "deputy_error")
        )
      }
      limits <- normalize_usage_limits(limits)
      state <- private$new_callback_run_state()
      governed <- private$callback_run_stream(
        messages = messages,
        limits = limits,
        run_context = run_context,
        tool_mode = tool_mode,
        stream_mode = stream,
        controller = controller,
        structured = structured,
        state = state
      )
      agent <- self
      reg.finalizer(
        environment(governed),
        function(environment) {
          if (
            !isTRUE(state$finished) &&
              !is.null(state$active_run_id)
          ) {
            state$reason <- "abandoned"
            try(
              agent$.__enclos_env__$private$request_stream_stop("abandoned"),
              silent = TRUE
            )
            try(
              agent$.__enclos_env__$private$finish_callback_run(state),
              silent = TRUE
            )
          }
        },
        onexit = TRUE
      )
      list(stream = governed, state = state, limits = limits)
    },

    collect_governed_stream = function(governed_run) {
      stream <- governed_run$stream
      state <- governed_run$state
      coro::async(function() {
        repeat {
          chunk <- coro::await(stream())
          if (coro::is_exhausted(chunk)) {
            break
          }
        }
        result <- state$result
        if (is.null(result)) {
          cli_abort("The governed run ended without an AgentResult")
        }
        result
      })()
    },

    echo_chat_result = function(response, echo) {
      if (is.null(echo)) {
        echo <- getOption("ellmer_echo", "none")
      }
      if (isTRUE(echo)) {
        echo <- "output"
      } else if (isFALSE(echo)) {
        echo <- "none"
      } else if (identical(echo, "text")) {
        echo <- "output"
      }
      echo <- match.arg(echo, c("none", "output", "all"))
      if (!identical(echo, "none") && !is.null(response)) {
        cli::cli_text("{response}")
      }
      invisible(NULL)
    },

    resolve_promise = function(promise) {
      if (!promises::is.promising(promise)) {
        return(promise)
      }
      value <- NULL
      error <- NULL
      done <- FALSE
      promise |>
        promises::then(function(result) {
          value <<- result
          done <<- TRUE
        }) |>
        promises::catch(function(condition) {
          error <<- condition
          done <<- TRUE
        })
      while (!done) {
        run_now(0.1)
      }
      if (!is.null(error)) {
        rlang::cnd_signal(error)
      }
      value
    },

    sync_stream_generator = function(async_stream) {
      agent <- self
      coro::generator(function() {
        repeat {
          chunk <- agent$.__enclos_env__$private$resolve_promise(
            async_stream()
          )
          if (coro::is_exhausted(chunk)) {
            break
          }
          coro::yield(chunk)
        }
      })()
    },

    event_generator = function(
      governed_run,
      include_partial_messages
    ) {
      agent <- self
      async_stream <- governed_run$stream
      state <- governed_run$state
      coro::generator(function() {
        next_event <- 1L
        exhausted <- FALSE
        repeat {
          while (next_event <= length(state$events)) {
            event <- state$events[[next_event]]
            next_event <- next_event + 1L
            if (
              isTRUE(include_partial_messages) ||
                !identical(event$type, "text")
            ) {
              coro::yield(event)
            }
          }
          if (isTRUE(exhausted)) {
            break
          }
          chunk <- agent$.__enclos_env__$private$resolve_promise(
            async_stream()
          )
          exhausted <- coro::is_exhausted(chunk)
        }
      })()
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

    # Shared state for one governed callback-driven run.
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
      state$events <- list()
      state$response_parts <- character()
      state$structured_output <- NULL
      state$started_at <- Sys.time()
      state$run_context <- list()
      state$limits <- NULL
      state$result <- NULL
      state$turns_before <- 0L
      state
    },

    # Assemble the `AgentResult` for a finished `run_async()` run. Honors
    # `on_exceed = "error"` by signalling the structured limit error when the
    # run stopped because of the recorded limit.
    callback_run_result = function(state) {
      response <- if (length(state$response_parts) > 0L) {
        paste(state$response_parts, collapse = "")
      } else if (
        identical(state$reason, "complete") &&
          length(private$.chat$get_turns()) > state$turns_before
      ) {
        tryCatch(private$get_last_response(), error = function(e) NULL)
      } else {
        NULL
      }

      limit_status <- private$last_limit_status
      if (
        !is.null(limit_status) &&
          identical(state$limits$on_exceed, "error") &&
          identical(state$reason, limit_status$reason)
      ) {
        private$abort_usage_limit(limit_status)
      }

      AgentResult$new(
        response = response,
        turns = private$.chat$get_turns(),
        cost = state$cost %||% self$cost(),
        events = state$events,
        duration = as.numeric(Sys.time() - state$started_at, units = "secs"),
        stop_reason = state$reason %||% "complete",
        structured_output = state$structured_output,
        session_id = private$.session_id,
        run_id = state$active_run_id,
        agent_id = self$agent_id,
        agent_name = self$agent_name,
        parent_agent_id = private$.parent_agent_id,
        parent_run_id = private$.parent_run_id,
        delegation_id = private$.delegation_id,
        run_context = state$run_context,
        usage = state$usage %||% AgentUsage()
      )
    },

    # The single run kernel. Every public run interface is an adapter
    # over this lazily-started governed stream.
    callback_run_stream = function(
      messages,
      limits,
      run_context,
      tool_mode,
      stream_mode,
      controller,
      structured,
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

        compaction <- agent$.__enclos_env__$private$maybe_auto_compact(
          messages,
          limits = run_limits,
          usage = AgentUsage()
        )
        compaction_usage <- AgentUsage()
        if (!is.null(compaction)) {
          compaction_usage <- compaction$usage
        }

        agent$.__enclos_env__$private$run_active <- TRUE
        agent$.__enclos_env__$private$current_run_id <-
          agent$.__enclos_env__$private$new_run_id()
        agent$.__enclos_env__$private$current_run_context <-
          effective_run_context
        active_run_id <- agent$.__enclos_env__$private$current_run_id
        stream_state$active_run_id <- active_run_id
        stream_state$run_context <- effective_run_context
        stream_state$limits <- run_limits
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
          agent_usage_snapshot(agent$.__enclos_env__$private$.chat)
        stream_state$turns_before <- length(
          agent$.__enclos_env__$private$.chat$get_turns()
        )
        agent$.__enclos_env__$private$current_tool_calls <- 0L
        agent$.__enclos_env__$private$current_tool_results <- 0L
        agent$.__enclos_env__$private$current_outer_requests <- 0L
        agent$.__enclos_env__$private$current_external_usage <- compaction_usage
        agent$.__enclos_env__$private$current_stream_controller <-
          controller %||%
          tryCatch(
            ellmer::stream_controller(),
            error = function(e) NULL
          )
        agent$.__enclos_env__$private$current_stream_content <-
          identical(stream_mode, "content")
        agent$.__enclos_env__$private$current_run_state <- stream_state
        agent$.__enclos_env__$private$pending_events <- list()
        agent$.__enclos_env__$private$tool_started_at <- list()
        agent$.__enclos_env__$private$tool_event_overrides <- list()
        agent$.__enclos_env__$private$tool_call_records <- list()
        agent$.__enclos_env__$private$pending_delegations <- list()
        agent$.__enclos_env__$private$original_tool_results <- list()
        agent$.__enclos_env__$private$last_limit_status <- NULL
        agent$.__enclos_env__$private$last_tool_cycle_signature <- NULL
        agent$.__enclos_env__$private$consecutive_tool_cycles <- 0L
        agent$.__enclos_env__$private$last_run_usage <- AgentUsage()
        agent$.__enclos_env__$private$current_run_checkpoint_id <- NULL

        if (!is.null(agent$.__enclos_env__$private$.file_checkpoints)) {
          checkpoint_id <- agent$.__enclos_env__$private$.file_checkpoints$checkpoint(
            paste0("run ", active_run_id),
            metadata = list(
              run_id = active_run_id,
              message_count = length(messages)
            )
          )
          agent$.__enclos_env__$private$current_run_checkpoint_id <-
            checkpoint_id
        }

        task <- messages
        if (length(messages) == 1L) {
          task <- messages[[1L]]
        }
        agent$.__enclos_env__$private$record_run_event(
          agent$.__enclos_env__$private$agent_event(
            "start",
            task = task,
            usage_limits = run_limits,
            checkpoint_id = agent$.__enclos_env__$private$current_run_checkpoint_id
          )
        )
        if (
          !is.null(
            agent$.__enclos_env__$private$current_run_checkpoint_id
          )
        ) {
          agent$.__enclos_env__$private$record_run_event(
            agent$.__enclos_env__$private$agent_event(
              "file_checkpoint",
              checkpoint_id = agent$.__enclos_env__$private$current_run_checkpoint_id,
              name = paste0("run ", active_run_id)
            )
          )
        }

        agent$hooks$fire(
          "SessionStart",
          context = agent$.__enclos_env__$private$hook_context(
            permissions = agent$permissions,
            provider = agent$provider(),
            tools_count = length(agent$.__enclos_env__$private$.chat$get_tools()),
            run_id = active_run_id
          )
        )
        stream_state$session_started <- TRUE
        agent$hooks$fire(
          "UserPromptSubmit",
          prompt = if (length(messages) == 1L) messages[[1L]] else messages,
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
            agent$.__enclos_env__$private$start_async_stream(
              messages = messages,
              tool_mode = tool_mode,
              stream = stream_mode,
              controller = agent$.__enclos_env__$private$current_stream_controller,
              structured = structured
            ),
            error = function(error) {
              stream_state$reason <- "error"
              rlang::cnd_signal(error)
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
            rlang::cnd_signal(stream_error)
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

          if (!is.null(structured)) {
            stream_state$structured_output <- chunk
          }

          if (inherits(chunk, "ellmer::ContentToolRequest")) {
            extracted <- agent$.__enclos_env__$private$extract_tool_request_data(
              chunk
            )
            agent$.__enclos_env__$private$record_run_event(
              agent$.__enclos_env__$private$tool_start_event(extracted)
            )
          } else if (inherits(chunk, "ellmer::ContentToolResult")) {
            stream_state$response_parts <- character()
          } else if (inherits(chunk, "ellmer::ContentText")) {
            stream_state$response_parts <- c(
              stream_state$response_parts,
              chunk@text
            )
            agent$.__enclos_env__$private$record_run_event(
              AgentEvent(
                "text",
                run_id = active_run_id,
                text = chunk@text,
                is_complete = FALSE
              )
            )
          } else if (is.character(chunk) && length(chunk) == 1L) {
            stream_state$response_parts <- c(
              stream_state$response_parts,
              chunk
            )
            agent$.__enclos_env__$private$record_run_event(
              AgentEvent(
                "text",
                run_id = active_run_id,
                text = chunk,
                is_complete = FALSE
              )
            )
          } else if (
            !inherits(chunk, "ellmer::ContentToolRequest") &&
              !inherits(chunk, "ellmer::ContentToolResult")
          ) {
            agent$.__enclos_env__$private$record_run_event(
              AgentEvent(
                "content",
                run_id = active_run_id,
                content = chunk,
                content_type = class(chunk)[[1L]] %||% "unknown"
              )
            )
          }

          coro::yield(chunk)
          if (!isTRUE(is_generator)) {
            break
          }
        }
      })()
    },

    # Terminal accounting for a callback-driven run: settles the stop reason,
    # fires Stop/SessionEnd, records
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
          observed_last_turn <- tryCatch(
            private$.chat$last_turn(),
            error = function(e) NULL
          )
          if (
            isTRUE(private$should_stop) && identical(state$reason, "complete")
          ) {
            state$reason <- private$stop_reason_from_hook %||%
              "hook_requested_stop"
          }
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
          if (
            is.null(private$last_limit_status) &&
              !is.null(limits$max_cost_usd) &&
              is.finite(usage$cost_usd) &&
              usage$cost_usd >= limits$max_cost_usd * 0.9
          ) {
            private$notify(
              paste0(
                "Approaching run cost limit: ",
                format_cost(usage$cost_usd),
                " / ",
                format_cost(limits$max_cost_usd)
              ),
              level = "warning",
              code = "cost_limit_warning",
              usage = usage,
              max_cost_usd = limits$max_cost_usd
            )
            cli::cli_warn(
              "Approaching run cost limit: {format_cost(usage$cost_usd)} / {format_cost(limits$max_cost_usd)}"
            )
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

          if (length(state$response_parts) > 0L) {
            private$record_run_event(AgentEvent(
              "text_complete",
              run_id = active_run_id,
              text = paste(state$response_parts, collapse = "")
            ))
          }
          current_turn_count <- length(private$.chat$get_turns())
          if (current_turn_count > state$turns_before) {
            last_turn <- observed_last_turn
          } else {
            last_turn <- NULL
          }
          if (!is.null(last_turn)) {
            private$record_run_event(private$agent_event(
              "turn",
              turn = last_turn,
              turn_number = max(1L, usage$requests)
            ))
          }
          private$record_run_event(private$agent_event(
            "usage",
            usage = usage,
            limits = limits
          ))
          private$record_run_event(private$agent_event(
            "stop",
            reason = state$reason,
            cost = state$cost,
            usage = usage,
            limit = private$last_limit_status
          ))
          state$result <- private$callback_run_result(state)
          private$.last_run_result <- state$result
        },
        error = function(error) {
          cleanup_error <<- error
        }
      )

      private$tool_call_limit <- NULL
      private$tool_call_count <- 0L
      private$last_tool_cycle_signature <- NULL
      private$consecutive_tool_cycles <- 0L
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
      private$current_run_state <- NULL
      private$pending_events <- list()
      private$tool_started_at <- list()
      private$tool_event_overrides <- list()
      private$tool_call_records <- list()
      private$pending_delegations <- list()
      private$original_tool_results <- list()
      private$last_tool_cycle_signature <- NULL
      private$consecutive_tool_cycles <- 0L
      if (!is.null(private$current_run_context)) {
        private$last_run_context <- clone_run_context(
          private$current_run_context
        )
      }
      private$current_run_context <- NULL
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
        schema_version = 2L,
        turns = private$.chat$get_turns(),
        system_prompt = private$.chat$get_system_prompt(),
        compaction_summary = private$.compaction_summary,
        tool_result_envelopes = collect_tool_result_envelopes(
          private$.context_policy,
          private$.session_id
        ),
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

      if (!"schema_version" %in% names(session)) {
        abort_session_load(
          c(
            "Invalid session file - missing required fields",
            "x" = "Missing: schema_version"
          ),
          path = source
        )
      }

      if (!identical(session$schema_version, 2L)) {
        abort_session_load(
          "Unsupported session schema - expected version 2",
          path = source
        )
      }

      required_fields <- c(
        "turns",
        "system_prompt",
        "compaction_summary",
        "tool_result_envelopes",
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
      if (
        !is.null(session$compaction_summary) &&
          (!is.character(session$compaction_summary) ||
            length(session$compaction_summary) != 1L ||
            is.na(session$compaction_summary))
      ) {
        abort_session_load(
          "Invalid session file - compaction_summary must be one string or NULL",
          path = source
        )
      }

      restored_tool_results <- tryCatch(
        validate_tool_result_envelopes(
          session$tool_result_envelopes,
          metadata$session_id
        ),
        error = function(error) {
          abort_session_load(
            c(
              "Invalid session file - saved tool results failed validation",
              "x" = error$message
            ),
            path = source,
            parent = error
          )
        }
      )

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

      previous_turns <- private$.chat$get_turns()
      previous_prompt <- private$.chat$get_system_prompt()
      previous_tools <- private$.chat$get_tools()
      previous_reader_registered <- private$.tool_result_reader_registered
      tool_result_replacement <- NULL
      tryCatch(
        {
          tool_result_replacement <- begin_tool_result_envelope_replacement(
            restored_tool_results,
            policy = private$.context_policy,
            source_session_id = metadata$session_id,
            target_session_id = private$.session_id
          )
          private$.chat$set_turns(session$turns)
          private$.chat$set_system_prompt(session$system_prompt)
          if (length(restored_tool_results) > 0L) {
            private$ensure_tool_result_reader()
          }
          commit_tool_result_envelope_replacement(tool_result_replacement)
        },
        error = function(error) {
          try(private$.chat$set_turns(previous_turns), silent = TRUE)
          try(private$.chat$set_system_prompt(previous_prompt), silent = TRUE)
          try(private$.chat$set_tools(previous_tools), silent = TRUE)
          private$.tool_result_reader_registered <- previous_reader_registered
          if (!is.null(tool_result_replacement)) {
            try(
              rollback_tool_result_envelope_replacement(
                tool_result_replacement
              ),
              silent = TRUE
            )
          }
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
      private$.compaction_summary <- session$compaction_summary
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
          execution_started = FALSE,
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

    begin_tool_execution = function(tool_name) {
      records <- private$tool_call_records
      matches <- which(vapply(
        records,
        function(record) {
          identical(record$tool_name, tool_name) &&
            isTRUE(record$request_seen) &&
            !isTRUE(record$result_seen) &&
            !isTRUE(record$execution_started)
        },
        logical(1)
      ))
      if (length(matches) == 0L) {
        return(NULL)
      }

      index <- matches[[1L]]
      records[[index]]$execution_started <- TRUE
      private$tool_call_records <- records
      records[[index]]$tool_call_id
    },

    claim_original_tool_result = function(tool_call_id, fallback) {
      if (
        !is_nonempty_string(tool_call_id) ||
          !tool_call_id %in% names(private$original_tool_results)
      ) {
        return(fallback)
      }
      value <- private$original_tool_results[[tool_call_id]]
      private$original_tool_results[[tool_call_id]] <- NULL
      value
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

    current_run_usage = function() {
      baseline <- private$current_usage_baseline %||% AgentUsage()
      current <- agent_usage_snapshot(private$.chat)
      requests <- max(
        current$requests - baseline$requests,
        private$current_outer_requests
      )
      usage <- agent_usage_difference(
        current,
        baseline,
        tool_calls = private$current_tool_calls,
        requests = requests
      )
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
      if (identical(status$reason, "cost_unavailable")) {
        abort_cost_unavailable(
          message,
          max_cost = status$limit,
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
    handle_tool_request = function(request) {
      # Validate and extract request data safely
      extracted <- private$extract_tool_request_data(request)
      if (!is.null(extracted$tool_identity_error)) {
        ellmer::tool_reject(extracted$tool_identity_error)
      }
      tool_name <- extracted$tool_name
      tool_input <- extracted$tool_input
      tool_annotations <- extracted$tool_annotations
      provider_tool_call_id <- extracted$provider_tool_call_id

      private$current_tool_calls <- private$current_tool_calls + 1L
      record <- private$tool_call_record(extracted, "request")
      extracted$tool_call_id <- record$tool_call_id
      private$tool_call_records[[record$record_index]]$request_signature <-
        tool_request_signature(tool_name, tool_input)
      if (!isTRUE(record$start_seen)) {
        private$record_run_event(private$tool_start_event(extracted))
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

      # Retain the adapter-specific counter for callers that configure it
      # directly. The governed run limit above counts all requests.
      if (!is.null(private$tool_call_limit)) {
        private$tool_call_count <- private$tool_call_count + 1L
        if (private$tool_call_count > private$tool_call_limit) {
          private$request_stream_stop("tool_call_limit")
          message <- paste0(
            "Tool call limit reached. Please provide your final answer with ",
            "the information gathered so far."
          )
          private$notify(
            message,
            level = "warning",
            code = "tool_call_limit"
          )
          ellmer::tool_reject(message)
        }
      }

      file_info <- if (identical(extracted$tool_metadata$source$type, "mcp")) {
        NULL
      } else {
        private$file_tool_path_info(tool_name, tool_input)
      }
      context <- private$hook_context(
        tool_annotations = tool_annotations,
        tool_metadata = extracted$tool_metadata,
        tool_call_id = record$tool_call_id,
        permission_mode = self$permissions$mode,
        usage = usage,
        usage_limits = limits,
        delegation_id = record$delegation_id
      )

      # Deputy's session-local result reader is not part of the configured tool
      # surface. Its private marker exempts only the allowlist gate; ordinary
      # denylist, callback, mode, and capability checks still apply.
      permission_context <- context
      permission_context$.deputy_internal_tool <- extracted$internal_tool
      perm_result <- self$permissions$check(
        tool_name,
        tool_input,
        permission_context
      )

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
    handle_tool_result = function(result) {
      # Validate and extract tool result data safely
      # ContentToolResult (S7) has: value, error, extra, request
      # request is ContentToolRequest with: id, name, arguments, tool, extra
      extracted <- private$extract_tool_result_data(result)
      private$current_tool_results <- private$current_tool_results + 1L
      record <- private$tool_call_record(extracted, "result")
      extracted$tool_call_id <- record$tool_call_id
      hook_tool_result <- private$claim_original_tool_result(
        record$tool_call_id,
        extracted$tool_result
      )

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
        tool_result = hook_tool_result,
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
          tool_result = hook_tool_result,
          tool_error = extracted$tool_error,
          context = context
        )
      }

      private$record_run_event(private$tool_end_event(extracted))

      record_state <- private$tool_call_records[[record$record_index]]
      request_signature <- record_state$request_signature
      cycle_signature <- if (is.null(request_signature)) {
        NULL
      } else {
        tool_cycle_signature(
          request_signature,
          hook_tool_result,
          extracted$tool_error
        )
      }
      if (is.null(cycle_signature)) {
        private$last_tool_cycle_signature <- NULL
        private$consecutive_tool_cycles <- 0L
      } else {
        loop <- advance_tool_loop(
          signature = cycle_signature,
          last_signature = private$last_tool_cycle_signature,
          consecutive_calls = private$consecutive_tool_cycles
        )
        private$last_tool_cycle_signature <- loop$signature
        private$consecutive_tool_cycles <- loop$consecutive_calls
        if (isTRUE(loop$stalled) && !isTRUE(private$should_stop)) {
          message <- paste0(
            "Tool request `",
            extracted$tool_name,
            "` completed with the same result ",
            loop$consecutive_calls,
            " times without progress."
          )
          private$request_stream_stop("tool_loop")
          private$notify(
            message,
            level = "warning",
            code = "tool_loop",
            tool_name = extracted$tool_name,
            repeated = loop$consecutive_calls
          )
        }
      }

      # ellmer may make another provider request after this tool result. Check
      # the complete context again while the run is between provider turns.
      if (!isTRUE(private$should_stop)) {
        private$maybe_auto_compact(messages = list())
      }

      invisible(NULL)
    },

    # Safely extract data from an ellmer tool request.
    extract_tool_request_data = function(request) {
      # Default values if extraction fails
      tool_name <- "unknown"
      tool_input <- list()
      tool_annotations <- NULL
      internal_tool <- NULL
      provider_tool_call_id <- NULL
      tool_identity_error <- NULL

      # Check if we have a valid request object
      if (is.null(request)) {
        cli_warn("Tool request callback received NULL request")
        return(list(
          tool_name = tool_name,
          tool_input = tool_input,
          tool_annotations = tool_annotations,
          internal_tool = internal_tool,
          provider_tool_call_id = provider_tool_call_id,
          tool_identity_error = tool_request_identity_error(request)
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
          internal_tool = internal_tool,
          provider_tool_call_id = provider_tool_call_id,
          tool_identity_error = tool_request_identity_error(request)
        ))
      }

      # Extract from S7 object with error handling
      # Tool name
      request_name <- read_tool_request_name(request)
      tool_name <- request_name$value
      tool_identity_error <- request_name$error

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

      # Resolve annotations from the registered executable. Providers may omit
      # the tool object or attach a stale copy to the request.
      registered_tool <- private$.chat$get_tools()[[tool_name]]
      metadata <- if (is.null(registered_tool)) {
        NULL
      } else {
        tool_metadata(registered_tool)
      }
      tool_annotations <- tryCatch(
        {
          if (!is.null(registered_tool)) {
            registered_tool@annotations
          } else {
            NULL
          }
        },
        error = function(e) {
          # Annotations are optional, don't warn
          NULL
        }
      )
      internal_tool <- tryCatch(
        {
          if (is.null(registered_tool)) {
            NULL
          } else {
            attr(registered_tool, "deputy_internal_tool", exact = TRUE)
          }
        },
        error = function(e) NULL
      )

      list(
        tool_name = tool_name,
        tool_input = tool_input,
        tool_annotations = tool_annotations,
        tool_metadata = metadata,
        internal_tool = internal_tool,
        provider_tool_call_id = provider_tool_call_id,
        tool_identity_error = tool_identity_error
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

      current_prompt <- private$.chat$get_system_prompt() %||% ""
      private$.chat$set_system_prompt(paste(
        current_prompt,
        "",
        "# Hook Additional Context",
        context_text,
        sep = "\n"
      ))

      invisible(NULL)
    },

    # Create a true coro generator for streaming events

    get_last_response = function() {
      last <- private$.chat$last_turn()
      if (is.null(last)) {
        return(NULL)
      }
      last@text
    },

    compaction_prompt_parts = function(prompt) {
      if (
        !is.character(prompt) ||
          length(prompt) != 1L ||
          is.na(prompt)
      ) {
        return(NULL)
      }
      start_pattern <- paste0(
        "\\n\\n<!-- deputy-compaction-summary:v1 chars=([0-9]+) ",
        "sha256=([a-f0-9]{64}) -->\\n",
        "## Previous Conversation Summary\\n"
      )
      start <- regexec(start_pattern, prompt, perl = TRUE)[[1L]]
      captured <- regmatches(prompt, list(start))[[1L]]
      if (length(captured) != 3L) {
        return(NULL)
      }
      summary_chars <- suppressWarnings(as.numeric(captured[[2L]]))
      if (
        length(summary_chars) != 1L ||
          is.na(summary_chars) ||
          !is.finite(summary_chars) ||
          summary_chars < 0 ||
          summary_chars != floor(summary_chars)
      ) {
        return(NULL)
      }

      summary_start <- start[[1L]] + attr(start, "match.length")[[1L]]
      summary_end <- summary_start + summary_chars - 1
      summary <- if (summary_chars == 0) {
        ""
      } else {
        substr(prompt, summary_start, summary_end)
      }
      if (
        !identical(
          digest::digest(summary, algo = "sha256", serialize = FALSE),
          captured[[3L]]
        )
      ) {
        return(NULL)
      }

      end_marker <- paste0(
        "\n\n## End Previous Conversation Summary\n",
        "<!-- deputy-compaction-summary:v1:end -->"
      )
      end_start <- summary_start + summary_chars
      end_end <- end_start + nchar(end_marker, type = "chars") - 1
      if (!identical(substr(prompt, end_start, end_end), end_marker)) {
        return(NULL)
      }

      before <- substr(prompt, 1L, start[[1L]] - 1L)
      after_start <- end_end + 1
      after <- if (after_start > nchar(prompt)) {
        ""
      } else {
        substr(prompt, after_start, nchar(prompt))
      }
      list(before = before, summary = summary, after = after)
    },

    compaction_prompt_block = function(summary) {
      paste0(
        "\n\n<!-- deputy-compaction-summary:v1 chars=",
        nchar(summary, type = "chars"),
        " sha256=",
        digest::digest(summary, algo = "sha256", serialize = FALSE),
        " -->\n## Previous Conversation Summary\n",
        summary,
        "\n\n## End Previous Conversation Summary\n",
        "<!-- deputy-compaction-summary:v1:end -->"
      )
    },

    system_prompt_without_compaction = function() {
      prompt <- private$.chat$get_system_prompt() %||% ""
      if (is.null(private$.compaction_summary)) {
        return(prompt)
      }
      parts <- private$compaction_prompt_parts(prompt)
      if (
        is.null(parts) ||
          !identical(parts$summary, private$.compaction_summary)
      ) {
        return(prompt)
      }
      paste0(parts$before, parts$after)
    },

    context_token_count = function(messages, turns = NULL) {
      chat <- private$.chat
      if (!is.null(turns)) {
        chat <- tryCatch(chat$clone(deep = TRUE), error = function(e) NULL)
        if (is.null(chat) || identical(chat, private$.chat)) {
          return(NULL)
        }
        turns_set <- tryCatch(
          {
            chat$set_turns(turns)
            TRUE
          },
          error = function(e) FALSE
        )
        if (!isTRUE(turns_set)) {
          return(NULL)
        }
      }

      count <- tryCatch(
        do.call(
          chat$token_count,
          c(messages, list(include = "complete"))
        ),
        error = function(e) NULL
      )
      if (!is.numeric(count) || length(count) == 0L || anyNA(count)) {
        return(NULL)
      }
      as.numeric(sum(count))
    },

    is_human_turn = function(turn) {
      if (!inherits(turn, "ellmer::UserTurn")) {
        return(FALSE)
      }
      contents <- tryCatch(turn@contents, error = function(e) list())
      !any(vapply(
        contents,
        inherits,
        logical(1),
        what = "ellmer::ContentToolResult"
      ))
    },

    has_tool_request = function(turn) {
      if (!inherits(turn, "ellmer::AssistantTurn")) {
        return(FALSE)
      }
      contents <- tryCatch(turn@contents, error = function(e) list())
      any(vapply(
        contents,
        inherits,
        logical(1),
        what = "ellmer::ContentToolRequest"
      ))
    },

    compaction_keep_last = function(messages, target_tokens) {
      turns <- private$.chat$get_turns()
      if (length(turns) == 0L) {
        return(0L)
      }

      starts <- which(vapply(turns, private$is_human_turn, logical(1)))
      minimum_keep <- 0L
      if (
        isTRUE(private$run_active) &&
          private$has_tool_request(tail(turns, 1L)[[1L]])
      ) {
        recent_human <- tail(starts, 1L)
        minimum_keep <- if (length(recent_human) == 0L) {
          1L
        } else {
          length(turns) - recent_human + 1L
        }
      }
      candidates <- unique(c(starts, length(turns) + 1L))
      for (start in candidates) {
        kept <- if (start > length(turns)) {
          list()
        } else {
          turns[start:length(turns)]
        }
        if (length(kept) < minimum_keep) {
          next
        }
        count <- private$context_token_count(messages, turns = kept)
        if (!is.null(count) && count <= target_tokens) {
          return(as.integer(length(kept)))
        }
      }

      # A conservative fallback for providers that cannot estimate cloned
      # contexts. Keep a complete recent user/assistant exchange when possible.
      recent <- tail(starts, 1L)
      if (length(recent) == 0L) {
        return(as.integer(minimum_keep))
      }
      as.integer(max(minimum_keep, length(turns) - recent + 1L))
    },

    maybe_auto_compact = function(messages, limits = NULL, usage = NULL) {
      policy <- private$.context_policy
      if (is.null(policy$max_tokens)) {
        return(NULL)
      }
      turns <- private$.chat$get_turns()
      if (length(turns) == 0L) {
        return(NULL)
      }

      if (is.null(limits) && isTRUE(private$run_active)) {
        limits <- private$current_usage_limits
      }
      if (!is.null(limits)) {
        if (is.null(usage)) {
          usage <- if (isTRUE(private$run_active)) {
            private$current_run_usage()
          } else {
            AgentUsage()
          }
        }
        limit_status <- usage_limit_status(
          usage,
          limits,
          require_followup = TRUE
        )
        if (!is.null(limit_status)) {
          if (isTRUE(private$run_active)) {
            private$mark_usage_limit(limit_status)
          }
          return(NULL)
        }
      }

      estimated <- private$context_token_count(messages)
      if (is.null(estimated) || estimated <= policy$max_tokens) {
        return(NULL)
      }

      keep_last <- private$compaction_keep_last(
        messages = messages,
        target_tokens = floor(policy$max_tokens * policy$compact_to)
      )
      result <- self$compact(
        keep_last = keep_last,
        fallback = policy$fallback,
        automatic = TRUE,
        estimated_tokens = estimated
      )
      if (isTRUE(private$run_active)) {
        private$add_external_usage(result$usage)
      }
      result
    },

    # Generate a summary of turns using the LLM
    generate_compaction_summary = function(turns, fallback = "error") {
      fallback <- match.arg(fallback, c("error", "text"))
      # Format turns for compaction
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
      prior_summary <- private$.compaction_summary
      prior_summary_text <- if (is.null(prior_summary)) {
        ""
      } else {
        paste0(
          "Existing summary from earlier compactions:\n",
          prior_summary,
          "\n\n"
        )
      }

      # Create the compaction prompt
      compaction_prompt <- paste0(
        "Summarize the following conversation excerpt concisely. ",
        "Focus on:\n",
        "1. Key decisions made\n",
        "2. Important findings or results\n",
        "3. Files created, modified, or discussed\n",
        "4. Any errors encountered and how they were resolved\n",
        "5. Current state/progress of the task\n\n",
        "Keep the summary under 500 words. Be factual and specific.\n\n",
        prior_summary_text,
        "Conversation excerpt to merge into the summary:\n",
        "---\n",
        conversation_text,
        "\n---\n\n",
        "Summary:"
      )

      temp_chat <- tryCatch(
        clone_compaction_chat(private$.chat),
        error = function(e) e
      )
      response <- if (inherits(temp_chat, "error")) {
        temp_chat
      } else {
        tryCatch(
          temp_chat$chat(compaction_prompt, echo = "none"),
          error = function(e) e
        )
      }

      if (!inherits(response, "error")) {
        return(list(
          summary = response,
          method = "llm",
          usage = agent_usage_snapshot(temp_chat)
        ))
      }

      if (identical(fallback, "error")) {
        cli_abort(
          c(
            "Conversation compaction failed.",
            "x" = response$message,
            "i" = "Set ContextPolicy(fallback = 'text') to permit degraded compaction."
          ),
          class = c("deputy_compaction_error", "deputy_error"),
          parent = response
        )
      }

      private$notify(
        "Compaction used the configured deterministic text fallback.",
        level = "warning",
        code = "compact_fallback",
        error = response$message
      )
      list(
        summary = private$generate_fallback_summary(turns),
        method = "text",
        usage = AgentUsage()
      )
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

      excerpt_summary <- paste0(
        "[Compacted ",
        length(turns),
        " earlier turns - LLM summary unavailable]\n\n",
        paste(summary_parts, collapse = "\n\n")
      )
      if (is.null(private$.compaction_summary)) {
        return(excerpt_summary)
      }
      paste0(
        "[Prior compacted conversation]\n",
        private$.compaction_summary,
        "\n\n",
        excerpt_summary
      )
    },

    # Storage for loaded skills
    loaded_skills = list(),

    # Storage for loaded MCP tool names
    loaded_mcp_tools = character(),
    loaded_mcp_status = list(),

    # Tool call counter for callback-based limits
    tool_call_count = 0L,

    # Active tool call limit; NULL means unbounded.
    tool_call_limit = NULL
  )
)
