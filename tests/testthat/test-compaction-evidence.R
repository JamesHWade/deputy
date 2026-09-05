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

test_that("structured tool evidence keeps field names and relationships", {
  withr::local_options(ellmer_max_tries = 1)
  cases <- list(
    list(
      value = list(denominator = 84L, page = 17L),
      json = '{"denominator":84,"page":17}'
    ),
    list(
      value = c(denominator = 84L, page = 17L),
      json = '{"denominator":84,"page":17}'
    ),
    list(
      value = c(study = "C", document = "assay-C-r3"),
      json = '{"study":"C","document":"assay-C-r3"}'
    ),
    list(
      value = list(estimate = 0.123456789),
      json = '{"estimate":0.123456789}'
    ),
    list(
      value = data.frame(
        study = c("C", "D"),
        denominator = c(84L, 23L),
        page = c(17L, 2L)
      ),
      json = paste0(
        '[{"study":"C","denominator":84,"page":17},',
        '{"study":"D","denominator":23,"page":2}]'
      )
    ),
    list(
      value = list(
        finding = list(
          denominator = 84L,
          source = list(document = "C", page = 17L)
        ),
        unresolved = c("D", "F")
      ),
      json = paste0(
        '{"finding":{"denominator":84,"source":{"document":"C","page":17}},',
        '"unresolved":["D","F"]}'
      )
    ),
    list(
      value = list(
        finding = ellmer::ContentText("Denominator 84."),
        citation = ellmer::ContentText("Source C, page 17.")
      ),
      json = '{"finding":"Denominator 84.","citation":"Source C, page 17."}'
    )
  )
  for (case in cases) {
    for (fallback in c(FALSE, TRUE)) {
      server <- local_runtime_server(list(
        runtime_reply(tool = "source_read"),
        runtime_reply("Source inspected."),
        if (fallback) {
          runtime_failure(401L)
        } else {
          runtime_reply("Evidence summarized.", stream = FALSE)
        }
      ))
      source <- ellmer::tool(
        function() {
          ellmer::ContentToolResult(
            value = case$value,
            extra = list(private = "HOST-ONLY-SECRET")
          )
        },
        name = "source_read",
        description = "Read structured source evidence.",
        annotations = ellmer::tool_annotations(
          read_only_hint = TRUE,
          open_world_hint = FALSE
        )
      )
      agent <- Agent$new(runtime_chat(server), tools = list(source))
      agent$run_sync("Read the source.")
      source_turns <- agent$get_turns()
      result <- agent$compact(keep_last = 0L, fallback = "text")
      prompt <- paste(
        unlist(lapply(
          tail(server$requests(), 1L)[[1L]]$body$messages,
          `[[`,
          "content"
        )),
        collapse = "\n"
      )
      expect_match(prompt, case$json, fixed = TRUE)
      expect_no_match(prompt, "HOST-ONLY-SECRET", fixed = TRUE)
      expect_identical(source_turns[[3L]]@contents[[1L]]@value, case$value)
      expect_identical(result$method, if (fallback) "text" else "llm")
      if (fallback) {
        expect_match(result$summary, case$json, fixed = TRUE)
        expect_no_match(result$summary, "HOST-ONLY-SECRET", fixed = TRUE)
      }
    }
  }
})

test_that("compaction offloads oversized explicit tool results before formatting", {
  withr::local_options(ellmer_max_tries = 1)
  large_text <- paste0(strrep("evidence ", 20000L), "SOURCE-END")
  for (value in list(large_text, list(source = large_text, page = 17L))) {
    for (fallback in c(FALSE, TRUE)) {
      directory <- withr::local_tempdir()
      server <- local_runtime_server(list(
        runtime_reply(tool = "source_read"),
        runtime_reply("Source inspected."),
        if (fallback) {
          runtime_failure(401L)
        } else {
          runtime_reply("Evidence summarized.", stream = FALSE)
        }
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
      agent <- Agent$new(
        runtime_chat(server),
        tools = list(source),
        context_policy = ContextPolicy(offload_dir = directory)
      )
      agent$run_sync("Read the source.")
      source_turns <- agent$get_turns()
      result <- agent$compact(keep_last = 0L, fallback = "text")
      prompt <- paste(
        unlist(lapply(
          tail(server$requests(), 1L)[[1L]]$body$messages,
          `[[`,
          "content"
        )),
        collapse = "\n"
      )
      expect_lt(nchar(prompt), 10000L)
      expect_match(prompt, "Tool result offloaded by Deputy", fixed = TRUE)
      expect_no_match(prompt, "SOURCE-END", fixed = TRUE)
      expect_no_match(prompt, "HOST-ONLY-SECRET", fixed = TRUE)
      reference <- regmatches(
        prompt,
        regexpr(
          "deputy://tool-result/result_[a-f0-9]+\\?text_sha256=[a-f0-9]+",
          prompt
        )
      )
      expect_identical(agent$resolve_tool_result(reference), value)
      expect_identical(source_turns[[3L]]@contents[[1L]]@value, value)
      expect_match(
        agent$get_tools()[["deputy_read_tool_result"]](
          reference,
          max_chars = 64L
        ),
        "evidence",
        fixed = TRUE
      )
      expect_identical(result$method, if (fallback) "text" else "llm")
      if (fallback) {
        expect_match(result$summary, reference, fixed = TRUE)
        expect_lt(nchar(result$summary), 10000L)
      }
    }
  }
})
