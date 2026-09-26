#' Connect an agent to a sandboxed mcp-repl session
#'
#' @description
#' Starts one mcp-repl server from an mcptools configuration and connects it to
#' `agent`. mcp-repl runs R inside an OS sandbox and keeps variables between
#' calls; each connection has its own R session. Register `connection$tools()`
#' on the agent so that calls go through its permissions, hooks and limits.
#' The server entry must pass `--sandbox`, as described in [tools_mcp_repl()].
#'
#' @param config Path to an mcptools configuration. Defaults to
#'   `~/.config/mcptools/config.json`.
#' @param agent The agent that owns the connection.
#' @param server Name of the mcp-repl server in `config`.
#' @param sandbox The sandbox mode the server must be configured with.
#' @param timeout Maximum seconds to wait for one MCP request before closing
#'   the connection. This is separate from the per-call `timeout_ms` limit
#'   described in Details.
#' @param startup_timeout Maximum seconds for the client and server to start.
#' @return A [McpConnection]. Call its `$close()` method when the conversation
#'   ends.
#'
#' @details
#' Supported with mcptools 1.0.2 or 1.0.3 and mcp-repl 0.3.0. You install and
#' configure the mcp-repl executable yourself; it handles the sandbox,
#' interrupts, resets, rich output and large outputs. The connection errors if
#' the server's `repl` tool doesn't take exactly the arguments `input` and
#' `timeout_ms`.
#'
#' mcptools waits only about 4 seconds for a reply, so each `repl` call waits at
#' most 3 seconds: `timeout_ms` is capped at 3000 and defaults to 3000 (instead
#' of mcp-repl's 60 seconds). Longer work keeps running: the call returns a busy
#' result, and a later call with empty `input` collects the rest of the output.
#' The tool description tells the model this.
#'
#' A busy result means the code hasn't finished. Use [mcp_repl_control()] to
#' interrupt it or reset the session. A connection handles one request at a
#' time; `$cancel()` ends the connection and discards the R session.
#' Interrupting the agent also cancels its active MCP connections.
#'
#' @export
#' @examples
#' \dontrun{
#' agent <- Agent$new(chat = ellmer::chat("openai/gpt-6-luna"))
#' connection <- mcp_repl_connection(agent = agent)
#' agent$register_tools(connection$tools())
#' # In a Shiny app: session$onSessionEnded(function() connection$close())
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
  attr(connection, "deputy_mcp_adapter") <- list(
    tool = "repl",
    execution = list(backend = "mcp-repl", sandbox = sandbox),
    arguments = mcp_repl_bound_arguments,
    description = mcp_repl_tool_description
  )
  ok <- TRUE
  connection
}

#' Interrupt or reset an mcp-repl session
#'
#' Sends Ctrl-C (`"interrupt"`) or Ctrl-D (`"reset"`) to the R session behind a
#' [mcp_repl_connection()]. An interrupt may not stop the code. A reset starts
#' a fresh interpreter and discards its variables. Check the returned result to
#' see what happened.
#'
#' @param connection A connection created by [mcp_repl_connection()].
#' @param action `"interrupt"` or `"reset"`.
#' @return A promise for mcp-repl's reply. The call goes straight to the
#'   server, not through the agent, and errors if the connection is already
#'   handling a request.
#' @export
mcp_repl_control <- function(connection, action = c("interrupt", "reset")) {
  action <- match.arg(action)
  if (
    !inherits(connection, "McpConnection") ||
      !identical(
        attr(connection, "deputy_mcp_adapter", exact = TRUE)$execution$backend,
        "mcp-repl"
      )
  ) {
    abort_deputy(
      "Use a connection created by {.fn mcp_repl_connection}.",
      class = "mcp_repl"
    )
  }
  input <- if (identical(action, "interrupt")) "\003" else "\004"
  connection$tools()$repl(input = input)
}

# mcptools 1.0.2/1.0.3 stdio requests stop reading after about 4 seconds
# (20 polls of 0.2 s). mcp-repl answers slightly before `timeout_ms` with a
# busy result, so this bound leaves transport and scheduling headroom.
mcp_repl_timeout_ms_max <- 3000L

mcp_repl_bound_arguments <- function(arguments) {
  value <- arguments$timeout_ms
  if (is.null(value)) {
    arguments$timeout_ms <- mcp_repl_timeout_ms_max
  } else if (is.numeric(value) && length(value) == 1L && !is.na(value)) {
    # Invalid values pass through so mcp-repl reports its own parameter error.
    arguments$timeout_ms <- min(value, mcp_repl_timeout_ms_max)
  }
  arguments
}

mcp_repl_tool_description <- function(description) {
  paste0(
    description %||% "",
    "\n\nDeputy caps `timeout_ms` at ",
    mcp_repl_timeout_ms_max,
    " ms per call (also when omitted). Longer work keeps running: the call ",
    "returns a busy status, and a later call with empty `input` retrieves ",
    "the remaining output."
  )
}

# Apply the same bound to the in-process tools_mcp_repl() handle, keeping the
# metadata bridge's origin and connection-currency attributes.
mcp_repl_bound_tool <- function(tool) {
  if (
    !identical(tool@name, "repl") ||
      !"timeout_ms" %in% names(tool@arguments@properties)
  ) {
    return(tool)
  }
  invoke <- function(arguments) {
    do.call(tool, mcp_repl_bound_arguments(arguments))
  }
  fun <- rlang::new_function(
    formals(tool),
    rlang::expr((!!invoke)(base::mget(
      base::as.character(base::names(base::as.list(base::match.call())[-1L])),
      envir = base::environment(),
      inherits = FALSE
    )))
  )
  bounded <- ellmer::tool(
    fun,
    name = tool@name,
    description = mcp_repl_tool_description(tool@description),
    arguments = tool@arguments@properties,
    convert = tool@convert,
    annotations = tool@annotations
  )
  for (name in c("deputy_tool_source", "deputy_mcp_connection_current")) {
    attr(bounded, name) <- attr(tool, name, exact = TRUE)
  }
  bounded
}
