#' @keywords internal
"_PACKAGE"

## usethis namespace: start
#' @importFrom R6 R6Class
#' @importFrom rlang %||% abort warn inform is_installed check_installed
#' @importFrom cli cli_alert cli_alert_info cli_alert_success cli_alert_warning
#' @importFrom cli cli_alert_danger cli_abort cli_warn cli_inform
#' @importFrom digest digest
#' @importFrom coro generator exhausted is_exhausted
## usethis namespace: end
NULL

# Package-level documentation
#' deputy: Agentic AI Workflows for R
#'
#' @description
#' A provider-agnostic framework for building agentic AI workflows in R.
#' Built on ellmer, it enables multi-step reasoning with tool use,
#' permissions, hooks, and human-in-the-loop capabilities.
#'
#' @section Main Functions:
#' * [Agent] - The main class for creating agents
#' * [tools_file()] - File operation tools
#' * [tools_code()] - Code execution tools
#' * [permissions_standard()] - Standard permission policy
#' * [permissions_readonly()] - Read-only permission policy
#'
#' @section Getting Started:
#' ```r
#' library(deputy)
#'
#' # Create an agent with file tools
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-4o"),
#'   tools = tools_file()
#' )
#'
#' # Run a task with streaming output
#' for (event in agent$run("List files in current directory")) {
#'   if (event$type == "text") cat(event$text)
#' }
#' ```
#'
#' @name deputy-package
#' @aliases deputy
NULL
