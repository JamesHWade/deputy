test_that("compaction includes tool evidence without private display metadata", {
  server <- local_runtime_server(list(
    runtime_reply(
      tool = "source_read",
      arguments = list(item_id = "assay-C-r3")
    ),
    runtime_reply("Source inspected."),
    runtime_reply("Ready for the next checkpoint."),
    runtime_reply("C uses denominator 84, page 17.", stream = FALSE)
  ))
  source <- ellmer::tool(
    function(item_id) {
      ellmer::ContentToolResult(
        value = "Document assay-C-r3: denominator 84, page 17.",
        extra = list(private_display_metadata = "HOST-ONLY-SECRET")
      )
    },
    name = "source_read",
    description = "Read an evidence source.",
    arguments = list(item_id = ellmer::type_string()),
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE
    )
  )
  agent <- Agent$new(runtime_chat(server), tools = list(source))
  agent$run_sync("Inspect the source.")
  agent$run_sync("Move to the next checkpoint.")
  agent$compact(keep_last = 2L)

  prompt <- jsonlite::toJSON(tail(server$requests(), 1L)[[1]]$body)
  expect_match(
    prompt,
    "Document assay-C-r3: denominator 84, page 17.",
    fixed = TRUE
  )
  expect_match(prompt, "source_read", fixed = TRUE)
  expect_no_match(prompt, "HOST-ONLY-SECRET", fixed = TRUE)
})

test_that("degraded text compaction retains bounded tool evidence", {
  withr::local_options(ellmer_max_tries = 1)
  server <- local_runtime_server(list(
    runtime_reply(tool = "source_read"),
    runtime_reply("Source inspected."),
    runtime_failure(401L)
  ))
  source <- ellmer::tool(
    function() {
      ellmer::ContentToolResult(
        value = list(ellmer::ContentText(
          "Document assay-C-r3: denominator 84, page 17."
        )),
        extra = list(private = "HOST-ONLY-SECRET")
      )
    },
    name = "source_read",
    description = "Read source evidence.",
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE
    )
  )
  agent <- Agent$new(runtime_chat(server), tools = list(source))
  agent$run_sync("Inspect the source.")
  result <- agent$compact(keep_last = 0L, fallback = "text")
  expect_identical(result$method, "text")
  expect_match(result$summary, "denominator 84, page 17", fixed = TRUE)
  expect_no_match(result$summary, "HOST-ONLY-SECRET", fixed = TRUE)
  expect_match(
    agent$get_system_prompt(),
    "denominator 84, page 17",
    fixed = TRUE
  )
  expect_length(server$requests(), 3L)
})

test_that("compaction preserves documented non-string ellmer tool payloads", {
  for (value in list(
    ellmer::ContentText("Evidence: denominator 84, page 17."),
    list(
      ellmer::ContentText("Evidence: denominator 84"),
      ellmer::ContentText("page 17.")
    ),
    c(84L, 17L)
  )) {
    server <- local_runtime_server(list(
      runtime_reply(tool = "source_read"),
      runtime_reply("Source inspected."),
      runtime_reply("C uses denominator 84, page 17.", stream = FALSE)
    ))
    source <- ellmer::tool(
      function() {
        ellmer::ContentToolResult(
          value = value,
          extra = list(private = "HOST-ONLY-SECRET")
        )
      },
      name = "source_read",
      description = "Read source evidence.",
      annotations = ellmer::tool_annotations(
        read_only_hint = TRUE,
        open_world_hint = FALSE
      )
    )
    agent <- Agent$new(runtime_chat(server), tools = list(source))
    agent$run_sync("Read the source.")
    source_turns <- agent$get_turns()
    agent$compact(keep_last = 0L)
    prompt <- jsonlite::toJSON(tail(server$requests(), 1L)[[1L]]$body)
    expect_match(prompt, "84", fixed = TRUE)
    expect_match(prompt, "17", fixed = TRUE)
    expect_no_match(prompt, "HOST-ONLY-SECRET", fixed = TRUE)
    expect_identical(source_turns[[3L]]@contents[[1L]]@value, value)
  }
})
