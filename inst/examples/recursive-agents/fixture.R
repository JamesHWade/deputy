# A deterministic local OpenAI-compatible transport for the recursive example.
# Every response is generated from the request's system prompt and tool history,
# so the example exercises real ellmer streaming without paid model calls.
recursive_local_fixture <- function(delay = 0.15) {
  directory <- tempfile("deputy-recursive-agents-")
  dir.create(directory, recursive = TRUE)
  process <- callr::r_bg(
    function(directory, delay) {
      `%||%` <- function(x, y) if (is.null(x)) y else x
      count <- 0L

      message_text <- function(message) {
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

      sse <- function(message, finish, id, call_id = NULL) {
        usage <- list(
          prompt_tokens = 10L,
          completion_tokens = 5L,
          total_tokens = 15L
        )
        delta <- if (is.null(call_id)) {
          list(role = "assistant", content = message)
        } else {
          list(
            role = "assistant",
            tool_calls = list(list(
              index = 0L,
              id = call_id,
              type = "function",
              `function` = list(
                name = message$name,
                arguments = jsonlite::toJSON(
                  message$arguments,
                  auto_unbox = TRUE
                )
              )
            ))
          )
        }
        chunks <- list(
          list(
            id = id,
            model = "gpt-4o-mini",
            choices = list(list(index = 0L, delta = delta))
          ),
          list(
            id = id,
            model = "gpt-4o-mini",
            choices = list(list(
              index = 0L,
              delta = list(),
              finish_reason = finish
            )),
            usage = usage
          )
        )
        paste0(
          paste0(
            vapply(
              chunks,
              function(chunk) {
                paste0(
                  "data: ",
                  jsonlite::toJSON(chunk, auto_unbox = TRUE, null = "null"),
                  "\n\n"
                )
              },
              character(1)
            ),
            collapse = ""
          ),
          "data: [DONE]\n\n"
        )
      }

      port <- httpuv::randomPort(
        min = 1024L,
        max = 65535L,
        n = 200L
      )
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
          messages <- request$messages %||% list()
          system <- paste(
            vapply(
              Filter(
                function(message) identical(message$role, "system"),
                messages
              ),
              message_text,
              character(1)
            ),
            collapse = " "
          )
          user_messages <- vapply(
            Filter(function(message) identical(message$role, "user"), messages),
            message_text,
            character(1)
          )
          tool_messages <- Filter(
            function(message) identical(message$role, "tool"),
            messages
          )
          tool_text <- paste(
            vapply(tool_messages, message_text, character(1)),
            collapse = " "
          )
          role <- if (grepl("RECURSIVE_ROOT", system, fixed = TRUE)) {
            "root"
          } else if (grepl("RECURSIVE_ANALYST", system, fixed = TRUE)) {
            "analyst"
          } else {
            "reviewer"
          }
          id <- paste0("recursive-fixture-", count)
          call_id <- paste0("recursive-call-", count)
          response <- if (identical(role, "root")) {
            if (!length(tool_messages)) {
              list(
                name = "analyze",
                arguments = list(task = "Analyze the fixture evidence.")
              )
            } else {
              "ROOT: the analyst and reviewer agree on the bounded evidence."
            }
          } else if (identical(role, "analyst")) {
            latest <- if (length(user_messages)) tail(user_messages, 1L) else ""
            if (grepl("follow-up", latest, ignore.case = TRUE)) {
              "ANALYST: follow-up complete using the retained graph history."
            } else if (
              !any(grepl("fixture evidence", tool_text, fixed = TRUE))
            ) {
              list(
                name = "inspect_fixture",
                arguments = list()
              )
            } else if (!any(grepl("REVIEWER", tool_text, fixed = TRUE))) {
              list(
                name = "review",
                arguments = list(task = "Review the analyst evidence.")
              )
            } else {
              "ANALYST: evidence reviewed and ready for synthesis."
            }
          } else {
            "REVIEWER: the evidence is internally consistent and bounded."
          }
          Sys.sleep(delay)
          if (is.list(response)) {
            list(
              status = 200L,
              headers = list("Content-Type" = "text/event-stream"),
              body = sse(response, "tool_calls", id, call_id)
            )
          } else {
            list(
              status = 200L,
              headers = list("Content-Type" = "text/event-stream"),
              body = sse(response, "stop", id)
            )
          }
        })
      )
      on.exit(server$stop(), add = TRUE)
      saveRDS(port, file.path(directory, "port.rds"))
      file.create(file.path(directory, "ready"))
      repeat {
        httpuv::service(50)
      }
    },
    args = list(directory = directory, delay = delay)
  )
  deadline <- Sys.time() + 10
  while (!file.exists(file.path(directory, "ready"))) {
    if (!process$is_alive() || Sys.time() > deadline) {
      error <- tryCatch(
        paste(process$read_error_lines(), collapse = "\n"),
        error = function(condition) conditionMessage(condition)
      )
      cli::cli_abort(
        "Recursive local fixture did not start{if (nzchar(error)) paste0(': ', error)}"
      )
    }
    Sys.sleep(0.02)
  }
  url <- paste0(
    "http://127.0.0.1:",
    readRDS(file.path(directory, "port.rds")),
    "/v1"
  )
  list(
    url = url,
    chat = function(role, model = paste0("recursive-", role), ...) {
      ellmer::chat_openai_compatible(
        base_url = url,
        credentials = function() "fixture",
        model = model,
        echo = "none",
        ...
      )
    },
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
