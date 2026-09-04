# Compatibility bridge for mcptools 1.0.2 ----------------------------------
# mcptools::mcp_tools() owns connections, schemas and invocation. Its released
# converter discards annotations and origin. Read its existing descriptors;
# never reconnect just to fetch metadata or mutate its namespace.

mcp_metadata_state <- function() {
  version <- as.character(utils::packageVersion("mcptools"))
  if (!identical(version, "1.0.2")) {
    abort_deputy(
      "MCP metadata requires the qualified {.pkg mcptools} 1.0.2 release; found {version}.",
      class = "mcp_metadata"
    )
  }
  state <- get0("the", envir = asNamespace("mcptools"), inherits = FALSE)
  if (!is.environment(state) || !is.list(state$mcp_servers)) {
    abort_deputy(
      "The mcptools metadata contract has changed.",
      class = "mcp_metadata"
    )
  }
  state
}

mcp_ellmer_annotations <- function(annotations, tool_name) {
  if (is.null(annotations)) {
    return(list())
  }
  if (!is.list(annotations)) {
    tool_registration_error(
      "MCP annotations for {.val {tool_name}} must be an object."
    )
  }
  fields <- c(
    readOnlyHint = "read_only_hint",
    destructiveHint = "destructive_hint",
    idempotentHint = "idempotent_hint",
    openWorldHint = "open_world_hint"
  )
  translated <- names(annotations)
  known <- translated %in% names(fields)
  translated[known] <- fields[translated[known]]
  names(annotations) <- translated
  validate_tool_annotations(annotations, tool_name)
  annotations
}

mcp_tool_with_metadata <- function(tool, state, servers) {
  if (!inherits(tool, "ellmer::ToolDef")) {
    abort_deputy(
      "mcptools returned an unsupported tool object.",
      class = "mcp_metadata"
    )
  }
  origin <- environment(tool)
  server_name <- get0("server", envir = origin, inherits = FALSE)
  tool_name <- get0("tool", envir = origin, inherits = FALSE)
  if (!is_nonempty_string(server_name) || !identical(tool_name, tool@name)) {
    abort_deputy(
      "Could not identify the MCP tool's server and name.",
      class = "mcp_metadata"
    )
  }
  if (!server_name %in% servers) {
    return(NULL)
  }
  server <- state$mcp_servers[[server_name]]
  descriptors <- server$tools$tools
  transport <- server$transport
  if (!is.list(descriptors) || !is.environment(transport)) {
    abort_deputy(
      "The MCP server descriptor contract has changed.",
      class = "mcp_metadata"
    )
  }
  matches <- which(vapply(
    descriptors,
    function(descriptor) {
      is.list(descriptor) && identical(descriptor$name, tool_name)
    },
    logical(1)
  ))
  if (length(matches) != 1L) {
    abort_deputy(
      "MCP tool {.val {tool_name}} must have exactly one source descriptor.",
      class = "mcp_metadata"
    )
  }
  annotations <- mcp_ellmer_annotations(
    descriptors[[matches]]$annotations,
    tool_name
  )
  # mcptools resolves calls by server name. A reconnect can change the actual
  # executable behind that name; an old tool must not authorize a new server
  # using stale annotations, even if its name and schema still match.
  invoke <- rlang::new_function(
    alist(arguments = ),
    quote({
      if (!identical(state$mcp_servers[[server_name]]$transport, transport)) {
        abort_deputy(
          "MCP server {.val {server_name}} was reconnected; load and register its tools again.",
          class = "mcp_metadata"
        )
      }
      do.call(original, arguments)
    }),
    rlang::env(
      original = tool,
      state = state,
      server_name = server_name,
      transport = transport
    )
  )
  guarded <- rlang::new_function(
    formals(tool),
    rlang::expr((!!invoke)(base::as.list(
      base::environment(),
      all.names = TRUE
    )))
  )
  result <- ellmer::tool(
    fun = guarded,
    name = tool@name,
    description = tool@description,
    arguments = tool@arguments@properties,
    convert = tool@convert,
    annotations = annotations
  )
  attr(result, "deputy_tool_source") <- list(
    type = "mcp",
    server = server_name,
    tool = tool_name
  )
  result
}

load_mcp_tools_with_metadata <- function(config, servers) {
  config <- config %||%
    getOption(
      ".mcptools_config",
      file.path("~", ".config", "mcptools", "config.json")
    )
  payload <- jsonlite::fromJSON(path.expand(config), simplifyVector = FALSE)
  configured <- payload$mcpServers
  if (
    !is.list(configured) ||
      (length(configured) > 0L &&
        (is.null(names(configured)) || anyDuplicated(names(configured))))
  ) {
    abort_deputy(
      "MCP configuration must contain a named {.field mcpServers} object.",
      class = "mcp_metadata"
    )
  }
  if (length(servers) == 0L) {
    servers <- names(configured)
  }
  if (
    !is.null(servers) &&
      (!is.character(servers) ||
        anyNA(servers) ||
        !all(nzchar(servers)) ||
        !all(servers %in% names(configured)))
  ) {
    abort_deputy(
      "{.arg servers} must name configured MCP servers exactly.",
      class = "mcp_metadata"
    )
  }
  if (length(servers) == 0L) {
    return(list())
  }
  state <- mcp_metadata_state()
  # Filter before connecting: an excluded server must never be started.
  selected_config <- tempfile("deputy-mcp-", fileext = ".json")
  on.exit(unlink(selected_config), add = TRUE)
  file.create(selected_config)
  Sys.chmod(selected_config, "0600")
  jsonlite::write_json(
    list(mcpServers = configured[unique(servers)]),
    selected_config,
    auto_unbox = TRUE,
    null = "null"
  )
  tools <- mcptools::mcp_tools(config = selected_config)
  if (!is.list(tools)) {
    abort_deputy(
      "mcptools returned a non-list tool collection.",
      class = "mcp_metadata"
    )
  }
  tools <- lapply(
    tools,
    mcp_tool_with_metadata,
    state = state,
    servers = servers
  )
  tools <- Filter(Negate(is.null), tools)
  validate_tool_batch(tools)
}
