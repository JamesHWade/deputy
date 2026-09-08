test_that("rich results bound images independently and retain offloaded evidence", {
  directory <- withr::local_tempdir()
  image <- ellmer::content_image_url(paste0(
    "data:image/png;base64,",
    jsonlite::base64_enc(as.raw(1:100))
  ))
  value <- ellmer::ContentToolResult(
    value = list(
      ellmer::ContentText("small"),
      image,
      image,
      ellmer::ContentText(strrep("x", 2000))
    ),
    extra = list(display = list(html = "host display"))
  )
  policy <- ContextPolicy(
    max_tool_result_bytes = 1024L,
    max_tool_result_images = 1L,
    offload_dir = directory
  )
  bounded <- bound_rich_tool_result(value, "test", policy, "session", "agent")
  expect_length(
    Filter(
      function(x) inherits(x, "ellmer::ContentImage"),
      bounded$result@value
    ),
    1L
  )
  expect_identical(bounded$result@extra, value@extra)
  expect_match(
    r_session_text(bounded$result),
    "deputy://tool-result/",
    fixed = TRUE
  )
  expect_false(grepl(
    strrep("x", 1000),
    r_session_text(bounded$result),
    fixed = TRUE
  ))
  unlimited <- ContextPolicy(
    max_tool_result_bytes = NULL,
    max_tool_result_image_bytes = NULL,
    max_tool_result_images = NULL,
    offload_dir = directory
  )
  expect_null(bound_rich_tool_result(
    value,
    "test",
    unlimited,
    "session",
    "agent"
  ))
  no_images <- ContextPolicy(
    max_tool_result_image_bytes = 1L,
    offload_dir = directory
  )
  bounded <- bound_rich_tool_result(
    value,
    "test",
    no_images,
    "session",
    "agent"
  )
  expect_length(
    Filter(
      function(x) inherits(x, "ellmer::ContentImage"),
      bounded$result@value
    ),
    0L
  )
  many <- ellmer::ContentToolResult(value = rep(list(image), 1000))
  bounded <- bound_rich_tool_result(many, "test", no_images, "session", "agent")
  expect_length(bounded$result@value, 2L)
})

test_that("structured and error rich results retain display when bounded", {
  policy <- ContextPolicy(
    max_tool_result_bytes = 100L,
    offload_dir = withr::local_tempdir()
  )
  for (value in list(
    ellmer::ContentToolResult(
      value = list(text = strrep("x", 1000)),
      extra = list(label = "kept")
    ),
    ellmer::ContentToolResult(
      error = strrep("x", 1000),
      extra = list(label = "kept")
    )
  )) {
    bounded <- bound_rich_tool_result(value, "test", policy, "session", "agent")
    expect_identical(bounded$result@extra, value@extra)
    expect_match(
      bounded$result@error %||% bounded$result@value,
      "deputy://tool-result/",
      fixed = TRUE
    )
  }
})
