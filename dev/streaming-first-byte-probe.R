#!/usr/bin/env Rscript

# Qualification probe for #200 (curl/httr2 response-body streaming).
#
# This intentionally uses only a loopback HTTP/SSE fixture. It does not read
# provider credentials or make an external request. Run it from the package
# checkout with `Rscript dev/streaming-first-byte-probe.R`.

pkgload::load_all(quiet = TRUE, helpers = FALSE)

stopifnot(
  requireNamespace("callr"),
  requireNamespace("coro"),
  requireNamespace("ellmer"),
  requireNamespace("httpuv"),
  requireNamespace("later"),
  requireNamespace("promises")
)

delay_seconds <- 2
timeout_seconds <- 12

cat("package versions\n")
for (package in c("deputy", "curl", "httr2", "ellmer")) {
  cat(package, as.character(utils::packageVersion(package)), "\n")
}
cat("fixture delay_seconds", delay_seconds, "\n")
cat("timeout_seconds", timeout_seconds, "\n")
cat("\nresults\n")
cat(
  paste(
    "method",
    "scenario",
    "protocol",
    "reply",
    "ticks_before_1.9s",
    "max_event_loop_gap_s",
    "elapsed_s",
    sep = "\t"
  ),
  "\n"
)

stream_fixture_body <- paste0(
  "data: ",
  '{"id":"fixture","model":"gpt-4o-mini","choices":[{"index":0,"delta":{"content":"ok"},"finish_reason":"stop"}]}',
  "\n\ndata: [DONE]\n\n"
)

json_fixture_body <- paste0(
  '{"id":"fixture","object":"chat.completion","created":0,',
  '"model":"gpt-4o-mini","choices":[{"index":0,',
  '"message":{"role":"assistant","content":"ok"},',
  '"finish_reason":"stop"}],',
  '"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}'
)

start_fixture <- function(scenario, delay_seconds, protocol) {
  stopifnot(scenario %in% c("slow_body", "slow_headers"))
  stopifnot(protocol %in% c("sse", "json"))

  body <- if (identical(protocol, "sse")) {
    stream_fixture_body
  } else {
    json_fixture_body
  }
  content_type <- if (identical(protocol, "sse")) {
    "text/event-stream"
  } else {
    "application/json"
  }

  port <- httpuv::randomPort()
  ready <- tempfile("deputy-streaming-ready-")
  server <- callr::r_bg(
    function(port, ready, scenario, delay_seconds, body, content_type) {
      listener <- serverSocket(port)
      on.exit(close(listener), add = TRUE)
      file.create(ready)

      client <- socketAccept(listener, blocking = TRUE, open = "r+b")
      on.exit(close(client), add = TRUE)

      request_headers <- character()
      repeat {
        line <- readLines(client, n = 1L, warn = FALSE)
        if (!length(line) || !nzchar(line)) {
          break
        }
        request_headers <- c(request_headers, line)
      }
      length_line <- grep(
        "^content-length: ",
        request_headers,
        value = TRUE,
        ignore.case = TRUE
      )
      if (length(length_line)) {
        readBin(
          client,
          "raw",
          as.integer(sub(".*: ", "", length_line[[1L]]))
        )
      }

      header <- paste0(
        "HTTP/1.1 200 OK\r\n",
        "Content-Type: ",
        content_type,
        "\r\n",
        "Content-Length: ",
        nchar(body, type = "bytes"),
        "\r\n",
        "Connection: close\r\n\r\n"
      )
      if (identical(scenario, "slow_headers")) {
        Sys.sleep(delay_seconds)
      }
      writeBin(charToRaw(header), client)
      flush(client)
      if (identical(scenario, "slow_body")) {
        Sys.sleep(delay_seconds)
      }
      writeBin(charToRaw(body), client)
      flush(client)
    },
    args = list(
      port = port,
      ready = ready,
      scenario = scenario,
      delay_seconds = delay_seconds,
      body = body,
      content_type = content_type
    ),
    supervise = TRUE
  )

  deadline <- Sys.time() + 5
  while (!file.exists(ready) && server$is_alive() && Sys.time() < deadline) {
    Sys.sleep(0.02)
  }
  if (!file.exists(ready)) {
    server$kill()
    stop("Loopback fixture did not start")
  }

  list(server = server, port = port, ready = ready)
}

await_promise <- function(promise, timeout_seconds) {
  value <- NULL
  error <- NULL
  done <- FALSE

  promises::then(
    promise,
    onFulfilled = function(result) {
      value <<- result
      done <<- TRUE
    },
    onRejected = function(condition) {
      error <<- condition
      done <<- TRUE
    }
  )

  deadline <- Sys.time() + timeout_seconds
  while (!done && Sys.time() < deadline) {
    later::run_now(0.05)
  }
  if (!done) {
    stop("Timed out waiting for asynchronous response")
  }
  if (!is.null(error)) {
    stop(error)
  }
  value
}

run_case <- function(method, scenario) {
  protocol <- if (identical(method, "ellmer_chat_async")) "json" else "sse"
  fixture <- start_fixture(scenario, delay_seconds, protocol)
  on.exit(
    {
      if (fixture$server$is_alive()) {
        fixture$server$kill()
      }
      unlink(fixture$ready)
    },
    add = TRUE
  )

  chat <- ellmer::chat_openai_compatible(
    base_url = paste0("http://127.0.0.1:", fixture$port),
    model = "gpt-4o-mini",
    credentials = function() "loopback-fixture",
    echo = "none"
  )
  agent <- if (method %in% c("stream_async", "chat_async")) {
    deputy::Agent$new(chat = chat)
  } else {
    NULL
  }

  done <- FALSE
  ticks <- numeric()
  start <- proc.time()[["elapsed"]]
  tick <- function() {
    ticks <<- c(ticks, proc.time()[["elapsed"]] - start)
    if (!done) later::later(tick, 0.1)
  }
  later::later(tick, 0.1)

  if (identical(method, "stream_async")) {
    stream <- agent$stream_async("Say ok", stream = "text")
    value <- await_promise(coro::async_collect(stream), timeout_seconds)
    chunks <- unlist(value, use.names = FALSE)
    # The qualification assertion is deliberately exact: the stream must
    # deliver the model text and the terminating newline as separate chunks.
    stopifnot(identical(chunks, c("ok", "\n")))
    reply <- paste0(chunks, collapse = "")
    stopifnot(identical(reply, "ok\n"))
    run <- await_promise(deputy::stream_result(stream), timeout_seconds)
  } else if (identical(method, "chat_async")) {
    value <- await_promise(agent$chat_async("Say ok"), timeout_seconds)
    reply <- as.character(value)
    stopifnot(identical(reply, "ok\n"))
    run <- agent$last_run()
  } else if (identical(method, "ellmer_chat_async")) {
    value <- await_promise(chat$chat_async("Say ok"), timeout_seconds)
    reply <- as.character(value)
    # This is the nonstreaming ellmer control: the JSON response is consumed
    # through Chat$chat_async(), without Deputy governance.
    stopifnot(identical(reply, "ok"))
    run <- NULL
  } else {
    stop("Unknown method: ", method)
  }

  if (!is.null(run)) {
    stopifnot(S7::S7_inherits(run, deputy::AgentResult))
  }
  done <- TRUE
  elapsed <- proc.time()[["elapsed"]] - start
  max_gap <- max(diff(c(0, ticks, elapsed)))

  cat(
    paste(
      method,
      scenario,
      protocol,
      encodeString(reply),
      sum(ticks < 1.9),
      sprintf("%.2f", max_gap),
      sprintf("%.2f", elapsed),
      sep = "\t"
    ),
    "\n"
  )
  invisible(list(
    method = method,
    scenario = scenario,
    protocol = protocol,
    reply = reply,
    ticks_before_1_9 = sum(ticks < 1.9),
    max_event_loop_gap = max_gap,
    elapsed = elapsed
  ))
}

for (scenario in c("slow_body", "slow_headers")) {
  run_case("stream_async", scenario)
  run_case("chat_async", scenario)
  run_case("ellmer_chat_async", scenario)
}
