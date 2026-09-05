# Trusted one-shot R and shell tools.

run_r_code_impl <- function(code, timeout = 30, working_dir = getwd()) {
  rlang::check_installed("callr", reason = "to execute R code in a subprocess")

  result <- tryCatch(
    callr::r(
      function(code_string) {
        output <- utils::capture.output({
          result <- tryCatch(
            base::eval(base::parse(text = code_string)),
            error = function(e) list(.deputy_error = e$message)
          )
        })
        list(
          output = paste(output, collapse = "\n"),
          result = if (is.list(result) && ".deputy_error" %in% names(result)) {
            paste("Error:", result$.deputy_error)
          } else {
            utils::capture.output(print(result))
          }
        )
      },
      args = list(code_string = code),
      timeout = timeout,
      wd = working_dir
    ),
    error = function(e) {
      if (inherits(e, "callr_timeout_error")) {
        ellmer::tool_reject(sprintf(
          "R code execution timed out after %s seconds",
          format(timeout, trim = TRUE)
        ))
      }
      ellmer::tool_reject(paste(
        "R code execution failed:",
        conditionMessage(e)
      ))
    }
  )

  parts <- character()
  if (nchar(result$output) > 0) {
    parts <- c(parts, "Output:", result$output)
  }
  if (length(result$result) > 0 && any(nchar(result$result) > 0)) {
    parts <- c(parts, "Result:", paste(result$result, collapse = "\n"))
  }

  if (length(parts) == 0) {
    return("Code executed successfully (no output)")
  }

  paste(parts, collapse = "\n")
}

#' Execute R code
#'
#' @description
#' A tool that executes R code and returns the result. It runs in a separate
#' process for fault isolation and timeout enforcement (requires callr).
#'
#' @details
#' This tool intentionally uses R's code evaluation capabilities to execute
#' arbitrary R code provided by the LLM. This is a core feature for agentic
#' workflows where the agent needs to perform data analysis or other R tasks.
#'
#' The execution boundary is explicit:
#' - Code runs in a separate callr subprocess, not an OS security sandbox
#' - A timeout prevents runaway execution
#' - The Permissions system can disable this tool entirely
#'
#' @format A tool definition created with `ellmer::tool()`.
#' @return When called directly, a character string containing captured output
#'   and the returned value.
#'
#' @param code R code to execute (tool argument)
#'
#' @examples
#' \dontrun{
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-5.6-luna"),
#'   tools = list(tool_run_r_code)
#' )
#' }
#'
#' @export
tool_run_r_code <- ellmer::tool(
  fun = function(code) {
    run_r_code_impl(code)
  },
  name = "run_r_code",
  description = paste(
    "Execute R code in a separate process and return the output and result.",
    "Process isolation is not an OS security sandbox."
  ),
  arguments = list(
    code = ellmer::type_string("R code to execute")
    # Note: process isolation and timeout are internal, not exposed to the LLM
  ),
  annotations = ellmer::tool_annotations(
    read_only_hint = FALSE,
    destructive_hint = TRUE,
    open_world_hint = TRUE
  )
)
attr(tool_run_r_code, "deputy_workspace_runner") <-
  function(arguments, working_dir) {
    run_r_code_impl(arguments$code, working_dir = working_dir)
  }

run_bash_impl <- function(command, timeout = 30, working_dir = getwd()) {
  # Use callr for reliable timeout enforcement if available
  if (rlang::is_installed("callr")) {
    tryCatch(
      {
        result <- callr::r(
          function(cmd) {
            system(cmd, intern = TRUE)
          },
          args = list(cmd = command),
          timeout = timeout,
          wd = working_dir
        )
        if (length(result) == 0) {
          "Command executed successfully (no output)"
        } else {
          paste(result, collapse = "\n")
        }
      },
      error = function(e) {
        if (inherits(e, "callr_timeout_error")) {
          ellmer::tool_reject(sprintf(
            "Command timed out after %s seconds",
            format(timeout, trim = TRUE)
          ))
        }
        ellmer::tool_reject(paste(
          "Command failed:",
          conditionMessage(e)
        ))
      }
    )
  } else {
    # Keep the host process directory unchanged in the fallback path.
    command <- paste("cd", shQuote(working_dir), "&&", command)
    tryCatch(
      {
        result <- system(command, intern = TRUE, timeout = timeout)
        if (length(result) == 0) {
          "Command executed successfully (no output)"
        } else {
          paste(result, collapse = "\n")
        }
      },
      error = function(e) {
        ellmer::tool_reject(paste("Command failed:", e$message))
      },
      warning = function(w) {
        paste("Warning:", w$message)
      }
    )
  }
}

#' Execute bash commands
#'
#' @description
#' A tool that executes bash/shell commands and returns the output.
#' **Use with caution!** This can execute arbitrary system commands.
#'
#' @format A tool definition created with `ellmer::tool()`.
#' @return When called directly, a character string containing command output
#'   or a success message.
#'
#' @param command The bash command to execute (tool argument)
#'
#' @examples
#' \dontrun{
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-5.6-luna"),
#'   tools = list(tool_run_bash),
#'   permissions = permissions_full()  # Required for bash
#' )
#' }
#'
#' @export
tool_run_bash <- ellmer::tool(
  fun = function(command) {
    run_bash_impl(command)
  },
  name = "run_bash",
  description = "Execute a bash/shell command and return the output. Use with caution - this can execute arbitrary system commands.",
  arguments = list(
    command = ellmer::type_string("The bash command to execute")
    # Note: timeout is an internal parameter, not exposed to LLM
  ),
  annotations = ellmer::tool_annotations(
    read_only_hint = FALSE,
    destructive_hint = TRUE,
    open_world_hint = TRUE
  )
)
attr(tool_run_bash, "deputy_workspace_runner") <-
  function(arguments, working_dir) {
    run_bash_impl(arguments$command, working_dir = working_dir)
  }
