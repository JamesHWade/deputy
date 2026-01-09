# Tool bundles for deputy agents
# Convenient groupings of related tools

#' File operation tools
#'
#' @description
#' Returns a list of tools for file operations:
#' * `read_file` - Read file contents
#' * `write_file` - Write content to files
#' * `list_files` - List directory contents
#'
#' @return A list of tool definitions
#'
#' @examples
#' \dontrun{
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-4o"),
#'   tools = tools_file()
#' )
#' }
#'
#' @seealso [tool_read_file], [tool_write_file], [tool_list_files]
#' @export
tools_file <- function() {
  list(
    tool_read_file,
    tool_write_file,
    tool_list_files
  )
}

#' Code execution tools
#'
#' @description
#' Returns a list of tools for code execution:
#' * `run_r_code` - Execute R code (sandboxed by default)
#' * `run_bash` - Execute bash commands
#'
#' **Note:** These tools require appropriate permissions. By default,
#' [permissions_standard()] allows R code but not bash.
#'
#' @return A list of tool definitions
#'
#' @examples
#' \dontrun{
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-4o"),
#'   tools = tools_code()
#' )
#' }
#'
#' @seealso [tool_run_r_code], [tool_run_bash]
#' @export
tools_code <- function() {
  list(
    tool_run_r_code,
    tool_run_bash
  )
}

#' Data reading tools
#'
#' @description
#' Returns a list of tools for reading data files:
#' * `read_csv` - Read CSV files with summary
#' * `read_file` - Read any file as text
#'
#' @return A list of tool definitions
#'
#' @examples
#' \dontrun{
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-4o"),
#'   tools = tools_data()
#' )
#' }
#'
#' @seealso [tool_read_csv], [tool_read_file]
#' @export
tools_data <- function() {
  list(
    tool_read_csv,
    tool_read_file
  )
}

#' All built-in tools
#'
#' @description
#' Returns all built-in tools. Use with [permissions_full()] if you want
#' to allow all operations.
#'
#' @return A list of all tool definitions
#'
#' @examples
#' \dontrun{
#' # Allow all tools with full permissions
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-4o"),
#'   tools = tools_all(),
#'   permissions = permissions_full()
#' )
#' }
#'
#' @export
tools_all <- function() {
  list(
    tool_read_file,
    tool_write_file,
    tool_list_files,
    tool_run_r_code,
    tool_run_bash,
    tool_read_csv
  )
}
