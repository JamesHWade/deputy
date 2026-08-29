token_counting_chat <- function(responses = list("done")) {
  chat <- create_mock_chat(responses)
  add_counter <- function(target) {
    target$token_count <- function(..., include = c("new", "complete")) {
      length(target$get_turns()) * 20 + 10
    }
    target
  }
  chat <- add_counter(chat)
  chat$clone <- function(deep = FALSE) {
    cloned <- add_counter(create_mock_chat(responses))
    cloned$set_turns(chat$get_turns())
    cloned
  }
  chat
}

test_that("ContextPolicy validates context and offload thresholds", {
  policy <- ContextPolicy()
  expect_s3_class(policy, "ContextPolicy")
  expect_identical(policy$max_tokens, 32000L)
  expect_identical(policy$fallback, "error")

  expect_error(ContextPolicy(max_tokens = 0), "positive whole number")
  expect_error(ContextPolicy(compact_to = 1), "between 0 and 1")
  expect_error(ContextPolicy(offload_dir = ""), "non-empty path")
})

test_that("the run kernel compacts automatically before the provider call", {
  chat <- token_counting_chat()
  chat$set_turns(list(
    create_mock_user_turn("Q1"),
    create_mock_assistant_turn("A1"),
    create_mock_user_turn("Q2"),
    create_mock_assistant_turn("A2")
  ))
  post_compact <- NULL
  agent <- Agent$new(
    chat = chat,
    context_policy = ContextPolicy(
      max_tokens = 50,
      compact_to = 0.5,
      fallback = "text"
    )
  )
  agent$add_hook(HookMatcher$new(
    event = "PostCompact",
    timeout = 0,
    callback = function(result, context) {
      post_compact <<- result
      NULL
    }
  ))

  result <- suppressWarnings(agent$run_sync("Continue"))
  compaction <- agent$last_compaction()

  expect_s3_class(result, "AgentResult")
  expect_s3_class(compaction, "DeputyCompaction")
  expect_true(compaction$automatic)
  expect_identical(compaction$method, "text")
  expect_identical(compaction$turns_compacted, 4L)
  expect_identical(compaction$estimated_tokens, 90)
  expect_identical(post_compact, compaction)
  expect_match(agent$get_system_prompt(), "Previous Conversation Summary")
})

test_that("automatic compaction fails closed unless fallback is configured", {
  chat <- token_counting_chat()
  chat$set_turns(list(
    create_mock_user_turn("Q1"),
    create_mock_assistant_turn("A1"),
    create_mock_user_turn("Q2"),
    create_mock_assistant_turn("A2")
  ))
  agent <- Agent$new(
    chat = chat,
    context_policy = ContextPolicy(max_tokens = 50)
  )

  expect_error(
    agent$run_sync("Continue"),
    class = "deputy_compaction_error"
  )
  expect_false(agent$.__enclos_env__$private$run_active)
})

test_that("LLM compaction reports its own usage", {
  chat <- create_compaction_mock_chat(responses = list("Summary"))
  chat$set_turns(list(
    create_mock_user_turn("Q1"),
    create_mock_assistant_turn("A1"),
    create_mock_user_turn("Q2")
  ))
  agent <- Agent$new(chat = chat)

  compaction <- agent$compact(keep_last = 1L)

  expect_identical(compaction$method, "llm")
  expect_s3_class(compaction$usage, "AgentUsage")
  expect_equal(compaction$usage$total_tokens, 150)
  expect_equal(compaction$usage$cost_usd, 0.001)
})

test_that("large tool results become durable integrity-checked references", {
  directory <- withr::local_tempdir(pattern = "deputy-results-")
  value <- paste(rep("large result", 100), collapse = " ")
  tool <- ellmer::tool(
    fun = function() value,
    name = "large_result",
    description = "Return a large test value.",
    arguments = list()
  )
  agent <- Agent$new(
    chat = create_mock_chat(),
    tools = list(tool),
    context_policy = ContextPolicy(
      max_tokens = NULL,
      max_tool_result_bytes = 32,
      offload_dir = directory
    )
  )

  reference <- agent$get_tools()[["large_result"]]()

  expect_match(reference, "deputy://tool-result/result_")
  expect_identical(agent$resolve_tool_result(reference), value)
  expect_length(list.files(directory, recursive = TRUE), 1L)
})

test_that("native tool paths resolve against the Agent workspace", {
  root <- withr::local_tempdir(pattern = "deputy-runtime-root-")
  outside <- withr::local_tempdir(pattern = "deputy-runtime-outside-")
  tool <- ellmer::tool(
    fun = function(path, content) {
      writeLines(content, path)
      path
    },
    name = "write_file",
    description = "Write a test file.",
    arguments = list(
      path = ellmer::type_string("File path"),
      content = ellmer::type_string("Content")
    )
  )
  agent <- Agent$new(
    chat = create_mock_chat(),
    tools = list(tool),
    working_dir = root,
    context_policy = ContextPolicy(max_tool_result_bytes = NULL)
  )
  withr::local_dir(outside)

  returned <- agent$get_tools()[["write_file"]]("note.txt", "inside")

  expected <- file.path(agent$working_dir, "note.txt")
  expect_identical(returned, expected)
  expect_identical(readLines(expected), "inside")
  expect_false(file.exists(file.path(outside, "note.txt")))
})
