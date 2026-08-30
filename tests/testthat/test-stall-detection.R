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

test_that("near-identical responses cannot hide an identical tool-call loop", {
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

  for (index in 1:2) {
    chat$set_turns(list(create_mock_assistant_turn(response_text[[index]])))
    request <- create_mock_tool_request(
      id = paste0("repeat-", index),
      name = "run_r_code",
      arguments = list(code = "1 + 1")
    )
    expect_no_error(private$handle_tool_request(request))
  }
  chat$set_turns(list(create_mock_assistant_turn(response_text[[3L]])))
  condition <- rlang::catch_cnd(private$handle_tool_request(
    create_mock_tool_request(
      id = "repeat-3",
      name = "run_r_code",
      arguments = list(code = "1 + 1")
    )
  ))

  expect_s3_class(condition, "ellmer_tool_reject")
  expect_match(conditionMessage(condition), "repeated 3 times")
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
  }

  expect_identical(private$stop_reason_from_hook, NULL)
})
