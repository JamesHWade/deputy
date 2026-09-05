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

#' Load an R REPL with an enforced OS sandbox
#'
#' @description
#' Loads one explicitly configured [mcp-repl](https://github.com/posit-dev/mcp-repl)
#' server after verifying that its command requests the exact sandbox policy.
#' Deputy refuses missing, inherited, external, and unrestricted policies.
#'
#' This is the supported path for model-generated code that requires an OS
#' security boundary. Deputy's built-in [tool_run_r_code] and [tool_run_bash]
#' are trusted-code tools; their subprocesses provide fault isolation, not
#' filesystem or network confinement.
#'
#' @param config Path to an mcptools JSON configuration. Defaults to
#'   `~/.config/mcptools/config.json`.
#' @param server Exact MCP server name. Defaults to `"r"`, the name used by
#'   mcp-repl's installation examples.
#' @param sandbox Required mcp-repl policy. `"workspace-write"` confines writes
#'   to configured roots and `"read-only"` denies workspace writes. mcp-repl
#'   also controls network access according to its server configuration.
#'
#' @return A list of ellmer-compatible tools from the selected mcp-repl server.
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
#'   chat = ellmer::chat("openai/gpt-5.6-luna"),
#'   tools = repl_tools,
#'   permissions = Permissions$new(web = FALSE)
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
  tools
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
#'   performed on exact configuration names before connecting servers.
#'
#' @return A list of tool definitions compatible with `Agent$register_tools()`.
#'   [tool_metadata()] reports exact MCP origin, supplied annotations, and gaps.
#'   The metadata bridge is qualified for mcptools 1.0.2; other versions fail
#'   explicitly rather than silently losing annotations. Reconnecting a server
#'   invalidates tools loaded from its previous connection. Reload and explicitly
#'   replace those tools on the Agent. Load failures warn and return an empty list.
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
#' [mcptools package](https://posit-dev.github.io/mcptools/) for configuration
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
