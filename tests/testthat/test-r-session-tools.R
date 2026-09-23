local_r_tool_journey <- function(
  tool,
  code,
  permissions = Permissions(r_code = TRUE),
  usage_limits = NULL,
  timeout = 30,
  .local_envir = parent.frame()
) {
  # Each code string is one model run: a run_r_code call, then a final reply.
  replies <- unlist(
    lapply(code, function(step) {
      list(
        runtime_reply(tool = "run_r_code", arguments = list(code = step)),
        runtime_reply("done")
      )
    }),
    recursive = FALSE
  )
  server <- local_runtime_server(replies, .local_envir = .local_envir)
  agent <- Agent$new(
    chat = runtime_chat(server),
    tools = list(tool),
    permissions = permissions,
    usage_limits = usage_limits,
    working_dir = withr::local_tempdir(.local_envir = .local_envir)
  )
  session <- RSession$new(agent, tools = tool@name, timeout = timeout)
  withr::defer(session$close(), envir = .local_envir)
  agent$register_tools(session$tools())
  list(agent = agent, session = session, server = server)
}

r_bridge_test_tool <- function(fun, name = "fetch", arguments = list()) {
  ellmer::tool(
    fun,
    name = name,
    description = "Fixture data tool.",
    arguments = arguments,
    convert = FALSE,
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      destructive_hint = FALSE,
      open_world_hint = FALSE
    )
  )
}

r_bridge_outer_text <- function(agent) {
  ends <- Filter(
    function(event) {
      identical(event$type, "tool_end") &&
        identical(event$tool_name, "run_r_code")
    },
    agent$last_run()$events
  )
  paste(
    vapply(
      ends[[1L]]$tool_result,
      function(content) content@text,
      character(1)
    ),
    collapse = "\n"
  )
}

r_bridge_nested_ends <- function(agent, name = "fetch") {
  Filter(
    function(event) {
      identical(event$type, "tool_end") &&
        identical(event$tool_name, name)
    },
    agent$last_run()$events
  )
}

r_bridge_run_later <- function(seconds) {
  deadline <- Sys.time() + seconds
  while (Sys.time() < deadline) {
    later::run_now(0.05)
  }
  invisible(NULL)
}

test_that("an execution timeout settles the pending nested request", {
  # The tool never resolves on its own: the test releases the late result
  # itself after the run, so no timer races the execution deadline.
  calls <- 0L
  resolve_late <- NULL
  fixture <- local_r_tool_journey(
    r_bridge_test_tool(function() {
      calls <<- calls + 1L
      promises::promise(function(resolve, reject) {
        resolve_late <<- resolve
      })
    }),
    c(
      "invisible(jsonlite::toJSON(1)); cat('warm')",
      "x <- tools$fetch(); cat('unreachable')"
    ),
    timeout = 5
  )
  # A first governed run starts the worker and loads the bridge's
  # dependencies, so the timed execution only has to send its request.
  fixture$agent$chat("Warm up the session.")
  expect_identical(fixture$agent$last_run()$stop_reason, "complete")
  expect_identical(calls, 0L)
  fixture$agent$chat("Fetch slowly.")
  run <- fixture$agent$last_run()
  expect_identical(calls, 1L)
  expect_identical(run$stop_reason, "complete")
  expect_identical(run$usage$tool_calls, 2L)
  expect_identical(fixture$session$status()$last_reset, "timed_out")
  expect_match(r_bridge_outer_text(fixture$agent), "timed_out", fixed = TRUE)
  nested <- r_bridge_nested_ends(fixture$agent)
  expect_length(nested, 1L)
  expect_s3_class(nested[[1L]]$tool_error, "condition")
  expect_match(
    conditionMessage(nested[[1L]]$tool_error),
    "ended before the nested tool result arrived (reason: timed_out)",
    fixed = TRUE
  )

  expect_true(is.function(resolve_late))
  resolve_late("late result")
  r_bridge_run_later(0.5)
  expect_identical(fixture$agent$last_run(), run)
  expect_identical(fixture$session$status()$queued, 0L)
})

test_that("worker rejects NA arguments instead of sending the string NA", {
  calls <- 0L
  fixture <- local_r_tool_journey(
    r_bridge_test_tool(
      function(x) {
        calls <<- calls + 1L
        x
      },
      arguments = list(x = ellmer::type_array(ellmer::type_number()))
    ),
    paste(
      "tryCatch(tools$fetch(x = c(1, NA)),",
      "error = function(e) cat('caught:', conditionMessage(e)))"
    )
  )
  fixture$agent$chat("Send a missing value.")
  text <- r_bridge_outer_text(fixture$agent)
  expect_match(text, "caught:", fixed = TRUE)
  expect_match(text, "without NA", fixed = TRUE)
  expect_identical(calls, 0L)
  expect_identical(fixture$agent$last_run()$usage$tool_calls, 1L)
})

test_that("sequential nested calls in one execution get distinct request IDs", {
  seen <- character()
  fixture <- local_r_tool_journey(
    r_bridge_test_tool(
      function(x) {
        seen <<- c(seen, x)
        paste0("got ", x)
      },
      arguments = list(x = ellmer::type_string())
    ),
    paste(
      ".deputy_tool_counter <- 0L;",
      "a <- tools$fetch(x = 'first'); .deputy_tool_counter <- 0L;",
      "b <- tools$fetch(x = 'second'); cat(a, b)"
    )
  )
  fixture$agent$chat("Fetch twice.")
  expect_identical(seen, c("first", "second"))
  expect_match(
    r_bridge_outer_text(fixture$agent),
    "got first got second",
    fixed = TRUE
  )
  expect_identical(fixture$agent$last_run()$usage$tool_calls, 3L)
  ids <- vapply(
    r_bridge_nested_ends(fixture$agent),
    function(event) event$tool_call_id,
    character(1)
  )
  expect_length(ids, 2L)
  expect_false(anyDuplicated(ids) > 0L)
})

test_that("async tools preserve data attributes and notify async observers", {
  value <- list(
    matrix = matrix(1:6, 2),
    date = as.Date("2026-01-02"),
    factor = factor(c("b", "a"), levels = c("a", "b")),
    nothing = NULL
  )
  fixture <- local_r_tool_journey(
    r_bridge_test_tool(function() {
      promises::promise(function(resolve, reject) {
        later::later(function() resolve(value), 0.01)
      })
    }),
    paste(
      "x <- tools$fetch(); stopifnot(is.matrix(x$matrix),",
      "identical(dim(x$matrix), c(2L,3L)), inherits(x$date,'Date'),",
      "identical(levels(x$factor), c('a','b')), is.null(x$nothing)); cat('data retained')"
    )
  )
  observed <- list()
  fixture$agent$on_tool_result(function(result) {
    if (!identical(result@request@name, "fetch")) {
      return(NULL)
    }
    promises::promise(function(resolve, reject) {
      later::later(
        function() {
          observed[[length(observed) + 1L]] <<- result
          resolve(NULL)
        },
        0.01
      )
    })
  })
  fixture$agent$chat("Fetch and inspect data.")
  expect_match(
    r_bridge_outer_text(fixture$agent),
    "data retained",
    fixed = TRUE
  )
  expect_length(observed, 1L)
  expect_identical(observed[[1L]]@value, value)
  expect_identical(fixture$agent$last_run()$usage$tool_calls, 2L)
  nested <- Filter(
    function(event) {
      identical(event$type, "tool_end") &&
        identical(event$tool_name, "fetch")
    },
    fixture$agent$last_run()$events
  )[[1L]]
  expect_match(nested$r_session_execution_id, "^r_call_")
  expect_identical(nested$r_session_generation, "1")
})

test_that("nested limits and pending approval prevent effects", {
  calls <- 0L
  tool <- r_bridge_test_tool(function() {
    calls <<- calls + 1L
    "effect"
  })
  limited <- local_r_tool_journey(
    tool,
    "tools$fetch()",
    usage_limits = UsageLimits(max_tool_calls = 1)
  )
  suppressWarnings(limited$agent$chat("Try the tool."))
  expect_identical(calls, 0L)
  expect_identical(limited$agent$last_run()$stop_reason, "tool_call_limit")
  expect_identical(limited$agent$last_run()$usage$tool_calls, 2L)
  expect_length(limited$server$requests(), 1L)

  pending <- local_r_tool_journey(
    tool,
    "tools$fetch()",
    permissions = Permissions(
      r_code = TRUE,
      can_use_tool = function(tool_name, ...) {
        if (identical(tool_name, "fetch")) {
          PermissionResultPending("Review first")
        } else {
          PermissionResultAllow()
        }
      }
    )
  )
  suppressWarnings(pending$agent$chat("Try the tool."))
  expect_identical(calls, 0L)
  expect_match(
    r_bridge_outer_text(pending$agent),
    "cannot suspend for approval",
    fixed = TRUE
  )
  expect_null(pending$agent$pending_approval())
})

test_that("async request observer rejection is awaited before the effect", {
  calls <- 0L
  fixture <- local_r_tool_journey(
    r_bridge_test_tool(function() {
      calls <<- calls + 1L
      "effect"
    }),
    "tools$fetch()"
  )
  fixture$agent$on_tool_request(function(request) {
    if (identical(request@name, "fetch")) {
      return(promises::promise_reject(simpleError("observer denied")))
    }
    NULL
  })
  fixture$agent$chat("Try the tool.")
  expect_identical(calls, 0L)
  expect_match(
    r_bridge_outer_text(fixture$agent),
    "observer denied",
    fixed = TRUE
  )
})

test_that("cancelled async tool results never enter the next run", {
  resolve_tool <- NULL
  fixture <- local_r_tool_journey(
    r_bridge_test_tool(function() {
      promises::promise(function(resolve, reject) {
        resolve_tool <<- resolve
        later::later(function() fixture$agent$interrupt(), 0.01)
      })
    }),
    "x <- tools$fetch()"
  )
  fixture$agent$chat("Start the tool.")
  interrupted <- fixture$agent$last_run()
  expect_identical(interrupted$stop_reason, "interrupted")
  expect_identical(interrupted$usage$tool_calls, 2L)
  nested <- r_bridge_nested_ends(fixture$agent)
  expect_length(nested, 1L)
  expect_s3_class(nested[[1L]]$tool_error, "condition")
  expect_match(
    conditionMessage(nested[[1L]]$tool_error),
    "reason: cancelled",
    fixed = TRUE
  )
  expect_null(fixture$session$status()$pid)
  fixture$agent$chat("Continue without a tool.")
  before <- fixture$agent$last_run()
  resolve_tool("late result")
  for (i in seq_len(10L)) {
    later::run_now(0.01)
  }
  expect_identical(fixture$agent$last_run(), before)
  expect_identical(before$usage$tool_calls, 0L)
  expect_identical(fixture$session$status()$queued, 0L)
})

test_that("bridge transfer rejects runtime attributes and retains portable data", {
  value <- list(
    frame = data.frame(x = factor(c("a", "b"))),
    matrix = matrix(1:6, 2),
    date = as.Date("2026-01-02")
  )
  encoded <- r_session_tool_serialize_result(value)
  expect_identical(unserialize(jsonlite::base64_dec(encoded)), value)
  hidden <- structure(1, callback = function() NULL)
  expect_snapshot(error = TRUE, r_session_tool_serialize_result(hidden))
  expect_snapshot(error = TRUE, r_session_tool_serialize_result(new.env()))
  expect_snapshot(
    error = TRUE,
    r_session_tool_serialize_result(raw(100), max_bytes = 50)
  )
  path <- withr::local_tempfile()
  writeLines(strrep("x", 1024), path)
  expect_snapshot(error = TRUE, r_session_tool_read_json(path, 128, "request"))
})

test_that("request identity and raw JSON never restore worker classes", {
  request <- list(
    protocol = 1L,
    request_id = "req1",
    session_id = "session1",
    call_id = "call1",
    execution_id = "outer1",
    generation = 1L,
    tool_name = "fetch",
    arguments = list()
  )
  check <- function(request) {
    r_session_tool_validate_request(
      request,
      "session1",
      "call1",
      "outer1",
      1L,
      "fetch",
      "req1.request.json"
    )
  }
  expect_identical(check(request)$arguments, list())
  request$generation <- 2L
  expect_snapshot(error = TRUE, check(request))
  request$generation <- 1L
  request$tool_name <- "unselected"
  expect_snapshot(error = TRUE, check(request))
  request$tool_name <- "fetch"
  request$arguments <- list(x = structure(list(), class = "worker_class"))
  expect_snapshot(error = TRUE, check(request))
})

test_that("direct host calls cannot borrow a bridge and selection requires raw tools", {
  agent <- Agent$new(
    chat = create_mock_chat(),
    tools = list(r_bridge_test_tool(function() 1))
  )
  session <- RSession$new(agent, tools = "fetch")
  withr::defer(session$close())
  expect_snapshot(error = TRUE, session$run("tools$fetch()"))
  expect_null(session$status()$pid)
  converted <- ellmer::tool(
    function() 1,
    name = "converted",
    description = "Converted."
  )
  agent$register_tool(converted)
  expect_snapshot(error = TRUE, RSession$new(agent, tools = "converted"))

  durable <- Agent$new(
    chat = create_mock_chat(),
    tools = list(r_bridge_test_tool(function() 1)),
    approval_dir = withr::local_tempdir()
  )
  expect_snapshot(error = TRUE, RSession$new(durable, tools = "fetch"))
})

test_that("MCP-origin file tools retain remote path semantics", {
  received <- NULL
  tool <- ellmer::tool(
    function(path) {
      received <<- path
      "remote contents"
    },
    name = "read_file",
    description = "Read a remote file.",
    arguments = list(path = ellmer::type_string("Remote path.")),
    convert = FALSE,
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE
    )
  )
  attr(tool, "deputy_tool_source") <- list(
    type = "mcp",
    server = "fixture",
    tool = "read_file"
  )
  fixture <- local_r_tool_journey(
    tool,
    "cat(tools$read_file(path='relative.txt'))"
  )
  fixture$agent$chat("Read the remote file.")
  expect_identical(received, "relative.txt")
  expect_match(
    r_bridge_outer_text(fixture$agent),
    "remote contents",
    fixed = TRUE
  )
})


test_that("replacing a selected tool during an observer prevents its effect", {
  calls <- 0L
  fixture <- local_r_tool_journey(
    r_bridge_test_tool(function() {
      calls <<- calls + 1L
      "original effect"
    }),
    "tools$fetch()"
  )
  fixture$agent$on_tool_request(function(request) {
    if (!identical(request@name, "fetch")) {
      return(NULL)
    }
    promises::promise(function(resolve, reject) {
      later::later(
        function() {
          fixture$agent$register_tool(
            r_bridge_test_tool(function() {
              calls <<- calls + 1L
              "replacement effect"
            }),
            replace = TRUE
          )
          resolve(NULL)
        },
        0.01
      )
    })
  })
  fixture$agent$chat("Try the selected tool.")
  expect_identical(calls, 0L)
  expect_match(
    r_bridge_outer_text(fixture$agent),
    "replaced after dispatcher admission",
    fixed = TRUE
  )
})
