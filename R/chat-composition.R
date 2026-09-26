#' Turn an ellmer chat into a retained agent
#'
#' Copies a configured ellmer chat into a new agent that `owner` keeps for
#' later calls, for example through a [delegation_tool()]. The copy keeps the
#' provider, model settings, system prompt, tools and, optionally, turns, but
#' drops callbacks such as `on_tool_request()`; the new agent's permissions
#' and hooks apply instead. The original chat is unchanged but shares its
#' tools, and any state they hold, with the copy. To keep an existing `Agent`,
#' use `owner$retain_agent()`. See `vignette("retained-agents")`.
#'
#' @param chat A configured ellmer `Chat`.
#' @param owner The [Agent] that will own and call the new agent.
#' @param permissions [Permissions] for the new agent. The owner's current
#'   permissions also apply to every call.
#' @param usage_limits [UsageLimits] for all calls combined.
#' @param history `"retain"` to copy the chat's turns, or `"fresh"` to start
#'   with an empty history.
#' @param callbacks Must be `"replace"`, to confirm that the chat's callbacks
#'   are dropped.
#' @param name Optional display name for the new agent.
#' @param max_runs Maximum number of calls. Defaults to 32.
#' @return A handle for [delegation_tool()] and for `owner`'s
#'   `$continue_agent()`, `$cancel_agent()` and `$release_agent()`. It only
#'   works with `owner`.
#' @export
adopt_chat <- function(
  chat,
  owner,
  permissions,
  usage_limits,
  history,
  callbacks,
  name = NULL,
  max_runs = 32L
) {
  if (!inherits(owner, "Agent") || inherits(chat, "Agent")) {
    conversation_abort("Supply an Agent owner and an unwrapped curated Chat.")
  }
  if (!identical(callbacks, "replace")) {
    conversation_abort("Adoption requires callbacks = 'replace'.")
  }
  history <- match.arg(history, c("retain", "fresh"))
  validate_chat(chat)
  if (!is.null(attr(chat, "deputy_conversation_owner"))) {
    conversation_abort("Release an owned conversation before copying its Chat.")
  }
  if (
    any(vapply(chat$get_tools(), inherits, logical(1), "ellmer::ToolBuiltIn"))
  ) {
    conversation_abort(
      "Provider-native tools cannot bind delegation governance."
    )
  }
  # Reuse the qualified isolated-copy boundary used by compaction, then restore
  # only the explicitly selected curated state. It rejects shared callbacks.
  copy <- clone_compaction_chat(chat)
  copy$set_system_prompt(chat$get_system_prompt())
  copy$set_tools(chat$get_tools())
  if (history == "retain") {
    copy$set_turns(chat$get_turns())
  }
  child <- Agent$new(
    copy,
    permissions = permissions,
    usage_limits = usage_limits,
    agent_name = name,
    working_dir = owner$working_dir
  )
  owner$retain_agent(child, usage_limits, max_runs)
}

#' Create a tool that calls a retained agent
#'
#' Lets `owner`'s model send a task to a retained agent. The model writes only
#' the task; you control the rest, including the agent's model, prompt, tools
#' and budget. Each call continues the same conversation, like
#' `owner$continue_agent()`, and returns a [DelegationOutcome] as JSON. Use
#' the owner's inspection methods, such as `$inspect_subagents()`, for the
#' full history.
#'
#' @param owner The [Agent] that owns the retained agent. Register the tool on
#'   this agent only.
#' @param handle Handle returned by [adopt_chat()] or `owner$retain_agent()`.
#' @param name Tool name, unique among the owner's tools.
#' @param description Tells the model when to use this agent.
#' @param usage_limits [UsageLimits] for each call. A call also can't exceed
#'   the retained agent's remaining budget or the calling run's.
#' @return An ellmer tool. Calling it outside a run of `owner`, or registering
#'   it on another agent, is an error.
#' @export
delegation_tool <- function(owner, handle, name, description, usage_limits) {
  if (!inherits(owner, "Agent")) {
    conversation_abort("owner must be an Agent.")
  }
  conversation_entry(owner, handle)
  name <- delegation_text(name, "name")
  description <- delegation_text(description, "description")
  usage_limits <- normalize_usage_limits(usage_limits)
  make_delegation_tool(owner, handle, name, description, usage_limits)
}

graph_delegation_tool <- function(
  tree,
  caller,
  handle,
  name,
  description,
  usage_limits
) {
  make_delegation_tool(caller, handle, name, description, usage_limits, tree)
}

make_delegation_tool <- function(
  caller,
  handle,
  name,
  description,
  usage_limits,
  tree = NULL
) {
  invoke <- function(task, correlation) {
    owner <- if (is.null(tree)) caller else delegation_tree_root(tree)
    private <- owner$.__enclos_env__$private
    promises::then(
      continue_conversation(
        owner,
        handle,
        task,
        usage_limits,
        correlation,
        caller
      ),
      function(result) {
        record <- private$subagent_runs[[correlation$delegation_id]]
        delegation_json(S7::props(delegation_outcome(record, compact = TRUE)))
      },
      function(error) {
        record <- private$subagent_runs[[correlation$delegation_id]]
        if (is.null(record)) {
          rlang::cnd_signal(error)
        }
        payload <- delegation_json(S7::props(delegation_outcome(
          record,
          compact = TRUE
        )))
        ellmer::tool_reject(paste0(
          "Subagent '",
          inspection_text(record$agent_name %||% "specialist", 512L),
          "' failed.\n",
          payload
        ))
      }
    )
  }
  tool <- ellmer::tool(
    function(task) {
      conversation_abort(
        "Delegation tools require their owner's active governed run."
      )
    },
    name = name,
    description = description,
    arguments = list(
      task = ellmer::type_string("New brief for this specialist")
    ),
    annotations = ellmer::tool_annotations(
      read_only_hint = FALSE,
      destructive_hint = FALSE,
      open_world_hint = FALSE,
      idempotent_hint = FALSE
    )
  )
  attr(tool, "deputy_composition_owner") <- caller
  attr(tool, "deputy_composition_invoke") <- invoke
  tool
}

composition_tool_owner <- function(tool) {
  source <- attr(tool, "deputy_runtime_source_tool", exact = TRUE) %||% tool
  attr(source, "deputy_composition_owner", exact = TRUE)
}

composition_invocation_id <- function(tool, arguments) {
  if (is.null(composition_tool_owner(tool))) {
    return(NULL)
  }
  context <- tryCatch(ellmer::tool_context(), error = function(error) NULL)
  request <- context$request
  source <- if (!is.null(request) && !is.null(request@tool)) {
    attr(request@tool, "deputy_runtime_source_tool", exact = TRUE) %||%
      request@tool
  }
  if (
    is.null(request) ||
      !identical(source, tool) ||
      !identical(request@name, tool@name) ||
      !identical(request@arguments$task, arguments$task) ||
      !is_nonempty_string(request@id)
  ) {
    conversation_abort(
      "Delegation tools require their owner's governed tool invocation."
    )
  }
  request@id
}

validate_composition_tool_owner <- function(tool, agent) {
  owner <- composition_tool_owner(tool)
  if (!is.null(owner) && !identical(owner, agent)) {
    conversation_abort(
      "Delegation tools may only be registered and executed by their owner."
    )
  }
  invisible(NULL)
}
