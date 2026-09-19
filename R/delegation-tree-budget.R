#' @include run-usage.R
NULL

# The recursive delegation ledger is deliberately kept separate from the
# delegation runtime.  The root Agent owns this environment, while every
# Agent participating in the graph points at the same environment through its
# private state.  A tree records usage for the lifetime of the graph; a run's
# provider usage is still kept on the Agent and is sampled at run completion.

tree_positive_integer <- function(value, name) {
  if (
    !is.numeric(value) ||
      length(value) != 1L ||
      is.na(value) ||
      !is.finite(value) ||
      value < 1 ||
      value > .Machine$integer.max ||
      value != floor(value)
  ) {
    conversation_abort(paste0(
      name,
      " must be one positive finite whole number."
    ))
  }
  as.integer(value)
}

tree_check_environment <- function(tree) {
  if (!is.environment(tree)) {
    conversation_abort("The delegation tree must be an environment.")
  }
  invisible(tree)
}

tree_check_identifier <- function(value, name) {
  if (
    !is.character(value) ||
      length(value) != 1L ||
      is.na(value) ||
      !nzchar(value)
  ) {
    conversation_abort(paste0(name, " must be one non-empty string."))
  }
  value
}

tree_agent_private <- function(agent) {
  if (!is.environment(agent)) {
    conversation_abort("A delegation tree Agent must be an environment.")
  }
  private <- tryCatch(
    agent$.__enclos_env__$private,
    error = function(error) NULL
  )
  if (!is.environment(private)) {
    conversation_abort("A delegation tree Agent must expose private state.")
  }
  private
}

tree_agent_id <- function(agent) {
  private <- tree_agent_private(agent)
  id <- tryCatch(agent$agent_id, error = function(error) NULL)
  if (is.null(id)) {
    id <- private$.agent_id
  }
  tree_check_identifier(id, "agent_id")
}

tree_run_id <- function(private) {
  id <- private$current_run_id
  tree_check_identifier(id, "current_run_id")
}

tree_require_limits <- function(usage_limits) {
  if (!S7::S7_inherits(usage_limits, UsageLimits)) {
    conversation_abort(
      "{.arg usage_limits} must be an explicit UsageLimits object."
    )
  }
  max_requests <- S7::prop(usage_limits, "max_requests")
  if (
    is.null(max_requests) ||
      length(max_requests) != 1L ||
      !is.numeric(max_requests) ||
      is.na(max_requests) ||
      !is.finite(max_requests)
  ) {
    conversation_abort(
      "A delegation tree requires a finite {.field max_requests} limit."
    )
  }
  usage_limits
}

tree_check <- function(tree) {
  tree_check_environment(tree)
  root_ref <- tree$root
  if (!rlang::is_weakref(root_ref)) {
    conversation_abort("The delegation tree root is not a weak reference.")
  }
  delegation_tree_root(tree)
  invisible(tree)
}

tree_usage_difference <- function(inclusive, descendant) {
  if (!S7::S7_inherits(inclusive, AgentUsage)) {
    conversation_abort("Inclusive delegation usage must be an AgentUsage.")
  }
  if (!S7::S7_inherits(descendant, AgentUsage)) {
    conversation_abort("Descendant delegation usage must be an AgentUsage.")
  }

  subtract <- function(left, right) {
    max(0, left - right)
  }
  cost <- if (is.na(inclusive$cost_usd) || is.na(descendant$cost_usd)) {
    NA_real_
  } else {
    subtract(inclusive$cost_usd, descendant$cost_usd)
  }

  AgentUsage(
    requests = subtract(inclusive$requests, descendant$requests),
    tool_calls = subtract(inclusive$tool_calls, descendant$tool_calls),
    input_tokens = subtract(inclusive$input_tokens, descendant$input_tokens),
    output_tokens = subtract(
      inclusive$output_tokens,
      descendant$output_tokens
    ),
    cached_tokens = subtract(inclusive$cached_tokens, descendant$cached_tokens),
    cost_usd = cost
  )
}

# A model request can be counted before the provider has appended an assistant
# turn. In that interval current_run_usage() deliberately reports unknown cost
# because its forced request count has no cost row yet. Use the unforced
# provider snapshot for a still-live run, while preserving unknown cost after
# a completed response has actually omitted its cost.
tree_sample_run_usage <- function(private) {
  inclusive <- private$current_run_usage()
  if (!S7::S7_inherits(inclusive, AgentUsage)) {
    conversation_abort("An active delegation run must report AgentUsage.")
  }
  if (!is.na(inclusive$cost_usd)) {
    return(inclusive)
  }
  if (isTRUE(private$current_run_state$finished)) {
    return(inclusive)
  }
  baseline <- private$current_usage_baseline
  chat <- private$.chat
  if (
    !S7::S7_inherits(baseline, AgentUsage) ||
      is.null(chat) ||
      !is.function(chat$get_turns) ||
      !is.function(chat$get_tokens)
  ) {
    return(inclusive)
  }
  observed <- tryCatch(
    agent_usage_difference(
      agent_usage_snapshot(chat),
      baseline,
      tool_calls = private$current_tool_calls %||% 0L
    ),
    error = function(error) NULL
  )
  external <- private$current_external_usage %||% AgentUsage()
  if (
    is.null(observed) ||
      is.na(observed$cost_usd) ||
      is.na(external$cost_usd)
  ) {
    return(inclusive)
  }
  AgentUsage(
    requests = inclusive$requests,
    tool_calls = inclusive$tool_calls,
    input_tokens = inclusive$input_tokens,
    output_tokens = inclusive$output_tokens,
    cached_tokens = inclusive$cached_tokens,
    cost_usd = observed$cost_usd + external$cost_usd
  )
}

tree_active_count <- function(tree) {
  if (!length(tree$admissions)) {
    return(0L)
  }
  as.integer(sum(vapply(
    tree$admissions,
    function(admission) isTRUE(admission$active),
    logical(1)
  )))
}

# Create the root-owned bounded delegation ledger. This is an internal
# constructor. `usage_limits` is intentionally explicit: a graph without a
# finite request ceiling cannot make recursive dispatch fail closed.
new_delegation_tree <- function(
  root,
  usage_limits = NULL,
  max_depth,
  max_delegations,
  max_concurrency
) {
  if (!is.environment(root)) {
    conversation_abort("The delegation tree root must be an Agent environment.")
  }
  usage_limits <- tree_require_limits(usage_limits)

  tree <- new.env(parent = emptyenv())
  tree$root <- rlang::new_weakref(root)
  tree$limits <- usage_limits
  tree$max_depth <- tree_positive_integer(max_depth, "max_depth")
  tree$max_delegations <- tree_positive_integer(
    max_delegations,
    "max_delegations"
  )
  tree$max_concurrency <- tree_positive_integer(
    max_concurrency,
    "max_concurrency"
  )
  tree$usage <- AgentUsage()
  tree$active <- list()
  tree$admissions <- list()
  tree$count <- 0L
  tree$agents <- list()
  tree$handles <- character()
  tree$base_hooks <- list()
  tree
}

# Resolve the root Agent held by a delegation tree.
delegation_tree_root <- function(tree) {
  tree_check_environment(tree)
  root_ref <- tree$root
  if (!rlang::is_weakref(root_ref)) {
    conversation_abort("The delegation tree root is not a weak reference.")
  }
  root <- rlang::wref_key(root_ref)
  if (is.null(root)) {
    conversation_abort("The delegation tree root is no longer available.")
  }
  root
}

# Register a governed run before its first model request.  Descendant usage is
# tracked independently because current_run_usage() is inclusive of external
# child usage.
tree_run_started <- function(agent) {
  private <- tree_agent_private(agent)
  tree <- private$.delegation_tree
  if (is.null(tree)) {
    return(invisible(NULL))
  }
  tree_check(tree)
  run_id <- tree_run_id(private)
  if (!is.null(tree$active[[run_id]])) {
    conversation_abort(paste0("Delegation run ", run_id, " is already active."))
  }

  agent_id <- tree_agent_id(agent)
  tree$active[[run_id]] <- list(
    agent = agent,
    agent_id = agent_id,
    descendant_usage = AgentUsage()
  )
  invisible(NULL)
}

# Finish a run while its private usage fields still exist.  The ledger stores
# only the Agent's own usage; inclusive results remain available to the caller
# through tree_child_usage().
tree_run_finished <- function(agent) {
  private <- tree_agent_private(agent)
  tree <- private$.delegation_tree
  if (is.null(tree)) {
    return(invisible(NULL))
  }
  tree_check(tree)
  run_id <- tree_run_id(private)
  entry <- tree$active[[run_id]]
  if (is.null(entry)) {
    return(invisible(NULL))
  }
  inclusive <- tree_sample_run_usage(private)
  descendant <- entry$descendant_usage %||% AgentUsage()
  own <- tree_usage_difference(inclusive, descendant)
  tree$usage <- agent_usage_add(tree$usage, own)
  tree$active[[run_id]] <- NULL
  invisible(own)
}

# Track a child's inclusive result on its immediate caller.  The active run
# record keeps the same amount so the caller's own usage can be recovered when
# it settles. The caller's existing runtime path adds the same result to
# `current_external_usage`; keeping that mutation there avoids adding it twice.
tree_child_usage <- function(caller, usage) {
  private <- tree_agent_private(caller)
  tree <- private$.delegation_tree
  if (is.null(tree)) {
    return(invisible(NULL))
  }
  run_id <- private$current_run_id
  if (is.null(run_id) || is.null(tree$active[[run_id]])) {
    return(invisible(NULL))
  }
  if (!S7::S7_inherits(usage, AgentUsage)) {
    conversation_abort("Child delegation usage must be an AgentUsage.")
  }
  tree_check(tree)
  entry <- tree$active[[run_id]]
  entry$descendant_usage <- agent_usage_add(
    entry$descendant_usage %||% AgentUsage(),
    usage
  )
  tree$active[[run_id]] <- entry
  invisible(NULL)
}

# Return cumulative own usage for completed runs plus the own usage of each
# live run.  Summing recovered own usage avoids charging nested descendants
# again while they are represented in a parent's inclusive provider total.
tree_usage <- function(tree) {
  tree_check(tree)
  usage <- tree$usage
  if (!S7::S7_inherits(usage, AgentUsage)) {
    conversation_abort("The delegation tree must store AgentUsage usage.")
  }
  for (entry in tree$active) {
    if (!is.list(entry) || !is.environment(entry$agent)) {
      conversation_abort("The delegation tree has an invalid active run.")
    }
    private <- tree_agent_private(entry$agent)
    inclusive <- tree_sample_run_usage(private)
    own <- tree_usage_difference(
      inclusive,
      entry$descendant_usage %||% AgentUsage()
    )
    usage <- agent_usage_add(usage, own)
  }
  usage
}

# Evaluate the graph lifetime budget from an Agent.  Agents without a tree are
# ordinary single-conversation Agents and have no graph status to report.
tree_usage_status <- function(agent, require_followup = TRUE) {
  private <- tree_agent_private(agent)
  tree <- private$.delegation_tree
  if (is.null(tree)) {
    return(NULL)
  }
  tree_check(tree)
  status <- usage_limit_status(tree_usage(tree), tree$limits, require_followup)
  if (!is.null(status)) {
    status$on_exceed <- tree$limits$on_exceed
  }
  status
}

# Admit one child invocation.  Admission is the only place that increments
# the lifetime count or reserves a concurrency slot.
tree_admit <- function(tree, id, parent_delegation_id = NULL) {
  tree_check(tree)
  id <- tree_check_identifier(id, "delegation_id")
  if (!is.null(tree$admissions[[id]])) {
    conversation_abort(paste0("Delegation ", id, " has already been admitted."))
  }
  if (!is.null(parent_delegation_id)) {
    parent_delegation_id <- tree_check_identifier(
      parent_delegation_id,
      "parent_delegation_id"
    )
    parent <- tree$admissions[[parent_delegation_id]]
    if (is.null(parent) || !isTRUE(parent$active)) {
      conversation_abort(paste0(
        "Parent delegation ",
        parent_delegation_id,
        " is unknown or settled."
      ))
    }
    depth <- parent$depth + 1L
  } else {
    depth <- 1L
  }
  if (depth > tree$max_depth) {
    conversation_abort(paste0(
      "Delegation ",
      id,
      " exceeds the maximum depth of ",
      tree$max_depth,
      "."
    ))
  }
  if (tree$count >= tree$max_delegations) {
    conversation_abort(paste0(
      "The delegation tree has reached its maximum of ",
      tree$max_delegations,
      " admitted children."
    ))
  }
  if (tree_active_count(tree) >= tree$max_concurrency) {
    conversation_abort(paste0(
      "The delegation tree has reached its maximum concurrency of ",
      tree$max_concurrency,
      "."
    ))
  }

  root <- delegation_tree_root(tree)
  root_agent_id <- tree_agent_id(root)
  tree$admissions[[id]] <- list(
    delegation_id = id,
    parent_delegation_id = parent_delegation_id,
    depth = as.integer(depth),
    root_agent_id = root_agent_id,
    active = TRUE,
    settled = FALSE
  )
  tree$count <- as.integer(tree$count + 1L)
  list(
    parent_delegation_id = parent_delegation_id,
    depth = as.integer(depth),
    root_agent_id = root_agent_id
  )
}

# Mark an admitted child settled.  The record remains in the ledger so that
# lineage can still be inspected and duplicate identifiers cannot be reused.
tree_settle <- function(tree, id) {
  tree_check(tree)
  id <- tree_check_identifier(id, "delegation_id")
  admission <- tree$admissions[[id]]
  if (is.null(admission)) {
    conversation_abort(paste0("Delegation ", id, " has not been admitted."))
  }
  if (!isTRUE(admission$active)) {
    return(invisible(admission))
  }
  admission$active <- FALSE
  admission$settled <- TRUE
  tree$admissions[[id]] <- admission
  invisible(admission)
}
