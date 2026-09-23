# Stdio MCP server that emulates MCP Console 0.0.4's `send` tool.
# `mcp-console-tools.json` is the tools/list result of the released 0.0.4
# server (MIT licensed), so the schema and description are the real contract.
# Arguments: a log path, followed by the launch arguments Deputy passes.
# Environment:
#   DEPUTY_CONSOLE_FIXTURE_BOUNDARY  default, workspace, unsandboxed or proxy
#   DEPUTY_CONSOLE_FIXTURE_BARE      "1" omits `requirements` (bare runtime)
#   DEPUTY_CONSOLE_FIXTURE_RESTART   seconds a restart takes
`%||%` <- function(x, y) if (is.null(x)) y else x
input <- file("stdin", open = "r")
args <- commandArgs(trailingOnly = TRUE)
log <- args[[1L]]
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
record <- function(...) {
  cat(paste0(..., collapse = ""), "\n", sep = "", file = log, append = TRUE)
}
record(
  "start pid=",
  Sys.getpid(),
  " wd=",
  getwd(),
  " args=",
  paste(args[-1L], collapse = " ")
)
send <- function(message) {
  cat(
    jsonlite::toJSON(message, auto_unbox = TRUE, null = "null", digits = NA),
    "\n",
    sep = ""
  )
  flush(stdout())
}
object <- structure(list(), names = character())
tools <- jsonlite::fromJSON(
  file.path(dirname(script), "mcp-console-tools.json"),
  simplifyVector = FALSE
)$tools
boundary <- Sys.getenv("DEPUTY_CONSOLE_FIXTURE_BOUNDARY", "default")
security <- switch(
  boundary,
  default = NULL,
  workspace = paste(
    "Evaluated code uses the native \":workspace\" profile: it can edit files",
    "beneath the fixed launch workspace, write in the worker's private",
    "temporary directory and to explicitly allowed paths, and cannot directly",
    "access the network. The workspace's .git, .agents, .codex, and .claude",
    "paths are readable and protected from writes by default."
  ),
  unsandboxed = paste(
    "Evaluated code runs without a sandbox, with the server's permissions,",
    "including filesystem and network access."
  ),
  proxy = paste(
    "Evaluated code can read host files, can access the network subject to",
    "the launcher's proxy settings, and can write in the worker's private",
    "temporary directory and to paths explicitly allowed by the launcher."
  )
)
if (!is.null(security)) {
  parts <- strsplit(tools[[1L]]$description, "\n\n", fixed = TRUE)[[1L]]
  parts[[length(parts)]] <- security
  tools[[1L]]$description <- paste(parts, collapse = "\n\n")
}
if (identical(Sys.getenv("DEPUTY_CONSOLE_FIXTURE_BARE"), "1")) {
  tools[[1L]]$inputSchema$properties$requirements <- NULL
}
restart_seconds <- as.numeric(Sys.getenv("DEPUTY_CONSOLE_FIXTURE_RESTART", "0"))
png <- paste0(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAC",
  "hwGA60e6kgAAAABJRU5ErkJggg=="
)

globals <- new.env(parent = globalenv())
started <- FALSE
job <- NULL
text <- function(value, error = FALSE) {
  result <- list(content = list(list(type = "text", text = value)))
  if (error) {
    result$isError <- TRUE
  }
  result
}
observe <- function(timeout) {
  remaining <- as.numeric(difftime(job$end, Sys.time(), units = "secs"))
  Sys.sleep(max(0, min(remaining, timeout)))
  if (Sys.time() >= job$end) {
    output <- job$output
    job <<- NULL
    text(paste0(output, "\n[done]"))
  } else {
    text("[running; poll with an empty send]")
  }
}
evaluate <- function(code) {
  started <<- TRUE
  if (grepl("^work [0-9.]+$", code)) {
    job <<- list(
      end = Sys.time() + as.numeric(sub("^work ", "", code)),
      output = "work finished"
    )
    return(NULL)
  }
  if (identical(code, "plot")) {
    return(list(
      content = list(
        list(type = "text", text = "plotted"),
        list(type = "image", data = png, mimeType = "image/png")
      )
    ))
  }
  output <- tryCatch(
    {
      value <- withVisible(eval(parse(text = code), globals))
      if (value$visible) utils::capture.output(print(value$value)) else ""
    },
    error = function(error) paste("Error:", conditionMessage(error))
  )
  text(paste(output, collapse = "\n"))
}
call_send <- function(arguments) {
  cells <- arguments[intersect(c("r", "python", "sql"), names(arguments))]
  cells <- cells[!vapply(cells, is.null, logical(1))]
  if (length(cells) > 1L) {
    return(text("only one of `r`, `python`, or `sql` may be supplied", TRUE))
  }
  timeout <- (arguments$timeout_ms %||% 60000) / 1000
  control <- arguments$control
  if (identical(control, "interrupt")) {
    if (!started) {
      return(text("[worker is not running]", TRUE))
    }
    job <<- NULL
    return(text("^C\n[idle]"))
  }
  if (identical(control, "restart")) {
    Sys.sleep(restart_seconds)
    rm(list = ls(globals, all.names = TRUE), envir = globals)
    job <<- NULL
    started <<- TRUE
    return(text(
      "[worker stopped: in-memory state lost]\n[starting new worker]\n[idle]"
    ))
  }
  if (!is.null(job)) {
    if (length(cells)) {
      return(text("[cell not run: an evaluation is active]", TRUE))
    }
    return(observe(timeout))
  }
  if (!length(cells)) {
    return(text(
      if (is.null(arguments$requirements)) "[idle]" else "[prepared]"
    ))
  }
  if (!is.null(cells$r)) {
    result <- evaluate(cells$r)
    return(result %||% observe(timeout))
  }
  started <<- TRUE
  text(paste(names(cells), cells[[1L]]))
}

repeat {
  line <- readLines(input, 1L, warn = FALSE)
  if (!length(line)) {
    record("stdin closed")
    break
  }
  request <- jsonlite::fromJSON(line, simplifyVector = FALSE)
  if (is.null(request$id)) {
    next
  }
  arguments <- request$params$arguments
  if (identical(request$method, "tools/call")) {
    record(
      "call ",
      request$params$name,
      " ",
      jsonlite::toJSON(arguments, auto_unbox = TRUE, null = "null")
    )
  }
  result <- switch(
    request$method,
    initialize = list(
      protocolVersion = request$params$protocolVersion,
      capabilities = list(tools = object),
      serverInfo = list(name = "mcp-console", version = "0.0.4")
    ),
    `tools/list` = list(tools = tools),
    `tools/call` = call_send(arguments),
    object
  )
  send(list(jsonrpc = "2.0", id = request$id, result = result))
}
