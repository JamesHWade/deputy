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
    measure <- function(name, n) {
      list(
        id = paste0("call_", n),
        name = "commons_measure",
        arguments = list(name = name, arguments = "{}")
      )
    }
    search <- function(query, n) {
      list(
        id = paste0("call_", n),
        name = "commons_search",
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
        root = if (grepl("inventory", task, ignore.case = TRUE)) {
          if (done == 0L) {
            list(
              calls = list(route(
                "ask_ops",
                "Check inventory turnover.",
                n
              ))
            )
          } else {
            list(
              text = "ROOT: No approved calculation covers inventory turnover."
            )
          }
        } else if (grepl("again", task, ignore.case = TRUE)) {
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
        ops = if (grepl("inventory", task, ignore.case = TRUE)) {
          if (done == 0L) {
            list(calls = list(search("inventory turnover", n)))
          } else {
            list(
              text = "OPS: No approved calculation covers inventory turnover."
            )
          }
        } else if (grepl("SLOW", task, fixed = TRUE)) {
          Sys.sleep(args$slow)
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
      function(index) {
        nzchar(trimws(local_openai_message_text(messages[[index]])))
      },
      users
    )
    last <- if (length(tasks)) utils::tail(tasks, 1L) else 0L
    current <- if (last) messages[last:length(messages)] else messages
    done <- sum(vapply(
      current,
      function(message) identical(message$role, "tool"),
      logical(1)
    ))
    task <- if (last) local_openai_message_text(messages[[last]]) else ""
    answer <- reply(role, task, done)
    Sys.sleep(args$delay)
    if (!is.null(answer$error)) {
      return(local_openai_error_response(
        answer$error,
        status = 400L,
        type = "invalid_request_error"
      ))
    }
    local_openai_sse_response(local_openai_sse(
      id = paste0("commons-fixture-", count),
      model = "commons-fixture",
      text = answer$text,
      calls = answer$calls %||% list()
    ))
  }

  server <- shared$start_local_openai_fixture(
    prefix = "deputy-commons-subagents-",
    handler = handler,
    args = list(delay = delay, slow = slow),
    error_label = "The Commons example server did not start"
  )
  list(
    url = server$url,
    chat = function(role) {
      ellmer::chat_openai_compatible(
        base_url = server$url,
        credentials = function() "fixture",
        model = paste0("commons-", role),
        echo = "none"
      )
    },
    requests = server$requests,
    count = function() {
      length(list.files(server$directory, pattern = "^[0-9]+[.]rds$"))
    },
    close = server$close
  )
}
