#' @include delegation-binding.R delegation-inspection.R delegation-observation.R
NULL

# Agent class for deputy

#' Agent that runs tasks with tools
#'
#' @description
#' An `Agent` wraps an ellmer Chat and uses it to carry out tasks. The model can
#' call tools over several turns while the agent applies permissions, hooks and
#' usage limits and reports its progress as [AgentEvent] objects. Use
#' [LeadAgent] when the agent should delegate work to subagents.
#'
#' An `Agent` also works as an ellmer Chat (`$chat()`, `$stream_async()`,
#' `$get_turns()` and so on), so you can pass it to code that expects one, such
#' as shinychat.
#'
#' Settings given to `$new()`, such as `permissions`, `usage_limits` and
#' `working_dir`, are read-only afterwards.
#'
#' @section File checkpoints:
#' With `enable_file_checkpointing = TRUE`, the agent records the previous
#' contents of files changed by `write_file`, `edit_file` and `multi_edit`.
#' Changes made any other way, including by `run_r_code` or `run_bash`, are not
#' recorded. A checkpoint is created at the start of every run, and
#' `$checkpoint()` creates one on demand. `$rewind_files()` restores files to a
#' checkpoint without changing the conversation. A file tool call that would
#' exceed the checkpoint size limits is refused.
#'
#' @include agent-approval.R agent-stream.R agent-session.R agent-context.R agent-tool-callbacks.R agent-tool-records.R
#' @importFrom later run_now
#' @importFrom utils tail
#' @export
#'
#' @examples
#' \dontrun{
#' # Create an agent with file tools
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-6-luna"),
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
    #' Create a new agent.
    #'
    #' @param chat An ellmer Chat, for example from `ellmer::chat()`.
    #' @param tools A list of tools created with `ellmer::tool()`. See
    #'   [tools_preset()], [tools_file()] and [tools_code()] for built-in tools.
    #' @param system_prompt Optional system prompt. Replaces the Chat's system
    #'   prompt.
    #' @param permissions A [Permissions] policy. Defaults to
    #'   [permissions_standard()] for `working_dir`.
    #' @param usage_limits [UsageLimits] applied to each run separately.
    #'   Defaults to 25 model requests per run. `UsageLimits()` sets no limits.
    #' @param context_policy A [ContextPolicy] controlling automatic compaction
    #'   and where large tool results are stored. The default compacts the
    #'   conversation once it passes about 32,000 tokens.
    #' @param enable_file_checkpointing If `TRUE`, record file changes so they
    #'   can be undone with `$rewind_files()`. See the "File checkpoints" section.
    #' @param file_checkpoint_max_file_bytes Largest file, in bytes, whose
    #'   previous contents a checkpoint can record. Defaults to 50 MiB.
    #' @param file_checkpoint_max_journal_bytes Maximum total size, in bytes, of
    #'   all checkpoint records. Defaults to 250 MiB.
    #' @param working_dir Directory that file tools work in. Must exist.
    #'   Defaults to the current directory.
    #' @param session_id Optional session ID. One is generated if not given.
    #' @param run_context Named list of JSON-compatible values (strings,
    #'   numbers, logicals and nested lists) attached to every event and result,
    #'   for example user or conversation IDs. Keys that look like credentials,
    #'   such as `password` or `api_key`, are rejected.
    #' @param agent_id Optional agent ID. One is generated if not given.
    #' @param agent_name Optional human-readable name.
    #' @param fallback_chats A list of ellmer Chats to try, in order, when a
    #'   request fails with a transient error (a network failure or HTTP 408,
    #'   429, 500, 502, 503 or 504) before the run has received any response or
    #'   called any tool. Each must have no turns or tools; the agent copies it
    #'   and gives it the agent's system prompt, history and tools. Once used, a
    #'   fallback stays in use for later runs. Compaction summaries don't use
    #'   these; see `summary_fallback_chats` in [ContextPolicy()].
    #' @param approval_dir A directory, which must already exist, where tool
    #'   calls waiting for approval are saved, so you can decide them later
    #'   with `$resume_approval()`, even after restarting R. Tools that can wait
    #'   for approval must be created with `ellmer::tool(convert = FALSE)`. When
    #'   set, tools run one at a time. See [approval_read()].
    #' @param delegation_scope Named list identifying what this agent belongs
    #'   to, such as an owner or conversation ID. It is passed as `scope` to the
    #'   `authorize` function of `delegation_disclosure`.
    #' @param delegation_disclosure A [DelegationDisclosure] that decides who may
    #'   inspect this agent's subagents. The default denies everyone.
    #' @param delegation_observation A [DelegationObservation] setting how many
    #'   subagent events are kept for `$observe_subagents()`.
    #' @param trusted_results Optional [TrustedResults] policy naming the one
    #'   tool allowed to produce each type of trusted result. Registering a tool
    #'   that could get around it is an error.
    #' @return A new `Agent` object.
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
      agent_name = NULL,
      fallback_chats = list(),
      approval_dir = NULL,
      delegation_scope = list(),
      delegation_disclosure = DelegationDisclosure(),
      delegation_observation = DelegationObservation(),
      trusted_results = NULL
    ) {
      if (!is.null(private$.chat)) {
        check_conversation_initialization(self)
      }
      check_incoming_conversation(chat)
      if (
        !S7::S7_inherits(delegation_disclosure, DelegationDisclosure) ||
          !S7::S7_inherits(delegation_observation, DelegationObservation)
      ) {
        abort_deputy("Invalid delegation disclosure or observation policy.")
      }
      private$delegation_scope <- normalize_run_context(delegation_scope)
      private$.delegation_disclosure <- delegation_disclosure
      private$.delegation_buffer <- new_delegation_buffer(
        delegation_observation
      )
      validate_chat(chat)
      private$.fallback_chats <- normalize_fallback_chats(fallback_chats, chat)

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

      permissions <- permissions %||% permissions_standard(working_dir)
      if (!S7::S7_inherits(permissions, Permissions)) {
        cli_abort("{.arg permissions} must be a Permissions object")
      }
      private$.chat <- chat
      private$.permissions <- permissions
      private$.trusted_results <- normalize_trusted_results(trusted_results)
      private$.usage_limits <- normalize_usage_limits(usage_limits)
      private$.context_policy <- normalize_context_policy(context_policy)
      private$.working_dir <- working_dir
      if (!is.null(approval_dir)) {
        private$.approval_dir <- approval_store_path(approval_dir)
      }
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
      private$check_trusted_tools(c(backend_tools, tools))
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
      private$.compaction_catalog_registry <- new_compaction_catalog_registry(
        self,
        private$.context_policy,
        private$.session_id
      )

      reg.finalizer(self, finalize_owned_conversations, onexit = TRUE)
      invisible(self)
    },

    #' @description
    #' Retain another agent so you can send it more tasks with
    #' `$continue_agent()`. The retained agent keeps its conversation between
    #' tasks.
    #'
    #' Until you call `$release_agent()`, the retained agent can't be run
    #' directly, and its conversation, prompt, model, tools, hooks and tool
    #' observers can't be changed (observers it already has keep working). An
    #' agent can retain up to 32 others at a time. See
    #' `vignette("retained-agents", package = "deputy")`.
    #' @param agent Another `Agent` (not a `LeadAgent`) with its own Chat and no
    #'   `approval_dir`, `fallback_chats` or provider-native tools.
    #' @param usage_limits [UsageLimits] for all of its tasks combined, also
    #'   capped by the retained agent's own limits.
    #' @param max_runs Maximum number of tasks. Defaults to 32.
    #' @return A handle (a string) that only this agent can use.
    retain_agent = function(agent, usage_limits, max_runs = 32L) {
      retain_conversation(self, agent, usage_limits, max_runs)
    },

    #' @description
    #' Retain several agents at once and let them delegate to each other through
    #' tools you define in `routes`. This agent is the root of the graph and
    #' holds every conversation in it. The graph's usage limits add up across
    #' all delegated runs until you call `$release_agent_graph()`.
    #'
    #' Routes may form a cycle, but delegating to an agent that is already
    #' running fails. An agent waiting on its own delegate still counts toward
    #' `max_concurrency`.
    #' @param agents Named list of distinct agents, each meeting the conditions
    #'   in `$retain_agent()`. The name `root` is reserved for this agent.
    #' @param routes Named list keyed by `root` or an agent name. Each element is
    #'   a named list of delegation tools to add to that agent, where each tool
    #'   is a list with `target` (an agent name), `description` and
    #'   `usage_limits`.
    #' @param usage_limits [UsageLimits] for the whole graph. `max_requests` is
    #'   required.
    #' @param max_depth Maximum delegation depth. This agent's direct delegates
    #'   are at depth 1.
    #' @param max_delegations Maximum number of delegations over the graph's
    #'   lifetime.
    #' @param max_concurrency Maximum number of delegations running at once.
    #' @param max_runs Maximum number of tasks for each agent in the graph.
    #' @return A named character vector of handles, one per agent, for use with
    #'   `$continue_agent()`.
    retain_agent_graph = function(
      agents,
      routes,
      usage_limits,
      max_depth,
      max_delegations,
      max_concurrency,
      max_runs = 32L
    ) {
      retain_agent_graph(
        self,
        agents,
        routes,
        usage_limits,
        max_depth,
        max_delegations,
        max_concurrency,
        max_runs
      )
    },

    #' @description Get the total usage of all delegated runs in this agent's
    #' graph, including runs still in progress. Errors if this agent doesn't own
    #' a graph.
    #' @return An [AgentUsage] object.
    delegation_graph_usage = function() {
      tree <- private$.delegation_tree
      if (is.null(tree) || !identical(delegation_tree_root(tree), self)) {
        conversation_abort("This Agent does not own a delegation graph.")
      }
      tree_usage(tree)
    },

    #' @description Release the graph, removing its route tools and handles.
    #' Errors if anything in it is still running. This also discards the
    #' graph's delegation records, so save them first with `$export_subagents()`
    #' if you need them. The agents' own tools and connections are left open.
    #' @return `NULL`, invisibly.
    release_agent_graph = function() release_agent_graph(self),

    #' @description
    #' Send a retained agent its next task. It still has its earlier
    #' conversation. This errors, before any request is made, if the agent is
    #' busy, was changed or released, has used up `max_runs`, or the handle
    #' belongs to another agent. After a failed or cancelled task, call this
    #' again to carry on.
    #' @param handle A handle from this agent's `$retain_agent()` or
    #'   `$retain_agent_graph()`.
    #' @param task The next task, as one string of at most 64 KiB.
    #' @param usage_limits [UsageLimits] for this task. It is also capped by
    #'   what remains of the handle's total budget and by the retained agent's
    #'   own limits.
    #' @return A promise that resolves to an [AgentResult]. If the task is
    #'   cancelled before it starts, the result has zero usage and no run ID.
    continue_agent_async = function(handle, task, usage_limits) {
      continue_conversation(self, handle, task, usage_limits)
    },

    #' @description
    #' Blocking version of `$continue_agent_async()`.
    #' @param handle,task,usage_limits See `$continue_agent_async()`.
    #' @return An [AgentResult].
    continue_agent = function(handle, task, usage_limits) {
      private$resolve_promise(self$continue_agent_async(
        handle,
        task,
        usage_limits
      ))
    },

    #' @description
    #' Ask a retained agent to stop its current task. The run stops at the next
    #' safe point and keeps the conversation so far. Calling this more than once
    #' is harmless.
    #' @param handle A handle from `$retain_agent()`.
    #' @param reason Stop reason recorded on the cancelled run.
    #' @return `TRUE`, invisibly, if a task was cancelled; `FALSE` if the agent
    #'   was idle.
    cancel_agent = function(handle, reason = "interrupted") {
      entry <- conversation_entry(self, handle)
      if (!entry$busy || !length(entry$ids)) {
        return(invisible(FALSE))
      }
      self$interrupt_subagent(utils::tail(entry$ids, 1L), reason)
    },

    #' @description
    #' Stop retaining an agent so it can be used on its own again. This also
    #' discards its delegation records, so save them first with
    #' `$export_subagents()` if you need them. Its tools and connections stay
    #' open. Errors while the agent is running: cancel it with `$cancel_agent()`
    #' and wait for the task to end first. Agents in a graph are released with
    #' `$release_agent_graph()`. Handles don't survive an R restart.
    #' @param handle A handle from `$retain_agent()`.
    #' @return `NULL`, invisibly.
    release_agent = function(handle) release_conversation(self, handle),

    #' @description
    #' List this agent's delegations, oldest first, including ones still
    #' running. The records are kept in memory only.
    #'
    #' `status` is `"queued"`, `"running"`, `"completed"`, `"failed"`,
    #' `"stopped"`, `"not_started"` or `"suspended"` (waiting for a tool
    #' approval). `"completed"` means the subagent finished normally, not that
    #' it did the task well; `stop_reason` gives the exact reason. IDs and times
    #' are `NA` until known, and `completed_at` is set when the run ends or is
    #' suspended. `input_error` says why a task was rejected before it ran:
    #' `"invalid"`, `"missing"`, `"stale"`, `"unauthorized"` or `"oversized"`.
    #' `hook_error` records errors from hooks watching the subagent.
    #'
    #' @return A data frame with one row per delegation.
    list_subagents = function() {
      runs <- lead_delegation_records(self)
      if (length(runs) == 0) {
        return(data.frame(
          agent_name = character(),
          agent_id = character(),
          parent_agent_id = character(),
          parent_delegation_id = character(),
          depth = integer(),
          root_agent_id = character(),
          session_id = character(),
          run_id = character(),
          parent_run_id = character(),
          delegation_id = character(),
          tool_call_id = character(),
          task = character(),
          status = character(),
          stop_reason = character(),
          input_error = character(),
          admitted_at = as.POSIXct(character()),
          hook_error = character(),
          cleanup_error = character(),
          observation_error = character(),
          started_at = as.POSIXct(character()),
          completed_at = as.POSIXct(character()),
          error = character(),
          stringsAsFactors = FALSE
        ))
      }

      do.call(
        rbind,
        lapply(runs, function(run) {
          data.frame(
            agent_name = run$agent_name,
            agent_id = run$agent_id %||% NA_character_,
            parent_agent_id = run$parent_agent_id %||% NA_character_,
            parent_delegation_id = run$parent_delegation_id %||% NA_character_,
            depth = run$depth %||% NA_integer_,
            root_agent_id = run$root_agent_id %||% NA_character_,
            session_id = run$session_id %||% NA_character_,
            run_id = run$run_id %||% NA_character_,
            parent_run_id = run$parent_run_id %||% NA_character_,
            delegation_id = run$delegation_id %||% NA_character_,
            tool_call_id = run$tool_call_id %||% NA_character_,
            task = run$task,
            status = run$status,
            stop_reason = run$stop_reason %||% NA_character_,
            input_error = run$input_error %||% NA_character_,
            admitted_at = as.POSIXct(run$admitted_at, tz = "UTC"),
            hook_error = run$hook_error %||% NA_character_,
            cleanup_error = run$cleanup_error %||% NA_character_,
            observation_error = run$observation_error %||% NA_character_,
            started_at = as.POSIXct(run$started_at, tz = "UTC"),
            completed_at = as.POSIXct(run$completed_at, tz = "UTC"),
            error = run$error %||% NA_character_,
            stringsAsFactors = FALSE
          )
        })
      )
    },

    #' @description
    #' Get the results of delegated runs.
    #'
    #' @param agent_name Only return results from subagents with this name.
    #' @param delegation_id Only return the result of this delegation.
    #' @return A list of [AgentResult] objects, oldest first. It holds `NULL`
    #'   for runs that are still going, never started, or failed without a
    #'   result.
    get_subagent_results = function(agent_name = NULL, delegation_id = NULL) {
      runs <- lead_delegation_records(self)
      if (!is.null(agent_name)) {
        runs <- Filter(
          function(run) identical(run$agent_name, agent_name),
          runs
        )
      }
      if (!is.null(delegation_id)) {
        runs <- Filter(
          function(run) identical(run$delegation_id, delegation_id),
          runs
        )
      }
      lapply(runs, function(run) run$agent_result)
    },

    #' @description
    #' Get the conversation turns of each delegation. For a subagent that is
    #' still running, you get the turns completed so far. Reading them doesn't
    #' add anything to this agent's context. No disclosure checks are applied,
    #' so use `$inspect_subagents()` before showing history to users.
    #'
    #' @param agent_name Only return turns from subagents with this name.
    #' @param session_id Only return turns from the subagent with this session
    #'   ID.
    #' @return A list with one list of ellmer turns per delegation.
    get_subagent_messages = function(agent_name = NULL, session_id = NULL) {
      runs <- lead_delegation_records(self, messages = TRUE)
      if (!is.null(agent_name)) {
        runs <- Filter(
          function(run) identical(run$agent_name, agent_name),
          runs
        )
      }
      if (!is.null(session_id)) {
        runs <- Filter(
          function(run) identical(run$session_id, session_id),
          runs
        )
      }

      lapply(runs, function(run) run$turns)
    },

    #' @description
    #' See what each subagent was given at the start, or what its model context
    #' holds now, oldest first. Nothing is sent to a model. No disclosure checks
    #' are applied.
    #' @param delegation_id Only return this delegation.
    #' @param view `"initial"` returns the [DelegationManifest] recording what
    #'   the subagent started with. `"current"` returns a list with its
    #'   `system_prompt` and the `turns` in its model context.
    #' @param redact If `TRUE` (only with `view = "initial"`), leave out the
    #'   task, instructions and source text. Other metadata is still included.
    #' @return A list with one entry per delegation, `NULL` where nothing is
    #'   available. For a finished subagent, `"current"` shows its context when
    #'   it finished.
    get_subagent_contexts = function(
      delegation_id = NULL,
      view = "initial",
      redact = FALSE
    ) {
      lead_subagent_contexts(self, delegation_id, view, redact)
    },

    #' @description
    #' Follow subagent activity as it happens. The returned subscription lets
    #' you poll for new events without affecting the subagents' runs.
    #' @param requester Whoever is asking, as identified by your app (for
    #'   example a user ID). The `delegation_disclosure` policy checks it on
    #'   every read.
    #' @param delegation_id Only follow this delegation.
    #' @param after A cursor from an earlier subscription on this agent, to
    #'   resume from. `NULL` starts from now.
    #' @return A [DelegationSubscription]. Closing it stops observing but
    #'   doesn't stop any subagent.
    observe_subagents = function(
      requester,
      delegation_id = NULL,
      after = NULL
    ) {
      DelegationSubscription$new(self, requester, delegation_id, after)
    },

    #' @description
    #' Ask a running subagent to stop. It stops at the next safe point; in a
    #' delegation graph, its own delegations stop too. This doesn't consult
    #' `delegation_disclosure`, so check that the user may do this before
    #' calling it. Models can't call this method.
    #' @param delegation_id The delegation to stop.
    #' @param reason Stop reason to record. Defaults to `"interrupted"`.
    #' @return `TRUE`, invisibly, if a run was stopped; `FALSE` if the
    #'   delegation is unknown or already finished.
    interrupt_subagent = function(delegation_id, reason = "interrupted") {
      delegation_id <- delegation_text(delegation_id, "delegation_id")
      reason <- delegation_text(reason, "reason")
      ids <- if (is.null(private$.delegation_tree)) {
        delegation_id
      } else {
        graph_descendants(self, delegation_id)
      }
      interrupted <- FALSE
      for (id in rev(ids)) {
        interrupted <- isTRUE(interrupt_delegation(self, id, reason)) ||
          interrupted
      }
      invisible(interrupted)
    },

    #' @description
    #' Get a snapshot of each delegation that `requester` may see: its task, its
    #' outcome (what Deputy observed, kept apart from what the subagent
    #' claimed), usage, the [DelegationManifest] it started from and any errors.
    #' Retained agents also report their total usage across tasks; unknown usage
    #' is `NULL`. Each view passes through the `delegation_disclosure` policy,
    #' which may redact it. Errors if `requester` isn't allowed. Nothing is run.
    #' @param requester Whoever is asking, as identified by your app. Never pass
    #'   values that came from a model.
    #' @param delegation_id Only return this delegation. Unknown IDs give an
    #'   empty list.
    #' @param transcript If `TRUE`, also include the conversation, as
    #'   `transcript` records and as ellmer `turns`. Hidden reasoning and raw
    #'   provider data are left out.
    #' @return A list of views, one per delegation. Changing them doesn't
    #'   affect any agent.
    inspect_subagents = function(
      requester,
      delegation_id = NULL,
      transcript = FALSE
    ) {
      views <- lead_inspect_subagents(
        self,
        requester,
        delegation_id,
        transcript
      )
      views <- lapply(views, function(view) {
        if (transcript) {
          view$turns <- lapply(view$transcript, inspection_replay)
        }
        view
      })
      inspection_bound(views, private$.delegation_disclosure)
    },

    #' @description
    #' Export finished delegations, with their conversations, so you can store
    #' them and view them later with [delegation_history()]. The export is a
    #' record to read, not something you can resume.
    #' @param requester,delegation_id See `$inspect_subagents()`.
    #' @return A plain list for [delegation_history()]. Errors if a selected
    #'   delegation is still running. Reading it back checks a
    #'   [DelegationDisclosure] again.
    export_subagents = function(requester, delegation_id = NULL) {
      views <- lead_inspect_subagents(
        self,
        requester,
        delegation_id,
        TRUE,
        settled_only = TRUE
      )
      inspection_bound(
        list(
          schema_version = 1L,
          settled = TRUE,
          scope = inspection_scope(self),
          children = views
        ),
        private$.delegation_disclosure
      )
    },

    #' @description
    #' Read part of a large result that a subagent saved, using a reference
    #' from its `$inspect_subagents()` view. No tool or model is run.
    #' @param requester,delegation_id See `$inspect_subagents()`.
    #' @param reference A reference exactly as it appears in the delegation's
    #'   view. Errors if it isn't there or the saved result is gone.
    #' @param offset Character position to start reading from, starting at 0.
    #' @return The view after redaction: a list whose `result` holds up to
    #'   8,192 characters from `offset`, with the next offset and total length.
    read_subagent_result = function(
      requester,
      delegation_id,
      reference,
      offset = 0L
    ) {
      views <- lead_inspect_subagents(self, requester, delegation_id, FALSE)
      references <- unlist(
        lapply(views, function(view) view$outcome$references),
        recursive = FALSE
      )
      selected <- Filter(
        function(ref) identical(ref$reference, reference),
        references
      )
      if (
        !is.character(reference) ||
          length(reference) != 1L ||
          is.na(reference) ||
          !length(selected)
      ) {
        delegation_disclosure_abort()
      }
      # Disclosure authorizes the public reference. Storage routing remains
      # host-owned even when the redactor removes or replaces private metadata.
      records <- Filter(
        function(record) identical(record$delegation_id, delegation_id),
        lead_delegation_records(self)
      )
      stored <- if (length(records) == 1L) {
        Filter(
          function(ref) identical(ref$reference, reference),
          records[[1L]]$references
        )
      } else {
        list()
      }
      if (!length(stored)) {
        delegation_disclosure_abort()
      }
      record <- records[[1L]]
      storage <- lead_artifact_storage(self, record, stored[[1L]])
      chunk <- read_tool_result_chunk(
        reference,
        offset = offset,
        max_chars = 8192L,
        policy = storage$policy,
        session_id = storage$session_id
      )
      view <- private$.delegation_disclosure$redact(
        list(kind = "artifact", reference = reference, result = chunk),
        requester
      )
      inspection_portable(view)
      inspection_bound(view, private$.delegation_disclosure)
    },

    #' @description
    #' Run a task and stream its progress.
    #'
    #' Returns a generator that yields [AgentEvent] objects as the agent works.
    #' The run continues until the model finishes, a usage limit is reached or
    #' it is interrupted. The `"stop"` event gives the reason, and `$last_run()`
    #' then returns the [AgentResult].
    #'
    #' @param task The task for the agent.
    #' @param usage_limits [UsageLimits] for this run. `NULL` fields use the
    #'   agent's limits.
    #' @param include_partial_messages If `TRUE` (the default), yield a `"text"`
    #'   event for each streamed chunk. If `FALSE`, skip them; the full text
    #'   still arrives in the `"text_complete"` event.
    #' @param run_context Named list merged into the agent's `run_context` for
    #'   this run. It can't change or remove ID fields (keys ending in `id`)
    #'   that the agent already sets.
    #' @return A generator yielding [AgentEvent] objects.
    #' @param type Optional ellmer type, such as `ellmer::type_object()`. After
    #'   the task, the agent extracts data of this type from the conversation
    #'   into the result's `structured_output`. This counts toward the run's
    #'   limits.
    #' @param validate Optional function that checks the extracted value. Return
    #'   `TRUE` to accept it, or `FALSE` or a message to reject it; a message is
    #'   sent to the model as feedback. An error or any other return value, such
    #'   as `NA`, ends the run with an error.
    #' @param max_corrections How many times to ask the model to fix a rejected
    #'   value. Defaults to 0. If the value is still rejected, the run errors.
    #'   Every attempt counts toward the run's limits.
    run = function(
      task,
      usage_limits = NULL,
      include_partial_messages = TRUE,
      run_context = list(),
      type = NULL,
      validate = NULL,
      max_corrections = 0L
    ) {
      structured <- structured_run_spec(type, validate, max_corrections)
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
        stream = "content",
        extraction = structured
      )
      private$event_generator(
        governed_run,
        include_partial_messages = include_partial_messages
      )
    },

    #' @description
    #' Run a task and wait for it to finish.
    #'
    #' Runs `$run()` to the end and returns the [AgentResult], which holds
    #' every event.
    #'
    #' @param task The task for the agent.
    #' @param usage_limits [UsageLimits] for this run. `NULL` fields use the
    #'   agent's limits.
    #' @param include_partial_messages Passed to `$run()`. It doesn't change the
    #'   returned result, which always includes the `"text"` events.
    #' @param run_context Named list merged into the agent's `run_context` for
    #'   this run. It can't change or remove ID fields (keys ending in `id`)
    #'   that the agent already sets.
    #' @return An [AgentResult] object.
    #' @param type Optional ellmer type, such as `ellmer::type_object()`. After
    #'   the task, the agent extracts data of this type from the conversation
    #'   into `result$structured_output`. This counts toward the run's limits.
    #' @param validate Optional function that checks the extracted value. Return
    #'   `TRUE` to accept it, or `FALSE` or a message to reject it; a message is
    #'   sent to the model as feedback. An error or any other return value, such
    #'   as `NA`, ends the run with an error.
    #' @param max_corrections How many times to ask the model to fix a rejected
    #'   value. Defaults to 0. If the value is still rejected, the run errors.
    #'   Every attempt counts toward the run's limits.
    run_sync = function(
      task,
      usage_limits = NULL,
      include_partial_messages = TRUE,
      run_context = list(),
      type = NULL,
      validate = NULL,
      max_corrections = 0L
    ) {
      gen <- self$run(
        task = task,
        usage_limits = usage_limits,
        include_partial_messages = include_partial_messages,
        run_context = run_context,
        type = type,
        validate = validate,
        max_corrections = max_corrections
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
      result
    },

    #' @description
    #' Send a message and return the reply, like `ellmer::Chat$chat()`, with the
    #' agent's tools, permissions, hooks and usage limits applied. `$last_run()`
    #' then returns the full [AgentResult].
    #' @param ... Message content, as for ellmer.
    #' @param echo Print the reply unless this is `"none"` or `FALSE`. Defaults
    #'   to `getOption("ellmer_echo", "none")`.
    #' @param run_context Named list merged into the agent's `run_context` for
    #'   this run.
    #' @return The reply text.
    chat = function(..., echo = NULL, run_context = list()) {
      effective_run_context <- merge_run_context(
        private$.run_context,
        run_context
      )
      governed_run <- private$start_governed_stream(
        messages = rlang::list2(...),
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
    #' Asynchronous version of `$chat()`.
    #' @param ... Message content, as for ellmer.
    #' @param tool_mode `"concurrent"` runs the tool calls from one response in
    #'   parallel; `"sequential"` runs them one at a time.
    #' @param run_context Named list merged into the agent's `run_context` for
    #'   this run.
    #' @return A promise that resolves to the reply text.
    chat_async = function(
      ...,
      tool_mode = c("concurrent", "sequential"),
      run_context = list()
    ) {
      tool_mode <- match.arg(tool_mode)
      messages <- rlang::list2(...)
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

    #' @description Extract structured data, like
    #' `ellmer::Chat$chat_structured()`, with the agent's permissions, hooks and
    #' usage limits applied.
    #' @param ... Message content, as for ellmer.
    #' @param type An ellmer type describing the data, such as
    #'   `ellmer::type_object()`.
    #' @param echo Passed to ellmer.
    #' @param convert Passed to ellmer: whether to convert the result to R
    #'   objects.
    #' @param run_context Named list merged into the agent's `run_context` for
    #'   this run.
    #' @return The extracted data.
    #' @param validate Optional function that checks the extracted value. Return
    #'   `TRUE` to accept it, or `FALSE` or a message to reject it; a message is
    #'   sent to the model as feedback. An error or any other return value, such
    #'   as `NA`, ends the run with an error.
    #' @param max_corrections How many times to ask the model to fix a rejected
    #'   value. Defaults to 0. If the value is still rejected, the run errors.
    #'   Every attempt counts toward the usage limits.
    chat_structured = function(
      ...,
      type,
      echo = "none",
      convert = TRUE,
      run_context = list(),
      validate = NULL,
      max_corrections = 0L
    ) {
      private$resolve_promise(self$chat_structured_async(
        ...,
        type = type,
        echo = echo,
        convert = convert,
        run_context = run_context,
        validate = validate,
        max_corrections = max_corrections
      ))
    },

    #' @description Asynchronous version of `$chat_structured()`.
    #' @param ... Message content, as for ellmer.
    #' @param type An ellmer type describing the data, such as
    #'   `ellmer::type_object()`.
    #' @param echo Passed to ellmer.
    #' @param convert Passed to ellmer: whether to convert the result to R
    #'   objects.
    #' @param run_context Named list merged into the agent's `run_context` for
    #'   this run.
    #' @return A promise that resolves to the extracted data.
    #' @param validate Optional function that checks the extracted value. Return
    #'   `TRUE` to accept it, or `FALSE` or a message to reject it; a message is
    #'   sent to the model as feedback. An error or any other return value, such
    #'   as `NA`, ends the run with an error.
    #' @param max_corrections How many times to ask the model to fix a rejected
    #'   value. Defaults to 0. If the value is still rejected, the run errors.
    #'   Every attempt counts toward the usage limits.
    chat_structured_async = function(
      ...,
      type,
      echo = "none",
      convert = TRUE,
      run_context = list(),
      validate = NULL,
      max_corrections = 0L
    ) {
      effective_run_context <- merge_run_context(
        private$.run_context,
        run_context
      )
      governed_run <- private$start_governed_stream(
        messages = rlang::list2(...),
        limits = self$usage_limits,
        run_context = effective_run_context,
        stream = "content",
        structured = structured_run_spec(
          type,
          validate,
          max_corrections,
          echo = echo,
          convert = convert
        )
      )
      private$collect_governed_stream(governed_run) |>
        promises::then(function(...) governed_run$state$structured_output)
    },

    #' @description
    #' Stream a reply, like `ellmer::Chat$stream()`, with the agent's
    #' permissions, hooks and usage limits applied.
    #' @param ... Message content, as for ellmer.
    #' @param stream `"text"` yields text chunks; `"content"` yields ellmer
    #'   content objects, including tool requests and results.
    #' @param controller Optional ellmer stream controller.
    #' @param run_context Named list merged into the agent's `run_context` for
    #'   this run.
    #' @return A generator.
    #' @param type Optional ellmer type for structured streaming, passed to
    #'   ellmer. If the provider can't stream structured output, use
    #'   `$chat_structured()` instead.
    stream = function(
      ...,
      stream = c("text", "content"),
      controller = NULL,
      run_context = list(),
      type = NULL
    ) {
      stream <- match.arg(stream)
      effective_run_context <- merge_run_context(
        private$.run_context,
        run_context
      )
      governed_run <- private$start_governed_stream(
        messages = rlang::list2(...),
        limits = self$usage_limits,
        run_context = effective_run_context,
        stream = stream,
        controller = controller,
        stream_type = type
      )
      private$sync_stream_generator(governed_run$stream)
    },

    #' @description
    #' Asynchronous version of `$stream()`. This is the method shinychat uses:
    #' the stream is the same as ellmer's, with the agent's permissions, hooks,
    #' usage limits and compaction applied.
    #' @param ... Message content, as for ellmer, including the attachment
    #'   `Content` objects that shinychat sends.
    #' @param tool_mode `"concurrent"` runs the tool calls from one response in
    #'   parallel; `"sequential"` runs them one at a time.
    #' @param stream `"text"` yields text chunks; `"content"` yields ellmer
    #'   content objects, including tool requests and results.
    #' @param controller Optional ellmer stream controller.
    #' @param run_context Named list merged into the agent's `run_context` for
    #'   this run.
    #' @return An asynchronous generator suitable for `shinychat::chat_append()`.
    #' @param type Optional ellmer type for structured streaming, passed to
    #'   ellmer. If the provider can't stream structured output, use
    #'   `$chat_structured()` instead.
    stream_async = function(
      ...,
      tool_mode = c("concurrent", "sequential"),
      stream = c("text", "content"),
      controller = NULL,
      run_context = list(),
      type = NULL
    ) {
      tool_mode <- match.arg(tool_mode)
      stream <- match.arg(stream)
      effective_run_context <- merge_run_context(
        private$.run_context,
        run_context
      )
      private$start_governed_stream(
        messages = rlang::list2(...),
        limits = self$usage_limits,
        run_context = effective_run_context,
        tool_mode = tool_mode,
        stream = stream,
        controller = controller,
        stream_type = type
      )$stream
    },

    #' @description
    #' Get the result of the most recent run.
    #' @return An [AgentResult], or `NULL` before the first run finishes.
    last_run = function() {
      private$.last_run_result
    },

    #' @description Get the result of the most recent compaction.
    #' @return A [DeputyCompaction], or `NULL` if there hasn't been one.
    last_compaction = function() {
      private$.last_compaction
    },

    #' @description Get the full value of a large tool result that was saved
    #' outside the model context.
    #' @param reference A `deputy://tool-result/...` reference, or text
    #'   containing one, such as the placeholder the model saw.
    #' @return The stored R value. ellmer content objects saved during
    #'   compaction come back as text.
    resolve_tool_result = function(reference) {
      read_tool_result_envelope(
        reference,
        self$context_policy,
        private$.session_id
      )$value
    },

    #' @description Add a user turn and an assistant turn, as ellmer's
    #' `$add_turn()` does.
    #' @param user User turn or content.
    #' @param assistant Assistant turn or content.
    #' @param log_tokens Passed to ellmer's `$add_turn()`.
    #' @return The agent, invisibly.
    add_turn = function(user, assistant, log_tokens = TRUE) {
      check_conversation_lease(self, NULL)
      private$.chat$add_turn(user, assistant, log_tokens = log_tokens)
      invisible(self)
    },

    #' @description Get the whole conversation, as ellmer's `$get_turns()`
    #'   does. Unlike `$get_context_turns()`, this includes turns that
    #'   compaction removed from the model context, and the original tool
    #'   results that `$microcompact()` cleared. Removed turns stay in memory
    #'   until `$set_turns()` replaces the conversation.
    #' @param include_system_prompt Include the system prompt as a turn.
    #' @return A list of ellmer turns.
    get_turns = function(include_system_prompt = FALSE) {
      turns <- restore_cleared_tool_results(
        c(private$.compacted_turns, private$.chat$get_turns()),
        private$.cleared_tool_results
      )
      if (isTRUE(include_system_prompt)) {
        context <- self$get_context_turns(include_system_prompt = TRUE)
        system <- Filter(
          function(turn) inherits(turn, "ellmer::SystemTurn"),
          context
        )
        turns <- c(system, turns)
      }
      turns
    },

    #' @description Get the turns the model currently sees. After compaction
    #'   this is shorter than `$get_turns()`, and tool results cleared by
    #'   `$microcompact()` show their marker.
    #' @param include_system_prompt Include the system prompt, with any
    #'   compaction summary, as a turn.
    #' @return A list of ellmer turns.
    get_context_turns = function(include_system_prompt = FALSE) {
      if (
        "include_system_prompt" %in% names(formals(private$.chat$get_turns))
      ) {
        return(private$.chat$get_turns(
          include_system_prompt = include_system_prompt
        ))
      }
      private$.chat$get_turns()
    },

    #' @description Replace the conversation, as ellmer's `$set_turns()` does.
    #'   This also drops any compaction summary and the turns compaction
    #'   removed. During a run, usage counted so far still counts.
    #' @param value A list of ellmer turns.
    #' @return The agent, invisibly.
    set_turns = function(value) {
      check_conversation_lease(self, NULL)
      usage <- if (isTRUE(private$run_active)) private$current_run_usage()
      previous_turns <- private$.chat$get_turns()
      prompt <- private$.chat$get_system_prompt()
      prompt_without_compaction <- private$system_prompt_without_compaction()
      tryCatch(
        {
          private$.chat$set_turns(value)
          if (!identical(prompt, prompt_without_compaction)) {
            private$.chat$set_system_prompt(prompt_without_compaction)
          }
        },
        error = function(error) {
          try(private$.chat$set_turns(previous_turns), silent = TRUE)
          try(private$.chat$set_system_prompt(prompt), silent = TRUE)
          rlang::cnd_signal(error)
        }
      )
      preserve_run_usage(self, usage)
      private$.compaction_summary <- NULL
      private$.compacted_turns <- list()
      private$.cleared_tool_results <- list()
      invisible(self)
    },

    #' @description Get the system prompt, as ellmer's `$get_system_prompt()`
    #' does. After compaction it includes the conversation summary.
    #' @return The system prompt or `NULL`.
    get_system_prompt = function() {
      private$.chat$get_system_prompt()
    },

    #' @description Replace the system prompt, as ellmer's
    #' `$set_system_prompt()` does. After compaction, this also drops the
    #' conversation summary unless `value` still contains it.
    #' @param value The new system prompt or `NULL`.
    #' @return The agent, invisibly.
    set_system_prompt = function(value) {
      check_conversation_lease(self, NULL)
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

    #' @description Get the registered tools, as ellmer's `$get_tools()` does.
    #' @return A named list of ellmer tool definitions.
    get_tools = function() {
      private$.chat$get_tools()
    },

    #' @description Replace all registered tools. The new tools are checked and
    #' wrapped as in `$register_tools()`.
    #' @param tools A list of ellmer tool definitions.
    #' @return The agent, invisibly.
    set_tools = function(tools) {
      check_conversation_lease(self, NULL)
      had_result_reader <- isTRUE(private$.tool_result_reader_registered)
      tools <- validate_tool_batch(tools, preserve_reader = TRUE)
      private$check_trusted_tools(tools)
      wrapped <- lapply(tools, private$adapt_tool)
      if (had_result_reader) {
        wrapped[["deputy_read_tool_result"]] <-
          private$.chat$get_tools()[["deputy_read_tool_result"]]
      }
      private$.chat$set_tools(wrapped)
      invisible(self)
    },

    #' @description Get token usage by turn, as ellmer's `$get_tokens()` does.
    #' @param include_system_prompt Deprecated; passed to ellmer.
    #' @return A data frame.
    get_tokens = function(include_system_prompt = NULL) {
      if (is.null(include_system_prompt)) {
        return(private$.chat$get_tokens())
      }
      private$.chat$get_tokens(include_system_prompt = include_system_prompt)
    },

    #' @description Get the estimated cost, as ellmer's `$get_cost()` does.
    #' @param include `"all"` for every turn or `"last"` for the latest request.
    #' @return The cost, as returned by ellmer.
    get_cost = function(include = c("all", "last")) {
      private$.chat$get_cost(include = match.arg(include))
    },

    #' @description Count tokens, as ellmer's `$token_count()` does.
    #' @param ... Message content, as for ellmer.
    #' @param include `"new"` counts only the new content; `"complete"` counts
    #'   the whole context too.
    #' @param type Optional ellmer type, passed to ellmer.
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

    #' @description Get the ellmer provider.
    #' @return An ellmer provider object.
    get_provider = function() {
      private$.chat$get_provider()
    },

    #' @description Get the model name.
    #' @return The model name.
    get_model = function() {
      private$.chat$get_model()
    },

    #' @description Get ellmer's model object.
    #' @return An ellmer model object, including parameters and extra arguments.
    get_model_object = function() {
      private$.chat$get_model_object()
    },

    #' @description Change the model.
    #' @param model Model name.
    #' @return The agent, invisibly.
    set_model = function(model) {
      check_conversation_lease(self, NULL)
      private$.chat$set_model(model)
      invisible(self)
    },

    #' @description
    #' Add a tool. Calls to it go through the agent's permission checks and
    #' hooks.
    #'
    #' Provider-native web search and fetch tools run on the provider's
    #' servers, not in R, so they are checked once, when you register them. The
    #' permissions must have `web = TRUE`, list the tool in `tool_allowlist` and
    #' have no `can_use_tool` callback.
    #' @param tool A tool created with `ellmer::tool()` or a supported
    #'   provider-native web tool.
    #' @param replace If `TRUE`, replace a registered tool with the same name.
    #'   If `FALSE` (the default), a name clash is an error.
    #' @return The agent, invisibly, for chaining.
    register_tool = function(tool, replace = FALSE) {
      self$register_tools(list(tool), replace = replace)
    },

    #' @description
    #' Add several tools, as `$register_tool()` does. All of them are checked
    #' before any is added, so if one fails, none are added. List names are
    #' ignored: each tool keeps its own name.
    #'
    #' @param tools A list of tools created with `ellmer::tool()` or supported
    #'   provider-native web tools.
    #' @param replace If `TRUE`, replace registered tools with the same names.
    #'   If `FALSE` (the default), a name clash is an error. Two tools with the
    #'   same name in `tools` are always an error.
    #' @return The agent, invisibly, for chaining.
    register_tools = function(tools, replace = FALSE) {
      check_conversation_lease(self, NULL)
      existing <- private$.chat$get_tools()
      tools <- validate_tool_batch(tools, existing, replace = replace)
      merged <- existing
      merged[names(tools)] <- tools
      private$check_trusted_tools(merged)
      wrapped <- lapply(tools, private$adapt_tool)
      existing[names(wrapped)] <- wrapped
      private$.chat$set_tools(existing)
      invisible(self)
    },

    #' @description Add a callback that runs when the model requests a tool, as
    #' ellmer's `$on_tool_request()` does.
    #' @param callback A function with one `request` argument.
    #' @return A function that removes the callback.
    on_tool_request = function(callback) {
      register_tool_observer(self, "request", callback)
    },

    #' @description Add a callback that runs when a tool returns a result, as
    #' ellmer's `$on_tool_result()` does.
    #' @param callback A function with one `result` argument.
    #' @return A function that removes the callback.
    on_tool_result = function(callback) {
      register_tool_observer(self, "result", callback)
    },

    #' @description
    #' Add a hook. Hooks run at set points in a run (see [HookEvent]). They can
    #' observe the run and, at some points, change it, for example by denying a
    #' tool call.
    #'
    #' @param hook A [HookMatcher] object.
    #' @return The agent, invisibly, for chaining.
    #'
    #' @examples
    #' \dontrun{
    #' # Add a hook to block dangerous bash commands
    #' agent$add_hook(hook_block_dangerous_bash())
    #'
    #' # Add a custom PreToolUse hook
    #' agent$add_hook(HookMatcher(
    #'   event = "PreToolUse",
    #'   pattern = "^write_file$",
    #'   callback = function(tool_name, tool_input, context) {
    #'     cli::cli_alert_info("Writing to: {tool_input$path}")
    #'     HookResultPreToolUse(permission = "allow")
    #'   }
    #' ))
    #' }
    add_hook = function(hook) {
      check_conversation_lease(self, NULL)
      if (!S7::S7_inherits(hook, HookMatcher)) {
        cli_abort("{.arg hook} must be a HookMatcher object")
      }
      self$hooks$add(hook)
      invisible(self)
    },

    #' @description
    #' Get the whole conversation, including turns removed by compaction. The
    #' same as `$get_turns()`.
    #'
    #' @return A list of ellmer turns.
    turns = function() {
      self$get_turns()
    },

    #' @description
    #' Get the last turn in the conversation with a given role.
    #'
    #' @param role `"assistant"`, `"user"` or `"system"`.
    #' @return An ellmer turn, or `NULL`.
    last_turn = function(role = c("assistant", "user", "system")) {
      role <- match.arg(role)
      current <- private$.chat$last_turn(role = role)
      if (!is.null(current)) {
        # Restore the returned turn at its actual position in the context,
        # without assuming how the Chat chose it.
        context <- private$.chat$get_turns()
        matches <- which(vapply(
          context,
          function(turn) identical(turn, current),
          logical(1)
        ))
        position <- if (length(matches)) {
          length(private$.compacted_turns) + max(matches)
        } else {
          NA_integer_
        }
        return(restore_cleared_tool_results(
          list(current),
          private$.cleared_tool_results,
          positions = position
        )[[1L]])
      }
      turns <- Filter(
        function(turn) identical(turn@role, role),
        private$.compacted_turns
      )
      if (length(turns)) {
        roles <- vapply(
          private$.compacted_turns,
          function(turn) turn@role,
          character(1)
        )
        restore_cleared_tool_results(
          tail(turns, 1L),
          private$.cleared_tool_results,
          positions = max(which(roles == role))
        )[[1L]]
      } else {
        NULL
      }
    },

    #' @description
    #' Get the agent's session ID.
    #'
    #' @return A string.
    session_id = function() {
      private$.session_id
    },

    #' @description
    #' Get the current permission mode.
    #'
    #' @return The mode, such as `"standard"`.
    get_permission_mode = function() {
      self$permissions$mode
    },

    #' @description
    #' Switch to a narrower permission mode for later tool calls. Permissions
    #' can be narrowed but not widened: from `"full"` any mode is allowed, and
    #' `"standard"` and `"plan"` can only switch to `"readonly"`. Anything else
    #' is an error, so create a new `Agent` instead. Setting the current mode
    #' does nothing. The agent's other permission settings still apply within
    #' the new mode. If the new mode doesn't allow web access,
    #' provider-native web tools are removed, since Deputy can't check their
    #' calls.
    #'
    #' @param mode Permission mode, see [PermissionMode].
    #' @return The agent, invisibly.
    set_permission_mode = function(mode) {
      check_conversation_access(self, NULL)
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

      narrowed_permissions <- Permissions(
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

      private$fire_hook(
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
    #' Get token counts and estimated cost for the turns in the model context.
    #' Turns removed by compaction no longer count.
    #'
    #' @return A list with `input`, `output` and `cached` token counts, the
    #'   estimated `total` cost, `complete` (whether every response had a cost)
    #'   and `missing` (how many didn't). `total` is `NA` when `complete` is
    #'   `FALSE`.
    cost = function() {
      summary <- provider_usage_summary(private$.chat)
      summary[c("input", "output", "cached", "total", "complete", "missing")]
    },

    #' @description
    #' Get usage for the turns in the model context. Turns removed by compaction
    #' no longer count, and `tool_calls` is always 0 here. For one run's usage,
    #' use `$usage` on its [AgentResult] or the `"usage"` event from `$run()`.
    #'
    #' @return An [AgentUsage] object.
    usage = function() {
      agent_usage_snapshot(private$.chat)
    },

    #' @description
    #' Stop the current run, and any subagent runs it started.
    #'
    #' The run stops as soon as ellmer allows, usually during the current model
    #' request or before the next tool call. An [McpConnection] call in progress
    #' is stopped by closing its connection, which loses the server's session
    #' state.
    #'
    #' @param reason Stop reason recorded on the run's `"stop"` event and
    #'   result.
    #' @return `TRUE`, invisibly, if anything was running.
    interrupt = function(reason = "interrupted") {
      private$interrupt_run(reason)
    },

    #' @description
    #' Get the provider and model names.
    #'
    #' @return A list with `name` and `model`.
    provider = function() {
      provider <- private$.chat$get_provider()
      list(
        name = provider@name,
        model = private$.chat$get_model()
      )
    },

    #' @description
    #' Save the conversation to an `.rds` file that `$load_session()` can
    #' restore.
    #'
    #' @param path File path.
    #' @return The path, invisibly.
    #'
    #' @details
    #' The file holds the conversation (including turns removed by compaction),
    #' the system prompt and any compaction summary, copies of large tool
    #' results, the run context, file checkpoint state (when enabled) and some
    #' metadata, such as the time, Deputy version and provider. It doesn't hold
    #' tools, permissions, hooks or the Chat itself.
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
    #' Load a conversation saved by `$save_session()`.
    #'
    #' @param path Path to the session file.
    #' @return The agent, invisibly.
    #'
    #' @details
    #' Tools, permissions, hooks and the working directory come from the agent
    #' you load into, not from the file. The saved `run_context` is merged into
    #' the agent's, and loading fails if they disagree on an ID field. Saved
    #' tool results and compaction summaries are restored under this agent's
    #' session ID. Files saved by early development versions of Deputy can't be
    #' loaded. Loading errors while a run is active.
    load_session = function(path) {
      check_conversation_lease(self, NULL)
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
    #' Get the tool approval this agent is waiting on.
    #' @return An [ApprovalContinuation], or `NULL` if nothing is waiting. Its
    #'   `source$path` is the path to pass to `$resume_approval()`.
    pending_approval = function() {
      if (is.null(private$.pending_approval_path)) {
        return(NULL)
      }
      approval_read(private$.pending_approval_path)
    },

    #' @description
    #' Approve or deny a tool call that is waiting for approval, then continue
    #' the run. Both the saved permissions and the agent's current permissions
    #' apply. After restarting R, first create an agent with the same
    #' `session_id`, `agent_id`, `working_dir` and `approval_dir`, the same tool
    #' definition (with `convert = FALSE`) and the permission callback. Tool
    #' calls that already ran are not run again, and each approval can be
    #' decided only once.
    #' @param path The approval's directory, from the `"approval"` event or
    #'   `$pending_approval()`.
    #' @param decision `"approve"` or `"deny"`.
    #' @param tool_input Optional named list of edited tool arguments to use
    #'   instead of the original ones. Only allowed with `"approve"`.
    #' @param usage_limits Optional [UsageLimits] for the resumed run. They
    #'   can't exceed the agent's limits at the time of suspension or now, and
    #'   usage from before the suspension still counts. `NULL` keeps the
    #'   suspended run's limits.
    #' @return An [AgentResult]. Its usage includes the work done before the
    #'   suspension.
    resume_approval = function(
      path,
      decision = c("approve", "deny"),
      tool_input = NULL,
      usage_limits = NULL
    ) {
      check_conversation_lease(self, NULL)
      decision <- match.arg(decision)
      approval_resume(self, path, decision, tool_input, usage_limits)
    },

    #' @description
    #' Create a file checkpoint that `$rewind_files()` can restore. Needs
    #' `enable_file_checkpointing = TRUE`.
    #'
    #' @param name Optional label.
    #' @param metadata Optional list of metadata to store with it.
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
    #' List file checkpoints.
    #'
    #' @return A data frame, oldest first.
    list_checkpoints = function() {
      private$require_file_checkpoint_store()$list_checkpoints()
    },

    #' @description
    #' Restore files to how they were at a checkpoint. Later checkpoints are
    #' discarded. The conversation doesn't change. Errors during a run.
    #'
    #' @param checkpoint_id A checkpoint ID from `$checkpoint()`,
    #'   `$list_checkpoints()` or a `"file_checkpoint"` event.
    #' @return A list describing the checkpoint, including `restored_changes`,
    #'   the number of file changes undone.
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
    #' Replace older turns in the model context with a summary, so later
    #' requests are smaller. The removed turns stay available from
    #' `$get_turns()`. Errors during a run; runs compact automatically as set
    #' by the [ContextPolicy].
    #'
    #' @param keep_last Number of recent turns to keep. `NULL` keeps as many
    #'   recent turns as fit in `max_tokens * compact_to` of the context policy,
    #'   starting at a user turn, or the last 4 turns if `max_tokens` is `NULL`.
    #' @param summary Optional summary to use. If `NULL`, a `PreCompact` hook
    #'   can supply one; otherwise the model writes one covering decisions,
    #'   findings, files, errors and progress.
    #' @param fallback `"error"` or `"text"`: what to do if the model can't
    #'   write the summary. Defaults to the context policy's `fallback`.
    #' @param automatic Set by the agent when a run compacts automatically.
    #'   Leave it as `FALSE`.
    #' @param estimated_tokens Optional token estimate before compaction,
    #'   recorded in the result.
    #' @return A [DeputyCompaction] describing what happened.
    #'
    #' @details
    #' Compaction:
    #' 1. Fires the `PreCompact` hook, which can cancel compaction or supply a
    #'    summary.
    #' 2. Asks the model to summarise the older turns, unless a summary was
    #'    supplied.
    #' 3. Appends the summary to the system prompt under "Previous Conversation
    #'    Summary".
    #' 4. Keeps only the last `keep_last` turns in the model context.
    #'
    #' If the model can't write a summary, `$compact()` errors, unless
    #' `fallback = "text"`, which builds a plain summary from the first 200
    #' characters of each turn instead. The result's `method` shows which was
    #' used.
    compact = function(
      keep_last = NULL,
      summary = NULL,
      fallback = self$context_policy$fallback,
      automatic = FALSE,
      estimated_tokens = NULL
    ) {
      check_conversation_lease(self, NULL)
      if (isTRUE(private$run_active) && !isTRUE(automatic)) {
        cli::cli_abort(
          "Cannot compact conversation state while this agent has an active run",
          class = c("deputy_run_active", "deputy_error")
        )
      }
      plan <- private$prepare_compaction(
        keep_last,
        summary,
        fallback,
        automatic,
        estimated_tokens
      )
      if (!is.null(plan$result)) {
        return(plan$result)
      }
      artifacts <- private$begin_compaction_artifacts()
      on.exit(private$finish_compaction_artifacts(artifacts), add = TRUE)
      generated <- if (is.null(plan$summary)) {
        private$generate_compaction_summary(plan$turns_to_compact, fallback)
      } else {
        list(summary = plan$summary, method = plan$method, usage = AgentUsage())
      }
      private$install_compaction(
        plan,
        generated$summary,
        generated$method,
        generated$usage
      )
    },

    #' @description
    #' Clear old tool results from the model's context, as Posit Assistant's
    #' `/microcompact` does.
    #'
    #' Every tool result before the last `keep_last` turns has its value
    #' replaced by `marker` in the model's context, unless its tool is named in
    #' `keep_tools`. Nothing is summarised and no model call is made. Any
    #' earlier compaction summary is kept. Errors during a run.
    #'
    #' Like compaction, this changes only what the model sees. `$get_turns()`,
    #' `$last_turn()` and saved sessions keep the original results, so your
    #' app's conversation history is unchanged. `$get_context_turns()` shows
    #' the markers.
    #'
    #' @param keep_last Number of recent turns whose tool results are left as
    #'   they are. `Inf` keeps every turn.
    #' @param keep_tools Names of tools whose results are never cleared.
    #' @param marker The text that replaces a cleared result.
    #' @return A list with `cleared`, the number of tool results replaced.
    microcompact = function(
      keep_last = 2L,
      keep_tools = character(),
      marker = "[Old tool result cleared to save context.]"
    ) {
      check_conversation_lease(self, NULL)
      if (isTRUE(private$run_active)) {
        cli::cli_abort(
          "Cannot microcompact conversation state while this agent has an active run",
          class = c("deputy_run_active", "deputy_error")
        )
      }
      if (
        !is.numeric(keep_last) ||
          length(keep_last) != 1L ||
          is.na(keep_last) ||
          keep_last < 0 ||
          (is.finite(keep_last) && keep_last != floor(keep_last))
      ) {
        cli::cli_abort(
          "{.arg keep_last} must be a whole number of turns, 0 or more."
        )
      }
      if (!is.character(keep_tools) || anyNA(keep_tools)) {
        cli::cli_abort("{.arg keep_tools} must be a character vector.")
      }
      if (!is_nonempty_string(marker)) {
        cli::cli_abort("{.arg marker} must be one non-empty string.")
      }
      turns <- private$.chat$get_turns()
      # keep_last may be Inf or larger than the conversation: keep everything.
      upto <- if (keep_last >= length(turns)) {
        0L
      } else {
        length(turns) - as.integer(keep_last)
      }
      # Originals are keyed by position in the complete conversation, which
      # compaction and new turns do not shift. Tool call IDs can repeat.
      offset <- length(private$.compacted_turns)
      originals <- private$.cleared_tool_results
      cleared <- 0L
      for (i in seq_len(upto)) {
        contents <- turns[[i]]@contents
        changed <- FALSE
        for (j in seq_along(contents)) {
          content <- contents[[j]]
          if (!S7::S7_inherits(content, ellmer::ContentToolResult)) {
            next
          }
          name <- tryCatch(content@request@name, error = function(e) NULL)
          if (!is.null(name) && name %in% keep_tools) {
            next
          }
          key <- cleared_result_key(offset + i, j)
          # Already cleared: keep its first original and marker.
          if (!is.null(originals[[key]])) {
            next
          }
          originals[[key]] <- list(marker = marker, content = content)
          content@value <- marker
          content@error <- NULL
          contents[[j]] <- content
          changed <- TRUE
          cleared <- cleared + 1L
        }
        if (changed) {
          turns[[i]]@contents <- contents
        }
      }
      if (cleared > 0L) {
        private$.chat$set_turns(turns)
        private$.cleared_tool_results <- originals
      }
      list(cleared = cleared)
    },

    #' @description
    #' Print a summary of the agent.
    print = function() {
      cli::cat_line(cli::cli_format_method({
        provider_info <- self$provider()
        tools <- private$.chat$get_tools()

        cli::cli_text("<Agent>")
        cli::cli_div(theme = list(div = list("margin-left" = 2)))
        cli::cli_text("agent_id: {self$agent_id}")
        if (!is.null(self$agent_name)) {
          cli::cli_text("agent_name: {self$agent_name}")
        }
        cli::cli_text("provider: {provider_info$name}")
        cli::cli_text("model: {provider_info$model}")
        cli::cli_text("tools: {length(tools)} registered")
        if (length(tools) > 0) {
          tool_names <- names(tools)
          if (length(tool_names) > 5) {
            tool_names <- c(tool_names[1:5], "...")
          }
          cli::cli_text("{paste(tool_names, collapse = \", \")}")
        }
        cli::cli_text("working_dir: {self$working_dir}")
        cli::cli_text("permissions:")
        cli::cli_text("mode: {self$permissions$mode}")
      }))
      invisible(self)
    },

    #' @description
    #' Load a [Skill]: register its tools and append its prompt to the system
    #' prompt. Warns if packages the skill needs are missing or it expects a
    #' different provider.
    #'
    #' @param skill A [Skill] object or path to a skill directory.
    #' @param allow_conflicts If `TRUE`, the skill's tools replace registered
    #'   tools with the same names, with a warning. If `FALSE` (the default), a
    #'   name clash is an error.
    #' @return The agent, invisibly, for chaining.
    load_skill = function(skill, allow_conflicts = FALSE) {
      check_conversation_lease(self, NULL)
      if (is.character(skill)) {
        # Load from path
        skill <- skill_load(skill)
      }

      if (!S7::S7_inherits(skill, Skill)) {
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
      req_check <- skill_check_requirements(skill, current_provider)

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
    #' Get the loaded skills.
    #'
    #' @return Named list of [Skill] objects.
    skills = function() {
      if (is.null(private$loaded_skills)) {
        return(list())
      }
      private$loaded_skills
    },

    #' @description
    #' Load tools from the MCP (Model Context Protocol) servers in an mcptools
    #' configuration file.
    #'
    #' Needs the mcptools package. If it isn't installed or the tools can't be
    #' fetched, this warns and loads nothing; `$mcp_status()` records each
    #' attempt. If a reload fails, tools whose connections were closed are
    #' removed and the rest stay.
    #'
    #' @param config Path to the configuration file. `NULL` uses the mcptools
    #'   default, `~/.config/mcptools/config.json`.
    #' @param servers Names of the servers to load from. `NULL` loads from all
    #'   of them.
    #' @param replace If `TRUE`, replace the tools loaded earlier from these
    #'   servers, dropping any a server no longer offers, and replace any other
    #'   tools with the same names. If `FALSE`, a name clash is an error.
    #' @return The agent, invisibly, for chaining.
    load_mcp = function(config = NULL, servers = NULL, replace = FALSE) {
      check_conversation_lease(self, NULL)
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
    #' Get the names of loaded MCP tools.
    #'
    #' @return A character vector.
    mcp_tools = function() {
      private$loaded_mcp_tools
    },

    #' @description
    #' Get a log of `$load_mcp()` calls.
    #'
    #' @return A data frame with one row per call: `status` (`"connected"`,
    #'   `"empty"`, `"failed"` or `"unavailable"`), `config`, `servers`,
    #'   `tools`, `loaded_at` and `error`.
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
    #' Run a task asynchronously. Works like `$run_sync()` but returns a
    #' promise, so you can use it from async code, such as a Shiny app or a
    #' tool that runs another agent while its own chat is streaming.
    #'
    #' @param task The task for the agent.
    #' @param usage_limits [UsageLimits] for this run. `NULL` fields use the
    #'   agent's limits.
    #' @param run_context Named list merged into the agent's `run_context` for
    #'   this run. It can't change or remove ID fields (keys ending in `id`)
    #'   that the agent already sets.
    #' @return A promise that resolves to an [AgentResult]. It is rejected if
    #'   the provider request fails or a limit with `on_exceed = "error"` is
    #'   reached.
    #' @param type Optional ellmer type, such as `ellmer::type_object()`. After
    #'   the task, the agent extracts data of this type from the conversation
    #'   into `result$structured_output`. This counts toward the run's limits.
    #' @param validate Optional function that checks the extracted value. Return
    #'   `TRUE` to accept it, or `FALSE` or a message to reject it; a message is
    #'   sent to the model as feedback. An error or any other return value, such
    #'   as `NA`, ends the run with an error.
    #' @param max_corrections How many times to ask the model to fix a rejected
    #'   value. Defaults to 0. If the value is still rejected, the run errors.
    #'   Every attempt counts toward the run's limits.
    run_async = function(
      task,
      usage_limits = NULL,
      run_context = list(),
      type = NULL,
      validate = NULL,
      max_corrections = 0L
    ) {
      structured <- structured_run_spec(type, validate, max_corrections)
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
        stream = "content",
        extraction = structured
      )
      private$collect_governed_stream(governed_run)
    }
  ),
  active = list(
    #' @field agent_id The agent's ID. Read-only.
    agent_id = function(value) {
      if (missing(value)) {
        return(private$.agent_id)
      }
      cli_abort("Cannot modify agent: agent_id is immutable after construction")
    },

    #' @field agent_name The agent's name, or `NULL`. Read-only.
    agent_name = function(value) {
      if (missing(value)) {
        return(private$.agent_name)
      }
      cli_abort(
        "Cannot modify agent: agent_name is immutable after construction"
      )
    },

    #' @field run_context The `run_context` attached to every run. Read-only.
    run_context = function(value) {
      if (missing(value)) {
        return(clone_run_context(private$.run_context))
      }
      cli_abort(
        "Cannot modify agent: run_context is immutable after construction"
      )
    },

    #' @field trusted_results The [TrustedResults] policy, or `NULL`. Read-only.
    trusted_results = function(value) {
      if (missing(value)) {
        return(private$.trusted_results)
      }
      cli_abort(
        "Cannot modify agent: trusted_results are immutable after construction"
      )
    },

    #' @field permissions The agent's [Permissions]. Read-only; use
    #'   `$set_permission_mode()` to narrow them.
    permissions = function(value) {
      if (missing(value)) {
        return(private$.permissions)
      }
      cli_abort(
        "Cannot modify agent: permissions are immutable after construction"
      )
    },

    #' @field usage_limits The [UsageLimits] applied to each run. Read-only.
    usage_limits = function(value) {
      if (missing(value)) {
        return(private$.usage_limits)
      }
      cli_abort(
        "Cannot modify agent: usage_limits are immutable after construction"
      )
    },

    #' @field context_policy The agent's [ContextPolicy]. Read-only.
    context_policy = function(value) {
      if (missing(value)) {
        return(normalize_context_policy(private$.context_policy))
      }
      cli_abort(
        "Cannot modify agent: context_policy is immutable after construction"
      )
    },

    #' @field working_dir The directory file tools work in. Read-only.
    working_dir = function(value) {
      if (missing(value)) {
        return(private$.working_dir)
      }
      cli_abort(
        "Cannot modify agent: working_dir is immutable after construction"
      )
    },

    #' @field hooks The agent's [HookRegistry]. The field can't be replaced; add
    #'   hooks with `$add_hook()`.
    hooks = function(value) {
      if (missing(value)) {
        return(private$.hooks)
      }
      cli_abort("Cannot modify agent: hooks are immutable after construction")
    }
  ),

  private = c(
    list(
      derive_subagent_usage_limits = function(def) {
        limits <- private$current_usage_limits %||% self$usage_limits
        current <- if (isTRUE(private$run_active)) {
          private$current_run_usage()
        } else {
          AgentUsage()
        }
        usage_fields <- c(
          max_requests = "requests",
          max_tool_calls = "tool_calls",
          max_input_tokens = "input_tokens",
          max_output_tokens = "output_tokens",
          max_total_tokens = "total_tokens",
          max_cost_usd = "cost_usd"
        )
        reserved <- private$reserved_delegation_usage()
        remaining <- lapply(names(usage_fields), function(limit_field) {
          limit <- S7::prop(limits, limit_field)
          if (is.null(limit)) {
            return(NULL)
          }
          max(
            0,
            limit -
              S7::prop(current, usage_fields[[limit_field]]) -
              reserved[[limit_field]]
          )
        })
        names(remaining) <- names(usage_fields)
        if (!is.null(def$max_requests)) {
          remaining$max_requests <- if (is.null(remaining$max_requests)) {
            def$max_requests
          } else {
            min(remaining$max_requests, def$max_requests)
          }
        }

        do.call(
          UsageLimits,
          c(remaining, list(on_exceed = limits$on_exceed))
        )
      },

      reserve_delegation_usage = function(delegation_id, limits) {
        fields <- c(
          "max_requests",
          "max_tool_calls",
          "max_input_tokens",
          "max_output_tokens",
          "max_total_tokens",
          "max_cost_usd"
        )
        private$delegation_usage_reservations[[delegation_id]] <- vapply(
          fields,
          function(field) S7::prop(limits, field) %||% 0,
          numeric(1)
        )
        if (is.function(private$.job_checkpoint)) {
          private$.job_checkpoint(
            self,
            list(
              type = "delegation_reserved",
              delegation_id = delegation_id
            )
          )
        }
        invisible(NULL)
      },

      release_delegation_usage = function(delegation_id) {
        private$delegation_usage_reservations[[delegation_id]] <- NULL
        if (is.function(private$.job_checkpoint)) {
          private$.job_checkpoint(
            self,
            list(
              type = "delegation_released",
              delegation_id = delegation_id
            )
          )
        }
        invisible(NULL)
      },

      reserved_delegation_usage = function() {
        fields <- c(
          "max_requests",
          "max_tool_calls",
          "max_input_tokens",
          "max_output_tokens",
          "max_total_tokens",
          "max_cost_usd"
        )
        reserved <- stats::setNames(numeric(length(fields)), fields)
        for (reservation in private$delegation_usage_reservations) {
          reserved <- reserved + reservation[fields]
        }
        reserved
      },

      .delegation_disclosure = NULL,
      .delegation_buffer = NULL,
      delegation_bindings = list(),
      subagent_runs = list(),
      active_subagents = list(),
      delegation_scope = list(),
      delegation_max_bytes = 65536L,
      delegation_usage_reservations = list(),
      .conversation_owner = NULL,
      .delegation_tree = NULL,
      .delegation_ancestors = NULL,
      owned_conversations = list(),
      .chat = NULL,
      .fallback_chats = list(),
      .fallback_position = 0L,
      .permissions = NULL,
      .trusted_results = NULL,
      # Delegated children receive the lead's tree view: designated tools may
      # live elsewhere in the tree but must be the same executables.
      .trusted_tree_member = FALSE,
      .trusted_sources = NULL,
      .usage_limits = NULL,
      .context_policy = NULL,
      .working_dir = NULL,
      .hooks = NULL,
      .delegation_guard = NULL,
      .delegation_binding = NULL,
      .delegation_observe = NULL,
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

      # Pending executions retain cancellation even if registered tools change.
      active_owned_tools = list(),

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
      trusted_arguments = list(),
      delegation_artifacts = list(),
      last_run_usage = NULL,
      .last_run_result = NULL,
      last_limit_status = NULL,
      last_tool_cycle_signature = NULL,
      consecutive_tool_cycles = 0L,
      .last_compaction = NULL,
      .compaction_summary = NULL,
      .compacted_turns = list(),
      # Original tool results cleared from model context by microcompact(),
      # keyed by tool call ID, so the conversation view keeps them.
      .cleared_tool_results = list(),
      .compaction_catalog_registry = NULL,
      .compaction_artifacts = NULL,
      .tool_result_reader_registered = FALSE,
      .tool_request_observers = list(),
      .tool_result_observers = list(),
      .tool_observer_id = 0L,
      .tool_observer_removers = list(),
      .r6_clone = NULL,
      current_run_checkpoint_id = NULL,

      interrupt_run = function(reason, conversation_token = NULL) {
        check_conversation_access(self, conversation_token)
        interrupted <- isTRUE(graph_cancel_descendants(self, reason))
        for (id in names(private$active_subagents)) {
          interrupted <- isTRUE(self$interrupt_subagent(id, reason)) ||
            interrupted
        }
        if (!isTRUE(private$run_active)) {
          return(invisible(interrupted))
        }
        private$request_stream_stop(as.character(reason[[1]]))
        invisible(TRUE)
      },

      clone_client = function(deep = FALSE) {
        invisible(deep)
        if (
          !is.null(private$.conversation_owner) ||
            !is.null(attr(
              private$.chat,
              "deputy_conversation_owner",
              exact = TRUE
            )) ||
            length(private$owned_conversations)
        ) {
          conversation_abort(
            "Release retained conversations before cloning an Agent."
          )
        }
        cloned <- private$.r6_clone(deep = TRUE)
        reg.finalizer(cloned, finalize_owned_conversations, onexit = TRUE)
        cloned$.__enclos_env__$private$active_owned_tools <- list()
        cloned$.__enclos_env__$private$rewire_chat_runtime()
        cloned$.__enclos_env__$private$.compaction_artifacts <- NULL
        register_compaction_catalog_owner(
          private$.compaction_catalog_registry,
          cloned
        )
        cloned
      },

      deep_clone = function(name, value) {
        if (identical(name, ".delegation_buffer") && !is.null(value)) {
          return(new_delegation_buffer(value$policy))
        }
        if (identical(name, ".delegation_observe")) {
          return(NULL)
        }
        if (identical(name, ".chat") && is.function(value$clone)) {
          return(clone_governed_chat(value))
        }
        is_r6_object <- is.environment(value) &&
          !is.null(get0(".__enclos_env__", value, inherits = FALSE))
        if (is_r6_object) {
          return(value$clone(deep = TRUE))
        }
        value
      },

      rewire_chat_runtime = function() {
        clear_chat_tool_callbacks(private$.chat)

        tools <- private$.chat$get_tools()
        had_result_reader <- "deputy_read_tool_result" %in% names(tools)
        tools[["deputy_read_tool_result"]] <- NULL
        tools <- validate_tool_batch(tools)
        private$check_trusted_tools(tools)
        private$.chat$set_tools(lapply(tools, private$prepare_cloned_tool))
        private$.tool_result_reader_registered <- FALSE
        if (isTRUE(had_result_reader)) {
          private$ensure_tool_result_reader()
        }
        private$.chat$on_tool_request(private$handle_tool_request)
        private$.chat$on_tool_result(private$handle_tool_result)
        rebind_tool_observers(self)
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
        validate_composition_tool_owner(tool, self)
        validate_mcp_tool_owner(tool, self)
        validate_r_session_tool_owner(tool, self)
        if (inherits(tool, "ellmer::ToolBuiltIn")) {
          if (!is.null(private$.approval_dir)) {
            approval_abort(
              "Durable approvals require function tools; provider-native effects cannot be journaled."
            )
          }
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
          permission <- permissions_check(
            self$permissions,
            tool_name,
            list(),
            list(
              working_dir = private$.working_dir,
              tool_annotations = tool@annotations
            )
          )
          if (S7::S7_inherits(permission, PermissionResultDeny)) {
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
          process_result = private$process_tool_result,
          begin_execution = private$begin_tool_execution,
          execute = private$execute_tool,
          invocation_id = private$tool_invocation_id
        )
      },

      # Trusted tools run only as the tool of ellmer's active request, so host
      # code or another tool cannot claim a pending governed call or publish.
      tool_invocation_id = function(tool, arguments) {
        if (is.null(trusted_result_type(private$.trusted_results, tool@name))) {
          return(composition_invocation_id(tool, arguments))
        }
        trusted_invocation_id(tool)
      },

      execute_tool = function(tool, arguments, execution_id = NULL) {
        validate_composition_tool_owner(tool, self)
        if (
          !is.null(trusted_result_type(private$.trusted_results, tool@name))
        ) {
          if (!is_nonempty_string(execution_id)) {
            trusted_invocation_abort(tool@name)
          }
          private$trusted_arguments[[execution_id]] <- arguments
        }
        if (!is.null(composition_tool_owner(tool))) {
          if (
            !isTRUE(private$run_active) || !is_nonempty_string(execution_id)
          ) {
            conversation_abort(
              "Delegation tools require their owner's active governed run."
            )
          }
          correlation <- private$claim_delegation(
            tool_name = tool@name,
            tool_call_id = execution_id,
            required = TRUE
          )
          invoke <- attr(tool, "deputy_composition_invoke", exact = TRUE)
          return(invoke(arguments$task, correlation))
        }
        validate_mcp_tool_owner(tool, self, private$effective_run_context())
        validate_r_session_tool_owner(
          tool,
          self,
          private$effective_run_context()
        )
        workspace_runner <- attr(
          tool,
          "deputy_workspace_runner",
          exact = TRUE
        )
        if (is.function(workspace_runner)) {
          return(workspace_runner(arguments, private$.working_dir))
        }
        source <- attr(tool, "deputy_runtime_source_tool", exact = TRUE) %||%
          tool
        cancel <- attr(source, "deputy_mcp_cancel_active", exact = TRUE) %||%
          attr(source, "deputy_r_session_cancel_active", exact = TRUE)
        if (!is.function(cancel)) {
          return(do.call(tool, arguments))
        }
        id <- new_deputy_id("owned_call_")
        private$active_owned_tools[[id]] <- source
        pending <- FALSE
        on.exit({
          if (!pending) {
            private$active_owned_tools[[id]] <- NULL
          }
        })
        invoke <- attr(source, "deputy_r_session_invoke", exact = TRUE)
        value <- if (is.function(invoke)) {
          invoke(arguments$code, execution_id)
        } else {
          do.call(tool, arguments)
        }
        if (!promises::is.promising(value)) {
          return(value)
        }
        result <- promises::finally(value, function() {
          private$active_owned_tools[[id]] <- NULL
        })
        pending <- TRUE
        result
      },

      check_trusted_tools = function(tools) {
        policy <- private$.trusted_results
        check_trusted_registry(
          policy,
          tools,
          available = if (isTRUE(private$.trusted_tree_member)) {
            policy@results
          } else {
            names(tools)
          },
          sources = private$.trusted_sources,
          require_source = isTRUE(private$.trusted_tree_member)
        )
      },

      process_tool_result = function(tool_name, value, execution_id = NULL) {
        type <- trusted_result_type(private$.trusted_results, tool_name)
        if (!is.null(type)) {
          value <- private$deliver_trusted_result(
            type,
            tool_name,
            value,
            execution_id
          )
        }
        private$offload_tool_result(tool_name, value, execution_id)
      },

      # The trusted tool's return value reaches the host before any model
      # output, independently of offloading and PostToolUse event rewrites.
      deliver_trusted_result = function(type, tool_name, value, execution_id) {
        arguments <- NULL
        if (is_nonempty_string(execution_id)) {
          arguments <- private$trusted_arguments[[execution_id]]
          private$trusted_arguments[[execution_id]] <- NULL
        }
        if (
          inherits(value, "ellmer::ContentToolResult") && !is.null(value@error)
        ) {
          return(value)
        }
        policy <- private$.trusted_results
        result_id <- new_deputy_id("result_")
        event <- private$agent_event(
          "trusted_result",
          result_id = result_id,
          result_type = type,
          tool_name = tool_name,
          tool_call_id = execution_id,
          arguments = arguments,
          value = value
        )
        private$record_run_event(event)
        if (is.function(policy@on_result)) {
          delivered <- tryCatch(
            {
              policy@on_result(event)
              TRUE
            },
            error = function(error) error
          )
          if (!isTRUE(delivered)) {
            private$notify(
              paste0(
                "Trusted result ",
                result_id,
                " was produced but the host callback failed: ",
                conditionMessage(delivered)
              ),
              level = "warning",
              code = "trusted_result_delivery_failed",
              tool_name = tool_name,
              result_id = result_id,
              result_type = type
            )
            abort_tool_execution(
              "Trusted result {result_id} was produced but could not be delivered to the user.",
              tool_name = tool_name
            )
          }
        }
        if (isTRUE(policy@model_receipt)) {
          return(trusted_result_receipt(result_id, type))
        }
        value
      },

      offload_tool_result = function(tool_name, value, execution_id = NULL) {
        if (identical(tool_name, "deputy_read_tool_result")) {
          return(value)
        }
        rich <- bound_rich_tool_result(
          value,
          tool_name,
          private$.context_policy,
          private$.session_id,
          private$.agent_id
        )
        record <- if (!is.null(rich)) {
          rich$record
        } else {
          offload_tool_result(
            value = value,
            tool_name = tool_name,
            policy = private$.context_policy,
            session_id = private$.session_id,
            agent_id = private$.agent_id
          )
        }
        if (is.null(record)) {
          return(value)
        }
        # Returning a result to the caller claims it independently of any
        # concurrent compaction that first created these content-addressed bytes.
        private$.compaction_catalog_registry$provisional[[record$id]] <- NULL
        private$ensure_tool_result_reader()
        if (!is.null(private$.delegation_id)) {
          private$delegation_artifacts[[
            length(private$delegation_artifacts) + 1L
          ]] <- list(
            reference = record$uri,
            source = "tool_result",
            bytes = record$bytes,
            sha256 = record$sha256,
            agent_id = private$.agent_id,
            run_id = private$current_run_id,
            delegation_id = private$.delegation_id,
            tool_call_id = execution_id,
            tool_name = tool_name,
            storage_session_id = private$.session_id,
            verification = "not_assessed",
            approval = "not_granted"
          )
        }
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
          native <- inherits(value, "ellmer::ContentToolResult")
          private$original_tool_results[[execution_id]] <- list(
            value = if (native) value@value else value,
            error = if (native) value@error else NULL
          )
        }
        if (!is.null(rich)) rich$result else tool_result_reference_text(record)
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

      fire_hook = function(event, tool_name = NULL, ...) {
        if (length(self$hooks$get_hooks(event, tool_name))) {
          on.exit(
            private$record_run_event(private$agent_event("hook", hook = event)),
            add = TRUE
          )
        }
        graph_fire_hooks(self, event, tool_name = tool_name, ...)
      },

      record_run_event = function(event) {
        if (is.null(event)) {
          return(invisible(NULL))
        }
        if (is.function(private$.job_checkpoint)) {
          private$.job_checkpoint(self, event)
        }
        state <- private$current_run_state
        if (!is.null(state)) {
          state$events[[length(state$events) + 1L]] <- event
          trace_governance_event(state$trace_span, event)
        }
        if (is.function(private$.delegation_observe)) {
          private$.delegation_observe(event)
        }
        invisible(event)
      },

      # Track hashes of hook-supplied additional_context chunks already appended
      # to the system prompt so repeated hook returns don't grow it unboundedly.
      appended_hook_context_hashes = character(),

      notify = function(message, level = "info", code = NULL, ...) {
        private$fire_hook(
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
        if (!S7::S7_inherits(usage, AgentUsage)) {
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

      # Storage for loaded skills
      loaded_skills = list(),
      .approval_dir = NULL,
      .pending_approval_path = NULL,
      .approval_requests = list(),
      .approval_journal = list(),
      .approval_resume = NULL,
      .approval_ceilings = list(),
      .approval_tools = NULL,
      .approval_grant = NULL,
      .job_checkpoint = NULL,
      .job_state = NULL,

      # Storage for loaded MCP tool names
      loaded_mcp_tools = character(),
      loaded_mcp_status = list(),

      # Tool call counter for callback-based limits
      tool_call_count = 0L,

      # Active tool call limit; NULL means unbounded.
      tool_call_limit = NULL
    ),
    deputy_agent_approval_methods(),
    deputy_agent_stream_methods(),
    deputy_agent_session_methods(),
    deputy_agent_context_methods(),
    deputy_agent_tool_callbacks_methods(),
    deputy_agent_tool_records_methods()
  )
)
