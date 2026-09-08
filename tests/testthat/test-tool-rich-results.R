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
  single <- bound_rich_tool_result(
    ellmer::ContentToolResult(value = image),
    "test",
    no_images,
    "session",
    "agent"
  )
  expect_length(
    Filter(
      function(x) inherits(x, "ellmer::ContentImage"),
      single$result@value
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

test_that("native artifact text and original references survive repeated compaction and restore", {
  directory <- withr::local_tempdir()
  payload <- list(
    ellmer::ContentText(strrep("x", 5000)),
    ellmer::ContentText(strrep("recoverable evidence ", 10000)),
    ellmer::content_image_url(paste0(
      "data:image/png;base64,",
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    ))
  )
  server <- local_runtime_server(list(
    runtime_reply(tool = "source_read"),
    runtime_reply("Read."),
    runtime_reply("Summary without a reference.", stream = FALSE),
    runtime_reply("Updated summary without a reference.", stream = FALSE)
  ))
  source <- ellmer::tool(
    function() ellmer::ContentToolResult(value = payload),
    name = "source_read",
    description = "Read evidence.",
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE
    )
  )
  agent <- Agent$new(
    chat = runtime_chat(server),
    tools = list(source),
    context_policy = ContextPolicy(
      max_tool_result_bytes = 8192L,
      offload_dir = directory
    )
  )
  agent$run_sync("Read.")
  reference <- compaction_tool_result_references(r_session_text(agent$get_turns()[[
    3L
  ]]@contents[[1L]]))
  expect_length(reference, 1L)
  expect_identical(agent$resolve_tool_result(reference)$content, payload)
  expect_match(
    agent$get_tools()[["deputy_read_tool_result"]](
      reference,
      offset = 5500L,
      max_chars = 128L
    ),
    "recoverable evidence",
    fixed = TRUE
  )
  summary <- agent$compact(keep_last = 0L)
  expect_match(summary$summary, reference, fixed = TRUE)
  agent$add_turn(
    ellmer::UserTurn("Continue."),
    ellmer::AssistantTurn("Continuing."),
    log_tokens = FALSE
  )
  repeated <- agent$compact(keep_last = 0L)
  expect_match(repeated$summary, reference, fixed = TRUE)
  path <- file.path(directory, "saved.rds")
  suppressMessages(agent$save_session(path))
  restored <- Agent$new(
    chat = runtime_chat(server),
    context_policy = ContextPolicy(
      offload_dir = file.path(directory, "restored")
    )
  )
  suppressMessages(restored$load_session(path))
  expect_identical(restored$resolve_tool_result(reference)$content, payload)
  # Text regeneration uses the versioned public projection, including after restore.
  envelope <- read_tool_result_envelope(
    reference,
    restored$context_policy,
    restored$session_id()
  )
  text_path <- tool_result_text_path(
    tool_result_offload_dir(restored$context_policy, restored$session_id()),
    envelope$id
  )
  unlink(text_path)
  suppressMessages(restored$load_session(path))
  expect_match(
    restored$get_tools()[["deputy_read_tool_result"]](
      reference,
      offset = 5500L,
      max_chars = 128L
    ),
    "recoverable evidence",
    fixed = TRUE
  )
})
