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
#' Fetches ellmer-compatible tools from configured MCP servers using the
#' mcptools package for use with deputy agents.
#'
#' MCP (Model Context Protocol) allows agents to access tools from external services
#' like GitHub, Slack, Google Drive, and more. Tools are discovered dynamically
#' from running MCP servers.
#'
#' @param config Path to MCP configuration file. If NULL (default), uses the
#'   mcptools default location (`~/.config/mcptools/config.json`).
#' @param servers Optional character vector of server names to load tools from.
#'   If NULL (default), loads tools from all configured servers. Filtering is
#'   based on pattern matching against tool names.
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
#'   chat = ellmer::chat_anthropic(),
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
      result <- if (is.null(config)) {
        mcptools::mcp_tools()
      } else {
        mcptools::mcp_tools(config = config)
      }

      # Validate result is a list
      if (!is.list(result)) {
        cli::cli_warn("mcptools::mcp_tools() returned non-list value")
        return(list())
      }

      result
    },
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
      list()
    }
  )

  # Filter by server names if specified
  # Note: Filtering is based on tool name pattern matching since mcptools
  # tools may not expose server origin metadata consistently
  if (!is.null(servers) && length(servers) > 0 && length(tools) > 0) {
    tools <- Filter(function(tool) {
      # Get tool name for filtering
      tool_name <- tryCatch(
        tool@name %||% "unknown",
        error = function(e) "unknown"
      )
      # Check if tool name matches any requested server pattern
      any(vapply(servers, function(s) {
        grepl(s, tool_name, ignore.case = TRUE)
      }, logical(1)))
    }, tools)
  }

  if (length(tools) == 0) {
    cli::cli_alert_info("No MCP tools available")
  } else {
    tool_names <- vapply(seq_along(tools), function(i) {
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
#' @param config Path to MCP configuration file. If NULL (default), uses
#'   `~/.config/mcptools/config.json`.
#'
#' @return A character vector of server names. Returns `character(0)` if config
#'   exists but has no servers. Returns NULL on error (mcptools not installed,
#'   config file missing, or parse error).
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

  # Use provided config or fall back to standard mcptools config location
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
      server_names <- names(cfg$mcpServers)
      if (is.null(server_names)) character(0) else server_names
    },
    error = function(e) {
      error_class <- paste(class(e), collapse = ", ")
      # Escape braces in error message to prevent cli glue interpretation
      safe_msg <- gsub("\\{", "{{", gsub("\\}", "}}", e$message))
      cli::cli_warn(c(
        "Failed to read MCP config",
        "x" = safe_msg,
        "i" = paste0("Error type: ", error_class)
      ))
      NULL
    }
  )
}
