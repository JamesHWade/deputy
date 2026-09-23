# Temporary client adapter for the qualified mcptools releases listed in
# `mcptools_qualified_versions`. The worker isolates its global
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

# The worker function runs with baseenv() as its environment, so the host
# passes the qualified release list instead of the worker reading Deputy.
mcp_worker_start <- function(
  config,
  server,
  working_dir,
  load_tools,
  qualified_versions
) {
  version <- as.character(utils::packageVersion("mcptools"))
  if (!version %in% qualified_versions) {
    cli::cli_abort(
      "The client adapter requires a qualified {.pkg mcptools} release ({.val {qualified_versions}}); found {.val {version}}."
    )
  }
  setwd(working_dir)
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
    # mcp_tools() always calls tools/list in 1.0.2 and 1.0.3, even for resource-only
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

# mcptools 1.0.2/1.0.3 stdio requests poll about 4 seconds, return NULL when
# nothing arrived, and otherwise parse the first output line without checking
# its JSON-RPC id. A late reply would then answer the next request. Every
# request, including tool calls, therefore goes through one exchange that
# requires a response carrying this request's id. Anything else closes the
# server so no later line can be read as another request's answer.
mcp_worker_request <- function(operation, arguments) {
  client <- getOption("deputy.mcp_client")
  upstream <- asNamespace("mcptools")
  entry <- function() upstream$the$mcp_servers[[client$server]]
  lost <- FALSE
  check_alive <- function() {
    transport <- entry()$transport
    if (
      identical(transport$type, "stdio") &&
        !isTRUE(transport$process$is_alive())
    ) {
      cli::cli_abort(
        "The MCP server process exited; its session state is lost.",
        class = "deputy_mcp_server_exit"
      )
    }
  }
  desynchronized <- function(problem) {
    lost <<- TRUE
    client$desynchronized <- TRUE
    options(deputy.mcp_client = client)
    try(upstream$mcp_transport_close(entry()$transport), silent = TRUE)
    cli::cli_abort(
      c(
        problem,
        "x" = "The server was closed; its session state is lost.",
        "i" = "Create a new connection to continue."
      ),
      class = "deputy_mcp_desynchronized"
    )
  }
  exchange <- function(request) {
    response <- upstream$mcp_server_request_cancellable(client$server, request)
    if (is.null(response)) {
      # A server that exited is reported as an exit, not as a slow reply.
      check_alive()
      desynchronized(
        "The MCP server did not respond within the client's response window."
      )
    }
    id <- if (is.list(response)) response$id
    matches <- if (is.character(request$id)) {
      identical(id, request$id)
    } else {
      is.numeric(id) && length(id) == 1L && isTRUE(id == request$id)
    }
    if (!matches) {
      desynchronized(
        "The MCP server's reply did not match the request it was read for."
      )
    }
    response
  }
  if (!identical(operation, "close")) {
    if (isTRUE(client$desynchronized)) {
      cli::cli_abort(
        "The MCP connection lost request/response synchronization; its session state is lost.",
        class = "deputy_mcp_desynchronized"
      )
    }
    check_alive()
  }
  # Check liveness even when mcptools raises a transport error while reading.
  on.exit(
    if (!identical(operation, "close") && !lost) check_alive(),
    add = TRUE
  )
  if (identical(operation, "tool")) {
    tool <- client$tools[[arguments$name]]
    if (is.null(tool)) {
      cli::cli_abort("Unknown MCP tool.")
    }
    values <- arguments$arguments
    if (!all(names(values) %in% names(formals(tool)))) {
      cli::cli_abort("Unknown MCP tool argument.")
    }
    # The converted tool closure would send this same request, but it hides
    # the raw response. Build it with mcptools' constructor, verify the reply
    # and convert it with the converter that closure uses.
    request <- upstream$mcp_request_tool_call(
      id = upstream$jsonrpc_id(client$server),
      tool = arguments$name,
      arguments = values
    )
    return(upstream$mcp_tool_result_as_ellmer(exchange(request)))
  }
  if (identical(operation, "close")) {
    upstream$mcp_transport_close(entry()$transport)
    return(invisible(NULL))
  }
  # One protocol request. Cursor traversal remains explicit in the host;
  # this adapter does not implement a second discovery or pagination engine.
  request <- list(
    jsonrpc = "2.0",
    id = upstream$jsonrpc_id(client$server),
    method = operation,
    params = arguments
  )
  response <- exchange(request)
  if (!is.null(response$error)) {
    upstream$mcp_abort_jsonrpc_error(response$error)
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

mcp_condition_inherits <- function(condition, class) {
  while (inherits(condition, "condition")) {
    if (inherits(condition, class)) {
      return(TRUE)
    }
    condition <- condition$parent
  }
  FALSE
}

mcp_connection_server_exited <- function(condition) {
  mcp_condition_inherits(condition, "deputy_mcp_server_exit")
}

mcp_connection_desynchronized <- function(condition) {
  mcp_condition_inherits(condition, "deputy_mcp_desynchronized")
}

mcp_desynchronized_error <- function(server, parent) {
  rlang::catch_cnd(
    abort_deputy(
      c(
        "MCP server {.val {server}} lost request/response synchronization.",
        "x" = "The connection was closed; its server session state is lost.",
        "i" = "Create a new connection to continue."
      ),
      class = "mcp_desynchronized",
      parent = parent
    ),
    classes = "error"
  )
}

cancel_active_mcp_tools <- function(tools, agent, run_context) {
  owner <- mcp_connection_owner(agent, run_context)
  for (tool in tools) {
    source <- attr(tool, "deputy_runtime_source_tool", exact = TRUE) %||% tool
    if (!identical(attr(source, "deputy_mcp_owner", exact = TRUE), owner)) {
      next
    }
    cancel <- attr(source, "deputy_mcp_cancel_active", exact = TRUE)
    if (is.function(cancel)) cancel()
  }
  invisible(NULL)
}
