# Graph routes reuse owned continuations; only the root owns lifecycle records.
check_graph_caller <- function(tree, caller) {
  private <- caller$.__enclos_env__$private
  if (
    is.null(tree) ||
      !identical(private$.delegation_tree, tree) ||
      !isTRUE(private$run_active) ||
      is.null(private$.delegation_id)
  ) {
    conversation_abort(
      "A graph route requires its caller's active governed run."
    )
  }
  root <- delegation_tree_root(tree)
  record <- root$.__enclos_env__$private$subagent_runs[[private$.delegation_id]]
  if (is.null(record) || !is.na(record$completed_at)) {
    conversation_abort("The graph caller is no longer active.")
  }
  invisible(NULL)
}

graph_ancestors <- function(root, caller) {
  if (identical(root, caller)) {
    return(list(root))
  }
  check_graph_caller(root$.__enclos_env__$private$.delegation_tree, caller)
  private <- root$.__enclos_env__$private
  id <- caller$.__enclos_env__$private$.delegation_id
  ancestors <- list()
  while (!is.null(id)) {
    record <- private$subagent_runs[[id]]
    agent <- private$active_subagents[[id]]
    if (is.null(record) || is.null(agent)) {
      conversation_abort("The graph invocation ancestry is unavailable.")
    }
    ancestors <- c(list(agent), ancestors)
    id <- record$parent_delegation_id
  }
  c(list(root), ancestors)
}

check_graph_ancestors <- function(root, caller) {
  private <- root$.__enclos_env__$private
  for (ancestor in graph_ancestors(root, caller)) {
    ap <- ancestor$.__enclos_env__$private
    record <- if (!is.null(ap$.delegation_id)) {
      private$subagent_runs[[ap$.delegation_id]]
    }
    if (
      (isTRUE(ap$run_active) && isTRUE(ap$should_stop)) ||
        !is.null(record$cancel_reason)
    ) {
      conversation_abort("The graph invocation or an ancestor has stopped.")
    }
  }
  invisible(NULL)
}

graph_descendants <- function(root, id = NULL) {
  records <- root$.__enclos_env__$private$subagent_runs
  ids <- names(records)
  if (is.null(id)) {
    return(ids[vapply(records, function(x) is.na(x$completed_at), logical(1))])
  }
  selected <- id
  repeat {
    children <- ids[vapply(
      records,
      function(record) {
        !is.null(record$parent_delegation_id) &&
          record$parent_delegation_id %in% selected
      },
      logical(1)
    )]
    added <- setdiff(children, selected)
    if (!length(added)) {
      break
    }
    selected <- c(selected, added)
  }
  selected
}

graph_cancel_descendants <- function(agent, reason) {
  private <- agent$.__enclos_env__$private
  tree <- private$.delegation_tree
  if (is.null(tree)) {
    return(invisible(FALSE))
  }
  root <- delegation_tree_root(tree)
  id <- if (identical(agent, root)) NULL else private$.delegation_id
  if (!identical(agent, root) && is.null(id)) {
    return(invisible(FALSE))
  }
  ids <- setdiff(graph_descendants(root, id), id)
  interrupted <- FALSE
  for (child_id in rev(ids)) {
    interrupted <- isTRUE(interrupt_delegation(root, child_id, reason)) ||
      interrupted
  }
  invisible(interrupted)
}

interrupt_delegation <- function(owner, id, reason) {
  private <- owner$.__enclos_env__$private
  record <- private$subagent_runs[[id]]
  if (
    is.null(record) ||
      !is.na(record$completed_at) ||
      !is.null(record$cancel_reason)
  ) {
    return(invisible(FALSE))
  }
  private$subagent_runs[[id]]$cancel_reason <- reason
  child <- private$active_subagents[[id]]
  if (!is.null(child)) {
    if (!is.null(record$conversation_handle)) {
      entry <- conversation_entry(owner, record$conversation_handle)
      child$.__enclos_env__$private$interrupt_run(reason, entry$token)
    } else {
      child$interrupt(reason)
    }
  }
  invisible(TRUE)
}

# Each ancestor registry runs once. Its explicit allow cannot hide a denial or
# stop from another ancestor, and forwarding never recurses through wrappers.
graph_fire_hooks <- function(agent, event, tool_name = NULL, ...) {
  private <- agent$.__enclos_env__$private
  ancestors <- private$.delegation_ancestors
  if (
    is.null(ancestors) ||
      !event %in% c("PreToolUse", "PostToolUse", "PostToolUseFailure")
  ) {
    return(agent$hooks$fire(event, tool_name = tool_name, ...))
  }
  root <- delegation_tree_root(private$.delegation_tree)
  results <- lapply(c(ancestors, list(agent)), function(source) {
    registry <- source$hooks
    before <- length(registry$last_errors())
    value <- registry$fire(event, tool_name = tool_name, ...)
    errors <- registry$last_errors()
    if (length(errors) > before) {
      rp <- root$.__enclos_env__$private
      record <- rp$subagent_runs[[private$.delegation_id]]
      record$hook_error <- paste(
        c(
          record$hook_error,
          vapply(
            errors[seq.int(before + 1L, length(errors))],
            function(x) paste0(x$event, ": ", x$error),
            character(1)
          )
        ),
        collapse = "\n"
      )
      rp$subagent_runs[[private$.delegation_id]] <- record
    }
    value
  })
  class <- if (event == "PreToolUse") {
    HookResultPreToolUse
  } else {
    HookResultPostToolUse
  }
  results <- Filter(function(x) S7::S7_inherits(x, class), results)
  if (!length(results)) {
    return(NULL)
  }
  stopped <- Filter(function(x) !x$continue, results)
  context <- Filter(
    Negate(is.null),
    lapply(results, function(x) x$additional_context)
  )
  context <- if (length(context)) {
    paste(unlist(context), collapse = "\n")
  } else {
    NULL
  }
  stop_reason <- if (length(stopped)) stopped[[1L]]$stop_reason else NULL
  if (event == "PreToolUse") {
    denied <- Filter(function(x) x$permission == "deny", results)
    return(HookResultPreToolUse(
      permission = if (length(denied)) "deny" else "allow",
      reason = if (length(denied)) denied[[1L]]$reason else NULL,
      continue = !length(stopped),
      additional_context = context,
      stop_reason = stop_reason
    ))
  }
  outputs <- Filter(
    Negate(is.null),
    lapply(results, function(x) x$updated_tool_output)
  )
  HookResultPostToolUse(
    continue = !length(stopped),
    suppress_output = any(vapply(
      results,
      function(x) x$suppress_output,
      logical(1)
    )),
    updated_tool_output = if (length(outputs)) outputs[[1L]] else NULL,
    additional_context = context,
    stop_reason = stop_reason
  )
}
