#' @include permission-policy.R

# Runtime tool adaptation ---------------------------------------------------

native_file_tool_names <- c(
  permission_file_read_tool_ids,
  "write_file",
  "edit_file",
  "multi_edit"
)

deputy_tool_result_reader_marker <- new.env(parent = emptyenv())
# Marks a LeadAgent's own delegate_to_agent tool. Read-only and plan modes
# admit only the tool carrying it, never another tool with the same name.
deputy_delegation_tool_marker <- new.env(parent = emptyenv())
# Marks delegation_tool() and graph route tools, which call retained agents.
# Read-only and plan modes admit them by this marker; hosts choose the names.
deputy_composition_tool_marker <- new.env(parent = emptyenv())

clear_chat_tool_callbacks <- function(chat, source = NULL) {
  private <- tryCatch(chat$.__enclos_env__$private, error = function(e) NULL)
  source_private <- tryCatch(
    source$.__enclos_env__$private,
    error = function(e) NULL
  )
  for (name in c("callback_on_tool_request", "callback_on_tool_result")) {
    manager <- private[[name]]
    if (!is.null(manager) && identical(manager, source_private[[name]])) {
      cli_abort("Chat cloning must isolate tool callback managers")
    }
    if (!is.null(manager) && is.function(manager$clear)) manager$clear()
  }
  invisible(chat)
}

runtime_wrap_tool <- function(
  tool,
  resolve_arguments,
  process_result,
  begin_execution = function(tool_name, tool_call_id = NULL) NULL,
  execute = function(tool, arguments, execution_id) do.call(tool, arguments),
  invocation_id = composition_invocation_id
) {
  if (!inherits(tool, "ellmer::ToolDef")) {
    cli_abort("{.arg tool} must be an ellmer tool definition")
  }
  if (
    !is.function(resolve_arguments) ||
      !is.function(process_result) ||
      !is.function(begin_execution) ||
      !is.function(execute) ||
      !is.function(invocation_id)
  ) {
    cli_abort("Runtime tool adapters must be functions")
  }

  source_tool <- runtime_source_tool(tool)

  wrapper_env <- rlang::env(
    original = source_tool,
    resolve_arguments = resolve_arguments,
    process_result = process_result,
    begin_execution = begin_execution,
    execute = execute,
    invocation_id = invocation_id,
    tool_name = source_tool@name
  )
  invoke <- rlang::new_function(
    alist(arguments = ),
    quote({
      arguments <- resolve_arguments(
        tool_name,
        arguments
      )
      execution_id <- begin_execution(
        tool_name,
        invocation_id(original, arguments)
      )
      value <- execute(original, arguments, execution_id)
      if (promises::is.promising(value)) {
        return(promises::then(value, function(resolved) {
          process_result(tool_name, resolved, execution_id)
        }))
      }
      process_result(tool_name, value, execution_id)
    }),
    wrapper_env
  )
  wrapper <- rlang::new_function(
    formals(source_tool),
    rlang::expr((!!invoke)(base::as.list(
      base::environment(),
      all.names = TRUE
    )))
  )

  wrapped <- ellmer::tool(
    fun = wrapper,
    name = source_tool@name,
    description = source_tool@description,
    arguments = runtime_tool_arguments(source_tool),
    convert = source_tool@convert,
    annotations = source_tool@annotations
  )
  attr(wrapped, "deputy_runtime_tool") <- TRUE
  attr(wrapped, "deputy_runtime_source_tool") <- source_tool
  internal_tool <- attr(source_tool, "deputy_internal_tool", exact = TRUE)
  if (!is.null(internal_tool)) {
    attr(wrapped, "deputy_internal_tool") <- internal_tool
  }
  wrapped
}

# ellmer drops `type_ignore()` arguments from a tool's schema, but the wrapper
# keeps the source function's formals. Declare those formals ignored again so
# the rebuilt tool has the same schema and the model still never supplies them.
runtime_tool_arguments <- function(tool) {
  arguments <- tool@arguments@properties
  ignored <- setdiff(names(formals(tool)), c(names(arguments), "..."))
  arguments[ignored] <- rep(list(ellmer::type_ignore()), length(ignored))
  arguments
}

resolve_runtime_tool_arguments <- function(tool_name, arguments, working_dir) {
  if (
    !tool_name %in% native_file_tool_names ||
      is.null(arguments$path) ||
      !is.character(arguments$path) ||
      length(arguments$path) != 1L ||
      is.na(arguments$path) ||
      !nzchar(arguments$path)
  ) {
    return(arguments)
  }

  if (!is_absolute_path(arguments$path)) {
    arguments$path <- file.path(working_dir, arguments$path)
  }
  arguments
}

validate_owned_tool <- function(
  tool,
  owner_attr,
  expected_owner,
  message,
  call = rlang::caller_env()
) {
  source <- runtime_source_tool(tool)
  owner <- attr(source, owner_attr, exact = TRUE)
  if (!is.null(owner) && !identical(owner, expected_owner)) {
    tool_registration_error(message, call = call)
  }
  invisible(NULL)
}

cancel_owned_tools <- function(tools, owner_attr, cancel_attr, expected_owner) {
  for (tool in tools) {
    source <- runtime_source_tool(tool)
    if (!identical(attr(source, owner_attr, exact = TRUE), expected_owner)) {
      next
    }
    cancel <- attr(source, cancel_attr, exact = TRUE)
    if (is.function(cancel)) {
      cancel()
    }
  }
  invisible(NULL)
}
