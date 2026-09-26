#' Connect an agent to a sandboxed MCP Console session
#'
#' @description
#' Starts an [MCP Console](https://github.com/t-kalinowski/mcp-console) server
#' for one agent and connects to it. MCP Console runs R, Python and DuckDB SQL
#' in an OS sandbox and keeps their state for the conversation. Each connection
#' starts its own server. Register `connection$tools()` on the agent so that
#' the `send` tool goes through its permissions, hooks and limits.
#'
#' @param agent The agent that owns the connection. Its working directory
#'   becomes the Console workspace, where the server starts, the sandbox's
#'   workspace is rooted, and MCP Console reads its project configuration and
#'   writes recordings.
#' @param command Path to an `mcp-console` executable, version 0.0.4. Defaults
#'   to the `DEPUTY_MCP_CONSOLE_BIN` environment variable. Deputy doesn't
#'   install the executable or search for it.
#' @param args Extra arguments for `mcp-console serve`. Only
#'   `--writable-root PATH` and the overrides `-c extends=:workspace`,
#'   `-c extends=:read-only` and `-c sandbox.network=restricted` are accepted.
#'   Anything else, including `--no-sandbox`, is an error.
#' @param env Optional named character vector of environment variables for the
#'   server. The server inherits only a few variables (such as `HOME`, `PATH`
#'   and the `R_LIBS` family), so set others here, for example `UV_CACHE_DIR`
#'   or `XDG_CACHE_HOME`. Without them, dependency installs write to caches
#'   under `HOME`.
#' @param dependencies `"deny"` (the default) or `"allow"`. MCP Console can
#'   install packages that code needs, and it does so outside its sandbox,
#'   with the server's permissions. With `"deny"`, the connection errors if the
#'   server offers this, and calls that declare `requirements` are refused.
#'   See Details.
#' @param project_config Set to `TRUE` to start even though the workspace
#'   contains `.agents/console/config.yaml`. That file can widen the sandbox,
#'   so by default the connection refuses to start when it exists. Review the
#'   file before you opt in.
#' @param timeout Maximum seconds for one MCP request.
#' @param startup_timeout Maximum seconds for the client and server to start.
#' @return A [McpConnection]. Call its `$close()` method when the conversation
#'   ends.
#'
#' @details
#' ## Supported versions
#'
#' Requires MCP Console 0.0.4 and mcptools 1.0.2 or 1.0.3. The connection
#' checks the version with `command --version` before starting the server.
#' After starting, it checks the arguments of `send` and the sandbox
#' description MCP Console adds to it, and closes the connection unless the
#' server uses its native sandbox with restricted networking (the default
#' policy, or the `:workspace` or `:read-only` profile).
#'
#' ## Permissions
#'
#' `send` runs code, so it is treated like a shell tool: in `"standard"` mode
#' the agent's permissions need `bash = TRUE`. The server declares no tool
#' annotations, so the cautious defaults also require `web = TRUE`.
#' `"readonly"` and `"plan"` modes always deny `send`. A call that declares
#' `requirements` also needs `install_packages = TRUE` and a connection created
#' with `dependencies = "allow"`.
#'
#' With `dependencies = "allow"`, the server can also install packages on its
#' own, outside the sandbox, when code calls `library()` for a missing package
#' or imports a missing Python module. These installs can't be checked call by
#' call. MCP Console offers dependency installs when `ir`, `uv` or a recent
#' reticulate is available to it. The server's environment decides where they
#' are written.
#'
#' ## Long-running calls
#'
#' mcptools waits about 4 seconds for a reply, so each `send` waits at most
#' 2.5 seconds: `timeout_ms` is capped at 2500, also when omitted. Longer work
#' keeps running: the call returns `[running; poll with an empty send]`, and a
#' later `send` with no code collects the output. The tool description tells
#' the model this. Installs requested with `requirements`, restarts, and input
#' sent to a stopped worker have no time limit in MCP Console. If one takes
#' longer than the reply window, the connection closes with a
#' `deputy_mcp_desynchronized` error and the session is lost. That is why only
#' you can restart the session, with [mcp_console_control()]; the model's
#' `send` refuses it.
#'
#' ## Closing and recordings
#'
#' `$close()` asks MCP Console to shut down cleanly, then stops the process.
#' `$cancel()`, interrupting the agent during a call, and a lost reply stop the
#' server without asking; MCP Console's sandbox runner then stops its worker.
#' Processes that escape the runner are outside Deputy's control.
#'
#' MCP Console records every call, result and plot, without redaction, under
#' `.agents/console/sessions/<run-id>/` in the workspace. Version 0.0.4 can't
#' change that location or how long recordings are kept. The path is reported
#' in `$status()$execution$recordings`; deleting old recordings is up to you.
#'
#' @export
#' @examples
#' \dontrun{
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-6-luna"),
#'   permissions = Permissions(bash = TRUE, web = TRUE)
#' )
#' console <- mcp_console_connection(agent, command = "/path/to/mcp-console")
#' agent$register_tools(console$tools())
#' # In a Shiny app: session$onSessionEnded(function() console$close())
#' console$close()
#' }
mcp_console_connection <- function(
  agent,
  command = Sys.getenv("DEPUTY_MCP_CONSOLE_BIN"),
  args = character(),
  env = NULL,
  dependencies = c("deny", "allow"),
  project_config = FALSE,
  timeout = 60,
  startup_timeout = 60
) {
  dependencies <- match.arg(dependencies)
  if (!rlang::is_bool(project_config)) {
    abort_deputy(
      "{.arg project_config} must be TRUE or FALSE.",
      class = "mcp_console"
    )
  }
  mcp_connection_owner(agent)
  command <- mcp_console_executable(command)
  args <- validate_mcp_console_args(args)
  env <- validate_mcp_console_env(env)
  workspace <- agent$working_dir
  project <- file.path(workspace, ".agents", "console", "config.yaml")
  if (file.exists(project) && !project_config) {
    abort_deputy(
      c(
        "Refusing to launch MCP Console with a project configuration file.",
        "x" = "{.path {project}} is trusted launcher input and can widen the sandbox.",
        "i" = "Review it and pass {.code project_config = TRUE}, or remove it."
      ),
      class = "mcp_console"
    )
  }
  version <- mcp_console_version(command, env)

  server <- list(command = command, args = c("serve", args))
  if (length(env)) {
    server$env <- as.list(env)
  }
  path <- tempfile(fileext = ".json")
  on.exit(unlink(path), add = TRUE)
  file.create(path)
  Sys.chmod(path, "0600")
  jsonlite::write_json(
    list(mcpServers = list(console = server)),
    path,
    auto_unbox = TRUE,
    null = "null"
  )
  connection <- McpConnection$new(
    path,
    "console",
    agent,
    tools = "send",
    timeout = timeout,
    startup_timeout = startup_timeout
  )
  ok <- FALSE
  on.exit(if (!ok) connection$close(), add = TRUE)
  tool <- connection$tools()$send
  fields <- names(tool@arguments@properties)
  if (
    !all(fields %in% mcp_console_fields) ||
      !all(c("r", "control", "stdin", "timeout_ms") %in% fields)
  ) {
    abort_deputy(
      "The MCP Console {.fn send} contract has changed; this server is not qualified.",
      class = "mcp_console"
    )
  }
  sandbox <- mcp_console_sandbox_profile(tool@description)
  offers_dependencies <- "requirements" %in% fields
  if (offers_dependencies && identical(dependencies, "deny")) {
    abort_deputy(
      c(
        "This MCP Console server prepares dependencies outside its sandbox.",
        "i" = "It installs packages for {.field requirements} and when code loads a missing package.",
        "i" = "Pass {.code dependencies = \"allow\"} to accept this, or launch a bare runtime."
      ),
      class = "mcp_console"
    )
  }
  state <- new.env(parent = emptyenv())
  state$host_control <- FALSE
  attr(connection, "deputy_mcp_adapter") <- list(
    tool = "send",
    execution = list(
      backend = "mcp-console",
      version = version,
      sandbox = sandbox,
      dependencies = if (offers_dependencies) dependencies else "unavailable",
      workspace = workspace,
      recordings = file.path(workspace, ".agents", "console", "sessions")
    ),
    arguments = function(arguments) {
      mcp_console_bound_arguments(arguments, dependencies, state$host_control)
    },
    description = mcp_console_tool_description,
    close_grace = mcp_console_close_grace,
    state = state
  )
  ok <- TRUE
  connection
}

#' Interrupt or restart an MCP Console session
#'
#' `"interrupt"` sends SIGINT to the running code or dependency install and
#' keeps the session's state. The code may not stop, so check the returned
#' output: it can still end in `[running; poll with an empty send]`.
#' `"restart"` replaces the worker and discards all R, Python and DuckDB state.
#'
#' If a restart takes longer than about 4 seconds, the connection closes with a
#' `deputy_mcp_console_restart` error and the server stops. Create a new
#' connection to continue.
#'
#' @param connection A connection created by [mcp_console_connection()].
#' @param action `"interrupt"` or `"restart"`.
#' @return A promise for MCP Console's reply. The call goes straight to the
#'   server, not through the agent, and errors if the connection is already
#'   handling a request.
#' @export
mcp_console_control <- function(
  connection,
  action = c("interrupt", "restart")
) {
  action <- match.arg(action)
  adapter <- if (inherits(connection, "McpConnection")) {
    attr(connection, "deputy_mcp_adapter", exact = TRUE)
  }
  if (!identical(adapter$execution$backend, "mcp-console")) {
    abort_deputy(
      "Use a connection created by {.fn mcp_console_connection}.",
      class = "mcp_console"
    )
  }
  send <- connection$tools()$send
  if (identical(action, "interrupt")) {
    return(send(control = "interrupt"))
  }
  adapter$state$host_control <- TRUE
  on.exit(assign("host_control", FALSE, envir = adapter$state), add = TRUE)
  promises::catch(send(control = "restart"), function(error) {
    if (mcp_connection_desynchronized(error)) {
      abort_deputy(
        c(
          "MCP Console restart did not finish within the client's response window.",
          "x" = "The connection was closed; the server and its worker were stopped.",
          "i" = "Create a new connection to continue."
        ),
        class = c("mcp_console_restart", "mcp_console"),
        parent = error
      )
    }
    rlang::cnd_signal(error)
  })
}

mcp_console_qualified_versions <- "0.0.4"

mcp_console_fields <- c(
  "r",
  "python",
  "sql",
  "control",
  "requirements",
  "stdin",
  "timeout_ms"
)

# mcptools 1.0.2/1.0.3 stdio requests stop reading after about 4 seconds.
# MCP Console's wait starts after admission, and an interrupt adds a
# 100 ms grace, so this bound leaves headroom for assembly and transport.
mcp_console_timeout_ms_max <- 2500L

# Seconds to wait after closing the server's input before stopping it.
mcp_console_close_grace <- 2

mcp_console_executable <- function(command) {
  if (!is_nonempty_string(command)) {
    abort_deputy(
      c(
        "An explicit MCP Console executable is required.",
        "i" = "Pass {.arg command} or set {.envvar DEPUTY_MCP_CONSOLE_BIN}."
      ),
      class = "mcp_console"
    )
  }
  path <- path.expand(command)
  if (!file.exists(path) || dir.exists(path) || file.access(path, 1L) != 0L) {
    abort_deputy(
      "{.path {command}} is not an executable file.",
      class = "mcp_console"
    )
  }
  normalizePath(path, mustWork = TRUE)
}

mcp_console_version <- function(command, env) {
  result <- tryCatch(
    processx::run(
      command,
      "--version",
      env = c("current", env),
      timeout = 10,
      error_on_status = FALSE
    ),
    error = function(error) NULL
  )
  output <- if (!is.null(result) && identical(result$status, 0L)) {
    trimws(result$stdout)
  } else {
    ""
  }
  version <- if (grepl("^mcp-console [0-9][0-9A-Za-z.+-]*$", output)) {
    sub("^mcp-console ", "", output)
  } else {
    NA_character_
  }
  if (is.na(version) || !version %in% mcp_console_qualified_versions) {
    abort_deputy(
      c(
        "MCP Console {.val {mcp_console_qualified_versions}} is required.",
        "x" = if (is.na(version)) {
          "{.path {command}} did not report an MCP Console version."
        } else {
          "{.path {command}} reports version {.val {version}}."
        }
      ),
      class = "mcp_console"
    )
  }
  version
}

validate_mcp_console_env <- function(env) {
  if (is.null(env) || length(env) == 0L) {
    return(character())
  }
  env <- unlist(env)
  if (
    !is.character(env) ||
      anyNA(env) ||
      is.null(names(env)) ||
      !all(grepl("^[A-Za-z_][A-Za-z0-9_]*$", names(env))) ||
      anyDuplicated(names(env))
  ) {
    abort_deputy(
      "{.arg env} must be a named character vector of environment variables.",
      class = "mcp_console"
    )
  }
  env
}

# Deputy builds `serve` itself and admits only arguments that keep the native
# sandbox with restricted networking. Everything else fails closed.
validate_mcp_console_args <- function(args) {
  if (is.null(args) || length(args) == 0L) {
    return(character())
  }
  if (!is.character(args) || anyNA(args)) {
    abort_deputy(
      "{.arg args} must be a character vector.",
      class = "mcp_console"
    )
  }
  refuse <- function(message, ...) {
    abort_deputy(
      c(message, ...),
      class = "mcp_console",
      .envir = parent.frame()
    )
  }
  index <- 1L
  while (index <= length(args)) {
    argument <- args[[index]]
    value <- NULL
    if (argument %in% c("-c", "--config", "--writable-root")) {
      if (index == length(args)) {
        refuse("MCP Console {.code {argument}} requires a value.")
      }
      value <- args[[index + 1L]]
      index <- index + 1L
    } else if (grepl("^(--config|--writable-root)=", argument)) {
      value <- sub("^[^=]+=", "", argument)
      argument <- sub("=.*$", "", argument)
    } else if (grepl("^-c.", argument)) {
      value <- substring(argument, 3L)
      argument <- "-c"
    }
    if (startsWith(argument, "--no-sandbox")) {
      refuse(
        "Deputy never launches MCP Console with {.code --no-sandbox}.",
        "i" = "The adapter has no unsandboxed mode."
      )
    }
    if (identical(argument, "--writable-root")) {
      if (!nzchar(value)) {
        refuse("MCP Console {.code --writable-root} requires a path.")
      }
    } else if (argument %in% c("-c", "--config")) {
      validate_mcp_console_override(value, refuse)
    } else {
      refuse(
        "Unsupported MCP Console launch argument {.val {argument}}.",
        "i" = "Deputy admits {.code --writable-root} and sandbox-preserving {.code -c} overrides."
      )
    }
    index <- index + 1L
  }
  args
}

validate_mcp_console_override <- function(override, refuse) {
  if (!grepl("=", override, fixed = TRUE)) {
    refuse("MCP Console overrides must be {.code KEY=VALUE}.")
  }
  key <- trimws(sub("=.*$", "", override))
  value <- trimws(sub("^[^=]*=", "", override))
  value <- gsub("^[\"']|[\"']$", "", value)
  if (identical(key, "extends") && value %in% c(":workspace", ":read-only")) {
    return(invisible(TRUE))
  }
  if (identical(key, "sandbox.network") && identical(value, "restricted")) {
    return(invisible(TRUE))
  }
  if (grepl("proxy", override, fixed = TRUE)) {
    refuse(
      "MCP Console proxy overrides are refused.",
      "i" = "A proxy changes the sandbox's network boundary."
    )
  }
  if (
    key %in%
      c("sandbox", "sandbox.filesystem") ||
      startsWith(key, "sandbox.filesystem.")
  ) {
    refuse(
      "MCP Console filesystem overrides are refused.",
      "i" = "They can select unrestricted or external-sandbox enforcement."
    )
  }
  if (identical(key, "target") || startsWith(key, "target.")) {
    refuse(
      "MCP Console execution targets are refused.",
      "i" = "Remote and container targets have different sandbox and cleanup contracts."
    )
  }
  refuse(
    "Unsupported MCP Console override {.val {key}}.",
    "i" = "Deputy admits {.code extends=:workspace}, {.code extends=:read-only} and {.code sandbox.network=restricted}."
  )
}

# MCP Console 0.0.4 appends a security sentence derived from its effective
# policy to the `send` description. Accept only native restricted enforcement
# with restricted networking; anything else, including unknown prose, fails.
mcp_console_sandbox_profile <- function(description) {
  text <- gsub("\\s+", " ", paste(description %||% "", collapse = " "))
  boundaries <- c(
    default = paste(
      "Evaluated code can read host files, cannot directly access the",
      "network, and can write in the worker's private temporary directory",
      "and to paths explicitly allowed by the launcher."
    ),
    workspace = paste(
      "Evaluated code uses the native \":workspace\" profile: it can edit",
      "files beneath the fixed launch workspace, write in the worker's",
      "private temporary directory and to explicitly allowed paths, and",
      "cannot directly access the network."
    ),
    `read-only` = paste(
      "Evaluated code uses the native \":read-only\" profile: it can read",
      "host files subject to configured read restrictions, write in the",
      "worker's private temporary directory and to explicitly allowed",
      "paths, and cannot directly access the network."
    )
  )
  widened <- c(
    "without a sandbox",
    "without an inner native sandbox",
    "unrestricted filesystem access",
    "governed by the launcher's sandbox settings",
    "can directly access the network",
    "proxy settings",
    "Execution target:",
    "Docker"
  )
  found <- vapply(boundaries, grepl, logical(1), x = text, fixed = TRUE)
  if (
    sum(found) != 1L ||
      any(vapply(widened, grepl, logical(1), x = text, fixed = TRUE))
  ) {
    abort_deputy(
      c(
        "MCP Console did not report an active native sandbox with restricted networking.",
        "i" = "Deputy closed the connection instead of running code outside that boundary."
      ),
      class = "mcp_console"
    )
  }
  names(boundaries)[found]
}

mcp_console_has_requirements <- function(arguments) {
  is.list(arguments) && !is.null(arguments$requirements)
}

mcp_console_bound_arguments <- function(arguments, dependencies, host_control) {
  if (identical(arguments$control, "restart") && !isTRUE(host_control)) {
    abort_deputy(
      c(
        "MCP Console restart is a host control.",
        "i" = "Its worker replacement has no deadline and could outlast the client's response window.",
        "i" = "Ask the host to restart the session."
      ),
      class = "mcp_console"
    )
  }
  if (
    mcp_console_has_requirements(arguments) && !identical(dependencies, "allow")
  ) {
    abort_permission_denied(
      c(
        "MCP Console dependency preparation is not enabled for this connection.",
        "i" = "Preparation runs outside the sandbox with the server's permissions."
      ),
      tool_name = "send"
    )
  }
  value <- arguments$timeout_ms
  if (is.null(value)) {
    arguments$timeout_ms <- mcp_console_timeout_ms_max
  } else if (is.numeric(value) && length(value) == 1L && !is.na(value)) {
    # Invalid values pass through so MCP Console reports its own error.
    arguments$timeout_ms <- min(value, mcp_console_timeout_ms_max)
  }
  arguments
}

mcp_console_tool_description <- function(description) {
  paste0(
    description %||% "",
    "\n\nDeputy caps `timeout_ms` at ",
    mcp_console_timeout_ms_max,
    " ms per call (also when omitted). Longer work keeps running: poll with ",
    "an empty `send` as described above. Restart is reserved for the host, ",
    "and `requirements` need the host's dependency permission."
  )
}
