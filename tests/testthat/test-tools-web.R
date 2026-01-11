# Tests for web tools

# Provider detection tests ------------------------------------------------

test_that("tools_web returns universal tools by default", {
  tools <- tools_web()
  expect_length(tools, 2)

  # Should be our universal tools (functions, not ToolBuiltIn)
  tool_names <- vapply(
    tools,
    function(t) {
      if (inherits(t, "ellmer::ToolDef")) t@name else "builtin"
    },
    character(1)
  )
  expect_true("web_fetch" %in% tool_names)
  expect_true("web_search" %in% tool_names)
})

test_that("tools_web returns universal tools when use_native = FALSE", {
  mock_chat <- create_mock_chat()
  tools <- tools_web(mock_chat, use_native = FALSE)
  expect_length(tools, 2)

  tool_names <- vapply(
    tools,
    function(t) {
      if (inherits(t, "ellmer::ToolDef")) t@name else "builtin"
    },
    character(1)
  )
  expect_true("web_fetch" %in% tool_names)
  expect_true("web_search" %in% tool_names)
})

test_that("get_provider_name handles invalid input", {
  expect_equal(deputy:::get_provider_name(NULL), "unknown")
  expect_equal(deputy:::get_provider_name("not a chat"), "unknown")
  expect_equal(deputy:::get_provider_name(list()), "unknown")
})

test_that("get_provider_name extracts provider from mock chat", {
  mock_chat <- create_mock_chat()
  # Our mock chat doesn't have a real provider, should return "unknown"
  result <- deputy:::get_provider_name(mock_chat)
  expect_type(result, "character")
})

# Tool structure tests ---------------------------------------------------

test_that("tool_web_fetch has correct structure", {
  expect_true(inherits(tool_web_fetch, "ellmer::ToolDef"))
  expect_equal(tool_web_fetch@name, "web_fetch")

  # Check annotations
  expect_true(tool_web_fetch@annotations$read_only_hint)
  expect_false(tool_web_fetch@annotations$destructive_hint)
  expect_true(tool_web_fetch@annotations$open_world_hint)
})

test_that("tool_web_search has correct structure", {
  expect_true(inherits(tool_web_search, "ellmer::ToolDef"))
  expect_equal(tool_web_search@name, "web_search")

  # Check annotations
  expect_true(tool_web_search@annotations$read_only_hint)
  expect_false(tool_web_search@annotations$destructive_hint)
  expect_true(tool_web_search@annotations$open_world_hint)
})

test_that("tools_web returns correct tools", {
  web_tools <- tools_web()
  expect_type(web_tools, "list")
  expect_length(web_tools, 2)

  tool_names <- vapply(web_tools, function(t) t@name, character(1))
  expect_true("web_fetch" %in% tool_names)
  expect_true("web_search" %in% tool_names)
})

test_that("tools_all includes web tools", {
  all_tools <- tools_all()
  tool_names <- vapply(all_tools, function(t) t@name, character(1))

  expect_true("web_fetch" %in% tool_names)
  expect_true("web_search" %in% tool_names)
})

test_that("web_fetch requires httr2 package", {
  skip_if_not_installed("httr2")

  # If httr2 is installed, the tool should work (we can't easily mock uninstalled)
  # Just verify the tool is callable
  expect_true(is.function(tool_web_fetch))
})

test_that("web_search requires httr2 package", {
  skip_if_not_installed("httr2")

  # If httr2 is installed, the tool should work
  expect_true(is.function(tool_web_search))
})

test_that("web_fetch fetches real URL", {
  skip_if_not_installed("httr2")
  skip_on_cran()
  skip_if_offline()

  # Fetch a simple test URL
  result <- tool_web_fetch("https://httpbin.org/html")

  expect_type(result, "character")
  expect_true(nchar(result) > 0)
  expect_true(grepl("web_page", result))
})

test_that("web_fetch handles invalid URL", {
  skip_if_not_installed("httr2")
  skip_on_cran()

  # This should return an error
  result <- tryCatch(
    tool_web_fetch("https://this-domain-definitely-does-not-exist-12345.com"),
    ellmer_tool_reject = function(e) "rejected",
    error = function(e) "error"
  )

  expect_true(result %in% c("rejected", "error"))
})

test_that("web_search returns results", {
  skip_if_not_installed("httr2")
  skip_on_cran()
  skip_if_offline()

  # Search for something common
  result <- tool_web_search("R programming language", num_results = 5)

  expect_type(result, "character")
  expect_true(nchar(result) > 0)
  # Should contain search query
  expect_true(grepl("R programming language", result))
})

test_that("web permission is checked correctly", {
  mock_chat <- create_mock_chat()

  # Web denied by default
  agent_no_web <- Agent$new(
    chat = mock_chat,
    tools = list(tool_web_fetch),
    permissions = Permissions$new(web = FALSE)
  )

  result_no_web <- agent_no_web$permissions$check(
    "web_fetch",
    list(url = "https://example.com"),
    list()
  )
  expect_s3_class(result_no_web, "PermissionResultDeny")

  # Web allowed
  agent_web <- Agent$new(
    chat = mock_chat,
    tools = list(tool_web_fetch),
    permissions = Permissions$new(web = TRUE)
  )

  result_web <- agent_web$permissions$check(
    "web_fetch",
    list(url = "https://example.com"),
    list()
  )
  expect_s3_class(result_web, "PermissionResultAllow")
})

test_that("web_search permission is checked correctly", {
  mock_chat <- create_mock_chat()

  # Web denied
  agent_no_web <- Agent$new(
    chat = mock_chat,
    tools = list(tool_web_search),
    permissions = Permissions$new(web = FALSE)
  )

  result_no_web <- agent_no_web$permissions$check(
    "web_search",
    list(query = "test"),
    list()
  )
  expect_s3_class(result_no_web, "PermissionResultDeny")

  # Web allowed
  agent_web <- Agent$new(
    chat = mock_chat,
    tools = list(tool_web_search),
    permissions = Permissions$new(web = TRUE)
  )

  result_web <- agent_web$permissions$check(
    "web_search",
    list(query = "test"),
    list()
  )
  expect_s3_class(result_web, "PermissionResultAllow")
})

# Helper function tests

test_that("simple_html_to_text extracts text", {
  html <- "<html><body><p>Hello <b>world</b>!</p><script>alert('x')</script></body></html>"
  result <- deputy:::simple_html_to_text(html)

  expect_true(grepl("Hello", result))
  expect_true(grepl("world", result))
  expect_false(grepl("alert", result))
  expect_false(grepl("<", result))
})

test_that("clean_text normalizes whitespace", {
  text <- "  Hello    world  \n\n\n\n  test  "
  result <- deputy:::clean_text(text)

  expect_false(grepl("  ", result))
  expect_false(grepl("\n\n\n", result))
  expect_equal(trimws(result), result)
})

test_that("extract_web_content handles simple HTML", {
  skip_if_not_installed("xml2")
  skip_if_not_installed("rvest")

  html <- "<html><body><main><h1>Title</h1><p>Content here</p></main></body></html>"
  result <- deputy:::extract_web_content(html, "https://example.com")

  expect_true(grepl("Title", result) || grepl("Content", result))
})
