test_that("tool request signatures ignore object key order", {
  first <- tool_request_signature(
    "lookup",
    list(query = "R", options = list(limit = 10L, exact = TRUE))
  )
  reordered <- tool_request_signature(
    "lookup",
    list(options = list(exact = TRUE, limit = 10L), query = "R")
  )
  changed <- tool_request_signature(
    "lookup",
    list(query = "R", options = list(limit = 20L, exact = TRUE))
  )

  expect_identical(first, reordered)
  expect_false(identical(first, changed))
})

test_that("tool cycle signatures canonicalize structured results", {
  request <- tool_request_signature("job_status", list(id = "job-42"))
  first <- tool_cycle_signature(
    request,
    list(status = "running", progress = list(done = 2L, total = 3L)),
    NULL
  )
  reordered <- tool_cycle_signature(
    request,
    list(progress = list(total = 3L, done = 2L), status = "running"),
    NULL
  )
  changed <- tool_cycle_signature(
    request,
    list(status = "succeeded", progress = list(done = 3L, total = 3L)),
    NULL
  )

  expect_identical(first, reordered)
  expect_false(identical(first, changed))
})

test_that("near-identical responses cannot hide identical tool cycles", {
  chat <- create_mock_chat()
  agent <- Agent$new(
    chat = chat,
    permissions = permissions_full()
  )
  private <- agent$.__enclos_env__$private
  response_text <- c(
    "I will inspect the file now.",
    "I will inspect the file now!",
    "I will inspect the file now..."
  )

  for (index in seq_along(response_text)) {
    chat$set_turns(list(create_mock_assistant_turn(response_text[[index]])))
    request <- create_mock_tool_request(
      id = paste0("repeat-", index),
      name = "run_r_code",
      arguments = list(code = "1 + 1")
    )
    expect_no_error(private$handle_tool_request(request))
    expect_no_error(private$handle_tool_result(ellmer::ContentToolResult(
      value = 2,
      request = request
    )))
  }

  expect_identical(private$stop_reason_from_hook, "tool_loop")
})

test_that("different tool arguments reset loop detection", {
  agent <- Agent$new(
    chat = create_mock_chat(),
    permissions = permissions_full()
  )
  private <- agent$.__enclos_env__$private
  arguments <- list(1L, 1L, 2L, 1L, 1L)

  for (index in seq_along(arguments)) {
    request <- create_mock_tool_request(
      id = paste0("varied-", index),
      name = "run_r_code",
      arguments = list(code = paste("identity", arguments[[index]]))
    )
    expect_no_error(private$handle_tool_request(request))
    expect_no_error(private$handle_tool_result(ellmer::ContentToolResult(
      value = "ok",
      request = request
    )))
  }

  expect_identical(private$stop_reason_from_hook, NULL)
})

test_that("changing tool results reset loop detection for polling", {
  agent <- Agent$new(
    chat = create_mock_chat(),
    permissions = permissions_full()
  )
  private <- agent$.__enclos_env__$private
  results <- c("queued", "running", "succeeded")

  for (index in seq_along(results)) {
    request <- create_mock_tool_request(
      id = paste0("poll-", index),
      name = "job_status",
      arguments = list(id = "job-42")
    )
    expect_no_error(private$handle_tool_request(request))
    expect_no_error(private$handle_tool_result(ellmer::ContentToolResult(
      value = results[[index]],
      request = request
    )))
  }

  expect_identical(private$stop_reason_from_hook, NULL)
})
