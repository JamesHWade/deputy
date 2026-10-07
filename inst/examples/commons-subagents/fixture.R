# A deterministic local OpenAI-compatible server for the Commons example.
#
# Each chat uses its own model name, so the server knows which agent is asking.
# The reply depends only on that agent's latest task and the tool results it
# has already received, which keeps every run of the example identical without
# API keys or paid requests.
#
# `delay` is how long every reply takes. A slow operations check takes five
# searches of `slow` seconds each: the app waits for each reply before it can do
# anything else, so a long check is made of short steps, as a working agent's
# would be, and a cancellation takes effect at the next one.
commons_local_fixture <- function(delay = 0.1, slow = 1) {
  directory <- tempfile("deputy-commons-subagents-")
  dir.create(directory, recursive = TRUE)
  process <- callr::r_bg(
    function(directory, delay, slow) {
      `%||%` <- function(x, y) if (is.null(x)) y else x
      count <- 0L

      text_of <- function(message) {
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
              if (is.character(part)) part[[1L]] else part$text %||% ""
            },
            character(1)
          ),
          collapse = " "
        )
      }

      sse <- function(id, text = NULL, calls = list()) {
        delta <- if (length(calls)) {
          list(
            role = "assistant",
            tool_calls = lapply(seq_along(calls), function(index) {
              call <- calls[[index]]
              list(
                index = index - 1L,
                id = call$id,
                type = "function",
                `function` = list(
                  name = call$name,
                  arguments = as.character(jsonlite::toJSON(
                    call$arguments,
                    auto_unbox = TRUE
                  ))
                )
              )
            })
          )
        } else {
          list(role = "assistant", content = text)
        }
        chunks <- list(
          list(
            id = id,
            model = "commons-fixture",
            choices = list(list(index = 0L, delta = delta))
          ),
          list(
            id = id,
            model = "commons-fixture",
            choices = list(list(
              index = 0L,
              delta = list(),
              finish_reason = if (length(calls)) "tool_calls" else "stop"
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

      measure <- function(name, n) {
        list(
          id = paste0("call_", n),
          name = "call_measure",
          arguments = list(name = name, arguments = "{}")
        )
      }
      search <- function(query, n) {
        list(
          id = paste0("call_", n),
          name = "search_pool",
          arguments = list(query = query)
        )
      }
      route <- function(name, task, n) {
        list(
          id = paste0("call_", n),
          name = name,
          arguments = list(task = task)
        )
      }

      # The reply for one agent, given its latest task and the number of tool
      # results it has received since then.
      reply <- function(role, task, done) {
        n <- done + 1L
        switch(
          role,
          root = if (grepl("again", task, ignore.case = TRUE)) {
            if (done == 0L) {
              list(calls = list(route("ask_sales", "Total revenue only.", n)))
            } else {
              list(text = "ROOT: Sales confirmed the total revenue.")
            }
          } else if (grepl("slow", task, ignore.case = TRUE)) {
            if (done == 0L) {
              list(
                calls = list(route(
                  "ask_ops",
                  "SLOW: recheck the on-time delivery rate.",
                  n
                ))
              )
            } else {
              list(
                text = "ROOT: The operations check stopped before it finished."
              )
            }
          } else if (done == 0L) {
            list(
              calls = list(
                route("ask_sales", "Revenue by region, with a chart.", 1L),
                route("ask_ops", "On-time delivery rate.", 2L)
              )
            )
          } else {
            list(
              text = paste(
                "ROOT: Sales reported revenue by region with a chart, and the",
                "auditor confirmed the total. The operations check failed after",
                "its first measure."
              )
            )
          },
          sales = if (grepl("Total revenue only", task, fixed = TRUE)) {
            if (done == 0L) {
              list(calls = list(measure("total_revenue", n)))
            } else {
              list(text = "SALES: Total revenue is 435.")
            }
          } else {
            switch(
              as.character(min(done, 3L)),
              "0" = list(calls = list(measure("revenue_by_region", n))),
              "1" = list(calls = list(measure("revenue_chart", n))),
              "2" = list(
                calls = list(route(
                  "ask_auditor",
                  "Check the total revenue.",
                  n
                ))
              ),
              list(
                text = "SALES: East leads with 140; the auditor confirmed the total."
              )
            )
          },
          ops = if (grepl("SLOW", task, fixed = TRUE)) {
            Sys.sleep(slow)
            if (done < 5L) {
              list(calls = list(search("shipments", n)))
            } else {
              list(text = "OPS: The on-time delivery rate is unchanged.")
            }
          } else if (done == 0L) {
            list(calls = list(measure("on_time_rate", n)))
          } else {
            list(error = "Fixture: the shipment source is unavailable.")
          },
          auditor = if (done == 0L) {
            list(calls = list(measure("total_revenue", n)))
          } else {
            list(text = "AUDITOR: Total revenue of 435 matches the measure.")
          },
          list(text = "No scripted reply for this agent.")
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
          role <- sub("^commons-", "", request$model %||% "")
          messages <- request$messages %||% list()
          users <- which(vapply(
            messages,
            function(message) identical(message$role, "user"),
            logical(1)
          ))
          # Tool results count from the latest task; a tool result can also
          # arrive in a user message, which isn't a new task.
          tasks <- Filter(
            function(index) nzchar(trimws(text_of(messages[[index]]))),
            users
          )
          last <- if (length(tasks)) utils::tail(tasks, 1L) else 0L
          current <- if (last) messages[last:length(messages)] else messages
          done <- sum(vapply(
            current,
            function(message) identical(message$role, "tool"),
            logical(1)
          ))
          task <- if (last) text_of(messages[[last]]) else ""
          answer <- reply(role, task, done)
          Sys.sleep(delay)
          if (!is.null(answer$error)) {
            return(list(
              status = 400L,
              headers = list("Content-Type" = "application/json"),
              body = as.character(jsonlite::toJSON(
                list(
                  error = list(
                    message = answer$error,
                    type = "invalid_request_error"
                  )
                ),
                auto_unbox = TRUE
              ))
            ))
          }
          list(
            status = 200L,
            headers = list("Content-Type" = "text/event-stream"),
            body = sse(
              paste0("commons-fixture-", count),
              text = answer$text,
              calls = answer$calls %||% list()
            )
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
    args = list(directory = directory, delay = delay, slow = slow)
  )
  deadline <- Sys.time() + 10
  while (!file.exists(file.path(directory, "ready"))) {
    if (!process$is_alive() || Sys.time() > deadline) {
      error <- tryCatch(
        paste(process$read_error_lines(), collapse = "\n"),
        error = function(condition) conditionMessage(condition)
      )
      cli::cli_abort(
        "The Commons example server did not start{if (nzchar(error)) paste0(': ', error)}"
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
    chat = function(role) {
      ellmer::chat_openai_compatible(
        base_url = url,
        credentials = function() "fixture",
        model = paste0("commons-", role),
        echo = "none"
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
    count = function() {
      length(list.files(directory, pattern = "^[0-9]+[.]rds$"))
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
