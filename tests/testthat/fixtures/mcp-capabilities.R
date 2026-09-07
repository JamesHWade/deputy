# Stateful MCP producer, exercised through the released mcptools client.
input <- file("stdin", open = "r")
log <- commandArgs(trailingOnly = TRUE)[[1L]]
value <- "empty"
object <- structure(list(), names = character())
repeat {
  line <- readLines(input, 1L, warn = FALSE)
  if (!length(line)) {
    break
  }
  request <- jsonlite::fromJSON(line, simplifyVector = FALSE)
  cat(request$method, "\n", file = log, append = TRUE)
  if (is.null(request$id)) {
    next
  }
  error <- NULL
  result <- switch(
    request$method,
    initialize = list(
      protocolVersion = request$params$protocolVersion,
      capabilities = list(tools = object, resources = object, prompts = object),
      serverInfo = list(name = "deputy-capabilities", version = "1")
    ),
    `tools/list` = list(
      tools = list(list(
        name = "state",
        description = "Inspect or change fixture state.",
        inputSchema = list(
          type = "object",
          properties = list(
            operation = list(type = "string"),
            value = list(type = "string")
          ),
          required = list("operation")
        ),
        annotations = list(
          readOnlyHint = FALSE,
          destructiveHint = FALSE,
          openWorldHint = FALSE
        )
      ))
    ),
    `tools/call` = {
      arguments <- request$params$arguments
      if (identical(arguments$operation, "set")) {
        value <- arguments$value
      }
      if (identical(arguments$operation, "slow")) {
        Sys.sleep(2)
      }
      if (identical(arguments$operation, "crash")) {
        quit(save = "no", status = 7)
      }
      list(content = list(list(type = "text", text = value)))
    },
    `resources/list` = if (is.null(request$params$cursor)) {
      list(
        resources = list(list(uri = "fixture://allowed", name = "Allowed")),
        nextCursor = "page-2"
      )
    } else {
      list(resources = list(list(uri = "fixture://denied", name = "Denied")))
    },
    `resources/read` = list(
      contents = list(list(
        uri = request$params$uri,
        mimeType = "text/plain",
        text = paste("resource", value)
      ))
    ),
    `prompts/list` = list(
      prompts = list(list(
        name = "summarize",
        description = "Summarize the fixture."
      ))
    ),
    `prompts/get` = list(
      messages = list(list(
        role = "user",
        content = list(
          type = "text",
          text = paste("Summarize", value, request$params$arguments$topic)
        )
      ))
    ),
    {
      error <- list(code = -32601L, message = "Method is unavailable.")
      NULL
    }
  )
  response <- list(jsonrpc = "2.0", id = request$id)
  if (is.null(error)) {
    response$result <- result
  } else {
    response$error <- error
  }
  cat(
    jsonlite::toJSON(response, auto_unbox = TRUE, null = "null"),
    "\n",
    sep = ""
  )
  flush(stdout())
}
