# MCP (Model Context Protocol) tools integration
#
# This module provides integration with MCP servers through the mcptools package.
# MCP allows dynamic tool discovery from external services like GitHub, Slack, etc.

#' Check if MCP support is available
#'
#' @description
#' Returns TRUE if the mcptools package is installed and available.
#'
#' @return Logical indicating if MCP support is available
#' @noRd
#'
#' @examples
#' if (mcp_available()) {
#'   message("MCP support is available")
#' }
mcp_available <- function() {
  requireNamespace("mcptools", quietly = TRUE)
}

#' Get tools from MCP servers
#'
#' @description
#' Starts the servers in an mcptools configuration file and returns their
#' tools, ready to register on an [Agent]. MCP (Model Context Protocol) servers
#' give agents tools for services such as GitHub, Slack or Google Drive.
#'
#' @param config Path to an MCP configuration file. Defaults to mcptools'
#'   default location, `~/.config/mcptools/config.json`.
#' @param servers Names of the servers to load, matched exactly. Servers not
#'   named are not started. `NULL` (the default) loads every configured server.
#'
#' @return A list of tools. If mcptools isn't installed or loading fails,
#'   `tools_mcp()` warns and returns an empty list.
#'
#' @details
#' The configuration file uses the Claude Desktop format:
#' ```json
#' {
#'   "mcpServers": {
#'     "github": {
#'       "command": "npx",
#'       "args": ["-y", "@modelcontextprotocol/server-github"],
#'       "env": {"GITHUB_TOKEN": "..."}
#'     }
#'   }
#' }
#' ```
#'
#' Deputy supports mcptools 1.0.2 and 1.0.3; other versions give a warning and
#' no tools. Annotations a server leaves out get cautious defaults, so MCP
#' tools usually need `web = TRUE` in [Permissions()]. [tool_metadata()] shows
#' what a tool declares.
#'
#' Loading a server again restarts it and breaks the tools from the earlier
#' load; register the new ones with `replace = TRUE`. A stdio server that takes
#' more than about 4 seconds to answer a call is stopped, and the call fails.
#' [McpConnection] gives you a fixed tool allowlist, timeouts and control over
#' shutdown.
#'
#' @seealso
#' The [mcptools package](https://posit-dev.github.io/mcptools/) for
#' configuration, and `vignette("mcp")`.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Get all MCP tools from the default config
#' mcp_tools <- tools_mcp()
#'
#' # Create an agent with MCP tools
#' agent <- Agent$new(
#'   chat = ellmer::chat("anthropic/claude-sonnet-5-5"),
#'   tools = c(tools_file(), mcp_tools),
#'   permissions = Permissions(web = TRUE)
#' )
#'
#' # Use custom config file
#' mcp_tools <- tools_mcp(config = "path/to/config.json")
#'
#' # Load tools from specific servers only
#' mcp_tools <- tools_mcp(servers = c("github", "slack"))
#' }
tools_mcp <- function(config = NULL, servers = NULL) {
  load_mcp_tools_result(config, servers)$tools
}

load_mcp_tools_result <- function(config, servers) {
  failed <- list(
    tools = list(),
    servers = character(),
    success = FALSE,
    error = "mcptools is not installed"
  )
  # Check if mcptools is available
  if (!mcp_available()) {
    cli::cli_warn(c(
      "mcptools package is not installed",
      "i" = "Install with: {.code install.packages('mcptools')}",
      "i" = "Returning empty tool list"
    ))
    return(failed)
  }

  # Fetch MCP tools
  result <- tryCatch(
    load_mcp_tools_with_metadata(config, servers),
    error = function(e) {
      error_class <- paste(class(e), collapse = ", ")
      # Escape braces in error message to prevent cli glue interpretation
      safe_msg <- gsub("\\{", "{{", gsub("\\}", "}}", e$message))
      cli::cli_warn(c(
        "Failed to fetch MCP tools",
        "x" = safe_msg,
        "i" = paste0("Error type: ", error_class),
        "i" = "Check your MCP configuration and server status"
      ))
      failed$error <- conditionMessage(e)
      failed
    }
  )
  tools <- result$tools

  if (length(tools) == 0) {
    cli::cli_alert_info("No MCP tools available")
  } else {
    tool_names <- vapply(
      seq_along(tools),
      function(i) {
        t <- tools[[i]]
        tryCatch(
          t@name %||% paste0("<unnamed_", i, ">"),
          error = function(e) {
            cli::cli_warn(c(
              "Could not read name from MCP tool {.val {i}}",
              "x" = e$message
            ))
            paste0("<unknown_", i, ">")
          }
        )
      },
      character(1)
    )
    cli::cli_alert_success(
      "Loaded {length(tools)} MCP tool{?s}: {.val {tool_names}}"
    )
  }

  result
}
