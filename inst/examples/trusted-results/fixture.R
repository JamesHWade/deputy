# Local deterministic model transport. No API keys and no external model calls.
# The "model" proposes Oslo for 3 days, then writes deliberately wrong
# commentary so the difference between chat text and the result is visible.
forecast_fixture <- function() {
  directory <- tempfile("forecast-transport-")
  dir.create(directory)
  process <- callr::r_bg(
    function(directory) {
      count <- 0L
      reply <- function(text = NULL, tool = NULL, arguments = list()) {
        delta <- list(role = "assistant", content = text)
        if (!is.null(tool)) {
          delta$content <- NULL
          delta$tool_calls <- list(list(
            index = 0L,
            id = paste0("forecast-call-", count),
            type = "function",
            `function` = list(
              name = tool,
              arguments = as.character(jsonlite::toJSON(
                arguments,
                auto_unbox = TRUE
              ))
            )
          ))
        }
        chunks <- list(
          list(
            id = "forecast",
            model = "fixture",
            choices = list(list(index = 0L, delta = delta))
          ),
          list(
            id = "forecast",
            model = "fixture",
            choices = list(list(
              index = 0L,
              delta = list(),
              finish_reason = if (is.null(tool)) "stop" else "tool_calls"
            )),
            usage = list(
              prompt_tokens = 10L,
              completion_tokens = 5L,
              total_tokens = 15L
            )
          )
        )
        paste0(
          paste(
            vapply(
              chunks,
              function(x) {
                paste0(
                  "data: ",
                  jsonlite::toJSON(x, auto_unbox = TRUE, null = "null"),
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
      server <- httpuv::startServer(
        "127.0.0.1",
        port <- httpuv::randomPort(),
        list(call = function(req) {
          count <<- count + 1L
          saveRDS(count, file.path(directory, "count.rds"))
          body <- jsonlite::fromJSON(
            rawToChar(req$rook.input$read()),
            simplifyVector = FALSE
          )
          has_result <- any(vapply(
            body$messages,
            function(x) identical(x$role, "tool"),
            logical(1)
          ))
          response <- if (has_result) {
            reply(paste(
              "Model commentary, not a result: Oslo will reach 99 degrees.",
              "The forecast panel shows the tool's actual output."
            ))
          } else {
            reply(
              tool = "get_forecast",
              arguments = list(city = "Oslo", days = 3L)
            )
          }
          list(
            status = 200L,
            headers = list("Content-Type" = "text/event-stream"),
            body = response
          )
        })
      )
      on.exit(server$stop(), add = TRUE)
      saveRDS(port, file.path(directory, "port.rds"))
      repeat {
        httpuv::service(50)
      }
    },
    args = list(directory = directory)
  )
  deadline <- Sys.time() + 10
  while (!file.exists(file.path(directory, "port.rds"))) {
    if (!process$is_alive() || Sys.time() > deadline) {
      process$kill()
      cli::cli_abort("The local forecast fixture did not start.")
    }
    Sys.sleep(0.02)
  }
  url <- paste0(
    "http://127.0.0.1:",
    readRDS(file.path(directory, "port.rds")),
    "/v1"
  )
  list(
    chat = function() {
      ellmer::chat_openai_compatible(
        base_url = url,
        model = "gpt-4o-mini",
        credentials = function() "local-fixture",
        echo = "none"
      )
    },
    requests = function() {
      path <- file.path(directory, "count.rds")
      if (file.exists(path)) readRDS(path) else 0L
    },
    close = function() {
      process$kill()
      unlink(directory, recursive = TRUE)
    }
  )
}
