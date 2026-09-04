# Source this file to create approval hooks for one Agent.
# callback(questions, context) must return a named list of answers.
# Omit callback for an interactive terminal prompt.
library(deputy)

approval_gate <- function(
  callback = NULL,
  pattern = "^(run_bash|write_file)$"
) {
  HookMatcher$new(
    event = "PreToolUse",
    pattern = pattern,
    timeout = 0,
    callback = function(tool_name, tool_input, context) {
      ask <- tools_interactive(callback = callback, context = context)[[1]]
      question <- paste0(
        "Approve ",
        tool_name,
        " with these arguments?\n",
        paste(capture.output(dput(tool_input)), collapse = "\n")
      )
      response <- ask(list(list(
        question = question,
        header = "Approval",
        options = list(
          list(label = "Deny", description = "Do not execute this call"),
          list(label = "Approve", description = "Execute this exact call")
        ),
        multiSelect = FALSE
      )))
      approved <- identical(response$answers[[question]], "Approve")
      if (approved) {
        return(NULL)
      }
      HookResultPreToolUse(
        permission = "deny",
        reason = "The user did not approve this call"
      )
    }
  )
}

# Named tools make the sequence explicit: do not parse arbitrary shell commands
# to decide whether an installation or push happened.
approval_after_install <- function(callback = NULL) {
  installed_runs <- new.env(parent = emptyenv())
  gate <- approval_gate(callback, pattern = "^push_changes$")
  list(
    HookMatcher$new(
      event = "PostToolUse",
      pattern = "^install_dependency$",
      timeout = 0,
      callback = function(tool_name, tool_result, tool_error, context) {
        if (
          is.null(tool_error) &&
            is.list(tool_result) &&
            identical(tool_result$installed, TRUE)
        ) {
          installed_runs[[context$run_id]] <- TRUE
        }
        NULL
      }
    ),
    HookMatcher$new(
      event = "PreToolUse",
      pattern = "^push_changes$",
      timeout = 0,
      callback = function(tool_name, tool_input, context) {
        if (isTRUE(installed_runs[[context$run_id]])) {
          return(gate$callback(tool_name, tool_input, context))
        }
        NULL
      }
    ),
    HookMatcher$new(
      event = "Stop",
      timeout = 0,
      callback = function(reason, context) {
        if (exists(context$run_id, envir = installed_runs, inherits = FALSE)) {
          rm(list = context$run_id, envir = installed_runs)
        }
        NULL
      }
    )
  )
}
