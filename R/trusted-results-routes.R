#' @include trusted-results.R
NULL

# Trusted results across retained specialists and graph routes ----------------

# The agent whose policy governs `agent`'s tree: a retained specialist or graph
# member answers to the agent that retained it; anything else to itself.
trusted_policy_root <- function(agent) {
  private <- agent$.__enclos_env__$private
  if (!is.null(private$.trusted_root)) {
    return(rlang::wref_key(private$.trusted_root))
  }
  if (is.null(private$.trusted_results)) NULL else agent
}

# A route's retained entry, when Deputy built the route for `agent` and its
# target was checked against the same root policy when it was retained; NULL
# otherwise.
trusted_route_target <- function(agent, tool) {
  source <- runtime_source_tool(tool)
  handle <- attr(source, "deputy_composition_handle", exact = TRUE)
  if (
    !identical(composition_tool_owner(source), agent) ||
      !is_nonempty_string(handle)
  ) {
    return(NULL)
  }
  root <- trusted_policy_root(agent)
  if (is.null(root)) {
    return(NULL)
  }
  tree <- attr(tool, "deputy_graph_route_tree", exact = TRUE) %||%
    attr(source, "deputy_graph_route_tree", exact = TRUE)
  if (!is.null(tree)) {
    tree_root <- tryCatch(delegation_tree_root(tree), error = function(e) NULL)
    if (!identical(tree_root, root) || !handle %in% tree$handles) {
      return(NULL)
    }
  } else if (!identical(root, agent)) {
    return(NULL)
  }
  entry <- root$.__enclos_env__$private$owned_conversations[[handle]]
  if (is.null(entry) || is.null(entry$trusted)) {
    return(NULL)
  }
  entry
}

# The `admit_route` function for checking `agent`'s registry `tools`.
trusted_route_admission <- function(agent, tools) {
  walk <- new.env(parent = emptyenv())
  walk$tools <- tools
  function(tool) trusted_route_admitted(agent, tool, walk)
}

# A route is admitted only when `trusted_route_target()` finds its target.
# What it reaches also holds to the caller's policy together with the
# target's own, and further down a chain of routes to every policy along it,
# since a graph member's own result types or narrower exemptions make its
# policy stricter than the target's. The first route admitted for a registry
# checks everything its routes reach (`trusted_route_walk()`).
trusted_route_admitted <- function(agent, tool, walk = NULL) {
  if (is.null(trusted_route_target(agent, tool))) {
    return(FALSE)
  }
  walk <- walk %||% new.env(parent = emptyenv())
  if (!isTRUE(walk$done)) {
    walk$done <- TRUE
    trusted_route_walk(agent, walk$tools %||% agent$get_tools())
  }
  TRUE
}

# Collect all agents reachable from `start` along admitted routes, their tool
# registries, and the directed policy edges between them.
trusted_route_collect_graph <- function(start, tools) {
  agents <- list(start)
  registries <- list(tools)
  edges <- list()
  index <- 1L
  while (index <= length(agents)) {
    for (tool in registries[[index]]) {
      entry <- trusted_route_target(agents[[index]], tool)
      if (is.null(entry)) {
        next
      }
      to <- Position(function(agent) identical(agent, entry$agent), agents)
      if (is.na(to)) {
        agents[[length(agents) + 1L]] <- entry$agent
        registries[[length(registries) + 1L]] <- entry$agent$get_tools()
        to <- length(agents)
      }
      edges[[length(edges) + 1L]] <- list(
        from = index,
        to = to,
        policy = entry$trusted$policy
      )
    }
    index <- index + 1L
  }
  list(agents = agents, registries = registries, edges = edges)
}

# Validate one producer per result type and one type per producer across every
# policy reached along the graph.
trusted_route_merge_policies <- function(policy, edges) {
  results <- character()
  values <- list()
  for (each in c(list(policy), lapply(edges, `[[`, "policy"))) {
    for (type in names(each@results)) {
      name <- each@results[[type]]
      value <- each@producers[[type]] %||% name
      if (type %in% names(values) && !identical(values[[type]], value)) {
        trusted_combine_abort(
          "Result type {.val {type}} has a different producer behind a route.",
          tool_name = name
        )
      }
      if (name %in% results[names(results) != type]) {
        trusted_combine_abort(
          "Tool {.val {name}} cannot produce more than one trusted result type.",
          tool_name = name
        )
      }
      results[[type]] <- name
      values[[type]] <- value
    }
  }
  explicit <- !vapply(values, is.character, logical(1))
  sources <- stats::setNames(values[explicit], results[names(values)[explicit]])
  list(results = results, sources = sources)
}

# Propagate tool-name standings (designated, exempt, neither) across every
# reachable route chain using fixed-point iteration.
trusted_route_propagate_standings <- function(
  policy,
  universe,
  n_agents,
  edges
) {
  standing <- function(pol) {
    designated <- universe %in% unname(pol@results)
    list(
      designated = designated,
      exempt = !designated & universe %in% pol@exempt_tools,
      neither = !designated & !universe %in% pol@exempt_tools
    )
  }
  none <- rep(FALSE, length(universe))
  reached <- rep(
    list(list(designated = none, exempt = none, neither = none)),
    n_agents
  )
  reached[[1L]] <- standing(policy)
  initial <- reached[[1L]]
  queue <- 1L
  while (length(queue)) {
    from <- queue[[1L]]
    queue <- queue[-1L]
    for (edge in edges) {
      if (edge$from != from) {
        next
      }
      have <- reached[[from]]
      designates <- universe %in% unname(edge$policy@results)
      exempts <- universe %in% edge$policy@exempt_tools
      old <- reached[[edge$to]]
      new <- list(
        designated = old$designated |
          have$designated |
          ((have$exempt | have$neither) & designates),
        exempt = old$exempt | (have$exempt & !designates & exempts),
        neither = old$neither |
          (have$exempt & !designates & !exempts) |
          (have$neither & !designates)
      )
      if (!identical(new, old)) {
        reached[[edge$to]] <- new
        queue <- c(queue, edge$to)
      }
    }
  }
  list(reached = reached, initial = initial)
}

# Check what every chain of routes from `start` reaches, under the policy
# combined along each chain: its result types joined, its exemptions
# intersected. Chains reach an agent under different combined policies, and a
# check under one doesn't imply the others: a designated producer is excused
# from the read-only rule that holds where its name isn't designated. Each
# tool's check depends only on its name's standing, though: designated,
# exempt or neither. So this records, for every agent reached, the standings
# each name reaches there over all chains, and checks each tool once for each,
# as a chain-by-chain check would, at a cost that grows with the graph rather
# than with the number of chains. A chain that leads back to an agent it has
# passed is checked as any other.
trusted_route_walk <- function(start, tools) {
  graph <- trusted_route_collect_graph(start, tools)
  policy <- start$.__enclos_env__$private$.trusted_results
  merged <- trusted_route_merge_policies(policy, graph$edges)
  universe <- unique(unlist(lapply(graph$registries, names), use.names = FALSE))
  propagated <- trusted_route_propagate_standings(
    policy,
    universe,
    length(graph$agents),
    graph$edges
  )
  types <- names(merged$results)[match(universe, merged$results)]

  for (index in seq_along(graph$agents)) {
    have <- propagated$reached[[index]]
    # The start's own standings were checked with its registry.
    if (index == 1L) {
      have <- Map(function(now, before) now & !before, have, propagated$initial)
      if (!any(unlist(have))) {
        next
      }
    }
    trusted_route_check_agent(
      graph$agents[[index]],
      graph$registries[[index]],
      universe,
      have,
      types,
      merged$sources
    )
  }
  invisible(NULL)
}

# Check one agent's registry for the standings its tools' names reached.
trusted_route_check_agent <- function(
  agent,
  tools,
  universe,
  standings,
  types,
  sources
) {
  admit <- function(tool) !is.null(trusted_route_target(agent, tool))
  for (name in names(tools)) {
    at <- match(name, universe)
    if (standings$designated[[at]]) {
      trusted_check_tool(
        name,
        tools[[name]],
        type = types[[at]],
        sources = sources,
        explicit = sources,
        require_source = TRUE
      )
    }
    if (standings$exempt[[at]]) {
      trusted_check_tool(
        name,
        tools[[name]],
        exempt = TRUE,
        admit_route = admit
      )
    }
    if (standings$neither[[at]]) {
      trusted_check_tool(name, tools[[name]], admit_route = admit)
    }
  }
  invisible(NULL)
}

# The policy a route's target holds to for its caller: both policies' result
# types, each with its one producer, the tools both exempt, and a receipt if
# either asks.
trusted_route_policy <- function(caller, target) {
  values <- trusted_values(caller)
  for (type in names(target@results)) {
    value <- target@producers[[type]] %||% target@results[[type]]
    if (type %in% names(values) && !identical(values[[type]], value)) {
      trusted_combine_abort(
        "Result type {.val {type}} has a different producer behind a route.",
        tool_name = target@results[[type]]
      )
    }
    values[[type]] <- value
  }
  do.call(
    TrustedResults,
    c(
      values,
      list(
        exempt_tools = intersect(caller@exempt_tools, target@exempt_tools),
        model_receipt = caller@model_receipt || target@model_receipt
      )
    )
  )
}

trusted_values <- function(policy) {
  values <- as.list(policy@results)
  for (type in names(policy@producers)) {
    values[[type]] <- policy@producers[[type]]
  }
  values
}

# A copy of `policy` delivering to `on_result`, keeping explicit producers.
trusted_policy_copy <- function(
  policy,
  on_result,
  exempt_tools = policy@exempt_tools,
  model_receipt = policy@model_receipt
) {
  do.call(
    TrustedResults,
    c(
      trusted_values(policy),
      list(
        on_result = on_result,
        exempt_tools = exempt_tools,
        model_receipt = model_receipt
      )
    )
  )
}

trusted_combine_abort <- function(message, tool_name, .envir = parent.frame()) {
  trusted_registry_abort(
    c(
      message,
      "i" = "A retained agent's own policy can add to its root's, not change it."
    ),
    tool_name = tool_name,
    .envir = .envir
  )
}

# The policy a retained agent runs under: its root's and its own, neither
# weakened. Results of both, one producer each; exemptions both allow; a
# receipt if either asks; delivery to the root once, then to its own callback.
trusted_combine <- function(owner, root_policy, own, tools) {
  values <- trusted_values(root_policy)
  exempt <- root_policy@exempt_tools
  receipt <- root_policy@model_receipt
  own_callback <- NULL
  if (!is.null(own)) {
    for (type in names(own@results)) {
      name <- own@results[[type]]
      producer <- own@producers[[type]] %||%
        runtime_source_tool(tools[[name]] %||% list())
      if (!inherits(producer, "ellmer::ToolDef")) {
        trusted_combine_abort(
          "Trusted tool {.val {name}} of the retained agent is not registered.",
          tool_name = name
        )
      }
      if (type %in% names(values)) {
        if (!identical(values[[type]], producer)) {
          trusted_combine_abort(
            "Result type {.val {type}} has a different producer in the retained agent.",
            tool_name = name
          )
        }
        next
      }
      if (name %in% root_policy@results) {
        trusted_combine_abort(
          "Trusted tool {.val {name}} would produce two result types.",
          tool_name = name
        )
      }
      values[[type]] <- producer
    }
    exempt <- intersect(exempt, own@exempt_tools)
    receipt <- receipt || own@model_receipt
    own_callback <- own@on_result
  }
  # Each registration has its own key, so two members using one function
  # still get a delivery each.
  forward <- trusted_forward(
    owner,
    root_policy@on_result,
    if (is.function(own_callback)) {
      list(list(key = new_deputy_id(), callback = own_callback))
    } else {
      list()
    }
  )
  do.call(
    TrustedResults,
    c(
      values,
      list(on_result = forward, exempt_tools = exempt, model_receipt = receipt)
    )
  )
}

# Delivery for a policy installed below the root: the root records the event
# once and its callback runs, then each own callback of the agents whose
# policies were combined. Each runs even when another fails; the first failure
# still fails the delivery. The own callbacks stay on the function, so a
# route's run can combine them with its caller's.
trusted_forward <- function(owner, root_callback, callbacks) {
  root_ref <- rlang::new_weakref(owner)
  forward <- function(event) {
    root <- rlang::wref_key(root_ref)
    if (is.null(root)) {
      cli_abort("The agent that retained this one is no longer available.")
    }
    root$.__enclos_env__$private$record_run_event(event)
    failure <- NULL
    for (callback in c(
      list(root_callback),
      lapply(callbacks, `[[`, "callback")
    )) {
      if (!is.function(callback)) {
        next
      }
      error <- tryCatch(
        {
          callback(event)
          NULL
        },
        error = identity
      )
      failure <- failure %||% error
    }
    if (!is.null(failure)) {
      rlang::cnd_signal(failure)
    }
    invisible(NULL)
  }
  attr(forward, "deputy_trusted_callbacks") <- callbacks
  forward
}

# The policy a graph route's target runs under for one call: the one that
# admitted the route, its caller's combined with its own, so the caller's
# result types are published from the target too. Delivery reaches the root
# once, then each member's own callback along the chain of routes, once each:
# registrations are told apart by key, so a chain passing a member twice
# calls it once, and members sharing one function are each called.
trusted_routed_policy <- function(owner, caller, target) {
  callbacks <- list()
  for (entry in c(
    attr(caller@on_result, "deputy_trusted_callbacks", exact = TRUE),
    attr(target@on_result, "deputy_trusted_callbacks", exact = TRUE)
  )) {
    if (!entry$key %in% vapply(callbacks, `[[`, character(1), "key")) {
      callbacks[[length(callbacks) + 1L]] <- entry
    }
  }
  root_policy <- owner$.__enclos_env__$private$.trusted_results
  trusted_policy_copy(
    trusted_route_policy(caller, target),
    trusted_forward(owner, root_policy@on_result, callbacks)
  )
}

# Check `agent` against `owner`'s policy before `owner` retains it. Returns
# what to install while retained and what to restore on release, or NULL when
# `owner` has no policy.
trusted_admit_conversation <- function(owner, agent) {
  op <- owner$.__enclos_env__$private
  policy <- op$.trusted_results
  if (is.null(policy)) {
    return(NULL)
  }
  implicit <- setdiff(names(policy@results), names(policy@producers))
  if (length(implicit)) {
    trusted_registry_abort(
      c(
        "Trusted results reached through retained agents need explicit producers.",
        "i" = "Pass the tool itself, as in {.code TrustedResults({implicit[[1L]]} = tool)}."
      ),
      tool_name = policy@results[[implicit[[1L]]]]
    )
  }
  cp <- agent$.__enclos_env__$private
  if (isTRUE(cp$.trusted_tree_member) || !is.null(cp$.trusted_root)) {
    trusted_registry_abort(
      "The agent already belongs to another trusted-results tree.",
      tool_name = names(policy@results)[[1L]]
    )
  }
  tools <- agent$get_tools()
  effective <- trusted_combine(owner, policy, cp$.trusted_results, tools)
  trusted_check_siblings(op, effective)
  sources <- trusted_policy_sources(effective)
  # The names this agent's combined policy designates hold for the owner and
  # the other retained agents, and theirs hold for this agent.
  retained <- Filter(
    function(entry) !is.null(entry$trusted),
    op$owned_conversations
  )
  # A LeadAgent's definitions are part of its tree too.
  definitions <- if (is.function(op$trusted_definition_tools)) {
    op$trusted_definition_tools()
  }
  trusted_check_names(
    sources,
    c(
      list(owner$get_tools()),
      definitions,
      lapply(retained, function(entry) entry$agent$get_tools())
    )
  )
  for (entry in retained) {
    trusted_check_names(
      trusted_policy_sources(entry$trusted$policy),
      list(tools)
    )
  }
  withCallingHandlers(
    check_trusted_registry(
      effective,
      tools,
      available = effective@results,
      sources = sources,
      require_source = TRUE
    ),
    deputy_tool_registration = function(error) {
      agent_name <- agent$agent_name
      cli_abort(
        if (is_nonempty_string(agent_name)) {
          "The retained agent '{agent_name}' violates the trusted-results policy."
        } else {
          "The retained agent violates the trusted-results policy."
        },
        class = setdiff(class(error), c("rlang_error", "error", "condition")),
        parent = error
      )
    }
  )
  list(
    policy = effective,
    sources = sources,
    previous = list(
      policy = cp$.trusted_results,
      member = cp$.trusted_tree_member,
      sources = cp$.trusted_sources,
      root = cp$.trusted_root
    )
  )
}

# Result types that retained agents add keep one producer across everything
# the root has retained, and a producer one type, as within one policy. Graph
# members are retained by the root too, so this covers the whole tree.
trusted_check_siblings <- function(op, effective) {
  mine <- effective@producers
  for (entry in op$owned_conversations) {
    if (is.null(entry$trusted)) {
      next
    }
    theirs <- entry$trusted$policy@producers
    for (type in names(mine)) {
      name <- effective@results[[type]]
      for (other in names(theirs)) {
        same_tool <- identical(mine[[type]], theirs[[other]])
        if (identical(type, other) && !same_tool) {
          trusted_combine_abort(
            "Result type {.val {type}} has a different producer in another retained agent.",
            tool_name = name
          )
        }
        if (!identical(type, other) && same_tool) {
          trusted_combine_abort(
            "Trusted tool {.val {name}} would produce two result types.",
            tool_name = name
          )
        }
      }
    }
  }
  invisible(NULL)
}

trusted_install_conversation <- function(owner, agent, trusted) {
  if (is.null(trusted)) {
    return(invisible(NULL))
  }
  cp <- agent$.__enclos_env__$private
  cp$.trusted_results <- trusted$policy
  cp$.trusted_tree_member <- TRUE
  cp$.trusted_sources <- trusted$sources
  cp$.trusted_root <- rlang::new_weakref(owner)
  invisible(NULL)
}

trusted_release_conversation <- function(entry) {
  trusted <- entry$trusted
  if (is.null(trusted)) {
    return(invisible(NULL))
  }
  cp <- entry$agent$.__enclos_env__$private
  cp$.trusted_results <- trusted$previous$policy
  cp$.trusted_tree_member <- trusted$previous$member
  cp$.trusted_sources <- trusted$previous$sources
  cp$.trusted_root <- trusted$previous$root
  entry$trusted <- NULL
  invisible(NULL)
}

# Before each continuation: the installed policy is still the admitted one and
# the agent's current tools still pass it.
trusted_recheck_conversation <- function(entry) {
  trusted <- entry$trusted
  if (is.null(trusted)) {
    return(invisible(NULL))
  }
  cp <- entry$agent$.__enclos_env__$private
  if (
    !identical(cp$.trusted_results, trusted$policy) ||
      !identical(cp$.trusted_sources, trusted$sources) ||
      !isTRUE(cp$.trusted_tree_member)
  ) {
    trusted_registry_abort(
      "The retained agent's trusted-results policy changed; release it and retain it again.",
      tool_name = names(trusted$policy@results)[[1L]]
    )
  }
  cp$check_trusted_tools(entry$agent$get_tools())
  invisible(NULL)
}
