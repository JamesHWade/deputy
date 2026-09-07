#' Connect an Agent to an independent sandboxed REPL
#'
#' @description
#' Creates a [McpConnection] for one explicitly configured mcp-repl server.
#' Each connection owns an independent client and upstream interpreter session.
#' Register its `$tools()` on the supplied Agent to retain normal permissions,
#' hooks, budgets and execution provenance.
#'
#' @param config Path to an mcptools configuration. Defaults to
#'   `~/.config/mcptools/config.json`.
#' @param agent Agent that owns the connection.
#' @param server Exact configured mcp-repl server name.
#' @param sandbox Required explicit upstream sandbox policy.
#' @param timeout Maximum seconds for one MCP request. This is distinct from
#'   mcp-repl's `timeout_ms`, which can return a busy result while code continues.
#' @param startup_timeout Maximum seconds for client/server startup.
#' @return A [McpConnection]. The host must close it when the conversation ends.
#'
#' @details
#' The producer contract is qualified with mcptools 1.0.2 and mcp-repl 0.3.0.
#' The executable must be installed and configured by the host. mcp-repl owns
#' interpreter startup, sandbox enforcement, reset, interrupt, rich content and
#' oversized-output artifacts. The client requires its `repl(input, timeout_ms)`
#' tool contract; it does not infer a binary version from the executable name.
#'
#' A busy interpreter result is upstream output, not a completed calculation.
#' After such a response, [mcp_repl_control()] can request an interrupt or reset.
#' An active client request cannot accept a second request: use `$cancel()` to
#' terminate the connection and discard state, or wait for the request to return.
#' Interrupting the owning Agent also cancels its active MCP connections.
#'
#' @export
#' @examples
#' \dontrun{
#' agent <- Agent$new(chat = ellmer::chat("openai/gpt-5.6-luna"))
#' connection <- mcp_repl_connection(agent = agent)
#' agent$register_tools(connection$tools())
#' # In a Shiny host: session$onSessionEnded(function() connection$close())
#' connection$close()
#' }
mcp_repl_connection <- function(
  config = NULL,
  agent,
  server = "r",
  sandbox = c("workspace-write", "read-only"),
  timeout = 60,
  startup_timeout = 60
) {
  sandbox <- match.arg(sandbox)
  config <- config %||% file.path("~", ".config", "mcptools", "config.json")
  selected <- mcp_connection_config(config, server)
  validate_mcp_repl_sandbox_server(selected, sandbox)
  # Validate and connect the same frozen entry, even if the host edits its
  # configuration file while this connection is starting.
  path <- tempfile(fileext = ".json")
  on.exit(unlink(path), add = TRUE)
  file.create(path)
  Sys.chmod(path, "0600")
  jsonlite::write_json(
    list(mcpServers = stats::setNames(list(selected), server)),
    path,
    auto_unbox = TRUE,
    null = "null"
  )
  connection <- McpConnection$new(
    path,
    server,
    agent,
    tools = "repl",
    timeout = timeout,
    startup_timeout = startup_timeout
  )
  ok <- FALSE
  on.exit(if (!ok) connection$close(), add = TRUE)
  tool <- connection$tools()$repl
  if (!identical(names(tool@arguments@properties), c("input", "timeout_ms"))) {
    abort_deputy(
      "The mcp-repl tool contract has changed; this producer is not qualified.",
      class = "mcp_repl"
    )
  }
  attr(connection, "deputy_mcp_repl") <- list(
    backend = "mcp-repl",
    sandbox = sandbox
  )
  ok <- TRUE
  connection
}

#' Request an upstream REPL interrupt or reset
#'
#' Sends mcp-repl's documented Ctrl-C or Ctrl-D input through the same connection.
#' Interrupt is best effort; reset requests a fresh interpreter and discards its
#' state. The returned upstream result describes what happened. Neither action
#' is treated as proof of success merely because a request was sent.
#'
#' @param connection A connection created by [mcp_repl_connection()].
#' @param action `"interrupt"` or `"reset"`.
#' @return A promise for the upstream ellmer-compatible result. This is a direct
#'   host operation, not an Agent run. Busy client connections reject overlap.
#' @export
mcp_repl_control <- function(connection, action = c("interrupt", "reset")) {
  action <- match.arg(action)
  if (
    !inherits(connection, "McpConnection") ||
      is.null(attr(connection, "deputy_mcp_repl", exact = TRUE))
  ) {
    abort_deputy(
      "Use a connection created by {.fn mcp_repl_connection}.",
      class = "mcp_repl"
    )
  }
  input <- if (identical(action, "interrupt")) "\003" else "\004"
  connection$tools()$repl(input = input)
}
