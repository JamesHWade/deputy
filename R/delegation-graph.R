# Host-owned recursive delegation graph configuration and teardown.

graph_abort <- function(message) {
  conversation_abort(message)
}

graph_plain_text <- function(value, field) {
  if (
    !is.character(value) ||
      length(value) != 1L ||
      is.na(value) ||
      !is.null(attributes(value)) ||
      !nzchar(trimws(value))
  ) {
    graph_abort(paste0(field, " must be one non-empty text string."))
  }
  value
}

graph_positive_integer <- function(value, field) {
  tryCatch(
    context_policy_whole_number(value, field),
    error = function(error) graph_abort(conditionMessage(error))
  )
}

graph_agent_private <- function(agent) {
  agent$.__enclos_env__$private
}

graph_chat <- function(agent) {
  graph_agent_private(agent)$.chat
}

graph_node_tools <- function(agent) {
  graph_chat(agent)$get_tools()
}

graph_tool_source <- function(tool) {
  attr(tool, "deputy_runtime_source_tool", exact = TRUE) %||% tool
}

graph_tool_is_composition <- function(tool) {
  source <- graph_tool_source(tool)
  !is.null(composition_tool_owner(source))
}

graph_tool_is_delegation <- function(tool) {
  source <- graph_tool_source(tool)
  isTRUE(attr(source, "deputy_delegation_tool", exact = TRUE)) ||
    identical(
      tryCatch(source@name, error = function(error) NULL),
      "delegate_to_agent"
    )
}

graph_tool_is_native <- function(tool) {
  inherits(tool, "ellmer::ToolBuiltIn") ||
    inherits(graph_tool_source(tool), "ellmer::ToolBuiltIn")
}

graph_validate_root <- function(owner) {
  if (!inherits(owner, "Agent") || inherits(owner, "LeadAgent")) {
    graph_abort("A delegation graph requires a standalone Agent root.")
  }
  private <- graph_agent_private(owner)
  if (
    isTRUE(private$run_active) ||
      length(private$active_subagents) ||
      length(private$owned_conversations) ||
      !is.null(private$.conversation_owner) ||
      !is.null(private$.delegation_tree) ||
      !is.null(attr(
        private$.chat,
        "deputy_conversation_owner",
        exact = TRUE
      )) ||
      !is.null(attr(private$.chat, "deputy_active_runtime", exact = TRUE)) ||
      length(attr(private$.chat, "deputy_active_conversations", exact = TRUE))
  ) {
    graph_abort("The graph root is active or already owned.")
  }
  if (
    !is.null(private$.approval_dir) || !is.null(private$.pending_approval_path)
  ) {
    graph_abort("Delegation graphs do not support durable approvals.")
  }
  if (length(private$.fallback_chats)) {
    graph_abort("Delegation graphs require one configured provider.")
  }
  invisible(NULL)
}

graph_validate_agents <- function(owner, agents) {
  if (
    !is.list(agents) ||
      is.object(agents) ||
      !length(agents) ||
      is.null(names(agents)) ||
      anyDuplicated(names(agents))
  ) {
    graph_abort("agents must be a non-empty named list of distinct Agents.")
  }
  names(agents) <- vapply(
    names(agents),
    graph_plain_text,
    character(1),
    field = "agent name"
  )
  if (any(names(agents) == "root")) {
    graph_abort("The name 'root' is reserved for the graph owner.")
  }
  if (anyDuplicated(names(agents))) {
    graph_abort("Agent names must be unique.")
  }

  graph_validate_root(owner)
  all_agents <- c(list(root = owner), agents)
  all_private <- lapply(all_agents, graph_agent_private)
  for (index in seq_along(agents)) {
    validate_conversation_candidate(owner, agents[[index]])
    candidate_private <- all_private[[index + 1L]]
    if (!is.null(candidate_private$.delegation_tree)) {
      graph_abort("Graph members cannot already belong to a delegation graph.")
    }
  }
  if (length(all_agents) > 1L) {
    for (left in seq_len(length(all_agents) - 1L)) {
      for (right in seq.int(left + 1L, length(all_agents))) {
        if (
          identical(all_agents[[left]], all_agents[[right]]) ||
            identical(all_private[[left]]$.chat, all_private[[right]]$.chat)
        ) {
          graph_abort("Graph nodes must use distinct Agents and Chats.")
        }
      }
    }
  }
  invisible(agents)
}

graph_validate_existing_tools <- function(agent, node_name) {
  tools <- graph_node_tools(agent)
  if (is.null(tools)) {
    return(invisible(NULL))
  }
  tool_names <- names(tools)
  if (
    length(tools) &&
      (is.null(tool_names) || anyNA(tool_names) || !all(nzchar(tool_names)))
  ) {
    graph_abort(paste0("Tools on graph node '", node_name, "' must be named."))
  }
  for (tool in tools) {
    if (
      graph_tool_is_composition(tool) ||
        graph_tool_is_delegation(tool) ||
        graph_tool_is_native(tool)
    ) {
      graph_abort(
        paste0(
          "Graph node '",
          node_name,
          "' already contains a composition or provider-native tool."
        )
      )
    }
  }
  invisible(NULL)
}

graph_validate_routes <- function(routes, nodes, agents) {
  if (is.null(routes)) {
    routes <- list()
  }
  if (!is.list(routes) || is.object(routes)) {
    graph_abort("routes must be a named list keyed by graph node.")
  }
  if (!length(routes)) {
    return(list())
  }
  if (is.null(names(routes))) {
    graph_abort("routes must be a named list keyed by graph node.")
  }
  source_names <- vapply(
    names(routes),
    graph_plain_text,
    character(1),
    field = "route source"
  )
  if (anyDuplicated(source_names)) {
    graph_abort("Route sources must be unique.")
  }
  allowed_sources <- c("root", nodes)
  if (!all(source_names %in% allowed_sources)) {
    graph_abort("routes contains an unknown graph node.")
  }

  normalized <- stats::setNames(
    vector("list", length(source_names)),
    source_names
  )
  for (source_index in seq_along(source_names)) {
    source_name <- source_names[[source_index]]
    specs <- routes[[source_index]]
    if (!is.list(specs) || is.object(specs)) {
      graph_abort(paste0(
        "Routes for '",
        source_name,
        "' must be a named list."
      ))
    }
    if (!length(specs)) {
      normalized[[source_name]] <- list()
      next
    }
    if (is.null(names(specs))) {
      graph_abort(paste0(
        "Routes for '",
        source_name,
        "' must be a named list."
      ))
    }
    tool_names <- vapply(
      names(specs),
      graph_plain_text,
      character(1),
      field = "route tool name"
    )
    if (anyDuplicated(tool_names)) {
      graph_abort(paste0(
        "Route tool names for '",
        source_name,
        "' must be unique."
      ))
    }
    if ("deputy_read_tool_result" %in% tool_names) {
      graph_abort(
        "Route tool name 'deputy_read_tool_result' is reserved by Deputy."
      )
    }
    source_agent <- agents[[source_name]]
    existing <- names(graph_node_tools(source_agent))
    if (any(tool_names %in% existing)) {
      graph_abort(paste0(
        "A route tool collides with an existing tool on '",
        source_name,
        "'."
      ))
    }
    normalized_specs <- stats::setNames(
      vector("list", length(tool_names)),
      tool_names
    )
    for (tool_index in seq_along(tool_names)) {
      tool_name <- tool_names[[tool_index]]
      spec <- specs[[tool_index]]
      if (
        !is.list(spec) ||
          is.object(spec) ||
          is.null(names(spec)) ||
          anyDuplicated(names(spec)) ||
          !identical(
            sort(names(spec)),
            sort(c("target", "description", "usage_limits"))
          )
      ) {
        graph_abort(
          paste0(
            "Route '",
            source_name,
            ".",
            tool_name,
            "' must contain target, description and usage_limits."
          )
        )
      }
      target <- graph_plain_text(spec$target, "route target")
      if (target == "root" || !target %in% nodes) {
        graph_abort("Delegation graph routes may target member nodes only.")
      }
      description <- graph_plain_text(spec$description, "route description")
      if (!S7::S7_inherits(spec$usage_limits, UsageLimits)) {
        graph_abort("Each graph route requires a UsageLimits value.")
      }
      limits <- tryCatch(
        normalize_usage_limits(spec$usage_limits),
        error = function(error) graph_abort(conditionMessage(error))
      )
      normalized_specs[[tool_name]] <- list(
        target = target,
        description = description,
        usage_limits = limits
      )
    }
    normalized[[source_name]] <- normalized_specs
  }
  normalized
}

graph_route_tool_matches <- function(tool, tree) {
  source <- graph_tool_source(tool)
  identical(attr(source, "deputy_graph_route_tree", exact = TRUE), tree)
}

graph_route_source <- function(tree, source_name) {
  if (identical(source_name, "root")) {
    root <- delegation_tree_root(tree)
    if (is.null(root)) {
      graph_abort("The delegation graph root is unavailable.")
    }
    return(root)
  }
  agent <- tree$agents[[source_name]]
  if (is.null(agent)) {
    graph_abort("The delegation graph member is unavailable.")
  }
  agent
}

graph_route_install <- function(tree, source_name, source, route_name, spec) {
  tool <- graph_delegation_tool(
    tree,
    source,
    tree$handles[[spec$target]],
    route_name,
    spec$description,
    spec$usage_limits
  )
  attr(tool, "deputy_graph_route_tree") <- tree
  private <- graph_agent_private(source)
  adapted <- private$adapt_tool(tool)
  attr(adapted, "deputy_graph_route_tree") <- tree
  tools <- private$.chat$get_tools()
  tools[[route_name]] <- adapted
  check_trusted_registry(private$.trusted_results, tools)
  private$.chat$set_tools(tools)
  tree$route_names[[source_name]] <- c(
    tree$route_names[[source_name]] %||% character(),
    route_name
  )
  invisible(adapted)
}

graph_restore_tools <- function(private, base_tools) {
  current <- private$.chat$get_tools()
  reader <- current[["deputy_read_tool_result"]]
  restored <- base_tools %||% list()
  if (
    !is.null(reader) &&
      identical(
        attr(graph_tool_source(reader), "deputy_internal_tool", exact = TRUE),
        deputy_tool_result_reader_marker
      )
  ) {
    restored[["deputy_read_tool_result"]] <- reader
  }
  private$.chat$set_tools(restored)
  private$.tool_result_reader_registered <- !is.null(
    restored[["deputy_read_tool_result"]]
  )
  invisible(NULL)
}

graph_restore_member_tools <- function(tree, node_name) {
  agent <- tree$agents[[node_name]]
  if (is.null(agent)) {
    return(invisible(NULL))
  }
  private <- graph_agent_private(agent)
  base_tools <- tree$base_tools[[node_name]]
  graph_restore_tools(private, base_tools)
  invisible(NULL)
}

graph_remove_root_routes <- function(tree, root = NULL) {
  root <- root %||%
    tryCatch(
      delegation_tree_root(tree),
      error = function(error) NULL
    )
  if (is.null(root)) {
    return(invisible(NULL))
  }
  private <- graph_agent_private(root)
  tools <- private$.chat$get_tools()
  for (route_name in tree$route_names[["root"]] %||% character()) {
    if (
      route_name %in%
        names(tools) &&
        graph_route_tool_matches(tools[[route_name]], tree)
    ) {
      tools[[route_name]] <- NULL
    }
  }
  private$.chat$set_tools(tools)
  invisible(NULL)
}

graph_restore_after_failure <- function(
  owner,
  tree,
  handles,
  root_tools,
  member_tools,
  member_hooks
) {
  root_private <- graph_agent_private(owner)
  if (!is.null(root_tools)) {
    root_private$.chat$set_tools(root_tools)
  }
  for (node_name in names(member_tools)) {
    agent <- tree$agents[[node_name]]
    if (is.null(agent)) {
      next
    }
    private <- graph_agent_private(agent)
    graph_restore_tools(private, member_tools[[node_name]])
    private$.hooks <- member_hooks[[node_name]]
    private$.delegation_tree <- NULL
    private$.delegation_ancestors <- NULL
  }
  root_private$.delegation_tree <- NULL
  for (handle in rev(unname(handles))) {
    entry <- root_private$owned_conversations[[handle]]
    if (is.null(entry)) {
      next
    }
    tryCatch(
      {
        release_conversation(owner, handle)
      },
      error = function(error) {
        entry <- root_private$owned_conversations[[handle]]
        if (!is.null(entry)) {
          child_private <- graph_agent_private(entry$agent)
          child_private$.conversation_owner <- NULL
          child_private$.hooks$.__enclos_env__$private$configuration_locked <- FALSE
          attr(child_private$.chat, "deputy_conversation_owner") <- NULL
          root_private$owned_conversations[[handle]] <- NULL
        }
      }
    )
  }
  invisible(NULL)
}

# Retain and configure a bounded graph of curated Agents.
#
# This is a host control operation. All validation happens before any
# conversation lease is acquired; a later installation failure rolls back the
# complete graph.
retain_agent_graph <- function(
  owner,
  agents,
  routes,
  usage_limits,
  max_depth,
  max_delegations,
  max_concurrency,
  max_runs = 32L
) {
  graph_validate_root(owner)
  agents <- graph_validate_agents(owner, agents)
  node_names <- names(agents)
  all_agents <- c(list(root = owner), agents)
  for (node_name in names(all_agents)) {
    graph_validate_existing_tools(all_agents[[node_name]], node_name)
  }

  limits <- tryCatch(
    normalize_usage_limits(usage_limits),
    error = function(error) graph_abort(conditionMessage(error))
  )
  if (is.null(S7::prop(limits, "max_requests"))) {
    graph_abort("Graph usage_limits must include max_requests.")
  }
  max_depth <- graph_positive_integer(max_depth, "max_depth")
  max_delegations <- graph_positive_integer(max_delegations, "max_delegations")
  max_concurrency <- graph_positive_integer(max_concurrency, "max_concurrency")
  max_runs <- graph_positive_integer(max_runs, "max_runs")
  routes <- graph_validate_routes(routes, node_names, all_agents)

  root_tools <- graph_node_tools(owner)
  member_tools <- lapply(agents, graph_node_tools)
  member_hooks <- lapply(agents, function(agent) {
    graph_agent_private(agent)$.hooks
  })

  tree <- new_delegation_tree(
    owner,
    limits,
    max_depth,
    max_delegations,
    max_concurrency
  )
  tree$agents <- agents
  tree$root_agent_id <- owner$agent_id
  tree$handles <- stats::setNames(character(length(agents)), node_names)
  tree$base_tools <- member_tools
  tree$base_hooks <- member_hooks
  tree$routes <- routes
  route_sources <- unique(c("root", names(routes)))
  tree$route_names <- stats::setNames(
    vector("list", length(route_sources)),
    route_sources
  )
  for (source_name in route_sources) {
    tree$route_names[[source_name]] <- character()
  }

  handles <- character()
  success <- FALSE
  on.exit(
    if (!success) {
      graph_restore_after_failure(
        owner,
        tree,
        handles,
        root_tools,
        member_tools,
        member_hooks
      )
    },
    add = TRUE
  )

  for (node_name in node_names) {
    handles[[node_name]] <- retain_conversation(
      owner,
      agents[[node_name]],
      limits,
      max_runs
    )
  }
  tree$handles <- handles

  for (source_name in names(routes)) {
    source <- graph_route_source(tree, source_name)
    for (route_name in names(routes[[source_name]])) {
      graph_route_install(
        tree,
        source_name,
        source,
        route_name,
        routes[[source_name]][[route_name]]
      )
    }
  }

  root_private <- graph_agent_private(owner)
  root_private$.delegation_tree <- tree
  for (node_name in node_names) {
    private <- graph_agent_private(agents[[node_name]])
    private$.delegation_tree <- tree
    private$.delegation_ancestors <- NULL
    entry <- root_private$owned_conversations[[handles[[node_name]]]]
    entry$configuration <- conversation_configuration(agents[[node_name]])
  }
  success <- TRUE
  handles
}

graph_release_agent_graph <- function(
  owner,
  tree,
  allow_unavailable_root = FALSE
) {
  private <- graph_agent_private(owner)
  root <- tryCatch(
    delegation_tree_root(tree),
    error = function(error) NULL
  )
  if (is.null(root)) {
    if (
      !isTRUE(allow_unavailable_root) ||
        !identical(owner$agent_id, tree$root_agent_id)
    ) {
      graph_abort("This Agent does not own a delegation graph.")
    }
  } else if (!identical(root, owner)) {
    graph_abort("This Agent does not own a delegation graph.")
  }
  handles <- tree$handles
  if (
    isTRUE(private$run_active) ||
      length(private$active_subagents) ||
      any(vapply(
        handles,
        function(handle) {
          entry <- private$owned_conversations[[handle]]
          !is.null(entry) && isTRUE(entry$busy)
        },
        logical(1)
      ))
  ) {
    graph_abort("Cancel and await graph work before release.")
  }
  for (node_name in names(tree$agents)) {
    child_private <- graph_agent_private(tree$agents[[node_name]])
    if (isTRUE(child_private$run_active)) {
      graph_abort("Cancel and await graph work before release.")
    }
  }

  graph_remove_root_routes(tree, owner)
  for (node_name in names(tree$agents)) {
    graph_restore_member_tools(tree, node_name)
  }

  private$.delegation_tree <- NULL
  for (node_name in names(tree$agents)) {
    child_private <- graph_agent_private(tree$agents[[node_name]])
    child_private$.delegation_tree <- NULL
    child_private$.delegation_ancestors <- NULL
  }
  for (node_name in names(tree$agents)) {
    handle <- handles[[node_name]]
    release_conversation(owner, handle)
  }
  tree$released <- TRUE
  invisible(NULL)
}

# Release a complete delegation graph owned by `owner`.
release_agent_graph <- function(owner) {
  if (!inherits(owner, "Agent")) {
    graph_abort("owner must be an Agent.")
  }
  private <- graph_agent_private(owner)
  tree <- private$.delegation_tree
  if (is.null(tree)) {
    graph_abort("This Agent does not own a delegation graph.")
  }
  graph_release_agent_graph(owner, tree)
}

# Registered as a finalizer callback without capturing the owner in the tree.
finalize_delegation_graph <- function(owner) {
  private <- tryCatch(graph_agent_private(owner), error = function(error) NULL)
  tree <- if (is.null(private)) NULL else private$.delegation_tree
  if (is.null(tree)) {
    return(invisible(NULL))
  }
  if (!identical(owner$agent_id, tree$root_agent_id)) {
    return(invisible(NULL))
  }
  idle <- !isTRUE(private$run_active) &&
    !length(private$active_subagents) &&
    !any(vapply(
      tree$handles,
      function(handle) {
        entry <- private$owned_conversations[[handle]]
        !is.null(entry) && isTRUE(entry$busy)
      },
      logical(1)
    ))
  if (isTRUE(idle)) {
    tryCatch(
      graph_release_agent_graph(owner, tree, allow_unavailable_root = TRUE),
      error = function(error) NULL
    )
  }
  invisible(NULL)
}
