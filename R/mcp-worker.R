# Temporary mcptools 1.0.2 client adapter. The worker isolates its global
# connection registry; mcptools still owns transport, authentication, IDs,
# conversion and shutdown. No interpreter runs in this R worker.

mcp_worker_function <- function(fun) {
  environment(fun) <- baseenv()
  fun
}

# callr can deliver conditions and progress before the terminal result.
# Keep the operation pending until its completion or worker termination event.
mcp_worker_read_result <- function(worker) {
  response <- worker$read()
  if (is.null(response)) {
    return(NULL)
  }
  if (response$code == 301L) {
    rlang::cnd_signal(response$message)
    return(NULL)
  }
  if (response$code == 200L || response$code >= 500L && response$code < 600L) {
    return(response)
  }
  NULL
}

mcp_worker_start <- function(config, server, working_dir, load_tools) {
  setwd(working_dir)
  if (!identical(as.character(utils::packageVersion("mcptools")), "1.0.2")) {
    cli::cli_abort("The client adapter requires qualified mcptools 1.0.2.")
  }
  path <- tempfile(fileext = ".json")
  on.exit(unlink(path))
  file.create(path)
  Sys.chmod(path, "0600")
  jsonlite::write_json(
    list(mcpServers = stats::setNames(list(config), server)),
    path,
    auto_unbox = TRUE,
    null = "null"
  )
  state <- utils::getFromNamespace("the", "mcptools")
  if (load_tools) {
    tools <- mcptools::mcp_tools(config = path)
  } else {
    # mcp_tools() always calls tools/list in 1.0.2, even for resource-only
    # servers. Compose its transport/handshake helpers without that discovery.
    upstream <- asNamespace("mcptools")
    selected <- upstream$read_mcp_config(path)[[server]]
    transport <- upstream$mcp_transport(selected)
    initialized <- upstream$mcp_transport_request(
      transport,
      upstream$mcp_request_initialize(id = 1L)
    )
    upstream$mcp_transport_store_initialize(transport, initialized)
    upstream$mcp_transport_notify(transport, upstream$mcp_request_initialized())
    state$mcp_servers[[server]] <- list(
      name = server,
      type = transport$type,
      transport = transport,
      process = transport$process,
      tools = list(tools = list()),
      ignore_tools = character(),
      id = 2L
    )
    tools <- list()
  }
  if (is.null(tools)) {
    tools <- list()
  }
  names(tools) <- vapply(tools, function(tool) tool@name, character(1))
  entry <- state$mcp_servers[[server]]
  if (!is.environment(entry$transport) || !is.list(entry$tools$tools)) {
    cli::cli_abort("The mcptools connection descriptor contract has changed.")
  }
  descriptors <- entry$tools$tools
  names(descriptors) <- vapply(descriptors, `[[`, character(1), "name")
  if (anyDuplicated(names(descriptors))) {
    cli::cli_abort("The server returned duplicate tool descriptors.")
  }
  options(deputy.mcp_client = list(server = server, tools = tools))
  list(
    tools = lapply(tools, function(tool) {
      list(
        name = tool@name,
        description = tool@description,
        arguments = tool@arguments@properties,
        convert = tool@convert,
        formals = formals(tool),
        annotations = descriptors[[tool@name]]$annotations
      )
    }),
    protocol = entry$transport$protocol_version
  )
}

mcp_worker_request <- function(operation, arguments) {
  client <- getOption("deputy.mcp_client")
  check_alive <- function() {
    entry <- utils::getFromNamespace("the", "mcptools")$mcp_servers[[
      client$server
    ]]
    if (
      identical(entry$transport$type, "stdio") &&
        !isTRUE(entry$transport$process$is_alive())
    ) {
      cli::cli_abort(
        "The MCP server process exited; its session state is lost.",
        class = "deputy_mcp_server_exit"
      )
    }
  }
  if (!identical(operation, "close")) {
    check_alive()
  }
  # Check liveness even when mcptools raises a transport error while reading.
  on.exit(if (!identical(operation, "close")) check_alive(), add = TRUE)
  if (identical(operation, "tool")) {
    tool <- client$tools[[arguments$name]]
    if (is.null(tool)) {
      cli::cli_abort("Unknown MCP tool.")
    }
    return(do.call(tool, arguments$arguments))
  }
  if (identical(operation, "close")) {
    entry <- utils::getFromNamespace("the", "mcptools")$mcp_servers[[
      client$server
    ]]
    utils::getFromNamespace("mcp_transport_close", "mcptools")(entry$transport)
    return(invisible(NULL))
  }
  # One protocol request. Cursor traversal remains explicit in the host;
  # this adapter does not implement a second discovery or pagination engine.
  request <- list(
    jsonrpc = "2.0",
    id = utils::getFromNamespace("jsonrpc_id", "mcptools")(client$server),
    method = operation,
    params = arguments
  )
  response <- utils::getFromNamespace(
    "mcp_server_request_cancellable",
    "mcptools"
  )(
    client$server,
    request
  )
  if (!is.null(response$error)) {
    utils::getFromNamespace("mcp_abort_jsonrpc_error", "mcptools")(
      response$error
    )
  }
  if (!is.list(response$result)) {
    cli::cli_abort("MCP returned no result object.")
  }
  response$result
}

mcp_connection_config <- function(config, server) {
  if (!is_nonempty_string(server) || !is_nonempty_string(config)) {
    abort_deputy(
      "{.arg config} and {.arg server} must be non-empty strings.",
      class = "mcp_connection"
    )
  }
  payload <- jsonlite::fromJSON(path.expand(config), simplifyVector = FALSE)
  entries <- payload$mcpServers
  if (
    !is.list(entries) ||
      is.null(names(entries)) ||
      anyDuplicated(names(entries)) ||
      !server %in% names(entries) ||
      !is.list(entries[[server]])
  ) {
    abort_deputy(
      "Select one exact, uniquely named MCP server configuration.",
      class = "mcp_connection"
    )
  }
  entries[[server]]
}

mcp_connection_allowlist <- function(value, argument) {
  if (
    !is.character(value) ||
      anyNA(value) ||
      !all(nzchar(value)) ||
      anyDuplicated(value)
  ) {
    abort_deputy(
      "{.arg {argument}} must contain unique, non-empty strings.",
      class = "mcp_connection"
    )
  }
  value
}

mcp_connection_owner <- function(agent, run_context = agent$run_context) {
  if (!inherits(agent, "Agent")) {
    abort_deputy("{.arg agent} must be an Agent.", class = "mcp_connection")
  }
  list(
    agent_id = agent$agent_id,
    session_id = agent$session_id(),
    run_context = run_context
  )
}

validate_mcp_tool_owner <- function(
  tool,
  agent,
  run_context = agent$run_context
) {
  source <- attr(tool, "deputy_runtime_source_tool", exact = TRUE) %||% tool
  owner <- attr(source, "deputy_mcp_owner", exact = TRUE)
  if (
    !is.null(owner) &&
      !identical(owner, mcp_connection_owner(agent, run_context))
  ) {
    tool_registration_error(
      "The MCP connection belongs to a different Agent, session or run context."
    )
  }
  invisible(NULL)
}

mcp_connection_server_exited <- function(condition) {
  while (inherits(condition, "condition")) {
    if (inherits(condition, "deputy_mcp_server_exit")) {
      return(TRUE)
    }
    condition <- condition$parent
  }
  FALSE
}

cancel_active_mcp_tools <- function(tools) {
  for (tool in tools) {
    source <- attr(tool, "deputy_runtime_source_tool", exact = TRUE) %||% tool
    cancel <- attr(source, "deputy_mcp_cancel_active", exact = TRUE)
    if (is.function(cancel)) cancel()
  }
  invisible(NULL)
}
