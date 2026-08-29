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

test_that("ContextPolicy anchors relative offload roots at construction", {
  first <- withr::local_tempdir(pattern = "deputy-policy-first-")
  second <- withr::local_tempdir(pattern = "deputy-policy-second-")
  withr::local_dir(first)
  policy <- ContextPolicy(
    max_tokens = NULL,
    max_tool_result_bytes = 32,
    offload_dir = "tool-results"
  )
  expected_root <- policy$offload_dir
  expect_true(is_absolute_path(expected_root))

  value <- paste(rep("anchored result", 100), collapse = " ")
  tool <- ellmer::tool(
    fun = function() value,
    name = "large_result",
    description = "Return a large value.",
    arguments = list()
  )
  agent <- Agent$new(
    chat = create_mock_chat(),
    tools = list(tool),
    context_policy = policy
  )
  reference <- agent$get_tools()[["large_result"]]()

  withr::local_dir(second)
  chunk <- agent$get_tools()[["deputy_read_tool_result"]](
    reference,
    max_chars = 64L
  )

  expect_match(chunk, "anchored result", fixed = TRUE)
  expect_true(dir.exists(expected_root))
  expect_false(dir.exists(file.path(second, "tool-results")))
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
  expect_length(list.files(directory, recursive = TRUE), 3L)
})

test_that("tool-result reader pages through persisted text", {
  directory <- withr::local_tempdir(pattern = "deputy-chunked-results-")
  value <- c(strrep("a", 20000), "marker", rep("tail", 10000))
  tool <- ellmer::tool(
    fun = function() value,
    name = "large_result",
    description = "Return a large character vector.",
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
  result_path <- list.files(
    directory,
    pattern = "^result_[a-f0-9]{64}\\.rds$",
    recursive = TRUE,
    full.names = TRUE
  )
  backup_path <- paste0(result_path, ".backup")
  expect_true(file.rename(result_path, backup_path))
  chunk <- agent$get_tools()[["deputy_read_tool_result"]](
    reference,
    offset = 19998L,
    max_chars = 16L
  )
  expect_true(file.rename(backup_path, result_path))

  expect_match(chunk, "marker", fixed = TRUE)
  expect_match(chunk, "next_offset: 20014", fixed = TRUE)
  expect_length(
    list.files(directory, pattern = "\\.(rds|txt)$", recursive = TRUE),
    3L
  )
})

test_that("non-character tool results use chunkable sidecars", {
  directory <- withr::local_tempdir(pattern = "deputy-list-results-")
  value <- rep(list(list(payload = strrep("nested", 100))), 1000)
  tool <- ellmer::tool(
    fun = function() value,
    name = "large_list",
    description = "Return a large nested list.",
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

  reference <- agent$get_tools()[["large_list"]]()
  chunk <- agent$get_tools()[["deputy_read_tool_result"]](
    reference,
    max_chars = 128L
  )

  expect_match(chunk, "payload", fixed = TRUE)
  expect_match(chunk, "complete: FALSE", fixed = TRUE)
})

test_that("post-tool hooks inspect original offloaded results", {
  directory <- withr::local_tempdir(pattern = "deputy-hook-results-")
  value <- paste(rep("sensitive large result", 100), collapse = " ")
  tool <- ellmer::tool(
    fun = function() value,
    name = "large_result",
    description = "Return a large test value.",
    arguments = list()
  )
  captured <- NULL
  agent <- Agent$new(
    chat = create_mock_chat(),
    tools = list(tool),
    context_policy = ContextPolicy(
      max_tokens = NULL,
      max_tool_result_bytes = 32,
      offload_dir = directory
    )
  )
  agent$add_hook(HookMatcher$new(
    event = "PostToolUse",
    timeout = 0,
    callback = function(tool_name, tool_result, tool_error, context) {
      captured <<- tool_result
      NULL
    }
  ))
  wrapped <- agent$get_tools()[["large_result"]]
  request <- ellmer::ContentToolRequest(
    id = "large-result-call",
    name = wrapped@name,
    arguments = list(),
    tool = wrapped
  )
  private <- agent$.__enclos_env__$private

  private$handle_tool_request(request)
  model_result <- wrapped()
  private$handle_tool_result(ellmer::ContentToolResult(
    value = model_result,
    request = request
  ))

  expect_match(model_result, "deputy://tool-result/result_")
  expect_identical(captured, value)
  expect_length(private$original_tool_results, 0L)
})

test_that("tool-result previews render bounded slices", {
  character_value <- c(
    strrep("a", 1000),
    rep("tail should not be rendered", 100000)
  )
  nested_value <- rep(
    list(list(payload = strrep("nested", 1000))),
    10000
  )
  wide_frame <- structure(
    rep(list(strrep("column", 1000)), 10000),
    names = paste0("column_", seq_len(10000)),
    row.names = 1L,
    class = "data.frame"
  )

  character_preview <- tool_result_preview(character_value, max_chars = 64L)
  nested_preview <- tool_result_preview(nested_value, max_chars = 256L)
  frame_preview <- tool_result_preview(wide_frame, max_chars = 256L)

  expect_match(character_preview, "^a+")
  expect_no_match(
    character_preview,
    "tail should not be rendered",
    fixed = TRUE
  )
  expect_match(character_preview, "[preview truncated]", fixed = TRUE)
  expect_lte(nchar(character_preview), 84L)
  expect_lte(nchar(nested_preview), 276L)
  expect_lte(nchar(frame_preview), 276L)
})

test_that("the internal result reader remains available behind an allowlist", {
  directory <- withr::local_tempdir(pattern = "deputy-results-allowlist-")
  value <- paste(rep("large result", 100), collapse = " ")
  large_tool <- ellmer::tool(
    fun = function() value,
    name = "large_result",
    description = "Return a large test value.",
    arguments = list()
  )
  other_tool <- ellmer::tool(
    fun = function() "other",
    name = "other_tool",
    description = "Return another value.",
    arguments = list()
  )
  permissions <- Permissions$new(
    mode = "standard",
    file_read = FALSE,
    file_write = FALSE,
    bash = FALSE,
    r_code = FALSE,
    web = FALSE,
    install_packages = FALSE,
    tool_allowlist = "large_result"
  )
  agent <- Agent$new(
    chat = create_mock_chat(),
    tools = list(large_tool, other_tool),
    permissions = permissions,
    context_policy = ContextPolicy(
      max_tokens = NULL,
      max_tool_result_bytes = 32,
      offload_dir = directory
    )
  )
  reference <- agent$get_tools()[["large_result"]]()
  reader <- agent$get_tools()[["deputy_read_tool_result"]]
  reader_request <- ellmer::ContentToolRequest(
    id = "reader-call",
    name = reader@name,
    arguments = list(reference = reference, offset = 0L),
    tool = reader
  )
  other <- agent$get_tools()[["other_tool"]]
  other_request <- ellmer::ContentToolRequest(
    id = "other-call",
    name = other@name,
    arguments = list(),
    tool = other
  )

  expect_no_error(
    agent$.__enclos_env__$private$handle_tool_request(reader_request)
  )
  expect_error(
    agent$.__enclos_env__$private$handle_tool_request(other_request),
    class = "ellmer_tool_reject"
  )
})

test_that("the internal result reader preserves explicit permission vetoes", {
  directory <- withr::local_tempdir(pattern = "deputy-reader-vetoes-")
  value <- paste(rep("private result", 100), collapse = " ")
  large_tool <- ellmer::tool(
    fun = function() value,
    name = "large_result",
    description = "Return a large private value.",
    arguments = list()
  )
  make_reader_request <- function(permissions, session_id) {
    agent <- Agent$new(
      chat = create_mock_chat(),
      tools = list(large_tool),
      permissions = permissions,
      context_policy = ContextPolicy(
        max_tokens = NULL,
        max_tool_result_bytes = 32,
        offload_dir = directory
      ),
      session_id = session_id
    )
    reference <- agent$get_tools()[["large_result"]]()
    reader <- agent$get_tools()[["deputy_read_tool_result"]]
    list(
      agent = agent,
      request = ellmer::ContentToolRequest(
        id = paste0(session_id, "-reader"),
        name = reader@name,
        arguments = list(reference = reference, offset = 0L),
        tool = reader
      )
    )
  }

  denied <- make_reader_request(
    Permissions$new(
      tool_allowlist = "large_result",
      tool_denylist = "DEPUTY_READ_TOOL_RESULT"
    ),
    "denylisted-reader"
  )
  expect_error(
    denied$agent$.__enclos_env__$private$handle_tool_request(denied$request),
    "denylist",
    class = "ellmer_tool_reject"
  )

  vetoed <- make_reader_request(
    Permissions$new(
      tool_allowlist = "large_result",
      can_use_tool = function(tool_name, tool_input, context) {
        if (identical(tool_name, "deputy_read_tool_result")) {
          return(PermissionResultDeny("Reader vetoed"))
        }
        PermissionResultAllow()
      }
    ),
    "callback-vetoed-reader"
  )
  expect_error(
    vetoed$agent$.__enclos_env__$private$handle_tool_request(vetoed$request),
    "Reader vetoed",
    class = "ellmer_tool_reject"
  )
})

test_that("saved sessions carry offloaded tool results to a new Agent", {
  directory <- withr::local_tempdir(pattern = "deputy-portable-results-")
  value <- paste(rep("portable result", 100), collapse = " ")
  large_tool <- ellmer::tool(
    fun = function() value,
    name = "large_result",
    description = "Return a portable result.",
    arguments = list()
  )
  policy <- ContextPolicy(
    max_tokens = NULL,
    max_tool_result_bytes = 32,
    offload_dir = directory
  )
  source <- Agent$new(
    chat = create_mock_chat(),
    tools = list(large_tool),
    context_policy = policy,
    session_id = "source-results-session"
  )
  reference <- source$get_tools()[["large_result"]]()
  source$set_turns(list(create_mock_user_turn(reference)))
  session_file <- file.path(directory, "session.rds")
  suppressMessages(source$save_session(session_file))

  receiver <- Agent$new(
    chat = create_mock_chat(),
    context_policy = policy,
    session_id = "receiver-results-session"
  )
  suppressMessages(receiver$load_session(session_file))

  expect_identical(receiver$session_id(), "receiver-results-session")
  expect_identical(receiver$resolve_tool_result(reference), value)
  expect_true("deputy_read_tool_result" %in% names(receiver$get_tools()))
  expect_match(
    receiver$get_tools()[["deputy_read_tool_result"]](
      reference,
      max_chars = 64L
    ),
    "portable result"
  )
})

test_that("session tool-result integrity failures are atomic", {
  directory <- withr::local_tempdir(pattern = "deputy-corrupt-results-")
  large_tool <- ellmer::tool(
    fun = function() paste(rep("large result", 100), collapse = " "),
    name = "large_result",
    description = "Return a large result.",
    arguments = list()
  )
  policy <- ContextPolicy(
    max_tokens = NULL,
    max_tool_result_bytes = 32,
    offload_dir = directory
  )
  source <- Agent$new(
    chat = create_mock_chat(),
    tools = list(large_tool),
    context_policy = policy,
    session_id = "corrupt-source-session"
  )
  source$get_tools()[["large_result"]]()
  session_file <- file.path(directory, "session.rds")
  suppressMessages(source$save_session(session_file))
  payload <- readRDS(session_file)
  payload$tool_result_envelopes[[1L]]$value <- "tampered"
  saveRDS(payload, session_file)

  old_turns <- list(create_mock_user_turn("Keep this turn"))
  receiver_chat <- create_mock_chat()
  receiver_chat$set_turns(old_turns)
  receiver_chat$set_system_prompt("Keep this prompt")
  receiver <- Agent$new(
    chat = receiver_chat,
    context_policy = policy,
    session_id = "corrupt-receiver-session"
  )

  expect_error(
    suppressMessages(receiver$load_session(session_file)),
    class = "deputy_session_load"
  )
  expect_equal(receiver$get_turns(), old_turns)
  expect_identical(receiver$get_system_prompt(), "Keep this prompt")
  expect_false(dir.exists(tool_result_offload_dir(
    policy,
    "corrupt-receiver-session"
  )))
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

test_that("set_system_prompt recovers a retained compaction summary", {
  probe <- new.env(parent = emptyenv())
  chat <- create_compaction_mock_chat(
    responses = list("Replacement summary"),
    probe = probe
  )
  chat$set_system_prompt("Base prompt")
  chat$set_turns(list(
    create_mock_user_turn("Q1"),
    create_mock_assistant_turn("A1"),
    create_mock_user_turn("Q2")
  ))
  agent <- Agent$new(chat = chat)
  agent$compact(keep_last = 1L, summary = "Retained summary")

  agent$set_system_prompt(paste(
    agent$get_system_prompt(),
    "Keep this addition",
    sep = "\n\n"
  ))
  chat$set_turns(list(
    create_mock_user_turn("Q2"),
    create_mock_assistant_turn("A2"),
    create_mock_user_turn("Q3")
  ))
  agent$compact(keep_last = 1L)

  expect_match(
    probe$summary_call$prompt,
    "Existing summary from earlier compactions:\nRetained summary",
    fixed = TRUE
  )
  expect_match(agent$get_system_prompt(), "Keep this addition", fixed = TRUE)
})

test_that("set_turns clears compacted history but preserves prompt additions", {
  chat <- create_mock_chat()
  chat$set_system_prompt("Base prompt")
  chat$set_turns(list(
    create_mock_user_turn("Q1"),
    create_mock_assistant_turn("A1"),
    create_mock_user_turn("Q2")
  ))
  agent <- Agent$new(chat = chat)
  agent$compact(keep_last = 1L, summary = "History to clear")
  agent$.__enclos_env__$private$append_hook_context("Keep this context")

  agent$set_turns(list())

  expect_length(agent$get_turns(), 0L)
  expect_match(agent$get_system_prompt(), "Base prompt", fixed = TRUE)
  expect_match(agent$get_system_prompt(), "Keep this context", fixed = TRUE)
  expect_no_match(agent$get_system_prompt(), "History to clear", fixed = TRUE)
  expect_null(agent$.__enclos_env__$private$.compaction_summary)
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

test_that("R code tools execute from the Agent workspace", {
  skip_on_cran()
  skip_if_not_installed("callr")
  root <- withr::local_tempdir(pattern = "deputy-r-workspace-")
  outside <- withr::local_tempdir(pattern = "deputy-r-outside-")
  agent <- Agent$new(
    chat = create_mock_chat(),
    tools = list(tool_run_r_code),
    working_dir = root,
    context_policy = ContextPolicy(max_tool_result_bytes = NULL)
  )
  withr::local_dir(outside)

  result <- agent$get_tools()[["run_r_code"]](paste(
    "writeLines(getwd(), 'r-working-dir.txt')",
    "getwd()",
    sep = "; "
  ))

  expected <- file.path(root, "r-working-dir.txt")
  expect_match(result, normalizePath(root, winslash = "/"), fixed = TRUE)
  expect_true(file.exists(expected))
  expect_false(file.exists(file.path(outside, "r-working-dir.txt")))
})

test_that("bash tools execute from the Agent workspace", {
  skip_on_cran()
  skip_on_os("windows")
  root <- withr::local_tempdir(pattern = "deputy-bash-workspace-")
  outside <- withr::local_tempdir(pattern = "deputy-bash-outside-")
  agent <- Agent$new(
    chat = create_mock_chat(),
    tools = list(tool_run_bash),
    working_dir = root,
    context_policy = ContextPolicy(max_tool_result_bytes = NULL)
  )
  withr::local_dir(outside)

  result <- agent$get_tools()[["run_bash"]](
    "pwd > bash-working-dir.txt; pwd"
  )

  expected <- file.path(root, "bash-working-dir.txt")
  expect_match(result, normalizePath(root, winslash = "/"), fixed = TRUE)
  expect_true(file.exists(expected))
  expect_false(file.exists(file.path(outside, "bash-working-dir.txt")))
})
