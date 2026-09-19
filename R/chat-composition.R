#' Adopt a curated Chat for owned delegation
#'
#' Makes an independent conversation copy and explicitly replaces its tool and
#' request callbacks with Deputy governance. Provider configuration, model
#' parameters, system prompt and executable tools are preserved. Tool closures
#' remain shared host resources; copying a Chat is not a sandbox. The original
#' Chat is unchanged. Use `owner$retain_agent()` to transfer an existing Agent.
#'
#' @param chat A configured ellmer Chat with a public `clone()` method.
#' @param owner The host-owned [Agent] that will invoke and inspect this specialist.
#' @param permissions Explicit specialist [Permissions], also bounded by the
#'   caller's current policy on every invocation.
#' @param usage_limits Explicit cumulative [UsageLimits] for the retained handle.
#' @param history Explicit `"retain"` or `"fresh"` choice for copied turns.
#' @param callbacks Must be `"replace"` to acknowledge Deputy callback ownership.
#' @param name Optional specialist display name.
#' @param max_runs Maximum retained invocations, default 32.
#' @return An owner-local conversation handle for [delegation_tool()] and the
#'   owner's continuation, cancellation and release methods.
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

#' Delegate through a host-curated specialist
#'
#' Register this tool only on its owning Agent. The model supplies a new task
#' brief; ownership, provider, prompt, tools and budgets are fixed by the host.
#' Every call uses the same continuation implementation as host follow-ups.
#' Results are compact serializable delegation outcomes; full child history and
#' live activity use the owner's independently authorized inspection APIs.
#'
#' @param owner The [Agent] owning the retained conversation.
#' @param handle Handle returned by [adopt_chat()] or `owner$retain_agent()`.
#' @param name Unique tool name selected by the host.
#' @param description Description telling the caller when to use the specialist.
#' @param usage_limits Explicit per-invocation allocation, intersected with the
#'   remaining conversation and caller budgets.
#' @return An ellmer tool. Direct calls outside its owner's governed tool runtime
#'   reject. Registering the tool on another Agent also rejects.
#' @export
delegation_tool <- function(owner, handle, name, description, usage_limits) {
  if (!inherits(owner, "Agent")) {
    conversation_abort("owner must be an Agent.")
  }
  conversation_entry(owner, handle)
  name <- delegation_text(name, "name")
  description <- delegation_text(description, "description")
  usage_limits <- normalize_usage_limits(usage_limits)
  tool <- ellmer::tool(
    function(task) {
      private <- owner$.__enclos_env__$private
      if (!isTRUE(private$run_active)) {
        conversation_abort(
          "Delegation tools require their owner's active governed run."
        )
      }
      correlation <- private$claim_delegation(tool_name = name, required = TRUE)
      continue_conversation(owner, handle, task, usage_limits, correlation) |>
        promises::then(function(result) {
          record <- private$subagent_runs[[correlation$delegation_id]]
          delegation_json(S7::props(delegation_outcome(record, compact = TRUE)))
        })
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
  attr(tool, "deputy_composition_owner") <- owner
  tool
}

composition_tool_owner <- function(tool) {
  source <- attr(tool, "deputy_runtime_source_tool", exact = TRUE) %||% tool
  attr(source, "deputy_composition_owner", exact = TRUE)
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
