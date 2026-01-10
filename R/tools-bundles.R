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

#' Available tool preset names
#'
#' @description
#' Character vector of valid preset names for [tools_preset()].
#'
#' @export
ToolPresets <- c("minimal", "standard", "full", "data")

#' Get a tool preset by name
#'
#' @description
#' Returns a pre-configured collection of tools for common use cases.
#' Presets simplify agent setup by providing curated toolsets.
#'
#' @param name The preset name. One of:
#'   * `"minimal"` - Read-only tools for safe exploration
#'     (`read_file`, `list_files`)
#'   * `"standard"` - Balanced toolset for typical tasks
#'     (`read_file`, `write_file`, `list_files`, `run_r_code`)
#'   * `"full"` - All available tools (requires appropriate permissions)
#'   * `"data"` - Data analysis focused tools
#'     (`read_file`, `list_files`, `read_csv`, `run_r_code`)
#'
#' @return A list of tool definitions
#'
#' @examples
#' \dontrun{
#' # Minimal preset for read-only operations
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-4o"),
#'   tools = tools_preset("minimal"),
#'   permissions = permissions_readonly()
#' )
#'
#' # Standard preset for typical development
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-4o"),
#'   tools = tools_preset("standard")
#' )
#'
#' # Data analysis preset
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-4o"),
#'   tools = tools_preset("data")
#' )
#' }
#'
#' @seealso [tools_file()], [tools_code()], [tools_data()], [tools_all()]
#' @export
tools_preset <- function(name) {
  if (!name %in% ToolPresets) {
    cli_abort(c(
      "Unknown tool preset: {.val {name}}",
      "i" = "Available presets: {.val {ToolPresets}}"
    ))
  }

  switch(name,
    minimal = list(
      tool_read_file,
      tool_list_files
    ),
    standard = list(
      tool_read_file,
      tool_write_file,
      tool_list_files,
      tool_run_r_code
    ),
    full = tools_all(),
    data = list(
      tool_read_file,
      tool_list_files,
      tool_read_csv,
      tool_run_r_code
    )
  )
}

#' List available tool presets
#'
#' @description
#' Returns information about available tool presets, including
#' their names, descriptions, and the tools they contain.
#'
#' @return A data frame with preset information
#'
#' @examples
#' list_presets()
#'
#' @export
list_presets <- function() {
  data.frame(
    name = c("minimal", "standard", "full", "data"),
    description = c(
      "Read-only tools for safe exploration",
      "Balanced toolset for typical tasks",
      "All available tools",
      "Data analysis focused tools"
    ),
    tools = c(
      "read_file, list_files",
      "read_file, write_file, list_files, run_r_code",
      "read_file, write_file, list_files, run_r_code, run_bash, read_csv",
      "read_file, list_files, read_csv, run_r_code"
    ),
    stringsAsFactors = FALSE
  )
}
