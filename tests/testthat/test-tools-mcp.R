# Tests for MCP (Model Context Protocol) tools integration

test_that("mcp_available returns logical", {
  result <- mcp_available()
  expect_true(is.logical(result))
  expect_length(result, 1)
})

test_that("tools_mcp returns list when mcptools not installed", {
  # Skip if mcptools is installed - we want to test the fallback

  skip_if(mcp_available(), "mcptools is installed")

  # Should return empty list with warning
  expect_warning(
    result <- tools_mcp(),
    "mcptools package is not installed"
  )
  expect_true(is.list(result))
  expect_length(result, 0)
})

test_that("tools_mcp with config parameter returns list", {
  skip_if_not(mcp_available(), "mcptools required")

  # Test with non-existent config - should return empty list
  expect_warning(
    result <- tools_mcp(config = "/nonexistent/config.json"),
    regexp = "Failed to fetch MCP tools|No such file"
  )
  expect_true(is.list(result))
})

test_that("mcp_servers returns NULL when mcptools not installed", {
  skip_if(mcp_available(), "mcptools is installed")

  expect_warning(
    result <- mcp_servers(),
    "mcptools package is not installed"
  )
  expect_null(result)
})

test_that("mcp_servers returns NULL for missing config", {
  skip_if_not(mcp_available(), "mcptools required")

  # Test with non-existent config
  result <- mcp_servers(config = "/nonexistent/config.json")
  expect_null(result)
})

test_that("Agent$mcp_tools returns empty vector initially", {
  skip_if_not_installed("ellmer")

  chat <- ellmer::chat_vllm(
    base_url = "http://localhost:9999",
    model = "test-model"
  )

  agent <- Agent$new(chat = chat)

  # Should have empty mcp_tools initially
  expect_equal(agent$mcp_tools(), character())
})

test_that("Agent$load_mcp handles missing mcptools gracefully", {
  skip_if(mcp_available(), "mcptools is installed")
  skip_if_not_installed("ellmer")

  chat <- ellmer::chat_vllm(
    base_url = "http://localhost:9999",
    model = "test-model"
  )

  agent <- Agent$new(chat = chat)

  # Should warn but not error
  expect_warning(
    result <- agent$load_mcp(),
    "mcptools package is not installed"
  )

  # Should return agent for chaining

  expect_s3_class(result, "Agent")

  # Should still have empty mcp_tools
  expect_equal(agent$mcp_tools(), character())
})

test_that("Agent$load_mcp is chainable", {
  skip_if(mcp_available(), "mcptools is installed")
  skip_if_not_installed("ellmer")

  chat <- ellmer::chat_vllm(
    base_url = "http://localhost:9999",
    model = "test-model"
  )

  # Should be able to chain load_mcp
  expect_warning(
    agent <- Agent$new(chat = chat)$load_mcp(),
    "mcptools"
  )

  expect_s3_class(agent, "Agent")
})
