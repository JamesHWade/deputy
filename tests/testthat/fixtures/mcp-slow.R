# Stdio MCP producer whose replies can outlast the mcptools response window.
# Arguments: a log path, followed by any arguments a wrapper passes through.
input <- file("stdin", open = "r")
args <- commandArgs(trailingOnly = TRUE)
log <- args[[1L]]
object <- structure(list(), names = character())
record <- function(...) {
  cat(paste0(..., collapse = ""), "\n", sep = "", file = log, append = TRUE)
}
send <- function(message) {
  cat(
    jsonlite::toJSON(message, auto_unbox = TRUE, null = "null"),
    "\n",
    sep = ""
  )
  flush(stdout())
}
schema <- function(properties, required) {
  list(
    type = "object",
    properties = properties,
    required = as.list(required)
  )
}
tools <- list(
  list(
    name = "wait",
    description = "Wait before replying.",
    inputSchema = schema(list(seconds = list(type = "number")), "seconds")
  ),
  list(
    name = "stale",
    description = "Reply with another request's id.",
    inputSchema = schema(object, character())
  ),
  list(
    name = "empty",
    description = "Return a result with no content.",
    inputSchema = schema(object, character())
  )
)
text <- function(value) list(content = list(list(type = "text", text = value)))
repeat {
  line <- readLines(input, 1L, warn = FALSE)
  if (!length(line)) {
    break
  }
  request <- jsonlite::fromJSON(line, simplifyVector = FALSE)
  if (is.null(request$id)) {
    next
  }
  id <- request$id
  arguments <- request$params$arguments
  if (identical(request$method, "tools/call")) {
    record(
      "call ",
      request$params$name,
      " id=",
      id,
      " timeout_ms=",
      if (is.null(arguments$timeout_ms)) "absent" else arguments$timeout_ms
    )
  }
  result <- switch(
    request$method,
    initialize = list(
      protocolVersion = request$params$protocolVersion,
      capabilities = list(tools = object),
      serverInfo = list(name = "deputy-slow", version = "1")
    ),
    `tools/list` = list(tools = tools),
    `tools/call` = switch(
      request$params$name,
      wait = {
        Sys.sleep(arguments$seconds)
        text(paste0("waited ", arguments$seconds, " for id ", id))
      },
      stale = {
        id <- id + 100L
        text("an answer to another request")
      },
      empty = list(content = list())
    ),
    object
  )
  send(list(jsonrpc = "2.0", id = id, result = result))
}
