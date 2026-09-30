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

mcp_repl_sandbox_setting <- function(arguments) {
  arguments <- unlist(arguments %||% list(), use.names = FALSE)
  if (length(arguments) == 0L) {
    return(NULL)
  }
  if (!is.character(arguments) || anyNA(arguments)) {
    cli_abort("mcp-repl arguments must be character strings")
  }

  positions <- integer()
  values <- character()
  for (index in seq_along(arguments)) {
    argument <- arguments[[index]]
    if (identical(argument, "--config") || startsWith(argument, "--config=")) {
      override <- if (
        identical(argument, "--config") && index < length(arguments)
      ) {
        arguments[[index + 1L]]
      } else {
        sub("^--config=", "", argument)
      }
      key <- trimws(strsplit(override, "=", fixed = TRUE)[[1L]][[1L]])
      if (identical(key, "sandbox_mode")) {
        cli_abort(c(
          "Set the sandbox mode with {.code --sandbox}, not {.code --config sandbox_mode}.",
          "i" = "Deputy cannot qualify an overriding sandbox mode through this adapter."
        ))
      }
    }
    if (identical(argument, "--sandbox")) {
      if (
        index == length(arguments) || startsWith(arguments[[index + 1L]], "--")
      ) {
        cli_abort("mcp-repl {.code --sandbox} requires a value")
      }
      positions <- c(positions, index)
      values <- c(values, arguments[[index + 1L]])
    } else if (startsWith(argument, "--sandbox=")) {
      positions <- c(positions, index)
      values <- c(values, sub("^--sandbox=", "", argument))
    }
  }

  if (length(values) == 0L) {
    return(NULL)
  }
  values[[which.max(positions)]]
}

validate_mcp_repl_sandbox_server <- function(server, sandbox) {
  if (!is.list(server)) {
    cli_abort("The selected MCP server must be a configuration object")
  }
  if (!is.null(server$url)) {
    cli_abort(
      "The sandboxed mcp-repl server must use stdio; a URL would bypass the checked local command."
    )
  }
  command <- server$command
  if (
    !is.character(command) ||
      length(command) != 1L ||
      is.na(command) ||
      !basename(command) %in%
        c(
          "mcp-repl",
          "mcp-repl.exe",
          "posit-mcp-repl",
          "posit-mcp-repl.exe"
        )
  ) {
    cli_abort("The selected server must invoke the mcp-repl executable")
  }

  configured <- mcp_repl_sandbox_setting(server$args)
  if (is.null(configured) || !nzchar(configured)) {
    cli_abort(c(
      "The mcp-repl server must explicitly set {.code --sandbox}.",
      "i" = "Deputy will not infer a sandbox guarantee from backend defaults."
    ))
  }
  if (configured %in% c("inherit", "inherit-codex")) {
    cli_abort(c(
      "mcp-repl sandbox mode {.val {configured}} is not valid here.",
      "i" = "mcptools does not send Codex per-call sandbox metadata."
    ))
  }
  if (configured %in% c("danger-full-access", "external-sandbox")) {
    cli_abort(
      "mcp-repl sandbox mode {.val {configured}} does not enforce the requested boundary."
    )
  }
  if (!configured %in% c("read-only", "workspace-write")) {
    cli_abort("Unsupported mcp-repl sandbox mode: {.val {configured}}")
  }
  if (!identical(configured, sandbox)) {
    cli_abort(c(
      "Requested sandbox {.val {sandbox}}, but mcp-repl is configured for {.val {configured}}.",
      "i" = "Change the server configuration or request its configured mode."
    ))
  }
  configured
}

#' Load sandboxed R tools from mcp-repl
#'
#' @description
#' Loads the tools of one [mcp-repl](https://github.com/posit-dev/mcp-repl)
#' server, which runs R inside an OS sandbox. Use it when model-written code
#' must not have your full user access; [tool_run_r_code] and [tool_run_bash]
#' can reach your files and network.
#'
#' The server's configuration entry must run the mcp-repl executable over stdio
#' with `--sandbox` set to `sandbox`. A missing flag, a different mode, or a
#' mode that doesn't guarantee a sandbox (`inherit`, `inherit-codex`,
#' `external-sandbox`, `danger-full-access`) is an error. For a connection
#' owned by one agent that you can interrupt, reset and close, use
#' [mcp_repl_connection()].
#'
#' @param config Path to an mcptools JSON configuration. Defaults to
#'   `~/.config/mcptools/config.json`.
#' @param server Name of the server in `config`. Defaults to `"r"`, the name
#'   mcp-repl's installation examples use.
#' @param sandbox The sandbox mode the server must use. `"workspace-write"`
#'   limits writes to the configured workspace roots; `"read-only"` blocks
#'   workspace writes. Network access follows the server's own configuration.
#'
#' @return A list of tools from the server. The `repl` tool waits at most
#'   3 seconds per call (see [mcp_repl_connection()]); longer work returns a
#'   busy result, and a later call with empty `input` collects its output.
#' @export
#'
#' @examples
#' \dontrun{
#' repl_tools <- tools_mcp_repl(
#'   config = "~/.config/mcptools/config.json",
#'   server = "r",
#'   sandbox = "workspace-write"
#' )
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-6-luna"),
#'   tools = repl_tools,
#'   permissions = Permissions(web = FALSE)
#' )
#' }
tools_mcp_repl <- function(
  config = NULL,
  server = "r",
  sandbox = c("workspace-write", "read-only")
) {
  sandbox <- match.arg(sandbox)
  if (
    !is.character(server) ||
      length(server) != 1L ||
      is.na(server) ||
      !nzchar(server)
  ) {
    cli_abort("{.arg server} must be one non-empty string")
  }
  rlang::check_installed("jsonlite", reason = "to validate MCP configuration")

  config <- path.expand(
    config %||%
      file.path(
        "~",
        ".config",
        "mcptools",
        "config.json"
      )
  )
  if (!file.exists(config)) {
    cli_abort("MCP configuration not found: {.path {config}}")
  }
  payload <- tryCatch(
    jsonlite::fromJSON(config, simplifyVector = FALSE),
    error = function(error) {
      cli_abort("Could not parse MCP configuration", parent = error)
    }
  )
  servers <- payload$mcpServers
  if (!is.list(servers) || is.null(servers[[server]])) {
    cli_abort("MCP configuration has no server named {.val {server}}")
  }
  selected <- servers[[server]]
  validate_mcp_repl_sandbox_server(selected, sandbox)

  if (!mcp_available()) {
    cli_abort("{.pkg mcptools} is required to load mcp-repl tools")
  }

  isolated_config <- tempfile("deputy-mcp-repl-", fileext = ".json")
  on.exit(unlink(isolated_config), add = TRUE)
  file.create(isolated_config)
  Sys.chmod(isolated_config, mode = "0600")
  jsonlite::write_json(
    list(mcpServers = stats::setNames(list(selected), server)),
    isolated_config,
    auto_unbox = TRUE,
    null = "null"
  )

  tools <- tools_mcp(config = isolated_config)
  if (length(tools) == 0L) {
    cli_abort("The sandboxed mcp-repl server returned no tools")
  }
  lapply(tools, mcp_repl_bound_tool)
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
#'   chat = ellmer::chat("anthropic/claude-sonnet-5"),
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
#' @noRd
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
  config_path <- config %||%
    file.path(
      Sys.getenv("HOME"),
      ".config",
      "mcptools",
      "config.json"
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
