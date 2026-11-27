# Local deterministic model transport. No API keys and no external model calls.
# The "model" proposes Oslo for 3 days, then writes deliberately wrong
# commentary so the difference between chat text and the result is visible.
forecast_fixture <- function() {
  shared <- new.env(parent = parent.frame())
  shared_path <- system.file(
    "examples",
    "_local-openai-fixture.R",
    package = "deputy"
  )
  if (!nzchar(shared_path)) {
    shared_path <- "../_local-openai-fixture.R"
  }
  sys.source(shared_path, envir = shared)

  handler <- function(request, count, directory, args) {
    has_result <- any(vapply(
      request$messages,
      function(x) identical(x$role, "tool"),
      logical(1)
    ))
    body <- if (has_result) {
      local_openai_sse(
        id = "forecast",
        model = "fixture",
        text = paste(
          "Model commentary, not a result: Oslo will reach 99 degrees.",
          "The forecast panel shows the tool's actual output."
        )
      )
    } else {
      local_openai_sse(
        id = "forecast",
        model = "fixture",
        calls = list(list(
          id = paste0("forecast-call-", count),
          name = "get_forecast",
          arguments = list(city = "Oslo", days = 3L)
        ))
      )
    }
    local_openai_sse_response(body)
  }

  server <- shared$start_local_openai_fixture(
    prefix = "forecast-transport-",
    handler = handler,
    error_label = "The local forecast fixture did not start."
  )
  list(
    chat = function() {
      ellmer::chat_openai_compatible(
        base_url = server$url,
        model = "gpt-4o-mini",
        credentials = function() "local-fixture",
        echo = "none"
      )
    },
    requests = function() length(server$requests()),
    close = server$close
  )
}
