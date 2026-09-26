# Tool bundles for deputy agents
# Convenient groupings of related tools

#' Get the basic file tools
#'
#' @description
#' Returns `read_file`, `read_markdown`, `write_file` and `list_files`. The
#' editing and search tools, such as [tool_edit_file] and [tool_grep_files],
#' are separate.
#'
#' @return A list of tools.
#'
#' @examples
#' \dontrun{
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-6-luna"),
#'   tools = tools_file()
#' )
#' }
#'
#' @seealso [tool_read_file], [tool_read_markdown], [tool_write_file],
#'   [tool_list_files]
#' @export
tools_file <- function() {
  list(
    tool_read_file,
    tool_read_markdown,
    tool_write_file,
    tool_list_files
  )
}

#' Get the code execution tools
#'
#' @description
#' Returns `run_r_code` and `run_bash`. Both run model-written code with your
#' user account's access. Each call runs in a separate process, which is not a
#' sandbox. [permissions_standard()] denies both tools; allow them with
#' `r_code = TRUE` and `bash = TRUE` in [Permissions()]. For an OS sandbox, use
#' [tools_mcp_repl()].
#'
#' @return A list of tools.
#'
#' @examples
#' \dontrun{
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-6-luna"),
#'   tools = tools_code(),
#'   permissions = Permissions(r_code = TRUE, bash = TRUE)
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

#' Get the data reading tools
#'
#' @description
#' Returns `read_csv`, `read_file` and `read_markdown`.
#'
#' @return A list of tools.
#'
#' @examples
#' \dontrun{
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-6-luna"),
#'   tools = tools_data()
#' )
#' }
#'
#' @seealso [tool_read_csv], [tool_read_file], [tool_read_markdown]
#' @export
tools_data <- function() {
  list(
    tool_read_csv,
    tool_read_file,
    tool_read_markdown
  )
}

#' Get web tools
#'
#' @description
#' Returns a `web_search` and a `web_fetch` tool. By default these are
#' [tool_web_search] (DuckDuckGo) and [tool_web_fetch], which work with any
#' provider. If you pass `chat`, the provider's own tools are used where
#' available:
#'
#' * Anthropic: `claude_tool_web_search()` and `claude_tool_web_fetch()`.
#'   These cost extra and may need to be enabled by your organization's admin.
#' * Google Gemini and Vertex: `google_tool_web_search()` and
#'   `google_tool_web_fetch()`.
#' * OpenAI: `openai_tool_web_search()`, plus [tool_web_fetch].
#' * Other providers: the default tools.
#'
#' Provider tools run on the provider's servers, so the agent checks them once,
#' at registration, not on each call. It accepts them only if its permissions
#' set `web = TRUE`, list the tool names in `tool_allowlist`, and have no
#' `can_use_tool` callback.
#'
#' @param chat Optional ellmer Chat, used to pick the provider's own tools.
#' @param use_native If `FALSE`, always return the default tools.
#'
#' @return A list of tools.
#'
#' @examples
#' \dontrun{
#' # Default tools, for any provider
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-6-luna"),
#'   tools = tools_web(),
#'   permissions = Permissions(web = TRUE)
#' )
#'
#' # Anthropic's own web tools
#' chat <- ellmer::chat("anthropic/claude-sonnet-5")
#' agent <- Agent$new(
#'   chat = chat,
#'   tools = tools_web(chat),
#'   permissions = Permissions(
#'     web = TRUE,
#'     tool_allowlist = c("web_search", "web_fetch")
#'   )
#' )
#'
#' # Default tools, even with Anthropic
#' agent <- Agent$new(
#'   chat = chat,
#'   tools = tools_web(chat, use_native = FALSE),
#'   permissions = Permissions(web = TRUE)
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

#' Get all built-in tools
#'
#' @description
#' Returns every built-in tool except `ask_user`, which you can add with
#' [tools_interactive()]. That includes `run_r_code` and `run_bash`, which run
#' with your user account's access and are not sandboxed. The default
#' permissions deny them and the web tools; [permissions_full()] allows
#' everything.
#'
#' @return A list of tools.
#'
#' @examples
#' \dontrun{
#' # Allow every tool
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-6-luna"),
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
    tool_edit_file,
    tool_multi_edit,
    tool_list_files,
    tool_glob_files,
    tool_grep_files,
    tool_run_r_code,
    tool_run_bash,
    tool_read_csv,
    tool_web_fetch,
    tool_web_search
  )
}

# Available tool preset names.
ToolPresets <- c("minimal", "standard", "dev", "data", "full")

#' Get a tool preset by name
#'
#' @description
#' Returns a ready-made set of tools for a common kind of task. The `"dev"`,
#' `"data"` and `"full"` presets include code execution tools, which run with
#' your user account's access. The default permissions deny them; allow them
#' with `r_code = TRUE` (and `bash = TRUE` for `run_bash`) in [Permissions()].
#'
#' @param name The preset name. One of:
#'   * `"minimal"`: read-only tools
#'     (`read_file`, `read_markdown`, `list_files`).
#'   * `"standard"`: file tools
#'     (`read_file`, `read_markdown`, `write_file`, `list_files`).
#'   * `"dev"`: file tools plus code execution (`read_file`, `read_markdown`,
#'     `write_file`, `list_files`, `run_r_code`, `run_bash`).
#'   * `"data"`: data analysis
#'     (`read_file`, `read_markdown`, `list_files`, `read_csv`, `run_r_code`).
#'   * `"full"`: everything in [tools_all()].
#'
#' @return A list of tools.
#'
#' @examples
#' \dontrun{
#' # Read-only exploration
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-6-luna"),
#'   tools = tools_preset("minimal"),
#'   permissions = permissions_readonly()
#' )
#'
#' # Reading and writing files
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-6-luna"),
#'   tools = tools_preset("standard")
#' )
#'
#' # Data analysis with R code
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-6-luna"),
#'   tools = tools_preset("data"),
#'   permissions = Permissions(r_code = TRUE)
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
      tool_list_files
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
