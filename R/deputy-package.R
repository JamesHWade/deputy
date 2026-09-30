#' @keywords internal
"_PACKAGE"

## usethis namespace: start
#' @importFrom R6 R6Class
#' @importFrom rlang %||% is_installed check_installed
#' @importFrom cli cli_alert cli_alert_info cli_alert_success cli_alert_warning
#' @importFrom cli cli_alert_danger cli_abort cli_warn cli_inform
#' @importFrom digest digest
#' @importFrom coro generator exhausted is_exhausted
## usethis namespace: end
NULL

# Package-level documentation
#' @section Main functions:
#' * [Agent]: runs a task with an ellmer Chat, tools, permissions and limits.
#' * [LeadAgent]: an agent that delegates tasks to subagents.
#' * [tools_preset()]: picks a set of built-in tools.
#' * [UsageLimits()]: caps requests, tool calls, tokens and cost.
#' * [permissions_standard()], [permissions_plan()] and
#'   [permissions_readonly()]: ready-made permission policies.
#'
#' @section Getting started:
#' ```r
#' library(deputy)
#'
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-6-luna"),
#'   tools = tools_preset("minimal"),
#'   permissions = permissions_readonly(),
#'   usage_limits = UsageLimits(max_requests = 6, max_tool_calls = 8),
#'   working_dir = getwd()
#' )
#'
#' result <- agent$run_sync("Read DESCRIPTION and explain what this package does.")
#' result$response
#' result$stop_reason
#' ```
#'
#' @name deputy-package
#' @aliases deputy
NULL

#' @rawNamespace if (getRversion() < "4.3.0") importFrom("S7", "@")
NULL

.onLoad <- function(libname, pkgname) {
  S7::methods_register()
}
