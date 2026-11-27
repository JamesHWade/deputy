# Shared local OpenAI-compatible HTTP server helper for runnable examples.
# Runs in a background R process so sync/async clients and Shiny apps stay
# responsive without API keys or external network calls.

local_openai_fixture_helpers <- function() {
  env <- new.env(parent = baseenv())
  env$`%||%` <- function(x, y) if (is.null(x)) y else x
  env$local_openai_message_text <- function(message) {
    content <- message$content
    if (is.character(content)) {
      return(paste(content, collapse = " "))
    }
    if (!is.list(content)) {
      return("")
    }
    paste(
      vapply(
        content,
        function(part) {
          if (is.character(part)) {
            return(part[[1L]])
          }
          part$text %||% part$input_text %||% ""
        },
        character(1)
      ),
      collapse = " "
    )
  }
  env$local_openai_sse_chunk <- function(
    id,
    model = "gpt-4o-mini",
    delta = structure(list(), names = character()),
    finish_reason = NULL,
    usage = NULL,
    choices = NULL
  ) {
    payload <- list(
      id = id,
      model = model,
      choices = if (is.null(choices)) {
        list(list(
          index = 0L,
          delta = delta,
          finish_reason = finish_reason
        ))
      } else {
        choices
      }
    )
    if (!is.null(usage)) {
      payload$usage <- usage
    }
    paste0(
      "data: ",
      jsonlite::toJSON(payload, auto_unbox = TRUE, null = "null"),
      "\n\n"
    )
  }
  env$local_openai_sse <- function(
    id,
    model = "gpt-4o-mini",
    text = NULL,
    calls = list(),
    usage = list(
      prompt_tokens = 10L,
      completion_tokens = 5L,
      total_tokens = 15L
    )
  ) {
    delta <- if (length(calls)) {
      list(
        role = "assistant",
        tool_calls = lapply(seq_along(calls), function(index) {
          call <- calls[[index]]
          list(
            index = index - 1L,
            id = call$id %||% paste0(id, "-call-", index),
            type = "function",
            `function` = list(
              name = call$name,
              arguments = as.character(jsonlite::toJSON(
                call$arguments %||% list(),
                auto_unbox = TRUE
              ))
            )
          )
        })
      )
    } else {
      list(role = "assistant", content = text)
    }
    paste0(
      local_openai_sse_chunk(
        id = id,
        model = model,
        delta = delta
      ),
      local_openai_sse_chunk(
        id = id,
        model = model,
        delta = structure(list(), names = character()),
        finish_reason = if (length(calls)) "tool_calls" else "stop",
        usage = usage
      ),
      "data: [DONE]\n\n"
    )
  }
  env$local_openai_sse_response <- function(body) {
    list(
      status = 200L,
      headers = list("Content-Type" = "text/event-stream"),
      body = body
    )
  }
  env$local_openai_error_response <- function(
    message,
    status = 400L,
    type = "invalid_request_error"
  ) {
    list(
      status = as.integer(status),
      headers = list("Content-Type" = "application/json"),
      body = as.character(jsonlite::toJSON(
        list(error = list(message = message, type = type)),
        auto_unbox = TRUE
      ))
    )
  }
  for (name in ls(env, all.names = TRUE)) {
    fn <- env[[name]]
    if (is.function(fn)) {
      environment(fn) <- env
      env[[name]] <- fn
    }
  }
  env
}

start_local_openai_fixture <- function(
  prefix,
  handler,
  args = list(),
  directory = NULL,
  timeout = 10,
  error_label = "The local model server did not start"
) {
  if (is.null(directory)) {
    directory <- tempfile(prefix)
    dir.create(directory, recursive = TRUE)
  }
  helpers <- local_openai_fixture_helpers()
  environment(handler) <- helpers
  process <- callr::r_bg(
    function(directory, handler, args) {
      count <- 0L
      port <- httpuv::randomPort(min = 1024L, max = 65535L, n = 200L)
      server <- httpuv::startServer(
        "127.0.0.1",
        port,
        list(call = function(req) {
          count <<- count + 1L
          request <- jsonlite::fromJSON(
            rawToChar(req$rook.input$read()),
            simplifyVector = FALSE
          )
          saveRDS(
            list(body = request, path = req$PATH_INFO),
            file.path(directory, sprintf("%04d.rds", count))
          )
          handler(request, count, directory, args)
        })
      )
      on.exit(server$stop(), add = TRUE)
      saveRDS(port, file.path(directory, "port.rds"))
      file.create(file.path(directory, "ready"))
      repeat {
        httpuv::service(50)
      }
    },
    args = list(directory = directory, handler = handler, args = args)
  )
  deadline <- Sys.time() + timeout
  while (!file.exists(file.path(directory, "ready"))) {
    if (!process$is_alive() || Sys.time() > deadline) {
      if (process$is_alive()) {
        process$kill()
      }
      error <- tryCatch(
        paste(process$read_error_lines(), collapse = "\n"),
        error = function(condition) conditionMessage(condition)
      )
      unlink(directory, recursive = TRUE, force = TRUE)
      cli::cli_abort(
        "{error_label}{if (nzchar(error)) paste0(': ', error)}"
      )
    }
    Sys.sleep(0.02)
  }
  port <- readRDS(file.path(directory, "port.rds"))
  url <- paste0("http://127.0.0.1:", port, "/v1")
  list(
    directory = directory,
    port = port,
    url = url,
    process = process,
    requests = function() {
      files <- list.files(
        directory,
        pattern = "^[0-9]+[.]rds$",
        full.names = TRUE
      )
      lapply(files, readRDS)
    },
    close = function() {
      if (process$is_alive()) {
        process$kill()
      }
      unlink(directory, recursive = TRUE, force = TRUE)
      invisible(NULL)
    }
  )
}
