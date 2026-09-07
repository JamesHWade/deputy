test_that("durable approvals reject provider-native execution at registration", {
  directory <- withr::local_tempdir()
  expect_error(
    Agent$new(
      chat = create_mock_chat(),
      tools = list(ellmer::openai_tool_web_search()),
      permissions = Permissions(web = TRUE, tool_allowlist = "web_search"),
      approval_dir = directory
    ),
    "provider-native effects cannot be journaled",
    class = "deputy_approval_error"
  )
  expect_length(list.files(directory, all.files = FALSE), 0L)
})

test_that("pending permission values preserve the read-only result family", {
  decision <- PermissionResultPending("Review {the operation}")
  expect_s7_class(decision, PermissionResult)
  expect_identical(decision$decision, "pending")
  expect_identical(decision$reason, "Review {the operation}")
  expect_error(decision@reason <- "Changed", "read.only|read only")
  expect_error(PermissionResultPending(NA_character_))
  expect_error(PermissionResultPending(c("one", "two")))
})

test_that("restored results preserve ellmer JSON and result content semantics", {
  request <- ellmer::contents_replay(list(
    version = 1,
    class = "ellmer::ContentToolRequest",
    props = list(id = "request_1", name = "effect", arguments = list())
  ))
  value <- jsonlite::toJSON(list(receipt = "receipt_1"), auto_unbox = TRUE)
  result <- approval_result_content(request, value)
  expect_identical(result@value, value)
  numeric <- approval_result_content(request, 42)
  expect_s3_class(numeric@value, "json")
  expect_equal(jsonlite::fromJSON(numeric@value), 42)
  rebound <- approval_result_content(request, result)
  expect_identical(rebound@request@id, "request_1")
  expect_identical(rebound@value, value)
})

test_that("ordinary JSON cannot become a constructor during content replay", {
  tagged <- list(
    version = 1,
    class = "deputy::PermissionResultAllow",
    props = list()
  )
  expect_error(
    approval_validate_inputs(list(value = tagged)),
    "resembles serialized content",
    class = "deputy_approval_error"
  )
  request <- ellmer::contents_replay(list(
    version = 1,
    class = "ellmer::ContentToolRequest",
    props = list(id = "request_1", name = "effect", arguments = list())
  ))
  request@arguments <- list(value = tagged)
  expect_error(approval_record_content(request), "resembles serialized content")
  request@arguments <- list()
  expect_error(
    approval_result_content(request, tagged),
    "resembles serialized content"
  )
  encoded <- jsonlite::toJSON(tagged, auto_unbox = TRUE)
  expect_identical(approval_result_content(request, encoded)@value, encoded)
})
