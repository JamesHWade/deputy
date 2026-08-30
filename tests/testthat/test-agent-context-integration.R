test_that("constructor run context is canonical and read-only", {
  input <- list(
    zeta = list(stage = "draft", alpha = 1L),
    product = "tempest",
    research_run_id = "research-123"
  )
  agent <- Agent$new(
    chat = create_mock_chat("done"),
    run_context = input,
    agent_id = "agent-context",
    agent_name = "evidence-reviewer"
  )

  input$zeta$alpha <- 99L
  expected <- list(
    product = "tempest",
    research_run_id = "research-123",
    zeta = list(alpha = 1L, stage = "draft")
  )
  expect_identical(agent$run_context, expected)
  expect_identical(agent$agent_id, "agent-context")
  expect_identical(agent$agent_name, "evidence-reviewer")

  returned <- agent$run_context
  returned$zeta$alpha <- 100L
  expect_identical(agent$run_context, expected)

  agent_error <- tryCatch(
    {
      agent$run_context <- list(product = "another-product")
      NULL
    },
    error = identity
  )
  expect_s3_class(agent_error, "error")
  expect_match(conditionMessage(agent_error), "run_context is immutable")

  result <- agent$run_sync("Finish the task")
  result_context <- result$run_context
  result_context$zeta$stage <- "changed"
  expect_identical(result$run_context, expected)

  result_error <- tryCatch(
    {
      result$run_context <- list()
      NULL
    },
    error = identity
  )
  expect_s3_class(result_error, "error")
  expect_match(conditionMessage(result_error), "run_context is immutable")
})

test_that("correlation identifiers do not change the caller RNG stream", {
  set.seed(42)
  expected <- runif(3)

  set.seed(42)
  first <- Agent$new(chat = create_mock_chat("first"))
  second <- Agent$new(chat = create_mock_chat("second"))
  first$run_sync("Generate run correlation")
  observed <- runif(3)

  expect_identical(observed, expected)
  expect_false(identical(first$agent_id, second$agent_id))
})

test_that("per-run context merges into result and terminal events", {
  defaults <- list(
    product = "tempest",
    research_run_id = "research-123",
    settings = list(mode = "strict", request_limit = 5L)
  )
  agent <- Agent$new(
    chat = create_mock_chat("done"),
    run_context = defaults,
    agent_id = "agent-merge",
    session_id = "session-merge"
  )

  result <- agent$run_sync(
    "Extract claims",
    run_context = list(
      settings = list(request_limit = 2L),
      stage = "extract_claims"
    )
  )
  expected <- list(
    product = "tempest",
    research_run_id = "research-123",
    settings = list(mode = "strict", request_limit = 2L),
    stage = "extract_claims"
  )
  start <- Filter(
    function(event) identical(event$type, "start"),
    result$events
  )[[1L]]
  stop <- Filter(
    function(event) identical(event$type, "stop"),
    result$events
  )[[1L]]

  expect_identical(result$run_context, expected)
  expect_identical(start$run_context, expected)
  expect_identical(stop$run_context, expected)
  expect_identical(start$run_id, stop$run_id)
  expect_identical(result$run_id, stop$run_id)
  expect_identical(result$session_id, "session-merge")
  expect_identical(start$session_id, "session-merge")
  expect_identical(stop$session_id, "session-merge")
  expect_identical(start$agent_id, "agent-merge")
  expect_identical(stop$agent_id, "agent-merge")
})

test_that("session identifiers are validated at construction", {
  expect_error(
    Agent$new(chat = create_mock_chat(), session_id = "../unsafe"),
    class = "deputy_id_error"
  )
})

test_that("per-run context cannot replace protected constructor identity", {
  chat <- create_mock_chat("unused")
  old_turns <- list(create_mock_user_turn("preserve me"))
  chat$set_turns(old_turns)
  agent <- Agent$new(
    chat = chat,
    run_context = list(
      product = "tempest",
      research_run_id = "research-123"
    )
  )

  error <- tryCatch(
    agent$run_sync(
      "Do not start",
      run_context = list(research_run_id = "research-elsewhere")
    ),
    error = identity
  )

  expect_s3_class(error, "deputy_run_context_conflict")
  expect_s3_class(error, "deputy_run_context_error")
  expect_equal(chat$get_turns(), old_turns)
  expect_identical(agent$.__enclos_env__$private$run_active, FALSE)
})

test_that("sequential runs do not leak per-run context", {
  agent <- Agent$new(
    chat = create_mock_chat(c("first", "second")),
    run_context = list(
      product = "tempest",
      research_run_id = "research-123",
      shared = list(policy = "strict")
    )
  )

  first <- agent$run_sync(
    "First task",
    run_context = list(stage = "extract", candidate = "claim-1")
  )
  second <- agent$run_sync(
    "Second task",
    run_context = list(stage = "verify")
  )

  expect_identical(first$run_context$candidate, "claim-1")
  expect_identical(first$run_context$stage, "extract")
  expect_null(second$run_context$candidate)
  expect_identical(second$run_context$stage, "verify")
  expect_identical(identical(first$run_id, second$run_id), FALSE)
  expect_identical(
    agent$run_context,
    list(
      product = "tempest",
      research_run_id = "research-123",
      shared = list(policy = "strict")
    )
  )
  expect_null(agent$.__enclos_env__$private$event_correlation()$run_id)
})

test_that("drop-in Chat streams accept per-run product context", {
  chat <- create_mock_chat("context response")
  agent <- Agent$new(
    chat = chat,
    run_context = list(product = "tempest", session = "research-1")
  )

  methods <- c(
    "chat",
    "chat_async",
    "chat_structured",
    "chat_structured_async",
    "stream",
    "stream_async"
  )
  for (method in methods) {
    expect_true("run_context" %in% names(formals(agent[[method]])))
  }

  stream <- agent$stream_async(
    "Research",
    run_context = list(stage = "dialogue", completion = "completion-1")
  )
  expect_equal(collect_async_stream(stream), list("context response"))
  expect_identical(
    agent$last_run()$run_context,
    list(
      completion = "completion-1",
      product = "tempest",
      session = "research-1",
      stage = "dialogue"
    )
  )
})

test_that("lazy generators retain their intended run contexts", {
  agent <- Agent$new(
    chat = create_mock_chat(c("first", "second")),
    run_context = list(
      product = "tempest",
      research_run_id = "research-123"
    )
  )

  first <- agent$run("First task", run_context = list(stage = "first"))
  second <- agent$run("Second task", run_context = list(stage = "second"))
  first_events <- collect_agent_events(first)
  second_events <- collect_agent_events(second)

  first_start <- Filter(
    function(event) identical(event$type, "start"),
    first_events
  )[[1L]]
  first_stop <- Filter(
    function(event) identical(event$type, "stop"),
    first_events
  )[[1L]]
  second_start <- Filter(
    function(event) identical(event$type, "start"),
    second_events
  )[[1L]]
  second_stop <- Filter(
    function(event) identical(event$type, "stop"),
    second_events
  )[[1L]]

  expect_identical(first_start$run_context$stage, "first")
  expect_identical(first_stop$run_context$stage, "first")
  expect_identical(second_start$run_context$stage, "second")
  expect_identical(second_stop$run_context$stage, "second")
  expect_identical(identical(first_start$run_id, second_start$run_id), FALSE)
})

test_that("tool events and major hooks share run correlation", {
  root <- withr::local_tempdir(pattern = "deputy-context-hooks-")
  mock <- create_content_stream_chat()
  seen <- new.env(parent = emptyenv())
  agent <- Agent$new(
    chat = mock$chat,
    tools = list(mock$tool),
    permissions = permissions_standard(root),
    working_dir = root,
    agent_id = "agent-hooks",
    agent_name = "evidence-reviewer",
    run_context = list(
      product = "tempest",
      research_run_id = "research-123",
      scientific = list(policy = list(domain = "chemistry"))
    )
  )
  agent$add_hook(HookMatcher$new(
    event = "SessionStart",
    timeout = 0,
    callback = function(context) {
      seen$SessionStart <- context
      NULL
    }
  ))
  agent$add_hook(HookMatcher$new(
    event = "UserPromptSubmit",
    timeout = 0,
    callback = function(prompt, context) {
      seen$UserPromptSubmit <- context
      NULL
    }
  ))
  agent$add_hook(HookMatcher$new(
    event = "PreToolUse",
    timeout = 0,
    callback = function(tool_name, tool_input, context) {
      seen$PreToolUse <- context
      HookResultPreToolUse(permission = "allow")
    }
  ))
  agent$add_hook(HookMatcher$new(
    event = "PostToolUse",
    timeout = 0,
    callback = function(tool_name, tool_result, tool_error, context) {
      seen$PostToolUse <- context
      HookResultPostToolUse()
    }
  ))
  agent$add_hook(HookMatcher$new(
    event = "Stop",
    timeout = 0,
    callback = function(reason, context) {
      seen$Stop <- context
      NULL
    }
  ))
  agent$add_hook(HookMatcher$new(
    event = "SessionEnd",
    timeout = 0,
    callback = function(reason, context) {
      seen$SessionEnd <- context
      NULL
    }
  ))

  result <- agent$run_sync(
    "Review evidence",
    run_context = list(
      scientific = list(
        policy = list(revision = 2L),
        role = "reviewer"
      ),
      stage = "verify_claims"
    )
  )
  expected_context <- list(
    product = "tempest",
    research_run_id = "research-123",
    scientific = list(
      policy = list(domain = "chemistry", revision = 2L),
      role = "reviewer"
    ),
    stage = "verify_claims"
  )
  hook_names <- c(
    "SessionStart",
    "UserPromptSubmit",
    "PreToolUse",
    "PostToolUse",
    "Stop",
    "SessionEnd"
  )
  contexts <- lapply(hook_names, get, envir = seen, inherits = FALSE)
  names(contexts) <- hook_names

  expect_setequal(ls(seen), hook_names)
  for (context in contexts) {
    expect_identical(context$run_context, expected_context)
    expect_identical(context$agent_id, "agent-hooks")
    expect_identical(context$agent_name, "evidence-reviewer")
    expect_identical(context$run_id, result$run_id)
  }

  tool_start <- Filter(
    function(event) identical(event$type, "tool_start"),
    result$events
  )[[1L]]
  tool_end <- Filter(
    function(event) identical(event$type, "tool_end"),
    result$events
  )[[1L]]
  expect_identical(tool_start$tool_call_id, "tool-use-1")
  expect_identical(tool_end$tool_call_id, tool_start$tool_call_id)
  expect_identical(tool_start$agent_id, "agent-hooks")
  expect_identical(tool_end$agent_id, tool_start$agent_id)
  expect_identical(tool_start$run_id, result$run_id)
  expect_identical(tool_end$run_id, tool_start$run_id)
  expect_identical(tool_start$run_context, expected_context)
  expect_identical(tool_end$run_context, expected_context)
  expect_identical(
    contexts$PreToolUse$tool_call_id,
    tool_start$tool_call_id
  )
  expect_identical(
    contexts$PostToolUse$tool_call_id,
    tool_start$tool_call_id
  )
})

test_that("missing provider IDs fail closed when correlation is ambiguous", {
  agent <- Agent$new(chat = create_mock_chat())
  private <- agent$.__enclos_env__$private
  extracted <- list(
    tool_name = "inspect_evidence",
    tool_input = list(claim = "claim-1"),
    provider_tool_call_id = NULL
  )

  first_start <- private$tool_start_event(extracted)
  error <- tryCatch(
    private$tool_start_event(extracted),
    error = identity
  )

  expect_match(first_start$tool_call_id, "^tool_")
  expect_s3_class(error, "deputy_tool_correlation_error")
  expect_s3_class(error, "deputy_error")

  first_end <- private$tool_end_event(c(
    extracted,
    list(tool_result = "first", tool_error = NULL)
  ))
  second_start <- private$tool_start_event(extracted)
  second_end <- private$tool_end_event(c(
    extracted,
    list(tool_result = "second", tool_error = NULL)
  ))

  expect_identical(first_end$tool_call_id, first_start$tool_call_id)
  expect_identical(second_end$tool_call_id, second_start$tool_call_id)
  expect_false(identical(second_start$tool_call_id, first_start$tool_call_id))
})

test_that("manual save and load preserve run context", {
  root <- withr::local_tempdir(pattern = "deputy-context-session-")
  path <- file.path(root, "session.rds")
  saved_turns <- list(
    create_mock_user_turn("Remember this"),
    create_mock_assistant_turn("Context saved")
  )
  source_chat <- create_mock_chat()
  source_chat$set_turns(saved_turns)
  source <- Agent$new(
    chat = source_chat,
    system_prompt = "Saved prompt",
    run_context = list(
      product = "tempest",
      research_run_id = "research-123",
      nested = list(role = "reviewer")
    )
  )
  suppressMessages(source$save_session(path))

  payload <- readRDS(path)
  expected <- list(
    nested = list(role = "reviewer"),
    product = "tempest",
    research_run_id = "research-123"
  )
  expect_identical(payload$schema_version, 2L)
  expect_identical(payload$run_context, expected)

  restored_chat <- create_mock_chat()
  restored <- Agent$new(chat = restored_chat)
  suppressMessages(restored$load_session(path))

  expect_identical(restored$run_context, expected)
  expect_equal(restored_chat$get_turns(), saved_turns)
  expect_identical(restored_chat$get_system_prompt(), "Saved prompt")
})

test_that("manual save after a run preserves its effective context", {
  root <- withr::local_tempdir(pattern = "deputy-context-last-run-")
  path <- file.path(root, "session.rds")
  source <- Agent$new(
    chat = create_mock_chat("verified"),
    run_context = list(
      product = "tempest",
      research_run_id = "research-123"
    )
  )
  result <- source$run_sync(
    "Verify claims",
    run_context = list(stage = "verify_claims")
  )
  suppressMessages(source$save_session(path))

  expected <- list(
    product = "tempest",
    research_run_id = "research-123",
    stage = "verify_claims"
  )
  payload <- readRDS(path)
  expect_identical(result$run_context, expected)
  expect_identical(payload$run_context, expected)

  restored <- Agent$new(chat = create_mock_chat())
  suppressMessages(restored$load_session(path))
  expect_identical(restored$run_context, expected)
})

test_that("unsupported session schemas are rejected", {
  root <- withr::local_tempdir(pattern = "deputy-context-unsupported-")
  path <- file.path(root, "unsupported.rds")
  unsupported_turns <- list(create_mock_user_turn("Unsupported conversation"))
  saveRDS(
    list(
      turns = unsupported_turns,
      system_prompt = "Unsupported prompt",
      metadata = list()
    ),
    path
  )
  agent <- Agent$new(
    chat = create_mock_chat(),
    run_context = list(
      product = "tempest",
      research_run_id = "research-current"
    )
  )

  expect_error(
    suppressMessages(agent$load_session(path)),
    class = "deputy_session_load"
  )
  expect_length(agent$get_turns(), 0L)
})

test_that("unsafe restored context is rejected before conversation mutation", {
  root <- withr::local_tempdir(pattern = "deputy-context-unsafe-")
  old_turns <- list(create_mock_user_turn("Keep this conversation"))
  unsafe_turns <- list(create_mock_user_turn("Do not restore this"))
  secret <- "super-secret-value-that-must-not-leak"
  cases <- list(
    conflict = list(
      context = list(
        product = "tempest",
        research_run_id = "research-saved"
      ),
      parent_class = "deputy_run_context_conflict"
    ),
    credential = list(
      context = list(api_key = secret),
      parent_class = "deputy_run_context_error"
    )
  )

  for (case_name in names(cases)) {
    case <- cases[[case_name]]
    path <- file.path(root, paste0(case_name, ".rds"))
    saveRDS(
      list(
        schema_version = 2L,
        turns = unsafe_turns,
        system_prompt = "Unsafe prompt",
        compaction_summary = NULL,
        tool_result_envelopes = list(),
        run_context = case$context,
        appended_hook_context_hashes = character(),
        file_checkpoint_state = NULL,
        metadata = list(session_id = paste0("unsafe-", case_name))
      ),
      path
    )
    chat <- create_mock_chat()
    chat$set_turns(old_turns)
    chat$set_system_prompt("Original prompt")
    agent <- Agent$new(
      chat = chat,
      run_context = list(
        product = "tempest",
        research_run_id = "research-current"
      )
    )

    error <- tryCatch(
      suppressMessages(agent$load_session(path)),
      error = identity
    )

    expect_s3_class(error, "deputy_session_load")
    expect_s3_class(error$parent, case$parent_class)
    expect_identical(
      grepl(secret, conditionMessage(error), fixed = TRUE),
      FALSE,
      info = case_name
    )
    expect_identical(
      grepl(secret, conditionMessage(error$parent), fixed = TRUE),
      FALSE,
      info = case_name
    )
    expect_equal(chat$get_turns(), old_turns, info = case_name)
    expect_identical(
      chat$get_system_prompt(),
      "Original prompt",
      info = case_name
    )
    expect_identical(
      agent$run_context,
      list(
        product = "tempest",
        research_run_id = "research-current"
      ),
      info = case_name
    )
  }
})
