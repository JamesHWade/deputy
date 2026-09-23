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
#'   Deputy forwards at most 3000 ms as `timeout_ms` (see Details).
#' @param startup_timeout Maximum seconds for client/server startup.
#' @return A [McpConnection]. The host must close it when the conversation ends.
#'
#' @details
#' The producer contract is qualified with mcptools 1.0.2 or 1.0.3 and mcp-repl 0.3.0.
#' The executable must be installed and configured by the host. mcp-repl owns
#' interpreter startup, sandbox enforcement, reset, interrupt, rich content and
#' oversized-output artifacts. The client requires its `repl(input, timeout_ms)`
#' tool contract; it does not infer a binary version from the executable name.
#'
#' Each `repl` call forwards `timeout_ms` capped at 3000 ms, and 3000 ms when
#' it is omitted (mcp-repl would otherwise wait up to 60 s). The qualified
#' mcptools releases wait only about 4 seconds for a stdio reply, and a reply
#' that misses that window would desynchronize the connection. Work that takes
#' longer keeps running in the interpreter: the call returns mcp-repl's busy
#' result, and a later call with empty `input` retrieves the remaining output.
#' The registered tool description tells the model this.
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
