# A local OpenAI-compatible server that stands in for the three models, so the
# example needs no API key. It runs in a separate R process and answers each
# model from a fixed script: the reply is chosen by how many assistant turns
# the request already holds, and task IDs are read back from the tool results
# in the request, as a real model would read them.
background_local_fixture <- function() {
  directory <- tempfile("deputy-background-tasks-")
  dir.create(directory, recursive = TRUE)
  process <- callr::r_bg(
    function(directory) {
      `%||%` <- function(x, y) if (is.null(x)) y else x
      count <- 0L

      text <- function(content) list(text = content)
      calls <- function(...) list(calls = list(...))
      call <- function(name, arguments = list()) {
        list(name = name, arguments = arguments)
      }

      script <- list(
        "background-lead" = list(
          function(ids) {
            calls(
              call(
                "task_start",
                list(
                  agent = "analyst",
                  task = "Summarize the viscosity measurements for batch 12."
                )
              ),
              call(
                "task_start",
                list(
                  agent = "reviewer",
                  task = "Check the draft report for batch 12 against the style guide."
                )
              )
            )
          },
          function(ids) calls(call("lookup_specification")),
          function(ids) calls(call("task_wait")),
          function(ids) {
            calls(call(
              "task_follow_up",
              list(
                task_id = ids$analyst[[1L]],
                task = "Is the mean within the specification of 4.0 to 4.5 Pa.s?"
              )
            ))
          },
          function(ids) {
            calls(call(
              "task_cancel",
              list(
                task_id = ids$reviewer[[1L]],
                reason = "The report will be rewritten, so the review can wait."
              )
            ))
          },
          function(ids) calls(call("task_wait", list(until = "all"))),
          function(ids) {
            text(paste(
              "LEAD: batch 12 has a mean viscosity of 4.2 Pa.s, inside the",
              "specification of 4.0 to 4.5 Pa.s. The draft review was",
              "cancelled before it finished."
            ))
          }
        ),
        "background-analyst" = list(
          function(ids) calls(call("load_measurements")),
          function(ids) {
            text(
              "ANALYST: three measurements, mean 4.2 Pa.s, range 4.1 to 4.3."
            )
          },
          function(ids) {
            text(paste(
              "ANALYST: yes. The mean of 4.2 Pa.s from the measurements I",
              "loaded earlier is within 4.0 to 4.5 Pa.s."
            ))
          }
        ),
        "background-reviewer" = list(
          function(ids) calls(call("read_draft")),
          function(ids) text("REVIEWER: the draft follows the style guide.")
        )
      )

      # Task IDs by specialist, oldest first, from the tool results so far.
      task_ids <- function(messages) {
        ids <- list()
        for (message in messages) {
          content <- message$content
          if (!identical(message$role, "tool") || !is.character(content)) {
            next
          }
          found <- regmatches(
            content,
            regexec('^\\{"task_id":"(task_[^"]+)","agent":"([^"]+)"', content)
          )[[1L]]
          if (length(found) == 3L && !found[[2L]] %in% ids[[found[[3L]]]]) {
            ids[[found[[3L]]]] <- c(ids[[found[[3L]]]], found[[2L]])
          }
        }
        ids
      }

      sse <- function(reply, id) {
        delta <- if (is.null(reply$calls)) {
          list(role = "assistant", content = reply$text)
        } else {
          list(
            role = "assistant",
            tool_calls = lapply(seq_along(reply$calls), function(index) {
              list(
                index = index - 1L,
                id = paste0(id, "-call-", index),
                type = "function",
                `function` = list(
                  name = reply$calls[[index]]$name,
                  arguments = as.character(jsonlite::toJSON(
                    reply$calls[[index]]$arguments,
                    auto_unbox = TRUE
                  ))
                )
              )
            })
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
              delta = structure(list(), names = character()),
              finish_reason = if (is.null(reply$calls)) "stop" else "tool_calls"
            )),
            usage = list(
              prompt_tokens = 10L,
              completion_tokens = 5L,
              total_tokens = 15L
            )
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
          messages <- request$messages %||% list()
          replies <- script[[request$model %||% ""]]
          reply <- if (is.null(replies)) {
            text(paste("No script for model", request$model))
          } else {
            assistant <- sum(vapply(
              messages,
              function(message) identical(message$role, "assistant"),
              logical(1)
            ))
            replies[[min(assistant + 1L, length(replies))]](task_ids(messages))
          }
          list(
            status = 200L,
            headers = list("Content-Type" = "text/event-stream"),
            body = sse(reply, paste0("background-fixture-", count))
          )
        })
      )
      on.exit(server$stop(), add = TRUE)
      saveRDS(port, file.path(directory, "port.rds"))
      file.create(file.path(directory, "ready"))
      repeat {
        httpuv::service(50)
      }
    },
    args = list(directory = directory)
  )
  deadline <- Sys.time() + 10
  while (!file.exists(file.path(directory, "ready"))) {
    if (!process$is_alive() || Sys.time() > deadline) {
      error <- tryCatch(
        paste(process$read_error_lines(), collapse = "\n"),
        error = function(condition) conditionMessage(condition)
      )
      cli::cli_abort(
        "The local model server did not start{if (nzchar(error)) paste0(': ', error)}"
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
    chat = function(role, ...) {
      ellmer::chat_openai_compatible(
        base_url = url,
        credentials = function() "fixture",
        model = paste0("background-", role),
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
