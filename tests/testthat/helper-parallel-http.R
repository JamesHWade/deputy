# A separate process is required: curl opens the streaming connection before
# yielding to the caller's event loop. No external service or key is used.
# The fixture is registered on the worker's shared server process; see
# `local_runtime_server()`.
local_parallel_server <- function(.local_envir = parent.frame()) {
  skip_if_not_installed("httpuv")
  skip_if_not_installed("jsonlite")
  directory <- withr::local_tempdir(.local_envir = .local_envir)
  reply <- list(
    status = 200L,
    headers = list("Content-Type" = "text/event-stream"),
    body = paste0(
      'data: {"id":"fixture","model":"gpt-4o-mini","choices":[{"index":0,"delta":{"role":"assistant","content":"fixture reply"},"finish_reason":null}]}\n\n',
      'data: {"id":"fixture","model":"gpt-4o-mini","choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}\n\n',
      'data: [DONE]\n\n'
    )
  )
  fixture <- local_fixture_registration(
    responses = list(reply),
    directory = directory,
    record = "body",
    failure = "Local streaming fixture failed to start",
    .local_envir = .local_envir
  )
  list(
    url = paste0(fixture$url, "/v1"),
    requests = function() {
      lapply(
        list.files(directory, pattern = "^[0-9]+[.]rds$", full.names = TRUE),
        readRDS
      )
    }
  )
}
