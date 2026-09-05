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
