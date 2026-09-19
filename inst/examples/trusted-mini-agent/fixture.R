# Local deterministic model transport. No API keys and no external model calls.
study_fixture <- function(plan) {
  directory <- tempfile("study-transport-")
  dir.create(directory)
  process <- callr::r_bg(
    function(directory, plan) {
      count <- 0L
      reply <- function(text = NULL, tool = NULL, arguments = list()) {
        delta <- list(role = "assistant", content = text)
        if (!is.null(tool)) {
          delta$content <- NULL
          delta$tool_calls <- list(list(
            index = 0L,
            id = paste0("study-call-", count),
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
            id = "study",
            model = "fixture",
            choices = list(list(index = 0L, delta = delta))
          ),
          list(
            id = "study",
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
          system <- paste(
            vapply(
              Filter(function(x) x$role == "system", body$messages),
              function(x) as.character(x$content),
              character(1)
            ),
            collapse = " "
          )
          has_result <- any(vapply(
            body$messages,
            function(x) x$role == "tool",
            logical(1)
          ))
          response <- if (has_result) {
            reply(
              "Model commentary: a deliberately incorrect answer is 999 grams. Use the designated result panel instead."
            )
          } else if (grepl("STUDY_EXECUTOR", system, fixed = TRUE)) {
            reply(tool = "compute_summary", arguments = list(plan = plan))
          } else if (grepl("STUDY_ANALYST", system, fixed = TRUE)) {
            reply(tool = "propose_analysis", arguments = list(plan = plan))
          } else {
            reply(
              tool = "delegate_to_agent",
              arguments = list(
                agent_name = "analyst",
                task = "Propose a descriptive comparison of trt2 and ctrl using the known dataset."
              )
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
    args = list(directory = directory, plan = plan)
  )
  deadline <- Sys.time() + 10
  while (!file.exists(file.path(directory, "port.rds"))) {
    if (!process$is_alive() || Sys.time() > deadline) {
      process$kill()
      cli::cli_abort("The local study fixture did not start.")
    }
    Sys.sleep(0.02)
  }
  url <- paste0(
    "http://127.0.0.1:",
    readRDS(file.path(directory, "port.rds")),
    "/v1"
  )
  list(
    chat = function(role) {
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
