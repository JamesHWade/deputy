# Deterministic wire responses for real ellmer producers, including failed
# HTTP requests. A separate event loop serves both sync and async clients.
local_runtime_server <- function(responses, .local_envir = parent.frame()) {
  skip_if_not_installed("httpuv")
  skip_if_not_installed("jsonlite")
  directory <- withr::local_tempdir(.local_envir = .local_envir)
  process <- callr::r_bg(
    function(directory, responses) {
      port <- httpuv::randomPort()
      count <- 0L
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
          response <- responses[[min(count, length(responses))]]
          delay <- attr(response, "fixture_delay")
          if (is.null(delay)) {
            response
          } else {
            promises::promise(function(resolve, reject) {
              later::later(function() resolve(response), delay)
            })
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
    args = list(directory = directory, responses = responses)
  )
  withr::defer(process$kill(), envir = .local_envir)
  deadline <- Sys.time() + 10
  while (!file.exists(file.path(directory, "ready"))) {
    if (!process$is_alive() || Sys.time() > deadline) {
      cli::cli_abort("Runtime fixture did not start")
    }
    Sys.sleep(0.02)
  }
  list(
    url = paste0(
      "http://127.0.0.1:",
      readRDS(file.path(directory, "port.rds")),
      "/v1"
    ),
    requests = function() {
      lapply(
        list.files(directory, pattern = "^[0-9]+[.]rds$", full.names = TRUE),
        readRDS
      )
    }
  )
}

runtime_reply <- function(
  text = "done",
  tool = NULL,
  stream = TRUE,
  finish = "stop",
  arguments = list()
) {
  usage <- list(prompt_tokens = 10, completion_tokens = 5, total_tokens = 15)
  message <- list(role = "assistant", content = text)
  if (!is.null(tool)) {
    message$content <- NULL
    message$tool_calls <- list(list(
      index = 0L,
      id = "call_fixture",
      type = "function",
      `function` = list(
        name = tool,
        arguments = as.character(jsonlite::toJSON(arguments, auto_unbox = TRUE))
      )
    ))
    finish <- "tool_calls"
  }
  if (stream) {
    chunks <- list(
      list(
        id = "fixture",
        model = "gpt-4o-mini",
        choices = list(list(index = 0L, delta = message))
      ),
      list(
        id = "fixture",
        model = "gpt-4o-mini",
        choices = list(list(
          index = 0L,
          delta = list(),
          finish_reason = finish
        )),
        usage = usage
      )
    )
    body <- paste0(
      paste0(
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
  } else {
    body <- jsonlite::toJSON(
      list(
        id = "fixture",
        model = "gpt-4o-mini",
        choices = list(list(
          index = 0L,
          message = message,
          finish_reason = finish
        )),
        usage = usage
      ),
      auto_unbox = TRUE,
      null = "null"
    )
  }
  list(
    status = 200L,
    headers = list(
      "Content-Type" = if (stream) "text/event-stream" else "application/json"
    ),
    body = body
  )
}

runtime_failure <- function(status = 503L) {
  list(
    status = status,
    headers = list("Content-Type" = "application/json", "Retry-After" = "0"),
    body = '{"error":{"message":"fixture unavailable","type":"server_error"}}'
  )
}

runtime_chat <- function(server, model = "gpt-4o-mini", ...) {
  ellmer::chat_openai_compatible(
    base_url = server$url,
    credentials = function() "fixture",
    model = model,
    echo = "none",
    ...
  )
}

runtime_events <- function(agent, type) {
  Filter(function(event) identical(event$type, type), agent$last_run()$events)
}
