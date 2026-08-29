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
  expect_error(ContextPolicy(max_tokens = 1e20), "positive whole number")
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

test_that("the run kernel rechecks context between provider tool turns", {
  active_chat <- NULL
  fixture <- create_shiny_tool_chat(
    "test_tool",
    list(),
    execute = function(request) {
      active_chat$set_turns(c(
        active_chat$get_turns(),
        list(ellmer::AssistantTurn(contents = list(request)))
      ))
    }
  )
  chat <- fixture$chat
  active_chat <- chat
  chat$set_turns(list(
    create_mock_user_turn("Q1"),
    create_mock_assistant_turn("A1"),
    create_mock_user_turn("Q2"),
    create_mock_assistant_turn("A2")
  ))
  chat$token_count <- function(..., include = c("new", "complete")) {
    if (isTRUE(fixture$state$executed)) 100 else 10
  }
  agent <- Agent$new(
    chat = chat,
    context_policy = ContextPolicy(
      max_tokens = 50,
      compact_to = 0.5,
      fallback = "text"
    )
  )

  result <- suppressWarnings(agent$run_sync("Use the tool"))
  compaction <- agent$last_compaction()

  expect_s3_class(result, "AgentResult")
  expect_true(compaction$automatic)
  expect_identical(compaction$estimated_tokens, 100)
  expect_gt(compaction$turns_compacted, 0L)
  expect_true(any(vapply(
    agent$get_turns(),
    function(turn) {
      inherits(turn, "ellmer::AssistantTurn") &&
        any(vapply(
          turn@contents,
          inherits,
          logical(1),
          what = "ellmer::ContentToolRequest"
        ))
    },
    logical(1)
  )))
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
  expect_match(reference, "preview:")
  expect_identical(agent$resolve_tool_result(reference), value)
  expect_true("deputy_read_tool_result" %in% names(agent$get_tools()))
  model_chunk <- agent$get_tools()[["deputy_read_tool_result"]](
    reference,
    max_chars = 64L
  )
  expect_match(model_chunk, "next_offset:")
  expect_match(model_chunk, "large result")
  expect_length(list.files(directory, recursive = TRUE), 1L)
})

test_that("tool replacement restores the model result reader when needed", {
  directory <- withr::local_tempdir(pattern = "deputy-tool-results-")
  large_tool <- ellmer::tool(
    fun = function() paste(rep("large result", 20), collapse = " "),
    name = "large_result",
    description = "Return a large result."
  )
  agent <- Agent$new(
    chat = create_mock_chat(),
    tools = list(large_tool),
    context_policy = ContextPolicy(
      max_tool_result_bytes = 64,
      offload_dir = directory
    )
  )
  agent$get_tools()[["large_result"]]()
  agent$set_tools(list(large_tool))

  expect_true("deputy_read_tool_result" %in% names(agent$get_tools()))
})

test_that("Agent clones retain model access to offloaded results", {
  directory <- withr::local_tempdir(pattern = "deputy-tool-results-")
  large_tool <- ellmer::tool(
    fun = function() paste(rep("large result", 20), collapse = " "),
    name = "large_result",
    description = "Return a large result."
  )
  agent <- Agent$new(
    chat = create_mock_chat(),
    tools = list(large_tool),
    context_policy = ContextPolicy(
      max_tool_result_bytes = 64,
      offload_dir = directory
    )
  )
  reference <- agent$get_tools()[["large_result"]]()

  cloned <- agent$clone()
  chunk <- cloned$get_tools()[["deputy_read_tool_result"]](
    reference,
    max_chars = 64L
  )

  expect_match(chunk, "large result")
})

test_that("tools already on the Chat are rebound to the Agent workspace", {
  root <- withr::local_tempdir(pattern = "deputy-preloaded-root-")
  outside <- withr::local_tempdir(pattern = "deputy-preloaded-outside-")
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
  chat <- create_mock_chat()
  chat$register_tool(tool)
  agent <- Agent$new(
    chat = chat,
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

test_that("tools copied between Agents are rebound to the receiving Agent", {
  first_root <- withr::local_tempdir(pattern = "deputy-first-root-")
  second_root <- withr::local_tempdir(pattern = "deputy-second-root-")
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
  first <- Agent$new(
    chat = create_mock_chat(),
    tools = list(tool),
    working_dir = first_root
  )
  second <- Agent$new(
    chat = create_mock_chat(),
    tools = first$get_tools(),
    working_dir = second_root
  )

  returned <- second$get_tools()[["write_file"]]("note.txt", "second")

  expected <- file.path(second$working_dir, "note.txt")
  expect_identical(returned, expected)
  expect_identical(readLines(expected), "second")
  expect_false(file.exists(file.path(first_root, "note.txt")))
})

test_that("repeated compaction preserves prompt additions after the summary", {
  chat <- create_mock_chat()
  chat$set_system_prompt("Base prompt")
  chat$set_turns(list(
    create_mock_user_turn("Q1"),
    create_mock_assistant_turn("A1"),
    create_mock_user_turn("Q2")
  ))
  agent <- Agent$new(chat = chat)
  agent$compact(keep_last = 1L, summary = "First summary")
  agent$.__enclos_env__$private$append_hook_context("Keep this context")
  chat$set_turns(list(
    create_mock_user_turn("Q2"),
    create_mock_assistant_turn("A2"),
    create_mock_user_turn("Q3")
  ))

  agent$compact(keep_last = 1L, summary = "Second summary")

  prompt <- agent$get_system_prompt()
  expect_match(prompt, "Base prompt")
  expect_match(prompt, "Keep this context")
  expect_match(prompt, "Second summary")
  expect_no_match(prompt, "First summary")
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
