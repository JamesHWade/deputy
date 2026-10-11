# A Stop hook may send an answered run on with HookResultStop(). The same run
# asks the model again: same run id, same limits, same usage, same stream.

# A mock chat whose stream_async plays the next reply on each call and records
# each prompt the model was asked. A reply that is a condition makes that
# call's stream fail.
scripted_stop_chat <- function(replies) {
  chat <- create_mock_chat(responses = list("unused"))
  asked <- list()
  chat$stream_async <- function(prompt, stream = "content", controller = NULL) {
    asked[[length(asked) + 1L]] <<- prompt
    reply <- replies[[min(length(asked), length(replies))]]
    coro::async_generator(function() {
      if (inherits(reply, "condition")) {
        stop(reply)
      }
      coro::yield(reply)
    })()
  }
  list(chat = chat, asked = function() asked)
}

test_that("a Stop hook that returns HookResultStop sends the run on, in the same run", {
  scripted <- scripted_stop_chat(list("First answer.", "Second answer."))
  agent <- Agent$new(chat = scripted$chat)
  agent$hooks$add(HookMatcher(
    event = "Stop",
    timeout = 0,
    callback = function(reason, context, ...) {
      if (isTRUE(context$stop_hook_active)) {
        return(NULL)
      }
      HookResultStop("Fix the table.")
    }
  ))

  events <- collect_agent_events(agent$run("Make a table."))
  result <- agent$last_run()

  expect_length(scripted$asked(), 2L)
  expect_identical(scripted$asked()[[2L]], "Fix the table.")
  types <- vapply(events, function(event) event$type, character(1L))
  expect_identical(sum(types == "start"), 1L)
  expect_identical(sum(types == "stop"), 1L)
  run_ids <- unique(vapply(events, function(event) event$run_id, character(1L)))
  expect_identical(run_ids, result$run_id)
  expect_identical(result$stop_reason, "complete")
  expect_s7_class(result$ending, RunEndingAnswered)
  expect_identical(result$response, "Second answer.")
  expect_identical(result$usage$requests, 2L)
})

test_that("Stop fires at every stop and says when a hook already sent the run on", {
  scripted <- scripted_stop_chat(list("First answer.", "Second answer."))
  agent <- Agent$new(chat = scripted$chat)
  seen <- logical()
  agent$hooks$add(HookMatcher(
    event = "Stop",
    timeout = 0,
    callback = function(reason, context, ...) {
      seen <<- c(seen, context$stop_hook_active)
      if (isTRUE(context$stop_hook_active)) {
        return(NULL)
      }
      HookResultStop("Fix the table.")
    }
  ))

  agent$run_sync("Make a table.")

  expect_identical(seen, c(FALSE, TRUE))
})

test_that("SessionEnd fires once, after the last stop", {
  scripted <- scripted_stop_chat(list("First answer.", "Second answer."))
  agent <- Agent$new(chat = scripted$chat)
  log <- character()
  note <- function(x) log <<- c(log, x)
  agent$hooks$add(HookMatcher(
    event = "Stop",
    timeout = 0,
    callback = function(reason, context, ...) {
      note("Stop")
      if (isTRUE(context$stop_hook_active)) {
        return(NULL)
      }
      HookResultStop("Fix the table.")
    }
  ))
  agent$hooks$add(HookMatcher(
    event = "SessionEnd",
    timeout = 0,
    callback = function(reason, context, ...) {
      note("SessionEnd")
      NULL
    }
  ))

  agent$run_sync("Make a table.")

  expect_identical(log, c("Stop", "Stop", "SessionEnd"))
})

test_that("the stream carries every pass", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  scripted <- scripted_stop_chat(list("First answer.", "Second answer."))
  agent <- Agent$new(chat = scripted$chat)
  agent$hooks$add(HookMatcher(
    event = "Stop",
    timeout = 0,
    callback = function(reason, context, ...) {
      if (isTRUE(context$stop_hook_active)) {
        return(NULL)
      }
      HookResultStop("Fix the table.")
    }
  ))

  chunks <- collect_async_stream(agent$stream_async("Make a table."))

  expect_identical(unlist(chunks), c("First answer.", "Second answer."))
})

test_that("a run that is sent on keeps its limits", {
  scripted <- scripted_stop_chat(list("First answer.", "Second answer."))
  agent <- Agent$new(
    chat = scripted$chat,
    usage_limits = UsageLimits(max_requests = 1)
  )
  agent$hooks$add(HookMatcher(
    event = "Stop",
    timeout = 0,
    callback = function(reason, context, ...) {
      HookResultStop("Fix the table.")
    }
  ))

  result <- agent$run_sync("Make a table.")

  expect_length(scripted$asked(), 1L)
  expect_identical(result$stop_reason, "request_limit")
  expect_s7_class(result$ending, RunEndingLimit)
})

test_that("a Stop hook cannot send on a run that was stopped", {
  scripted <- scripted_stop_chat(list("First answer.", "Second answer."))
  agent <- Agent$new(chat = scripted$chat)
  agent$hooks$add(HookMatcher(
    event = "Stop",
    timeout = 0,
    callback = function(reason, context, ...) {
      HookResultStop("more")
    }
  ))

  generator <- agent$run("Make a table.")
  expect_identical(generator()$type, "start")
  expect_true(agent$interrupt("stop now"))
  collect_agent_events(generator)
  result <- agent$last_run()

  expect_length(scripted$asked(), 1L)
  expect_identical(result$stop_reason, "stop now")
  expect_s7_class(result$ending, RunEndingStopped)
  expect_identical(result$ending@by, "caller")
})

test_that("an interrupt while a Stop hook is pending wins over its answer", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  scripted <- scripted_stop_chat(list("First answer.", "Second answer."))
  agent <- Agent$new(chat = scripted$chat)
  agent$hooks$add(HookMatcher(
    event = "Stop",
    timeout = 0,
    callback = function(reason, context, ...) {
      # The timer starts with the hook, so the interrupt lands in its wait:
      # the first pass alone takes longer than 0.05 s to reach the model.
      later::later(function() agent$interrupt("stop now"), 0.05)
      later_value(HookResultStop("more"), 0.2)
    }
  ))

  collect_async_stream(agent$stream_async("Make a table."))
  result <- agent$last_run()

  expect_length(scripted$asked(), 1L)
  expect_identical(result$stop_reason, "stop now")
  expect_s7_class(result$ending, RunEndingStopped)
  expect_identical(result$ending@by, "caller")
})

test_that("run_sync() follows a Stop hook that sends the run on", {
  scripted <- scripted_stop_chat(list("First answer.", "Second answer."))
  agent <- Agent$new(chat = scripted$chat)
  agent$hooks$add(HookMatcher(
    event = "Stop",
    timeout = 0,
    callback = function(reason, context, ...) {
      if (isTRUE(context$stop_hook_active)) {
        return(NULL)
      }
      HookResultStop("Fix the table.")
    }
  ))

  result <- agent$run_sync("Make a table.")

  expect_identical(scripted$asked()[[2L]], "Fix the table.")
  expect_identical(result$response, "Second answer.")
  expect_identical(result$stop_reason, "complete")
  expect_identical(result$usage$requests, 2L)
})

test_that("a second pass that fails ends the run failed and fires Stop once more", {
  scripted <- scripted_stop_chat(list(
    "First answer.",
    simpleError("second pass failed")
  ))
  agent <- Agent$new(chat = scripted$chat)
  stops <- 0L
  session_ends <- 0L
  ending <- NULL
  agent$hooks$add(HookMatcher(
    event = "Stop",
    timeout = 0,
    callback = function(reason, context, ...) {
      stops <<- stops + 1L
      if (isTRUE(context$stop_hook_active)) {
        return(NULL)
      }
      HookResultStop("Fix the table.")
    }
  ))
  agent$hooks$add(HookMatcher(
    event = "SessionEnd",
    timeout = 0,
    callback = function(reason, context, ...) {
      session_ends <<- session_ends + 1L
      ending <<- context$ending
      NULL
    }
  ))

  expect_error(agent$run_sync("Make a table."), "second pass failed")

  expect_identical(stops, 2L)
  expect_identical(session_ends, 1L)
  expect_s7_class(ending, RunEndingFailed)
})

test_that("a run sent on asks the provider again with the hook's message", {
  server <- local_runtime_server(list(
    runtime_reply("First answer."),
    runtime_reply("Second answer.")
  ))
  agent <- Agent$new(runtime_chat(server))
  agent$hooks$add(HookMatcher(
    event = "Stop",
    timeout = 0,
    callback = function(reason, context, ...) {
      if (isTRUE(context$stop_hook_active)) {
        return(NULL)
      }
      HookResultStop("Fix the table.")
    }
  ))

  result <- agent$run_sync("Make a table.")

  requests <- server$requests()
  expect_length(requests, 2L)
  messages <- requests[[2L]]$body$messages
  users <- Filter(function(message) identical(message$role, "user"), messages)
  last_user <- paste(unlist(users[[length(users)]]$content), collapse = "")
  expect_match(last_user, "Fix the table.", fixed = TRUE)
  expect_identical(trimws(result$response), "Second answer.")
})
