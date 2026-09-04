# A separate process is required: curl opens the streaming connection before
# yielding to the caller's event loop. No external service or key is used.
local_parallel_server <- function(.local_envir = parent.frame()) {
  skip_if_not_installed("httpuv")
  skip_if_not_installed("jsonlite")
  directory <- withr::local_tempdir(.local_envir = .local_envir)
  process <- callr::r_bg(
    function(directory) {
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
          saveRDS(request, file.path(directory, paste0(count, ".rds")))
          list(
            status = 200L,
            headers = list("Content-Type" = "text/event-stream"),
            body = paste0(
              'data: {"id":"fixture","model":"gpt-4o-mini","choices":[{"index":0,"delta":{"role":"assistant","content":"fixture reply"},"finish_reason":null}]}\n\n',
              'data: {"id":"fixture","model":"gpt-4o-mini","choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}\n\n',
              'data: [DONE]\n\n'
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
    args = list(directory = directory)
  )
  withr::defer(process$kill(), envir = .local_envir)
  deadline <- Sys.time() + 10
  while (!file.exists(file.path(directory, "ready"))) {
    if (!process$is_alive() || Sys.time() > deadline) {
      cli::cli_abort("Local streaming fixture failed to start")
    }
    Sys.sleep(0.05)
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
