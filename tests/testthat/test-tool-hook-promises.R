test_that("an interrupt while a PermissionRequest hook is pending keeps the call denied", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  sandbox <- withr::local_tempdir(pattern = "deputy-promise-interrupt-")
  root <- file.path(sandbox, "root")
  outside <- file.path(sandbox, "outside")
  dir.create(root)
  dir.create(outside)
  target <- file.path(normalizePath(outside, mustWork = TRUE), "approved.txt")

  server <- local_runtime_server(list(
    runtime_reply(
      tool = "write_file",
      arguments = list(path = target, content = "approved")
    ),
    runtime_reply("done")
  ))
  agent <- Agent$new(
    runtime_chat(server),
    tools = list(tool_write_file),
    permissions = permissions_standard(root),
    working_dir = root
  )
  agent$add_hook(HookMatcher(
    "PermissionRequest",
    function(tool_name, tool_input, permission_result, context) {
      # The caller stops the run while the approval is still being decided.
      later::later(function() agent$interrupt("stop now"), 0.05)
      later_value(PermissionResultAllow(), 0.3)
    }
  ))
  result <- suppressWarnings(resolve_async_value(
    agent$run_async("Write outside the root with approval."),
    max_polls = 500L
  ))

  expect_false(file.exists(target))
  expect_identical(result$stop_reason, "stop now")
  expect_length(server$requests(), 1L)
})

test_that("a tool waits for a PreToolUse hook's promise", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  server <- local_runtime_server(list(
    runtime_reply(tool = "probe", arguments = list()),
    runtime_reply("final answer")
  ))
  agent <- Agent$new(runtime_chat(server), permissions = permissions_full())
  log <- character()
  agent$register_tool(ellmer::tool(
    function() {
      log <<- c(log, "tool")
      "probed"
    },
    name = "probe",
    description = "Probe."
  ))
  agent$add_hook(HookMatcher(
    event = "PreToolUse",
    callback = function(tool_name, tool_input, context) {
      promises::then(later_value(NULL, 0.1), function(value) {
        log <<- c(log, "hook")
        value
      })
    }
  ))

  result <- resolve_async_value(agent$run_async("task"), max_polls = 500L)

  expect_identical(log, c("hook", "tool"))
  expect_identical(trimws(result$response), "final answer")
})

test_that("a PreToolUse hook's promised denial rejects the call", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  server <- local_runtime_server(list(
    runtime_reply(tool = "probe", arguments = list()),
    runtime_reply("final answer")
  ))
  agent <- Agent$new(runtime_chat(server), permissions = permissions_full())
  ran <- FALSE
  agent$register_tool(ellmer::tool(
    function() {
      ran <<- TRUE
      "probed"
    },
    name = "probe",
    description = "Probe."
  ))
  agent$add_hook(HookMatcher(
    event = "PreToolUse",
    callback = function(tool_name, tool_input, context) {
      later_value(
        HookResultPreToolUse(permission = "deny", reason = "no"),
        0.1
      )
    }
  ))

  # ellmer warns that the rejected call failed; that warning is the point here.
  result <- suppressWarnings(resolve_async_value(
    agent$run_async("task"),
    max_polls = 500L
  ))

  expect_false(ran)
  expect_identical(result$stop_reason, "complete")
  permissions <- Filter(
    function(event) identical(event$type, "permission"),
    agent$last_run()$events
  )
  expect_identical(permissions[[1]]$decision, "deny")
})

test_that("a PreToolUse hook's promised stop stops the run", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  server <- local_runtime_server(list(
    runtime_reply(tool = "probe", arguments = list()),
    runtime_reply("final answer")
  ))
  agent <- Agent$new(runtime_chat(server), permissions = permissions_full())
  ran <- FALSE
  agent$register_tool(ellmer::tool(
    function() {
      ran <<- TRUE
      "probed"
    },
    name = "probe",
    description = "Probe."
  ))
  agent$add_hook(HookMatcher(
    event = "PreToolUse",
    callback = function(tool_name, tool_input, context) {
      later_value(
        HookResultPreToolUse(
          permission = "deny",
          reason = "Critical security violation",
          continue = FALSE
        ),
        0.1
      )
    }
  ))

  result <- suppressWarnings(resolve_async_value(
    agent$run_async("task"),
    max_polls = 500L
  ))

  expect_false(ran)
  expect_identical(result$stop_reason, "hook_requested_stop")
  expect_length(server$requests(), 1L)
})

test_that("a PreToolUse hook whose promise rejects or times out denies the call", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  run_with_hook <- function(hook_promise, promise_timeout = 60) {
    server <- local_runtime_server(list(
      runtime_reply(tool = "probe", arguments = list()),
      runtime_reply("final answer")
    ))
    agent <- Agent$new(runtime_chat(server), permissions = permissions_full())
    ran <- FALSE
    agent$register_tool(ellmer::tool(
      function() {
        ran <<- TRUE
        "probed"
      },
      name = "probe",
      description = "Probe."
    ))
    agent$add_hook(HookMatcher(
      event = "PreToolUse",
      promise_timeout = promise_timeout,
      callback = function(tool_name, tool_input, context) hook_promise
    ))
    result <- suppressWarnings(resolve_async_value(
      agent$run_async("task"),
      max_polls = 500L
    ))
    list(agent = agent, result = result, ran = ran)
  }

  rejected <- run_with_hook(promises::promise(function(resolve, reject) {
    later::later(function() reject(simpleError("hook broke")), 0.05)
  }))
  expect_false(rejected$ran)
  expect_identical(rejected$result$stop_reason, "complete")
  expect_identical(
    Filter(
      function(event) identical(event$type, "permission"),
      rejected$agent$last_run()$events
    )[[1]]$decision,
    "deny"
  )
  expect_match(rejected$agent$hooks$last_errors()[[1]]$error, "hook broke")

  timed_out <- run_with_hook(
    later_value(NULL, 0.5),
    promise_timeout = 0.05
  )
  expect_false(timed_out$ran)
  expect_identical(
    Filter(
      function(event) identical(event$type, "permission"),
      timed_out$agent$last_run()$events
    )[[1]]$decision,
    "deny"
  )
  expect_length(timed_out$agent$hooks$last_errors(), 1L)
})

test_that("an interrupt while a PreToolUse hook is pending keeps the tool from running", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  server <- local_runtime_server(list(
    runtime_reply(tool = "probe", arguments = list()),
    runtime_reply("final answer")
  ))
  agent <- Agent$new(runtime_chat(server), permissions = permissions_full())
  ran <- FALSE
  agent$register_tool(ellmer::tool(
    function() {
      ran <<- TRUE
      "probed"
    },
    name = "probe",
    description = "Probe."
  ))
  agent$add_hook(HookMatcher(
    event = "PreToolUse",
    callback = function(tool_name, tool_input, context) later_value(NULL, 0.2)
  ))
  later::later(function() agent$interrupt("user_cancelled"), 0.05)

  result <- suppressWarnings(resolve_async_value(
    agent$run_async("task"),
    max_polls = 500L
  ))

  expect_false(ran)
  expect_identical(result$stop_reason, "user_cancelled")
})

test_that("a PermissionRequest hook's promised allow lets a denied call through", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  sandbox <- withr::local_tempdir(pattern = "deputy-promise-allow-")
  root <- file.path(sandbox, "root")
  outside <- file.path(sandbox, "outside")
  dir.create(root)
  dir.create(outside)
  target <- file.path(normalizePath(outside, mustWork = TRUE), "approved.txt")

  server <- local_runtime_server(list(
    runtime_reply(
      tool = "write_file",
      arguments = list(path = target, content = "approved")
    ),
    runtime_reply("done")
  ))
  agent <- Agent$new(
    runtime_chat(server),
    tools = list(tool_write_file),
    permissions = permissions_standard(root),
    working_dir = root
  )
  agent$add_hook(HookMatcher(
    "PermissionRequest",
    function(tool_name, tool_input, permission_result, context) {
      later_value(PermissionResultAllow(), 0.1)
    }
  ))
  suppressWarnings(resolve_async_value(
    agent$run_async("Write outside the root with approval."),
    max_polls = 500L
  ))

  expect_null(runtime_events(agent, "tool_end")[[1]]$tool_error)
  expect_identical(readLines(target), "approved")
})

test_that("a PermissionRequest hook whose promise does not settle in time leaves the call denied", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  sandbox <- withr::local_tempdir(pattern = "deputy-promise-timeout-")
  root <- file.path(sandbox, "root")
  outside <- file.path(sandbox, "outside")
  dir.create(root)
  dir.create(outside)
  target <- file.path(normalizePath(outside, mustWork = TRUE), "approved.txt")

  server <- local_runtime_server(list(
    runtime_reply(
      tool = "write_file",
      arguments = list(path = target, content = "approved")
    ),
    runtime_reply("done")
  ))
  agent <- Agent$new(
    runtime_chat(server),
    tools = list(tool_write_file),
    permissions = permissions_standard(root),
    working_dir = root
  )
  agent$add_hook(HookMatcher(
    "PermissionRequest",
    function(tool_name, tool_input, permission_result, context) {
      promises::promise(function(resolve, reject) NULL)
    },
    promise_timeout = 0.05
  ))
  suppressWarnings(resolve_async_value(
    agent$run_async("Write outside the root with approval."),
    max_polls = 500L
  ))

  expect_false(file.exists(target))
  expect_match(
    agent$hooks$last_errors()[[1]]$error,
    "did not settle within 0.05 seconds"
  )
})

test_that("plain-value tool hooks keep the tool events in order", {
  server <- local_runtime_server(list(
    runtime_reply(tool = "probe", arguments = list()),
    runtime_reply("final answer")
  ))
  agent <- Agent$new(runtime_chat(server), permissions = permissions_full())
  agent$register_tool(ellmer::tool(
    function() "probed",
    name = "probe",
    description = "Probe."
  ))
  agent$add_hook(HookMatcher(
    event = "PreToolUse",
    callback = function(tool_name, tool_input, context) NULL
  ))
  agent$add_hook(HookMatcher(
    event = "PostToolUse",
    callback = function(tool_name, tool_result, tool_error, context) NULL
  ))

  agent$run_sync("task")

  types <- vapply(agent$last_run()$events, function(event) event$type, "")
  tool_types <- types[types %in% c("tool_start", "permission", "tool_end")]
  expect_identical(tool_types, c("tool_start", "permission", "tool_end"))
})

test_that("the next model request waits for a PostToolUse hook's promise", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  server <- local_runtime_server(list(
    runtime_reply(tool = "probe", arguments = list()),
    runtime_reply("final answer")
  ))
  agent <- Agent$new(runtime_chat(server), permissions = permissions_full())
  agent$register_tool(ellmer::tool(
    function() "probed",
    name = "probe",
    description = "Probe."
  ))
  seen <- integer()
  agent$add_hook(HookMatcher(
    event = "PostToolUse",
    callback = function(tool_name, tool_result, tool_error, context) {
      promises::then(later_value(NULL, 0.1), function(value) {
        seen <<- c(seen, length(server$requests()))
        value
      })
    }
  ))

  result <- resolve_async_value(agent$run_async("task"), max_polls = 500L)

  expect_identical(seen, 1L)
  expect_identical(trimws(result$response), "final answer")
})

test_that("an interrupt while a PostToolUse hook is pending ends the run before the next request", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  server <- local_runtime_server(list(
    runtime_reply(tool = "probe", arguments = list()),
    runtime_reply("final answer")
  ))
  agent <- Agent$new(runtime_chat(server), permissions = permissions_full())
  agent$register_tool(ellmer::tool(
    function() "probed",
    name = "probe",
    description = "Probe."
  ))
  agent$add_hook(HookMatcher(
    event = "PostToolUse",
    callback = function(tool_name, tool_result, tool_error, context) {
      later::later(function() agent$interrupt("enough"), 0.05)
      later_value(NULL, 0.3)
    }
  ))

  result <- resolve_async_value(agent$run_async("task"), max_polls = 500L)

  expect_length(server$requests(), 1L)
  expect_identical(result$stop_reason, "enough")
})

test_that("a PostToolUse hook's promised stop ends the run before the next request", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  server <- local_runtime_server(list(
    runtime_reply(tool = "probe", arguments = list()),
    runtime_reply("final answer")
  ))
  agent <- Agent$new(runtime_chat(server), permissions = permissions_full())
  agent$register_tool(ellmer::tool(
    function() "probed",
    name = "probe",
    description = "Probe."
  ))
  agent$add_hook(HookMatcher(
    event = "PostToolUse",
    callback = function(tool_name, tool_result, tool_error, context) {
      later_value(
        HookResultPostToolUse(continue = FALSE, stop_reason = "enough"),
        0.1
      )
    }
  ))

  result <- resolve_async_value(agent$run_async("task"), max_polls = 500L)

  expect_length(server$requests(), 1L)
  expect_identical(result$stop_reason, "enough")
})

test_that("a PostToolUse hook's promised output change reaches the tool_end event", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  server <- local_runtime_server(list(
    runtime_reply(tool = "probe", arguments = list()),
    runtime_reply("final answer")
  ))
  agent <- Agent$new(runtime_chat(server), permissions = permissions_full())
  agent$register_tool(ellmer::tool(
    function() "secret",
    name = "probe",
    description = "Probe."
  ))
  agent$add_hook(HookMatcher(
    event = "PostToolUse",
    callback = function(tool_name, tool_result, tool_error, context) {
      later_value(
        HookResultPostToolUse(updated_tool_output = "redacted"),
        0.1
      )
    }
  ))

  resolve_async_value(agent$run_async("task"), max_polls = 500L)

  expect_identical(
    runtime_events(agent, "tool_end")[[1]]$tool_result,
    "redacted"
  )
})

test_that("a PostToolUseFailure hook's promise is waited for before the next request", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  server <- local_runtime_server(list(
    runtime_reply(tool = "probe", arguments = list()),
    runtime_reply("final answer")
  ))
  agent <- Agent$new(runtime_chat(server), permissions = permissions_full())
  agent$register_tool(ellmer::tool(
    function() stop("probe broke"),
    name = "probe",
    description = "Probe."
  ))
  seen <- integer()
  agent$add_hook(HookMatcher(
    event = "PostToolUseFailure",
    callback = function(tool_name, tool_result, tool_error, context) {
      promises::then(later_value(NULL, 0.1), function(value) {
        seen <<- c(seen, length(server$requests()))
        value
      })
    }
  ))

  result <- suppressWarnings(resolve_async_value(
    agent$run_async("task"),
    max_polls = 500L
  ))

  expect_identical(seen, 1L)
  expect_identical(trimws(result$response), "final answer")
})

test_that("a PostToolUse hook that answers after its run failed changes nothing in the next run", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  callbacks <- new.env(parent = emptyenv())
  callbacks$request <- function(request) invisible(NULL)
  callbacks$result <- function(result) invisible(NULL)
  calls <- 0L
  chat <- create_mock_chat()
  chat$on_tool_request <- function(callback) callbacks$request <- callback
  chat$on_tool_result <- function(callback) callbacks$result <- callback
  chat$stream_async <- function(prompt, stream = "content", controller = NULL) {
    calls <<- calls + 1L
    if (calls == 1L) {
      # A tool call whose result is reported, then a stream that fails while
      # the hook's promise is still pending.
      return(coro::async_generator(function() {
        request <- ellmer::ContentToolRequest(
          id = "late-1",
          name = "read_file",
          arguments = list(path = "a.txt")
        )
        callbacks$request(request)
        callbacks$result(ellmer::ContentToolResult(
          value = "ok",
          request = request
        ))
        stop("stream failed")
      })())
    }
    # The next run is still going when the first run's hook answers.
    coro::async_generator(function() {
      coro::await(later_value(NULL, 0.3))
      coro::yield(ellmer::ContentText("second run done"))
    })()
  }
  agent <- Agent$new(chat = chat, permissions = permissions_full())
  hook_calls <- 0L
  agent$add_hook(HookMatcher(
    "PostToolUse",
    function(tool_name, tool_result, tool_error, context) {
      hook_calls <<- hook_calls + 1L
      later_value(
        HookResultPostToolUse(continue = FALSE, stop_reason = "late"),
        0.15
      )
    }
  ))

  expect_error(resolve_async_value(agent$run_async("first")), "stream failed")
  second <- resolve_async_value(agent$run_async("second"), max_polls = 300L)

  expect_identical(hook_calls, 1L)
  expect_identical(second$stop_reason, "complete")
  expect_identical(second$response, "second run done")
})

test_that("a stop that arrives while a PermissionRequest hook is pending wins over its allow", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  # A stream that does not end when the run is stopped: it waits for the
  # request callback as ellmer does, then runs the tool unless it was
  # rejected. So the run is still active when the hook answers.
  callbacks <- new.env(parent = emptyenv())
  callbacks$request <- function(request) invisible(NULL)
  ran <- FALSE
  rejection <- NULL
  chat <- create_mock_chat()
  chat$on_tool_request <- function(callback) callbacks$request <- callback
  chat$stream_async <- function(prompt, stream = "content", controller = NULL) {
    coro::async_generator(function() {
      request <- ellmer::ContentToolRequest(
        id = "pending-1",
        name = "unlisted_tool",
        arguments = list()
      )
      outcome <- tryCatch(
        {
          answered <- callbacks$request(request)
          if (promises::is.promising(answered)) {
            coro::await(answered)
          }
          NULL
        },
        ellmer_tool_reject = function(error) error
      )
      if (is.null(outcome)) {
        ran <<- TRUE
      } else {
        rejection <<- conditionMessage(outcome)
      }
      coro::yield(ellmer::ContentText("after the tool"))
    })()
  }
  agent <- Agent$new(chat = chat)
  asked <- 0L
  agent$add_hook(HookMatcher(
    "PermissionRequest",
    function(tool_name, tool_input, permission_result, context) {
      asked <<- asked + 1L
      later::later(function() agent$interrupt("stop now"), 0.05)
      later_value(PermissionResultAllow(), 0.3)
    }
  ))

  result <- resolve_async_value(agent$run_async("go"), max_polls = 300L)

  # The policy denied the call, so the hook was asked.
  expect_identical(asked, 1L)
  expect_false(ran)
  expect_match(rejection, "stopped")
  expect_identical(result$stop_reason, "stop now")
})

test_that("a PreToolUse hook that interrupts the run keeps the tool from running", {
  server <- local_runtime_server(list(
    runtime_reply(tool = "probe", arguments = list()),
    runtime_reply("final answer")
  ))
  agent <- Agent$new(runtime_chat(server), permissions = permissions_full())
  ran <- 0L
  agent$register_tool(ellmer::tool(
    function() {
      ran <<- ran + 1L
      "probed"
    },
    name = "probe",
    description = "Probe."
  ))
  # The hook answers at once, with a plain value, having stopped the run.
  agent$add_hook(HookMatcher(
    "PreToolUse",
    function(tool_name, tool_input, context) {
      agent$interrupt("stop now")
      NULL
    }
  ))

  result <- suppressWarnings(agent$run_sync("task"))

  expect_identical(ran, 0L)
  expect_identical(result$stop_reason, "stop now")
  expect_length(server$requests(), 1L)
})

test_that("a PermissionRequest hook that interrupts the run does not let its allow through", {
  sandbox <- withr::local_tempdir(pattern = "deputy-sync-interrupt-")
  root <- file.path(sandbox, "root")
  outside <- file.path(sandbox, "outside")
  dir.create(root)
  dir.create(outside)
  target <- file.path(normalizePath(outside, mustWork = TRUE), "approved.txt")

  server <- local_runtime_server(list(
    runtime_reply(
      tool = "write_file",
      arguments = list(path = target, content = "approved")
    ),
    runtime_reply("done")
  ))
  agent <- Agent$new(
    runtime_chat(server),
    tools = list(tool_write_file),
    permissions = permissions_standard(root),
    working_dir = root
  )
  agent$add_hook(HookMatcher(
    "PermissionRequest",
    function(tool_name, tool_input, permission_result, context) {
      agent$interrupt("stop now")
      PermissionResultAllow()
    }
  ))

  result <- suppressWarnings(agent$run_sync(
    "Write outside the root with approval."
  ))

  expect_false(file.exists(target))
  expect_identical(result$stop_reason, "stop now")
  expect_length(server$requests(), 1L)
})

test_that("a PreToolUse hook that asks to stop after its tool still lets the tool run", {
  server <- local_runtime_server(list(
    runtime_reply(tool = "probe", arguments = list()),
    runtime_reply("final answer")
  ))
  agent <- Agent$new(runtime_chat(server), permissions = permissions_full())
  ran <- 0L
  agent$register_tool(ellmer::tool(
    function() {
      ran <<- ran + 1L
      "probed"
    },
    name = "probe",
    description = "Probe."
  ))
  agent$add_hook(HookMatcher(
    "PreToolUse",
    function(tool_name, tool_input, context) {
      HookResultPreToolUse(
        "allow",
        continue = FALSE,
        stop_reason = "last one"
      )
    }
  ))

  result <- suppressWarnings(agent$run_sync("task"))

  expect_identical(ran, 1L)
  expect_identical(result$stop_reason, "last one")
})

test_that("a tool asked for after the run was stopped does not run", {
  server <- local_runtime_server(list(
    runtime_reply(tool = "probe", arguments = list()),
    runtime_reply("final answer")
  ))
  agent <- Agent$new(runtime_chat(server), permissions = permissions_full())
  ran <- 0L
  agent$register_tool(ellmer::tool(
    function() {
      ran <<- ran + 1L
      "probed"
    },
    name = "probe",
    description = "Probe."
  ))
  asked <- character()
  agent$add_hook(HookMatcher(
    "PreToolUse",
    function(tool_name, tool_input, context) {
      asked <<- c(asked, tool_name)
      NULL
    }
  ))
  # The response that asks for the tool has arrived; the host stops the run.
  agent$add_hook(HookMatcher(
    "PostModelRequest",
    function(context) {
      agent$interrupt("over budget")
      NULL
    }
  ))

  result <- suppressWarnings(agent$run_sync("task"))

  expect_identical(ran, 0L)
  expect_identical(asked, character())
  expect_identical(result$stop_reason, "over budget")
  expect_length(server$requests(), 1L)
})

test_that("a permission callback that interrupts the run keeps the tool from running", {
  server <- local_runtime_server(list(
    runtime_reply(tool = "probe", arguments = list()),
    runtime_reply("final answer")
  ))
  ran <- 0L
  agent <- NULL
  agent <- Agent$new(
    runtime_chat(server),
    permissions = Permissions(
      web = TRUE,
      can_use_tool = function(tool_name, tool_input, context) {
        agent$interrupt("stop now")
        PermissionResultAllow()
      }
    )
  )
  agent$register_tool(ellmer::tool(
    function() {
      ran <<- ran + 1L
      "probed"
    },
    name = "probe",
    description = "Probe."
  ))

  result <- suppressWarnings(agent$run_sync("task"))

  expect_identical(ran, 0L)
  expect_identical(result$stop_reason, "stop now")
})
