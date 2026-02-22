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
    tool_read_markdown,
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
    tool_read_file,
    tool_read_markdown
  )
}

#' Web tools
#'
#' @description
#' Returns a list of tools for web operations. When a `chat` object is provided,
#' automatically selects the best tools for that provider:
#'
#' * **Claude (Anthropic)**: Uses native `claude_tool_web_search()` and
#'   `claude_tool_web_fetch()` for higher quality results (requires admin
#'   enablement and incurs extra cost)
#' * **Google (Gemini/Vertex)**: Uses native `google_tool_web_search()` and
#'   `google_tool_web_fetch()`
#' * **OpenAI**: Uses native `openai_tool_web_search()`
#' * **Other providers**: Falls back to universal tools using httr2 and DuckDuckGo
#'
#' Without a `chat` argument, returns universal tools that work with any provider.
#'
#' @param chat Optional ellmer Chat object. If provided, returns provider-specific
#'   tools when available for better quality results.
#' @param use_native Logical. If `TRUE` (default), use native provider tools when
#'   available. Set to `FALSE` to always use universal tools.
#'
#' @return A list of tool definitions
#'
#' @examples
#' \dontrun{
#' # Universal tools (work with any provider)
#' agent <- Agent$new(
#'   chat = ellmer::chat_ollama(),
#'   tools = tools_web(),
#'   permissions = Permissions$new(web = TRUE)
#' )
#'
#' # Provider-specific tools (auto-detected)
#' chat <- ellmer::chat_claude()
#' agent <- Agent$new(
#'   chat = chat,
#'   tools = tools_web(chat),  # Uses Claude's native web tools
#'   permissions = Permissions$new(web = TRUE)
#' )
#'
#' # Force universal tools even with Claude
#' agent <- Agent$new(
#'   chat = chat,
#'   tools = tools_web(chat, use_native = FALSE),
#'   permissions = Permissions$new(web = TRUE)
#' )
#' }
#'
#' @seealso [tool_web_fetch], [tool_web_search]
#' @export
tools_web <- function(chat = NULL, use_native = TRUE) {
  # If no chat provided or native disabled, return universal tools
  if (is.null(chat) || !use_native) {
    return(list(tool_web_fetch, tool_web_search))
  }

  # Detect provider from chat
  provider_name <- get_provider_name(chat)

  # Return provider-specific tools when available
  switch(
    provider_name,
    "Anthropic" = {
      cli_inform(c(
        "i" = "Using Claude's native web tools (higher quality, extra cost)",
        "i" = "Set {.code use_native = FALSE} for free universal tools"
      ))
      list(
        ellmer::claude_tool_web_search(),
        ellmer::claude_tool_web_fetch()
      )
    },
    "Google/Gemini" = ,
    "Google/Vertex" = {
      cli_inform(c(
        "i" = "Using Google's native web tools"
      ))
      list(
        ellmer::google_tool_web_search(),
        ellmer::google_tool_web_fetch()
      )
    },
    "OpenAI" = {
      cli_inform(c(
        "i" = "Using OpenAI's native web search (fetch not available)",
        "i" = "Adding universal web_fetch as fallback"
      ))
      list(
        ellmer::openai_tool_web_search(),
        tool_web_fetch # OpenAI doesn't have native fetch
      )
    },
    # Default: universal tools
    {
      list(tool_web_fetch, tool_web_search)
    }
  )
}

#' Get provider name from a Chat object
#'
#' @param chat An ellmer Chat object
#' @return Provider name string, or "unknown" if detection fails
#' @noRd
get_provider_name <- function(chat) {
  if (!inherits(chat, "Chat")) {
    return("unknown")
  }

  tryCatch(
    {
      provider <- chat$get_provider()
      provider@name
    },
    error = function(e) "unknown"
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
    tool_read_markdown,
    tool_write_file,
    tool_list_files,
    tool_run_r_code,
    tool_run_bash,
    tool_read_csv,
    tool_web_fetch,
    tool_web_search
  )
}

#' Available tool preset names
#'
#' @description
#' Character vector of valid preset names for [tools_preset()].
#'
#' @export
ToolPresets <- c("minimal", "standard", "dev", "data", "full")

#' Get a tool preset by name
#'
#' @description
#' Returns a pre-configured collection of tools for common use cases.
#' Presets simplify agent setup by providing curated toolsets.
#'
#' @param name The preset name. One of:
#'   * `"minimal"` - Read-only tools for safe exploration
#'     (`read_file`, `read_markdown`, `list_files`)
#'   * `"standard"` - Balanced toolset for R development
#'     (`read_file`, `read_markdown`, `write_file`, `list_files`, `run_r_code`)
#'   * `"dev"` - Full development with shell access
#'     (`read_file`, `read_markdown`, `write_file`, `list_files`, `run_r_code`, `run_bash`)
#'   * `"data"` - Data analysis focused tools
#'     (`read_file`, `read_markdown`, `list_files`, `read_csv`, `run_r_code`)
#'   * `"full"` - All available tools (requires appropriate permissions)
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

  switch(
    name,
    minimal = list(
      tool_read_file,
      tool_read_markdown,
      tool_list_files
    ),
    standard = list(
      tool_read_file,
      tool_read_markdown,
      tool_write_file,
      tool_list_files,
      tool_run_r_code
    ),
    dev = list(
      tool_read_file,
      tool_read_markdown,
      tool_write_file,
      tool_list_files,
      tool_run_r_code,
      tool_run_bash
    ),
    data = list(
      tool_read_file,
      tool_read_markdown,
      tool_list_files,
      tool_read_csv,
      tool_run_r_code
    ),
    full = tools_all()
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
    name = c("minimal", "standard", "dev", "data", "full"),
    description = c(
      "Read-only tools for safe exploration",
      "Balanced toolset for R development",
      "Full development with shell access",
      "Data analysis focused tools",
      "All available tools"
    ),
    tools = c(
      "read_file, read_markdown, list_files",
      "read_file, read_markdown, write_file, list_files, run_r_code",
      "read_file, read_markdown, write_file, list_files, run_r_code, run_bash",
      "read_file, read_markdown, list_files, read_csv, run_r_code",
      "read_file, read_markdown, write_file, list_files, run_r_code, run_bash, read_csv, web_fetch, web_search"
    ),
    stringsAsFactors = FALSE
  )
}
