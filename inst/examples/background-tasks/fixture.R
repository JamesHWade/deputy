# A local OpenAI-compatible server that stands in for the three models, so the
# example needs no API key. It runs in a separate R process and answers each
# model from a fixed script: the reply is chosen by how many assistant turns
# the request already holds, and task IDs are read back from the tool results
# in the request, as a real model would read them.
background_local_fixture <- function() {
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
    local_openai_sse_response(local_openai_sse(
      id = paste0("background-fixture-", count),
      model = "gpt-4o-mini",
      text = reply$text,
      calls = reply$calls %||% list()
    ))
  }

  server <- shared$start_local_openai_fixture(
    prefix = "deputy-background-tasks-",
    handler = handler
  )
  list(
    url = server$url,
    chat = function(role, ...) {
      ellmer::chat_openai_compatible(
        base_url = server$url,
        credentials = function() "fixture",
        model = paste0("background-", role),
        echo = "none",
        ...
      )
    },
    requests = server$requests,
    close = server$close
  )
}
