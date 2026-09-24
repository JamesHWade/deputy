#' @include value-properties.R agent-result.R
NULL

#' Designate trusted tools as the only producers of host results
#'
#' @description
#' A read-only S7 policy for [trusted mini-agents](https://trustedminiagents.dev).
#' Each named result type is produced by exactly one registered local tool.
#' When that tool returns successfully, Deputy delivers its value verbatim to
#' the host through a `"trusted_result"` [AgentEvent], [result_trusted_results()],
#' and the optional `on_result` callback. The value does not have to pass
#' through model text.
#'
#' An Agent created with a policy checks its complete tool registry whenever
#' tools are published: at construction, `$set_tools()`, `$register_tools()`,
#' skill and MCP loading, cloning, and graph route installation. Registration
#' fails, leaving the previous registry intact, when:
#'
#' * a designated trusted tool is missing from the registry;
#' * a trusted tool is not a local function tool (it is provider-native or
#'   MCP), executes code, or delegates to another Agent;
#' * any other tool executes model-supplied code or delegates to another Agent
#'   (`run_r_code`, `run_bash`, R session tools, delegation and graph route
#'   tools). These tools could produce a result of any kind;
#' * any other tool's effective annotations permit writes
#'   (`read_only_hint` not `TRUE`, or an explicit `destructive_hint = TRUE`)
#'   or the open world (`open_world_hint` not `FALSE`), unless the host names it in `exempt_tools`. Unannotated tools,
#'   including MCP REPL and console tools, use the conservative defaults from
#'   ADR-0007 and are rejected.
#'
#' Exemptions are the host's explicit assertion that a local function tool
#' cannot produce a trusted kind of result. MCP, provider-native, code-execution,
#' and delegation tools cannot be exempted. The policy is fixed at construction;
#' it constrains which tools may be registered alongside trusted ones and does
#' not grant permission to call any tool. Permissions, hooks, and durable
#' approvals still govern every call. LeadAgent delegation is rejected because
#' child text reaches the lead model; run trusted tools in a separate Agent.
#'
#' A trusted tool runs only as the tool of the Agent's own governed request, so
#' permissions, hooks, and approvals always precede it. Calls from host code or
#' from inside another tool fail without publishing a result.
#'
#' Tool argument values given to the trusted tool are recorded in the event
#' after ellmer's argument conversion and Deputy's path resolution.
#'
#' @param ... Named pairs `result_type = "tool_name"`. Result types must be
#'   unique identifiers (letters, numbers, dots, underscores, hyphens). Each tool
#'   may produce only one result type.
#' @param on_result Optional function called with the `"trusted_result"`
#'   [AgentEvent] as soon as the trusted tool returns, before the model sees
#'   any output. Use it to update a Shiny `reactiveValues()` or a host store.
#'   If it signals an error, the result event is still recorded, a
#'   `"trusted_result_delivery_failed"` notification is emitted, and the model
#'   receives a tool error instead of the value.
#' @param exempt_tools Character vector of local function tool names that the
#'   host asserts cannot bypass a trusted tool despite write or open-world
#'   annotations.
#' @param model_receipt If `TRUE`, the model receives a receipt naming the
#'   result ID and type instead of the value, so it cannot restate the values.
#'   Defaults to `FALSE`, which sends the model the same value as the host.
#' @prop results Named character vector mapping result types to tool names.
#' @return A read-only `TrustedResults` S7 value.
#' @seealso [result_trusted_results()], [Agent], [tool_metadata()]
#' @examples
#' policy <- TrustedResults(
#'   forecast = "get_forecast",
#'   on_result = function(event) print(event$value),
#'   model_receipt = TRUE
#' )
#' policy$results
#' @export
TrustedResults <- S7::new_class(
  "TrustedResults",
  package = "deputy",
  properties = list(
    results = readonly_property("results", S7::class_character),
    on_result = readonly_property(
      "on_result",
      S7::new_union(NULL, S7::class_function)
    ),
    exempt_tools = readonly_property("exempt_tools", S7::class_character),
    model_receipt = readonly_property("model_receipt", S7::class_logical)
  ),
  constructor = function(
    ...,
    on_result = NULL,
    exempt_tools = character(),
    model_receipt = FALSE
  ) {
    results <- list(...)
    types <- names(results)
    if (
      length(results) == 0L ||
        is.null(types) ||
        anyNA(types) ||
        !all(nzchar(types))
    ) {
      cli_abort(
        "{.fn TrustedResults} requires named {.code result_type = \"tool_name\"} pairs."
      )
    }
    for (type in types) {
      if (!grepl("^[A-Za-z0-9][A-Za-z0-9._-]*$", type)) {
        cli_abort(
          "Result type {.val {type}} must contain only letters, numbers, dots, underscores, or hyphens."
        )
      }
      if (!is_nonempty_string(results[[type]])) {
        cli_abort(
          "Result type {.val {type}} must name one tool with a non-empty string."
        )
      }
    }
    if (anyDuplicated(types)) {
      cli_abort("Each result type may be declared only once.")
    }
    results <- vapply(results, identity, character(1))
    if (anyDuplicated(results)) {
      duplicate <- results[duplicated(results)][[1L]]
      cli_abort(
        "Tool {.val {duplicate}} cannot produce more than one trusted result type."
      )
    }
    if (!is.null(on_result) && !is.function(on_result)) {
      cli_abort("{.arg on_result} must be NULL or a function.")
    }
    if (
      !is.character(exempt_tools) ||
        anyNA(exempt_tools) ||
        !all(nzchar(exempt_tools))
    ) {
      cli_abort("{.arg exempt_tools} must be a character vector of tool names.")
    }
    exempt_tools <- unique(exempt_tools)
    if (any(exempt_tools %in% results)) {
      cli_abort("Trusted tools cannot also be listed in {.arg exempt_tools}.")
    }
    if (!rlang::is_bool(model_receipt)) {
      cli_abort("{.arg model_receipt} must be TRUE or FALSE.")
    }
    value <- S7::new_object(
      S7::S7_object(),
      results = results,
      on_result = on_result,
      exempt_tools = exempt_tools,
      model_receipt = model_receipt
    )
    freeze_value(value)
  }
)

local({
  S7::method(`$`, TrustedResults) <- function(x, name) S7::prop(x, name)
})

S7::method(print, TrustedResults) <- function(x, ...) {
  cli::cat_line(cli::cli_format_method({
    cli::cli_text("{.cls TrustedResults}")
    for (type in names(x@results)) {
      cli::cli_bullets(c(
        "*" = "{.field {type}} from {.fn {x@results[[type]]}}"
      ))
    }
    if (length(x@exempt_tools) > 0L) {
      cli::cli_text("Exempt: {.val {x@exempt_tools}}")
    }
    cli::cli_text("Model receipt: {x@model_receipt}")
  }))
  invisible(x)
}

normalize_trusted_results <- function(policy) {
  if (is.null(policy)) {
    return(NULL)
  }
  if (!S7::S7_inherits(policy, TrustedResults)) {
    cli_abort("{.arg trusted_results} must be NULL or a TrustedResults object.")
  }
  policy
}

trusted_result_type <- function(policy, tool_name) {
  if (is.null(policy)) {
    return(NULL)
  }
  type <- names(policy@results)[policy@results == tool_name]
  if (length(type) == 0L) NULL else type
}

# Code execution and delegation can compute or relay any kind of result, so no
# host assertion makes them safe beside a trusted tool.
trusted_bypass_reason <- function(tool) {
  source <- attr(tool, "deputy_runtime_source_tool", exact = TRUE) %||% tool
  if (
    !is.null(composition_tool_owner(source)) ||
      !is.null(attr(source, "deputy_delegation_tool", exact = TRUE)) ||
      !is.null(attr(tool, "deputy_graph_route_tree", exact = TRUE)) ||
      identical(normalize_native_tool_id(source@name), "delegate_to_agent")
  ) {
    return("delegates to another Agent")
  }
  if (
    is.function(attr(source, "deputy_workspace_runner", exact = TRUE)) ||
      !is.null(attr(source, "deputy_r_session_owner", exact = TRUE)) ||
      normalize_native_tool_id(source@name) %in%
        c("run_r_code", "run_bash", "install_package")
  ) {
    return("executes model-supplied code")
  }
  NULL
}

trusted_registry_abort <- function(
  message,
  tool_name,
  .envir = parent.frame()
) {
  tool_registration_error(
    c(
      message,
      "i" = "See {.help deputy::TrustedResults} for the no-bypass rule."
    ),
    tool_name = tool_name,
    .envir = .envir
  )
}

# Validate a complete registry (named list of ellmer tools) against the policy.
check_trusted_registry <- function(policy, tools) {
  if (is.null(policy)) {
    return(invisible(NULL))
  }
  missing <- setdiff(policy@results, names(tools))
  if (length(missing) > 0L) {
    trusted_registry_abort(
      "Trusted tool {.val {missing}} must remain registered.",
      tool_name = missing[[1L]]
    )
  }
  for (name in names(tools)) {
    tool <- tools[[name]]
    if (
      !is.null(attr(tool, "deputy_internal_tool", exact = TRUE)) &&
        identical(name, "deputy_read_tool_result")
    ) {
      next
    }
    trusted_type <- trusted_result_type(policy, name)
    native <- inherits(tool, "ellmer::ToolBuiltIn")
    source_type <- if (native) "provider" else tool_metadata(tool)$source$type
    bypass <- if (native) NULL else trusted_bypass_reason(tool)
    if (!is.null(trusted_type)) {
      if (!is.null(bypass) || !source_type %in% c("function", "package")) {
        trusted_registry_abort(
          "Trusted tool {.val {name}} for {.val {trusted_type}} must be a local function tool that neither executes code nor delegates.",
          tool_name = name
        )
      }
      next
    }
    if (!is.null(bypass)) {
      trusted_registry_abort(
        "Tool {.val {name}} {bypass} and could bypass a trusted tool.",
        tool_name = name
      )
    }
    if (name %in% policy@exempt_tools) {
      if (!source_type %in% c("function", "package")) {
        trusted_registry_abort(
          "Only local function tools can be exempted; {.val {name}} is a {source_type} tool.",
          tool_name = name
        )
      }
      next
    }
    effective <- if (native) {
      tool_annotation_defaults
    } else {
      effective_tool_annotations(tool@annotations)
    }
    if (
      !isTRUE(effective$read_only_hint) ||
        !isFALSE(effective$destructive_hint) ||
        !isFALSE(effective$open_world_hint)
    ) {
      trusted_registry_abort(
        c(
          "Tool {.val {name}} may write or reach the open world, so it could bypass a trusted tool.",
          "i" = "Annotate it with {.code read_only_hint = TRUE, open_world_hint = FALSE} or list it in {.arg exempt_tools}."
        ),
        tool_name = name
      )
    }
  }
  invisible(NULL)
}

trusted_invocation_abort <- function(tool_name) {
  abort_tool_execution(
    "Trusted tool {.val {tool_name}} can only run through its own governed tool request.",
    tool_name = tool_name
  )
}

# Return the provider request ID for the trusted tool's own active request.
# NULL means the provider omitted an ID; name correlation then applies.
trusted_invocation_id <- function(tool) {
  context <- tryCatch(ellmer::tool_context(), error = function(error) NULL)
  request <- context$request
  source <- if (!is.null(request) && !is.null(request@tool)) {
    attr(request@tool, "deputy_runtime_source_tool", exact = TRUE) %||%
      request@tool
  }
  if (
    is.null(request) ||
      !identical(request@name, tool@name) ||
      (!is.null(source) && !identical(source, tool))
  ) {
    trusted_invocation_abort(tool@name)
  }
  id <- tryCatch(request@id, error = function(error) NULL)
  if (is_nonempty_string(id)) id else NULL
}

trusted_result_receipt <- function(id, type) {
  paste0(
    "Trusted result ",
    id,
    " (",
    type,
    ") was delivered directly to the user. Its values are withheld from ",
    "this conversation. Refer to it by ID; do not restate or estimate them."
  )
}

#' Inspect trusted results
#'
#' @param result An [AgentResult] S7 value.
#' @param type Optional result type to select.
#' @return List of `"trusted_result"` events. Each contains `result_id`,
#'   `result_type`, `tool_name`, `tool_call_id`, `arguments`, and the tool's
#'   verbatim `value`, plus run correlation fields.
#' @seealso [TrustedResults]
#' @export
result_trusted_results <- S7::new_generic(
  "result_trusted_results",
  "result",
  function(result, type = NULL) {
    S7::S7_dispatch()
  }
)

S7::method(result_trusted_results, AgentResult) <- function(
  result,
  type = NULL
) {
  if (!is.null(type) && !is_nonempty_string(type)) {
    cli_abort("{.arg type} must be NULL or one non-empty string.")
  }
  Filter(
    function(e) {
      e$type == "trusted_result" &&
        (is.null(type) || identical(e$result_type, type))
    },
    result@events
  )
}
