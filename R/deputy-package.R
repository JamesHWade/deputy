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
#' @section Main Functions:
#' * [Agent] - The main class for creating agents
#' * [LeadAgent] - Coordinate specialized delegated agents
#' * [tools_preset()] - Choose a set of built-in tools
#' * [UsageLimits()] - Set request, tool, token, and cost limits
#' * [permissions_standard()] - Standard permission policy
#' * [permissions_plan()] - Planning permission policy
#' * [permissions_readonly()] - Read-only permission policy
#'
#' @section Getting Started:
#' ```r
#' library(deputy)
#'
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-5.6-luna"),
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
