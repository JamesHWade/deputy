test_that("governed R tool data persists across model runs with nested provenance", {
  directory <- withr::local_tempdir()
  calls <- 0L
  fetch <- ellmer::tool(
    function(project) {
      stopifnot(identical(project, "pilot"))
      calls <<- calls + 1L
      data.frame(temperature = c(10, 20, 30), yield = c(2, 4, 6))
    },
    name = "fetch_measurements",
    description = "Fetch measurements for an explicitly named project.",
    arguments = list(project = ellmer::type_string("Project name.")),
    convert = FALSE,
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      destructive_hint = FALSE,
      open_world_hint = FALSE
    )
  )
  first <- paste0(
    "measurements <- tools$fetch_measurements(project = 'pilot'); ",
    "fit <- lm(yield ~ temperature, data = measurements); ",
    "cat('rows:', nrow(measurements))"
  )
  server <- local_runtime_server(list(
    runtime_reply(tool = "run_r_code", arguments = list(code = first)),
    runtime_reply("Three rows acquired."),
    runtime_reply(
      tool = "run_r_code",
      arguments = list(code = "cat('slope:', unname(coef(fit)[[2L]]))")
    ),
    runtime_reply("Slope calculated.")
  ))
  agent <- Agent$new(
    chat = runtime_chat(server),
    tools = list(fetch),
    permissions = Permissions(r_code = TRUE),
    working_dir = directory
  )
  session <- RSession$new(agent, tools = "fetch_measurements")
  withr::defer(session$close())
  agent$register_tools(session$tools())
  contexts <- list()
  agent$add_hook(HookMatcher(
    event = "PreToolUse",
    timeout = 0,
    callback = function(tool_name, context, ...) {
      if (identical(tool_name, "fetch_measurements")) {
        contexts[[length(contexts) + 1L]] <<- context
      }
      NULL
    }
  ))

  agent$chat("Fetch the pilot data and fit a model.")
  first_run <- agent$last_run()
  expect_identical(first_run$stop_reason, "complete")
  expect_identical(calls, 1L)
  expect_identical(first_run$usage$tool_calls, 2L)
  nested <- Filter(
    function(event) {
      identical(event$type, "tool_end") &&
        identical(event$tool_name, "fetch_measurements")
    },
    first_run$events
  )
  expect_length(nested, 1L)
  expect_identical(nested[[1L]]$parent_tool_call_id, "call_fixture")
  expect_identical(contexts[[1L]]$parent_tool_call_id, "call_fixture")
  expect_identical(contexts[[1L]]$tool_call_id, nested[[1L]]$tool_call_id)
  expect_null(nested[[1L]]$tool_error)
  generation <- session$status()$generation

  agent$chat("Calculate the slope from the existing model.")
  expect_identical(agent$last_run()$stop_reason, "complete")
  expect_identical(agent$last_run()$usage$tool_calls, 1L)
  expect_identical(calls, 1L)
  expect_identical(session$status()$generation, generation)
  wire <- jsonlite::toJSON(server$requests()[[4L]]$body, auto_unbox = TRUE)
  expect_match(wire, "slope: 0.2", fixed = TRUE)
})

test_that("a denied nested tool cannot perform its host effect", {
  directory <- withr::local_tempdir()
  marker <- file.path(directory, "effect")
  write <- ellmer::tool(
    function() file.create(marker),
    name = "record_measurement",
    description = "Record a measurement.",
    convert = FALSE,
    annotations = ellmer::tool_annotations(
      read_only_hint = FALSE,
      destructive_hint = FALSE,
      open_world_hint = FALSE
    )
  )
  server <- local_runtime_server(list(
    runtime_reply(
      tool = "run_r_code",
      arguments = list(code = "tools$record_measurement()")
    ),
    runtime_reply("The write was denied.")
  ))
  agent <- Agent$new(
    chat = runtime_chat(server),
    tools = list(write),
    permissions = Permissions(
      r_code = TRUE,
      tool_denylist = "record_measurement"
    ),
    working_dir = directory
  )
  session <- RSession$new(agent, tools = "record_measurement")
  withr::defer(session$close())
  agent$register_tools(session$tools())
  suppressWarnings(agent$chat("Record the measurement through R."))
  expect_identical(file.exists(marker), FALSE)
  expect_identical(agent$last_run()$usage$tool_calls, 2L)
  denied <- Filter(
    function(event) {
      identical(event$type, "permission") && identical(event$decision, "deny")
    },
    agent$last_run()$events
  )
  expect_length(denied, 1L)
  ends <- Filter(
    function(event) {
      identical(event$type, "tool_end") &&
        identical(event$tool_name, "record_measurement")
    },
    agent$last_run()$events
  )
  expect_length(ends, 1L)
  expect_s3_class(ends[[1L]]$tool_error, "condition")
})
