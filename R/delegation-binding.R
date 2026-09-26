#' @include value-properties.R
NULL

#' Configure subagent tools, hooks and user input
#'
#' Tells a [LeadAgent] how subagents get their tools, which lead hooks run for
#' subagent events, and how subagents ask the user questions. Pass it as
#' `LeadAgent$new(delegation_policy = )`. See `vignette("delegation")`.
#'
#' @param resource_mode How subagents get their tools. `"shared"` (the
#'   default) uses the tool objects from the definition and its skills
#'   directly, so any state they hold is shared between subagents.
#'   `"exclusive"` does the same, but only one delegation at a time may hold
#'   `resource_key`; an overlapping one fails before it starts. `"owned"`
#'   calls `resources` to build new tools for each subagent, and the definition
#'   and its skills may not have tools. Deputy never closes shared or
#'   exclusive tools.
#' @param resource_key Resource name for `"exclusive"` mode, required there
#'   and not allowed otherwise. Leads sharing a resource must use the same
#'   key. The lock works within one R process only.
#' @param resources For `"owned"` mode, a `function(agent, definition, context)`
#'   that builds tools for the new subagent `agent` (for example with an
#'   [RSession] or [McpConnection]) and returns them, with a cleanup function,
#'   as [DelegationResources]. Don't run or modify `agent`; Deputy registers
#'   the tools itself. If the function fails, it should first clean up
#'   anything it created. Definitions with `mcp_servers` need this mode.
#' @param human_input Optional `function(questions, context)` that answers
#'   `ask_user` questions from subagents whose definition includes that tool.
#'   `context` holds the subagent's IDs, the lead's `delegation_scope` and the
#'   run context. Return the answers or a promise of them; [AskUserDeferred()]
#'   isn't supported. Without it, delegating to a definition with `ask_user`
#'   fails. Subagents never use [set_ask_user_callback()].
#' @param observers Extra hook events for which the lead's hooks also run when
#'   a subagent fires them. The lead's `PreToolUse`, `PostToolUse` and
#'   `PostToolUseFailure` hooks always do. `PermissionRequest`,
#'   `SubagentStart` and `SubagentStop` can't be added.
#' @details
#' A subagent never has more permissions than the lead had when the
#' delegation started, and each of its tool calls is also checked against the
#' lead's current permissions. `disallowed_tools` also removes tools from
#' skills and `resources`. Provider-native tools, such as a provider's
#' built-in web search, aren't allowed because Deputy can't check their calls.
#' Subagents share the lead's working directory and file checkpoints; this is
#' not an OS sandbox.
#'
#' Subagents can't pause for durable approval: a lead with `approval_dir`
#' can't delegate, and a [PermissionResultPending] result for a subagent's
#' tool call rejects the call. Use a standalone [Agent] for durable approvals.
#'
#' Subagents started by `$parallel_delegate()` have no tools, so `resources`,
#' `human_input` and `resource_key` don't apply to them.
#' @return A `DelegationPolicy` object.
#' @export
DelegationPolicy <- S7::new_class(
  "DelegationPolicy",
  package = "deputy",
  properties = list(
    resource_mode = readonly_property("resource_mode", S7::class_character),
    resource_key = readonly_property("resource_key", S7::class_any),
    resources = readonly_property("resources", S7::class_any),
    human_input = readonly_property("human_input", S7::class_any),
    observers = readonly_property("observers", S7::class_character)
  ),
  constructor = function(
    resource_mode = "shared",
    resource_key = NULL,
    resources = NULL,
    human_input = NULL,
    observers = character()
  ) {
    resource_mode <- match.arg(resource_mode, c("shared", "exclusive", "owned"))
    if (resource_mode == "exclusive" && !is_nonempty_string(resource_key)) {
      delegation_binding_abort("Exclusive resources require a resource_key.")
    }
    if (resource_mode != "exclusive" && !is.null(resource_key)) {
      delegation_binding_abort(
        "resource_key is only supported in exclusive mode."
      )
    }
    if (
      (resource_mode == "owned") != is.function(resources) ||
        (resource_mode != "owned" && !is.null(resources))
    ) {
      delegation_binding_abort(
        "Owned resources require a factory; other modes cannot use one."
      )
    }
    if (!is.null(human_input) && !is.function(human_input)) {
      delegation_binding_abort("human_input must be a function or NULL.")
    }
    observers <- delegation_strings(observers, "observers")
    allowed <- setdiff(
      HookEvent,
      c("PermissionRequest", "SubagentStart", "SubagentStop")
    )
    if (!all(observers %in% allowed)) {
      delegation_binding_abort("Unsupported child observer event.")
    }
    value <- S7::new_object(
      S7::S7_object(),
      resource_mode = resource_mode,
      resource_key = resource_key,
      resources = resources,
      human_input = human_input,
      observers = unique(observers)
    )
    freeze_value(value)
  }
)

#' Return tools from a resource factory
#'
#' The value returned by a [DelegationPolicy] `resources` function: the tools
#' built for one subagent and a function that releases them.
#'
#' @param tools List of ellmer tools built for this subagent.
#' @param cleanup A function with no arguments that releases what the factory
#'   created. Deputy calls it once when the delegation ends, including after a
#'   failure during setup such as a rejected tool. Errors are recorded in the
#'   `cleanup_error` column of `$list_subagents()`.
#' @return A `DelegationResources` object.
#' @seealso [DelegationPolicy]
#' @export
DelegationResources <- S7::new_class(
  "DelegationResources",
  package = "deputy",
  properties = list(
    tools = readonly_property("tools", S7::class_list),
    cleanup = readonly_property("cleanup", S7::class_function)
  ),
  constructor = function(tools = list(), cleanup) {
    # Registration validates tools after the cleanup callback has been retained.
    value <- S7::new_object(
      S7::S7_object(),
      tools = tools,
      cleanup = cleanup
    )
    freeze_value(value)
  }
)

delegation_binding_abort <- function(message) {
  abort_deputy(message, class = "delegation_binding")
}

delegation_resource_leases <- new.env(parent = emptyenv())

begin_delegation_binding <- function(lead, definition, correlation, stateless) {
  private <- lead$.__enclos_env__$private
  policy <- private$.delegation_policy
  id <- correlation$delegation_id
  record <- if (is.character(id) && length(id) == 1L && !is.na(id)) {
    private$subagent_runs[[id]]
  }
  if (
    is.null(record) ||
      !identical(record$status, "queued") ||
      !identical(record$parent_agent_id, lead$agent_id) ||
      !is.null(private$delegation_bindings[[id]])
  ) {
    delegation_binding_abort(
      "Child binding requires an admitted, unbound delegation."
    )
  }
  if (!is.null(private$.approval_dir)) {
    delegation_binding_abort(
      "Delegated durable approvals are unsupported; use a standalone Agent approval workflow."
    )
  }
  if (length(definition$mcp_servers) && policy$resource_mode != "owned") {
    delegation_binding_abort(
      "Delegated MCP selections require an owned resource factory."
    )
  }
  id <- correlation$delegation_id
  mode <- if (stateless) "none" else policy$resource_mode
  key <- if (mode == "exclusive") policy$resource_key else NULL
  if (
    !is.null(key) && exists(key, delegation_resource_leases, inherits = FALSE)
  ) {
    delegation_binding_abort("The exclusive delegation resource is busy.")
  }
  token <- new.env(parent = emptyenv())
  if (!is.null(key)) {
    assign(key, token, delegation_resource_leases)
  }
  binding <- list(
    mode = mode,
    key = key,
    token = token,
    cleanup = NULL,
    manifest = list(
      resource_mode = mode,
      resource_key = key,
      workspace = list(mode = "shared", path = lead$working_dir),
      hooks = unique(c(
        "PreToolUse",
        "PostToolUse",
        "PostToolUseFailure",
        policy$observers
      )),
      permissions = "initial child ceiling plus current lead restrictions",
      approval = "unsupported",
      human_input = "none",
      cleanup = switch(
        mode,
        owned = "runtime-owned",
        none = "none",
        "host-owned"
      )
    )
  )
  private$delegation_bindings[[id]] <- binding
  invisible(binding)
}

release_delegation_binding <- function(lead, id) {
  private <- lead$.__enclos_env__$private
  binding <- private$delegation_bindings[[id]]
  if (is.null(binding)) {
    return(invisible(NULL))
  }
  private$delegation_bindings[[id]] <- NULL
  on.exit(
    {
      if (
        !is.null(binding$key) &&
          identical(
            get0(binding$key, delegation_resource_leases, inherits = FALSE),
            binding$token
          )
      ) {
        rm(list = binding$key, envir = delegation_resource_leases)
      }
    },
    add = TRUE
  )
  if (is.function(binding$cleanup)) {
    tryCatch(binding$cleanup(), error = function(error) {
      record <- private$subagent_runs[[id]]
      if (!is.null(record)) {
        record$cleanup_error <- conditionMessage(error)
        private$subagent_runs[[id]] <- record
      }
    })
  }
  invisible(NULL)
}

bind_delegation_host <- function(
  lead,
  child,
  definition,
  correlation,
  stateless
) {
  private <- lead$.__enclos_env__$private
  policy <- private$.delegation_policy
  id <- correlation$delegation_id
  binding <- private$delegation_bindings[[id]]
  child_private <- child$.__enclos_env__$private
  child_private$.delegation_observe <- function(event) {
    tryCatch(lead_observe_event(lead, id, event), error = function(error) {
      record <- private$subagent_runs[[id]]
      record$observation_error <- inspection_text(
        conditionMessage(error),
        1024L
      )
      private$subagent_runs[[id]] <- record
    })
    invisible(NULL)
  }
  child_private$.delegation_guard <- function(tool_name, tool_input, context) {
    # The child's callback already retains the immutable lead callback. Recheck
    # current static restrictions separately, including mode shortcuts.
    fields <- S7::props(lead$permissions)
    fields$can_use_tool <- NULL
    result <- permissions_check(
      do.call(Permissions, fields),
      tool_name,
      tool_input,
      context
    )
    if (!S7::S7_inherits(result, PermissionResultAllow)) {
      reason <- result$reason %||% "Denied by current lead policy."
      child_private$record_run_event(child_private$agent_event(
        "permission",
        tool_call_id = context$tool_call_id,
        decision = "deny"
      ))
      child_private$notify(
        reason,
        level = "warning",
        code = "permission_denied",
        tool_name = tool_name,
        tool_input = tool_input
      )
      ellmer::tool_reject(reason)
    }
  }
  for (event in binding$manifest$hooks) {
    local({
      selected <- event
      child$add_hook(HookMatcher(
        selected,
        timeout = 0,
        callback = function(...) {
          forward_delegation_hook(lead, id, selected, ...)
        }
      ))
    })
  }
  if (!stateless && binding$mode == "owned") {
    if (
      length(definition$tools) ||
        any(vapply(
          child$skills(),
          function(skill) length(skill$tools) > 0L,
          logical(1)
        ))
    ) {
      delegation_binding_abort(
        "Owned mode requires tools from the resource factory, not definitions or skills."
      )
    }
    original_tools <- child$get_tools()
    original_hooks <- child$hooks$count()
    resource <- policy$resources(
      child,
      definition,
      child_private$hook_context(scope = private$delegation_scope)
    )
    if (!S7::S7_inherits(resource, DelegationResources)) {
      delegation_binding_abort(
        "The resource factory must return DelegationResources."
      )
    }
    private$delegation_bindings[[id]]$cleanup <- resource$cleanup
    if (
      !identical(original_tools, child$get_tools()) ||
        !identical(original_hooks, child$hooks$count()) ||
        !is.null(child$last_run())
    ) {
      delegation_binding_abort(
        "Resource factories must return tools without changing or running the child."
      )
    }
    child$register_tools(resource$tools)
  }
  tools <- child$get_tools()
  for (tool in tools) {
    if (inherits(tool, "ellmer::ToolBuiltIn")) {
      delegation_binding_abort(
        "Delegated provider-native tools cannot bind host governance."
      )
    }
  }
  # Denylist applies to every origin, including skills and host factories.
  tools <- private$filter_disallowed_tools(tools, definition$disallowed_tools)
  child$set_tools(tools)
  if (
    "ask_user" %in%
      names(tools) &&
      !identical(tool_metadata(tools$ask_user)$source$type, "mcp")
  ) {
    if (is.null(policy$human_input)) {
      delegation_binding_abort(
        "Delegated human input requires DelegationPolicy(human_input = ...)."
      )
    }
    interactive_tool <- new_ask_user_tool(
      policy$human_input,
      context = function() {
        child_private$hook_context(scope = private$delegation_scope)
      },
      allow_deferred = FALSE
    )
    child$register_tool(
      ellmer::tool(
        function(questions) {
          delegated_ask_user_json(interactive_tool(questions))
        },
        name = interactive_tool@name,
        description = interactive_tool@description,
        arguments = interactive_tool@arguments@properties,
        annotations = interactive_tool@annotations
      ),
      replace = TRUE
    )
    binding$manifest$human_input <- "host-bound"
  }
  if (stateless && length(child$get_tools())) {
    delegation_binding_abort(
      "Stateless responders cannot acquire tools through host binding."
    )
  }
  # Retain only plain inspection data in the child; closures stay in runtime state.
  child_private$.delegation_binding <- binding$manifest
  invisible(child)
}

forward_delegation_hook <- function(lead, id, event, ...) {
  private <- lead$.__enclos_env__$private
  before <- length(lead$hooks$last_errors())
  on.exit(
    {
      errors <- lead$hooks$last_errors()
      record <- private$subagent_runs[[id]]
      if (!is.null(record) && length(errors) > before) {
        messages <- vapply(
          errors[seq.int(before + 1L, length(errors))],
          function(error) paste0(error$event, ": ", error$error),
          character(1)
        )
        record$hook_error <- paste(
          c(record$hook_error, messages),
          collapse = "\n"
        )
        private$subagent_runs[[id]] <- record
      }
    },
    add = TRUE
  )
  lead$hooks$fire(event, ...)
}

local({
  S7::method(`$`, DelegationPolicy) <- function(x, name) S7::prop(x, name)
  S7::method(`$`, DelegationResources) <- function(x, name) S7::prop(x, name)
})

# A delegated handler may answer now or through a promise; either way the child
# receives the answers as JSON within its current run.
delegated_ask_user_json <- function(result) {
  if (promises::is.promising(result)) {
    return(promises::then(result, delegated_ask_user_json))
  }
  jsonlite::toJSON(result, auto_unbox = TRUE, null = "null")
}
