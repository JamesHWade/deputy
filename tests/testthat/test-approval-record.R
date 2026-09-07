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
