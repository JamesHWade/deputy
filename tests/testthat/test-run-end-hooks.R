# Stop and SessionEnd fire from the run's body and wait for a promise. A run
# that ends with an error, an abandoned stream and a delegate batch fire them
# without waiting, as before.

# A mock chat whose stream yields `text`, with a last turn to report.
run_end_chat <- function(text = "done") {
  chat <- create_mock_chat(responses = list(text))
  chat$stream_async <- function(prompt, stream = "content", controller = NULL) {
    coro::async_generator(function() {
      coro::yield(text)
    })()
  }
  chat
}

# A hook callback that resolves `value` after `seconds` on the event loop.
delayed_hook <- function(note, label, seconds = 0.05, value = NULL) {
  function(reason, context, ...) {
    promises::promise(function(resolve, reject) {
      later::later(
        function() {
          note(label)
          resolve(value)
        },
        seconds
      )
    })
  }
}

test_that("Stop and SessionEnd fire once each, in order, with the reason, usage and ending", {
  log <- character()
  note <- function(x) log <<- c(log, x)
  seen <- list()
  agent <- Agent$new(chat = create_mock_chat(responses = list("Response")))
  agent$hooks$add(HookMatcher(
    event = "Stop",
    timeout = 0,
    callback = function(reason, context, ...) {
      note("Stop")
      seen$Stop <<- list(reason = reason, context = context)
      NULL
    }
  ))
  agent$hooks$add(HookMatcher(
    event = "SessionEnd",
    timeout = 0,
    callback = function(reason, context, ...) {
      note("SessionEnd")
      seen$SessionEnd <<- list(reason = reason, context = context)
      NULL
    }
  ))

  result <- agent$run_sync("Test task")

  expect_identical(log, c("Stop", "SessionEnd"))
  expect_identical(seen$Stop$reason, "complete")
  expect_identical(seen$SessionEnd$reason, "complete")
  expect_s7_class(seen$Stop$context$usage, AgentUsage)
  expect_identical(seen$Stop$context$ending, result$ending)
  expect_identical(seen$SessionEnd$context$ending, result$ending)
  expect_false(seen$Stop$context$stop_hook_active)
})

test_that("a stream waits for a Stop hook's promise before it ends", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  log <- character()
  note <- function(x) log <<- c(log, x)
  agent <- Agent$new(chat = run_end_chat())
  during <- list(ran = FALSE, last_run = list("unset"))
  agent$hooks$add(HookMatcher(
    event = "Stop",
    timeout = 0,
    callback = function(reason, context, ...) {
      # Read the run's last result while the hook's promise is pending.
      later::later(
        function() {
          during$ran <<- TRUE
          during$last_run <<- list(agent$last_run())
        },
        0.02
      )
      delayed_hook(note, "hook")(reason, context)
    }
  ))

  stream <- agent$stream_async("go")
  collect_async_stream(stream)
  note("stream")

  expect_identical(log, c("hook", "stream"))
  expect_true(during$ran)
  expect_null(during$last_run[[1L]])
  expect_identical(agent$last_run()$stop_reason, "complete")
})

test_that("a stream waits for a SessionEnd hook's promise before it ends", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  log <- character()
  note <- function(x) log <<- c(log, x)
  agent <- Agent$new(chat = run_end_chat())
  agent$hooks$add(HookMatcher(
    event = "SessionEnd",
    timeout = 0,
    callback = delayed_hook(note, "hook")
  ))

  stream <- agent$stream_async("go")
  collect_async_stream(stream)
  note("stream")

  expect_identical(log, c("hook", "stream"))
  expect_identical(agent$last_run()$stop_reason, "complete")
})

test_that("run_sync() waits for a Stop hook's promise", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  log <- character()
  note <- function(x) log <<- c(log, x)
  agent <- Agent$new(chat = run_end_chat())
  agent$hooks$add(HookMatcher(
    event = "Stop",
    timeout = 0,
    callback = delayed_hook(note, "hook")
  ))

  result <- agent$run_sync("go")
  note("returned")

  expect_identical(log, c("hook", "returned"))
  expect_identical(result$stop_reason, "complete")
})

test_that("an interrupt while a Stop hook is pending ends the run stopped", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  reasons <- list()
  agent <- Agent$new(chat = run_end_chat())
  agent$hooks$add(HookMatcher(
    event = "Stop",
    timeout = 0,
    callback = delayed_hook(function(x) NULL, "hook", seconds = 0.2)
  ))
  agent$hooks$add(HookMatcher(
    event = "SessionEnd",
    timeout = 0,
    callback = function(reason, context, ...) {
      reasons$SessionEnd <<- reason
      NULL
    }
  ))
  later::later(function() agent$interrupt("stop now"), 0.05)

  stream <- agent$stream_async("go")
  collect_async_stream(stream)
  result <- agent$last_run()

  expect_identical(result$stop_reason, "stop now")
  expect_s7_class(result$ending, RunEndingStopped)
  expect_identical(result$ending@by, "caller")
  expect_identical(reasons$SessionEnd, "stop now")
})

test_that("a Stop hook whose promise does not settle in time lets the run end", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  agent <- Agent$new(chat = run_end_chat())
  agent$hooks$add(HookMatcher(
    event = "Stop",
    timeout = 0,
    promise_timeout = 0.05,
    callback = function(reason, context, ...) {
      promises::promise(function(resolve, reject) NULL)
    }
  ))

  result <- NULL
  expect_message(
    result <- resolve_async_value(agent$run_async("go")),
    "Stop hook failed"
  )

  expect_identical(result$stop_reason, "complete")
  errors <- agent$hooks$last_errors()
  expect_length(errors, 1L)
  expect_match(errors[[1L]]$error, "did not settle")
})

test_that("a run that errors fires Stop and SessionEnd once, without waiting", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  log <- character()
  note <- function(x) log <<- c(log, x)
  chat <- create_mock_chat()
  chat$stream_async <- function(prompt, stream = "content", controller = NULL) {
    coro::async_generator(function() {
      stop("stream failed")
      coro::yield("unreachable")
    })()
  }
  agent <- Agent$new(chat = chat)
  resolved <- list(Stop = FALSE, SessionEnd = FALSE)
  for (event in c("Stop", "SessionEnd")) {
    local({
      name <- event
      agent$hooks$add(HookMatcher(
        event = name,
        timeout = 0,
        callback = function(reason, context, ...) {
          note(name)
          promises::promise(function(resolve, reject) {
            later::later(
              function() {
                resolved[[name]] <<- TRUE
                resolve(NULL)
              },
              0.2
            )
          })
        }
      ))
    })
  }

  error <- tryCatch(
    resolve_async_value(agent$run_async("go")),
    error = identity
  )

  expect_match(conditionMessage(error), "stream failed")
  expect_identical(log, c("Stop", "SessionEnd"))
  expect_false(resolved$Stop)
  expect_false(resolved$SessionEnd)
})

test_that("an abandoned stream still fires Stop and SessionEnd", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  counts <- c(Stop = 0L, SessionEnd = 0L)
  mock_chat <- create_mock_chat()
  mock_chat$stream_async <- function(
    prompt,
    stream = "content",
    controller = NULL
  ) {
    coro::async_generator(function() {
      coro::yield("first")
      coro::yield("second")
    })()
  }
  agent <- Agent$new(chat = mock_chat)
  for (event in c("Stop", "SessionEnd")) {
    local({
      name <- event
      agent$hooks$add(HookMatcher(
        event = name,
        timeout = 0,
        callback = function(reason, context, ...) {
          counts[[name]] <<- counts[[name]] + 1L
          NULL
        }
      ))
    })
  }
  stream <- agent$stream_async("test")
  expect_equal(resolve_async_value(stream()), "first")
  stream <- NULL
  invisible(gc())
  later::run_now(0.01)

  expect_identical(counts, c(Stop = 1L, SessionEnd = 1L))
  expect_false(agent$.__enclos_env__$private$run_active)
})

test_that("a delegate batch fires Stop and SessionEnd once each, in order", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  state <- new.env(parent = emptyenv())
  state$hold_a_until_b <- FALSE
  lead <- parallel_test_lead(state)
  log <- character()
  for (event in c("Stop", "SessionEnd")) {
    local({
      name <- event
      lead$add_hook(HookMatcher(
        event = name,
        timeout = 0,
        callback = function(reason, context, ...) {
          log <<- c(log, name)
          NULL
        }
      ))
    })
  }

  batch <- resolve_async_value(lead$parallel_delegate_async(c(
    a = "first",
    b = "second"
  )))

  expect_identical(batch$status, c(a = "completed", b = "completed"))
  expect_identical(log, c("Stop", "SessionEnd"))
})

test_that("the approaching-cost warning is given once", {
  mock_chat <- create_mock_chat(responses = list("Response"))
  mock_chat$stream <- function(prompt = NULL) {
    yielded <- FALSE
    function() {
      if (yielded) {
        return(coro::exhausted())
      }
      yielded <<- TRUE
      "Response"
    }
  }
  mock_chat$last_turn <- function(role = "assistant") {
    create_mock_assistant_turn(text = "Response")
  }
  token_reads <- 0L
  mock_chat$get_tokens <- function() {
    token_reads <<- token_reads + 1L
    if (token_reads == 1L) {
      return(data.frame(input = 0, output = 0, cached_input = 0, cost = 0))
    }
    data.frame(input = 1000, output = 500, cached_input = 0, cost = 0.95)
  }
  agent <- Agent$new(
    chat = mock_chat,
    usage_limits = UsageLimits(max_cost_usd = 1.00)
  )
  stops <- 0L
  agent$hooks$add(HookMatcher(
    event = "Stop",
    timeout = 0,
    callback = function(reason, context, ...) {
      stops <<- stops + 1L
      NULL
    }
  ))
  notices <- character()
  agent$hooks$add(HookMatcher(
    event = "Notification",
    timeout = 0,
    callback = function(message, context, ...) {
      if (identical(context$code, "cost_limit_warning")) {
        notices <<- c(notices, message)
      }
      NULL
    }
  ))

  warnings_raised <- character()
  withCallingHandlers(
    agent$run_sync("Test task"),
    warning = function(w) {
      warnings_raised <<- c(warnings_raised, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )

  expect_length(grep("cost limit", warnings_raised), 1L)
  expect_length(notices, 1L)
  expect_identical(stops, 1L)
})

test_that("Stop and SessionEnd hooks that return plain values see the same order of events as before", {
  agent <- Agent$new(chat = create_mock_chat(responses = list("Response")))
  for (event in c("Stop", "SessionEnd")) {
    local({
      name <- event
      agent$hooks$add(HookMatcher(
        event = name,
        timeout = 0,
        callback = function(reason, context, ...) NULL
      ))
    })
  }

  result <- agent$run_sync("Test task")
  types <- vapply(result$events, function(event) event$type, character(1))
  hooks <- which(types == "hook")
  usage <- which(types == "usage")
  stop_event <- which(types == "stop")

  expect_length(hooks, 2L)
  expect_true(all(hooks < min(usage)))
  expect_true(all(hooks < min(stop_event)))
  expect_identical(
    vapply(result$events[hooks], function(event) event$hook, character(1)),
    c("Stop", "SessionEnd")
  )
})
