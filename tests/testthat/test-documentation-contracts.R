test_that("first-success documentation policies stay executable", {
  workspace <- normalizePath(getwd(), winslash = "/")
  first_tools <- tools_preset("minimal")
  first_permissions <- permissions_readonly()
  first_limits <- UsageLimits(max_requests = 6, max_tool_calls = 8)
  first_context <- ContextPolicy(max_tokens = 32000, fallback = "error")

  expect_length(first_tools, 3L)
  expect_identical(first_permissions$mode, "readonly")
  expect_identical(first_limits$max_requests, 6L)
  expect_identical(first_context$max_tokens, 32000L)

  write_permissions <- Permissions$new(
    mode = "standard",
    file_read = TRUE,
    file_write = workspace,
    bash = FALSE,
    r_code = FALSE,
    web = FALSE,
    install_packages = FALSE
  )

  expect_identical(write_permissions$file_write, workspace)
  expect_identical(write_permissions$r_code, FALSE)
  expect_identical(write_permissions$bash, FALSE)
})
