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
#' @export
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
#' Fetches tools from configured MCP servers and converts them to ellmer-compatible
#' tool definitions for use with deputy agents.
#'
#' MCP (Model Context Protocol) allows agents to access tools from external services
#' like GitHub, Slack, Google Drive, and more. Tools are discovered dynamically
#' from running MCP servers.
#'
#' @param config Path to MCP configuration file. If NULL (default), uses the
#'   mcptools default location (`~/.config/mcptools/config.json`).
#' @param servers Optional character vector of server names to load tools from.
#'   If NULL (default), loads tools from all configured servers.
#'
#' @return A list of tool definitions compatible with `Agent$register_tools()`.
#'   Returns an empty list if mcptools is not installed or no tools are available.
#'
#' @details
#' The MCP configuration file follows the Claude Desktop format:
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
#' @seealso
#' - `mcp_available()` to check if MCP support is installed
#' - [mcptools package](https://posit-dev.github.io/mcptools/) for configuration
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Get all MCP tools from default config
#' mcp_tools <- tools_mcp()
#'
#' # Create agent with MCP tools
#' agent <- Agent$new(
#'   chat = ellmer::chat("anthropic/claude-sonnet-4-5-20250929"),
#'   tools = c(tools_file(), mcp_tools)
#' )
#'
#' # Use custom config file
#' mcp_tools <- tools_mcp(config = "path/to/config.json")
#'
#' # Load tools from specific servers only
#' mcp_tools <- tools_mcp(servers = c("github", "slack"))
#' }
tools_mcp <- function(config = NULL, servers = NULL) {
  # Check if mcptools is available
  if (!mcp_available()) {
    cli::cli_warn(c(
      "mcptools package is not installed",
      "i" = "Install with: {.code install.packages('mcptools')}",
      "i" = "Returning empty tool list"
    ))
    return(list())
  }

  # Fetch MCP tools
  tools <- tryCatch(
    {
      if (is.null(config)) {
        mcptools::mcp_tools()
      } else {
        mcptools::mcp_tools(config = config)
      }
    },
    error = function(e) {
      cli::cli_warn(c(
        "Failed to fetch MCP tools",
        "x" = e$message,
        "i" = "Check your MCP configuration and server status"
      ))
      list()
    }
  )

  # Filter by server names if specified
  if (!is.null(servers) && length(tools) > 0) {
    # MCP tools from mcptools have server info in metadata
    # Filter based on server origin if available
    tools <- Filter(function(tool) {
      # Try to extract server name from tool metadata
      server_name <- tryCatch(
        tool@extra$server %||% tool@name,
        error = function(e) tool@name
      )
      # Check if tool's server matches any requested server
      any(vapply(servers, function(s) {
        grepl(s, server_name, ignore.case = TRUE)
      }, logical(1)))
    }, tools)
  }

  if (length(tools) == 0) {
    cli::cli_alert_info("No MCP tools available")
  } else {
    tool_names <- vapply(tools, function(t) {
      tryCatch(t@name, error = function(e) "unknown")
    }, character(1))
    cli::cli_alert_success("Loaded {length(tools)} MCP tool{?s}: {.val {tool_names}}")
  }

  tools
}

#' List available MCP servers
#'
#' @description
#' Lists the MCP servers configured in the mcptools configuration file.
#'
#' @param config Path to MCP configuration file. If NULL (default), uses the
#'   mcptools default location.
#'
#' @return A character vector of server names, or NULL if no servers configured.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # List configured servers
#' mcp_servers()
#' }
mcp_servers <- function(config = NULL) {
  if (!mcp_available()) {
    cli::cli_warn("mcptools package is not installed")
    return(NULL)
  }

  # Read config file
  config_path <- config %||% file.path(
    Sys.getenv("HOME"),
    ".config", "mcptools", "config.json"
  )

  if (!file.exists(config_path)) {
    cli::cli_alert_info("No MCP config found at {.path {config_path}}")
    return(NULL)
  }

  tryCatch(
    {
      cfg <- jsonlite::fromJSON(config_path, simplifyVector = FALSE)
      names(cfg$mcpServers)
    },
    error = function(e) {
      cli::cli_warn(c(
        "Failed to read MCP config",
        "x" = e$message
      ))
      NULL
    }
  )
}
