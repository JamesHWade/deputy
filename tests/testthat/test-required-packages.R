test_that("required feature dependencies provide installation guidance", {
  # Exercise real dependency errors without uninstalling loaded packages.
  check_installed <- rlang::check_installed
  local_mocked_bindings(
    check_installed = function(pkg, reason) {
      check_installed(pkg, reason = reason, version = "9999")
    },
    is_interactive = function() FALSE,
    .package = "rlang"
  )

  expect_snapshot(error = TRUE, tool_web_fetch("https://example.com"))
  expect_snapshot(error = TRUE, tool_web_search("deputy"))
  expect_snapshot(error = TRUE, tools_mcp_repl())
  expect_snapshot(error = TRUE, parse_multi_edits("[]"))

  skill_dir <- withr::local_tempdir()
  writeLines("name: example", file.path(skill_dir, "SKILL.yaml"))
  expect_snapshot(error = TRUE, skill_load(skill_dir))

  markdown <- file.path(skill_dir, "SKILL.md")
  writeLines(c("---", "name: example", "---", "Prompt"), markdown)
  expect_snapshot(error = TRUE, parse_markdown_frontmatter(markdown))
  writeLines("Prompt without frontmatter", markdown)
  expect_equal(
    parse_markdown_frontmatter(markdown)$body,
    "Prompt without frontmatter"
  )
})
