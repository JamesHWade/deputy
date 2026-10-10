conversation_state_turns <- function() {
  request <- ellmer::ContentToolRequest(
    id = "conversation-state-tool",
    name = "search",
    arguments = list()
  )
  list(
    create_mock_user_turn("Earlier question"),
    ellmer::AssistantTurn(contents = list(request)),
    ellmer::UserTurn(
      contents = list(
        ellmer::ContentToolResult(
          value = "conversation state result",
          request = request
        )
      )
    ),
    create_mock_assistant_turn("Earlier answer"),
    create_mock_user_turn("Latest question")
  )
}

conversation_state_result_values <- function(turns) {
  unlist(lapply(turns, function(turn) {
    vapply(
      Filter(
        function(content) {
          S7::S7_inherits(content, ellmer::ContentToolResult)
        },
        turn@contents
      ),
      function(content) content@value,
      character(1)
    )
  }))
}

test_that("compaction after provider fallback uses the active Chat clone", {
  withr::local_options(ellmer_max_tries = 1)
  primary <- local_runtime_server(list(runtime_failure()))
  backup <- local_runtime_server(list(
    runtime_reply("Fallback task response"),
    runtime_reply("Fallback summary", stream = FALSE)
  ))
  agent <- Agent$new(
    runtime_chat(primary, "primary"),
    fallback_chats = list(runtime_chat(backup, "backup"))
  )

  result <- agent$run_sync("Continue the task")
  before <- agent$get_turns()
  compaction <- agent$compact(keep_last = 0L)

  expect_identical(trimws(result$response), "Fallback task response")
  expect_identical(agent$get_model(), "backup")
  expect_identical(compaction$method, "llm")
  expect_identical(trimws(compaction$summary), "Fallback summary")
  expect_length(primary$requests(), 1L)
  expect_length(backup$requests(), 2L)
  expect_length(agent$get_context_turns(), 0L)
  expect_identical(agent$get_turns(), before)
})

test_that("automatic compaction rejects a PreCompact prompt and history mutation", {
  server <- local_runtime_server(list(runtime_reply("Stale summary")))
  agent <- Agent$new(
    runtime_compaction_chat(server),
    context_policy = ContextPolicy(max_tokens = 50)
  )
  replacement <- list(ellmer::UserTurn("Host replacement"))
  agent$add_hook(HookMatcher(
    event = "PreCompact",
    timeout = 0,
    callback = function(...) {
      agent$set_system_prompt("Host replacement prompt")
      agent$set_turns(replacement)
      NULL
    }
  ))

  error <- tryCatch(agent$run_sync("Continue"), error = identity)

  expect_s3_class(error, "deputy_compaction_conflict")
  expect_identical(agent$get_system_prompt(), "Host replacement prompt")
  expect_identical(agent$get_turns(), replacement)
  expect_identical(agent$get_context_turns(), replacement)
  expect_null(agent$last_compaction())
  expect_identical(agent$last_run()$stop_reason, "error")
  expect_length(server$requests(), 1L)
})

test_that("failed session installation preserves compacted receiver state", {
  directory <- withr::local_tempdir(
    pattern = "deputy-session-install-rollback-"
  )
  policy <- ContextPolicy(
    max_tokens = NULL,
    max_tool_result_bytes = 32,
    offload_dir = directory
  )
  result_tool <- function(value) {
    ellmer::tool(
      fun = function() value,
      name = "large_result",
      description = "Return a large result.",
      arguments = list()
    )
  }

  # Leave an old result envelope in the receiver's session directory while
  # constructing the receiver without a reader. This makes reader installation
  # part of the session restore transaction rather than prior setup.
  stale_value <- paste(rep("stale receiver result", 100), collapse = " ")
  stale_owner <- Agent$new(
    chat = create_mock_chat(),
    tools = list(result_tool(stale_value)),
    context_policy = policy,
    session_id = "session-install-receiver"
  )
  stale_reference <- stale_owner$get_tools()[["large_result"]]()

  source_value <- paste(rep("loaded source result", 100), collapse = " ")
  source <- Agent$new(
    chat = create_mock_chat(),
    tools = list(result_tool(source_value)),
    context_policy = policy,
    session_id = "session-install-source",
    system_prompt = "Source prompt"
  )
  loaded_reference <- source$get_tools()[["large_result"]]()
  source$set_turns(list(create_mock_user_turn(loaded_reference)))
  session_file <- file.path(directory, "source-session.rds")
  suppressMessages(source$save_session(session_file))

  receiver_chat <- create_mock_chat()
  receiver <- Agent$new(
    chat = receiver_chat,
    context_policy = policy,
    session_id = "session-install-receiver"
  )
  stale_request <- ellmer::ContentToolRequest(
    id = "stale-call",
    name = "large_result",
    arguments = list()
  )
  receiver$set_system_prompt("Receiver prompt")
  receiver$set_turns(list(
    create_mock_user_turn("Old receiver question"),
    ellmer::AssistantTurn(contents = list(stale_request)),
    ellmer::UserTurn(
      contents = list(
        ellmer::ContentToolResult(
          value = stale_reference,
          request = stale_request
        )
      )
    ),
    create_mock_assistant_turn("Old receiver answer"),
    create_mock_user_turn("Recent receiver question")
  ))
  receiver$microcompact(keep_last = 1L, marker = "[receiver cleared]")
  receiver$compact(keep_last = 1L, summary = "Receiver summary")

  before_turns <- receiver$get_turns()
  before_context <- receiver$get_context_turns()
  before_prompt <- receiver$get_system_prompt()
  expect_false(identical(before_turns, before_context))
  expect_identical(receiver$resolve_tool_result(stale_reference), stale_value)

  reject_reader <- TRUE
  original_register_tool <- receiver_chat$register_tool
  receiver_chat$register_tool <- function(tool) {
    if (reject_reader && identical(tool@name, "deputy_read_tool_result")) {
      original_register_tool(tool)
      stop("recovered reader registration failed")
    }
    original_register_tool(tool)
  }

  expect_error(
    suppressMessages(receiver$load_session(session_file)),
    "recovered reader registration failed",
    class = "deputy_session_load"
  )
  expect_identical(receiver$get_turns(), before_turns)
  expect_identical(receiver$get_context_turns(), before_context)
  expect_identical(receiver$get_system_prompt(), before_prompt)
  expect_identical(receiver$resolve_tool_result(stale_reference), stale_value)
  expect_error(receiver$resolve_tool_result(loaded_reference), "not found")
  expect_false("deputy_read_tool_result" %in% names(receiver$get_tools()))

  reject_reader <- FALSE
  suppressMessages(receiver$load_session(session_file))

  expect_identical(receiver$get_system_prompt(), source$get_system_prompt())
  expect_identical(
    lapply(receiver$get_turns(), ellmer::contents_record),
    lapply(source$get_turns(), ellmer::contents_record)
  )
  expect_identical(
    lapply(receiver$get_context_turns(), ellmer::contents_record),
    lapply(source$get_context_turns(), ellmer::contents_record)
  )
  expect_error(receiver$resolve_tool_result(stale_reference), "not found")
  expect_identical(receiver$resolve_tool_result(loaded_reference), source_value)
  expect_true("deputy_read_tool_result" %in% names(receiver$get_tools()))
  expect_match(
    receiver$get_tools()[["deputy_read_tool_result"]](
      loaded_reference,
      max_chars = 64L
    ),
    "loaded source result",
    fixed = TRUE
  )
})

test_that("failed same-Chat initialization preserves compacted state", {
  chat <- create_compaction_mock_chat()
  chat$set_turns(conversation_state_turns())
  agent <- Agent$new(
    chat = chat,
    system_prompt = "Receiver prompt"
  )
  agent$microcompact(keep_last = 2L, marker = "[receiver cleared]")
  agent$compact(keep_last = 4L, summary = "Receiver summary")

  before_turns <- lapply(agent$get_turns(), ellmer::contents_record)
  before_context <- lapply(
    agent$get_context_turns(),
    ellmer::contents_record
  )
  before_prompt <- agent$get_system_prompt()
  before_values <- conversation_state_result_values(agent$get_turns())
  expect_match(before_prompt, "Receiver summary", fixed = TRUE)
  expect_true(
    "[receiver cleared]" %in%
      conversation_state_result_values(agent$get_context_turns())
  )

  expect_error(
    agent$initialize(chat, context_policy = "not a policy"),
    "ContextPolicy"
  )

  expect_identical(
    lapply(agent$get_turns(), ellmer::contents_record),
    before_turns
  )
  expect_identical(
    lapply(agent$get_context_turns(), ellmer::contents_record),
    before_context
  )
  expect_identical(agent$get_system_prompt(), before_prompt)
  expect_identical(
    conversation_state_result_values(agent$get_turns()),
    before_values
  )

  expect_identical(
    agent$microcompact(keep_last = 0L, marker = "[second clear]")$cleared,
    0L
  )
  expect_identical(
    lapply(agent$get_turns(), ellmer::contents_record),
    before_turns
  )
  expect_identical(
    conversation_state_result_values(agent$get_turns()),
    before_values
  )

  agent$compact(keep_last = 2L, summary = "Retry summary")
  expect_identical(
    lapply(agent$get_turns(), ellmer::contents_record),
    before_turns
  )
  expect_identical(
    conversation_state_result_values(agent$get_turns()),
    before_values
  )
  expect_match(agent$get_system_prompt(), "Retry summary", fixed = TRUE)
})
