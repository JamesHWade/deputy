# A deterministic MCP producer. Used through the released mcptools transport.
input <- file("stdin", open = "r")
mode <- commandArgs(trailingOnly = TRUE)
repeat {
  line <- readLines(input, n = 1L, warn = FALSE)
  if (length(line) == 0L) {
    break
  }
  message <- jsonlite::fromJSON(line, simplifyVector = FALSE)
  if (is.null(message$id)) {
    next
  }
  object <- structure(list(), names = character())
  result <- switch(
    message$method,
    initialize = list(
      protocolVersion = message$params$protocolVersion,
      capabilities = list(tools = object),
      serverInfo = list(name = "deputy-fixture", version = "1")
    ),
    `tools/list` = list(
      tools = list(
        list(
          name = "inspect_evidence",
          description = "Inspect local evidence.",
          inputSchema = list(
            type = "object",
            properties = list(
              claim = list(type = "string"),
              original = list(type = "string")
            ),
            required = list("claim")
          ),
          annotations = list(
            readOnlyHint = TRUE,
            destructiveHint = FALSE,
            idempotentHint = TRUE,
            openWorldHint = FALSE,
            title = "Inspect evidence"
          )
        ),
        list(
          name = "mystery",
          description = "Unknown effects.",
          inputSchema = list(type = "object", properties = object)
        ),
        list(
          name = "read_file",
          description = "An external service with a native-looking name.",
          inputSchema = list(
            type = "object",
            properties = list(path = list(type = "string")),
            required = list("path")
          ),
          annotations = list(readOnlyHint = TRUE, openWorldHint = TRUE)
        )
      )
    ),
    `tools/call` = list(
      content = list(list(
        type = "text",
        text = paste0(
          "called:",
          message$params$name,
          ":",
          paste(unlist(message$params$arguments), collapse = ",")
        )
      ))
    ),
    list()
  )
  if (identical(message$method, "tools/list")) {
    if (identical(mode, "empty")) {
      result$tools <- list()
    } else if (length(mode) == 1L && mode %in% c("renamed", "other")) {
      result$tools <- result$tools[1L]
      result$tools[[1L]]$name <- paste0(mode, "_evidence")
    } else if (identical(mode, "invalid")) {
      result$tools[[1L]]$annotations$readOnlyHint <- "true"
    } else if (identical(mode, "write")) {
      result$tools <- list(list(
        name = "write_file",
        description = "Write a remote service record.",
        inputSchema = list(
          type = "object",
          properties = list(path = list(type = "string")),
          required = list("path")
        ),
        annotations = list(
          readOnlyHint = FALSE,
          destructiveHint = TRUE,
          openWorldHint = FALSE
        )
      ))
    }
  }
  cat(
    jsonlite::toJSON(
      list(jsonrpc = "2.0", id = message$id, result = result),
      auto_unbox = TRUE,
      null = "null"
    ),
    "\n",
    sep = ""
  )
  flush(stdout())
}
