test_that("native shinychat history retains later replies across repeated compaction", {
  skip_if_not_installed("shinychat")
  skip_if_not(all(
    c("chat_server", "history_options", "FileConversationStore") %in%
      getNamespaceExports("shinychat")
  ))
  directory <- withr::local_tempdir()
  server <- local_runtime_server(local({
    replies <- list(
      summary = runtime_reply("Retain the evidence."),
      evidence = runtime_reply(tool = "evidence"),
      "Initial question" = runtime_reply("Initial explanation"),
      "First later question" = runtime_reply("First later explanation"),
      "Second later question" = runtime_reply("Second later explanation"),
      "Unrelated question" = runtime_reply("Separate conversation"),
      "Alternate later question" = runtime_reply("Alternate branch answer")
    )
    function(request, count) {
      if (is.null(request$tools)) {
        return(replies$summary)
      }
      users <- Filter(
        function(message) identical(message$role, "user"),
        request$messages
      )
      question <- tail(users, 1L)[[1L]]$content[[1L]]$text
      if (
        question %in%
          c("First later question", "Second later question") &&
          !identical(tail(request$messages, 1L)[[1L]]$role, "tool")
      ) {
        return(replies$evidence)
      }
      replies[[question]]
    }
  }))
  chat <- runtime_chat(server)
  compact_now <- FALSE
  rlang::env_binding_unlock(chat, "token_count")
  chat$token_count <- function(...) if (compact_now) 1000 else 0
  seed <- unlist(
    lapply(seq_len(22), function(i) {
      list(
        create_mock_user_turn(paste("Question", i)),
        create_mock_assistant_turn(paste("Answer", i))
      )
    }),
    recursive = FALSE
  )
  chat$set_turns(seed)
  effects <- 0L
  tool <- ellmer::tool(
    function() {
      effects <<- effects + 1L
      paste("Evidence", effects)
    },
    name = "evidence",
    description = "Read evidence",
    arguments = list(),
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE,
      destructive_hint = FALSE
    )
  )
  agent <- Agent$new(
    chat = chat,
    tools = list(tool),
    context_policy = ContextPolicy(
      max_tokens = 50,
      offload_dir = file.path(directory, "offload")
    )
  )
  session <- shiny::MockShinySession$new()
  withr::defer(session$close())
  module <- shinychat::chat_server(
    "chat",
    agent,
    history = shinychat::history_options(
      store = shinychat::FileConversationStore$new(file.path(
        directory,
        "history"
      )),
      scope = "workspace-a",
      title = NULL
    ),
    session = session
  )
  notice_example <- new.env(parent = baseenv())
  sys.source(
    system.file(
      "examples",
      "shiny-chat",
      "compaction-notice.R",
      package = "deputy"
    ),
    envir = notice_example
  )
  shiny::withReactiveDomain(session, {
    notice_example$compaction_notice_server(
      "compaction",
      agent,
      module,
      session
    )
  })
  busy_notices <- character()
  agent$add_hook(HookMatcher(
    event = "PreCompact",
    callback = function(...) {
      session$flushReact()
      busy_notices <<- c(busy_notices, session$getOutput("compaction")$html)
      NULL
    }
  ))
  session$setInputs(chat_history_browser_token = "browser-a")
  expect_null(session$getOutput("compaction"))
  append <- function(prompt) {
    shiny::withReactiveDomain(session, {
      resolve_async_value(
        shinychat::chat_append(
          "chat",
          agent$stream_async(prompt, stream = "content"),
          session = session
        ),
        max_polls = 1000L
      )
    })
    session$flushReact()
    expect_identical(shiny::isolate(module$history$save()), TRUE)
  }
  append("Initial question")
  original_id <- shiny::isolate(module$history$conversation_id())
  expect_length(agent$get_turns(), 46L)
  compact_now <- TRUE
  append("First later question")
  append("Second later question")
  expect_gt(length(busy_notices), 0L)
  expect_true(all(grepl("Summarizing earlier messages", busy_notices)))
  notice_html <- session$getOutput("compaction")$html
  expect_match(
    notice_html,
    "Your full conversation is still available",
    fixed = TRUE
  )
  expect_match(notice_html, "<summary>View summary</summary>", fixed = TRUE)
  expect_match(notice_html, "Retain the evidence.", fixed = TRUE)
  expect_false(grepl("Summarizing earlier messages", notice_html))
  expect_identical(effects, 2L)
  expect_length(agent$get_turns(), 54L)
  expect_lt(length(chat$get_turns()), 54L)
  expect_identical(agent$last_compaction()$automatic, TRUE)
  requests <- server$requests()
  later_requests <- Filter(
    function(request) !is.null(request$body$tools),
    requests
  )[-1L]
  expect_identical(length(later_requests), 4L)
  expect_identical(
    all(vapply(
      later_requests,
      function(request) {
        length(request$body$messages) < 46L
      },
      logical(1)
    )),
    TRUE
  )
  expected <- lapply(agent$get_turns(), ellmer::contents_record)
  session$setInputs(chat_history_new = 1L)
  expect_null(session$getOutput("compaction"))
  expect_length(agent$get_turns(), 0L)
  compact_now <- FALSE
  append("Unrelated question")
  other_id <- shiny::isolate(module$history$conversation_id())
  expect_identical(identical(other_id, original_id), FALSE)
  session$setInputs(chat_history_select = list(id = original_id))
  expect_null(session$getOutput("compaction"))
  expect_length(agent$get_turns(), 54L)
  expect_identical(lapply(agent$get_turns(), ellmer::contents_record), expected)
  expect_identical(effects, 2L)
  session$setInputs(chat_history_select = list(id = other_id))
  expect_length(agent$get_turns(), 2L)
  expect_match(format(agent$last_turn()), "Separate conversation", fixed = TRUE)
  session$setInputs(chat_history_select = list(id = original_id))
  session$setInputs(
    chat_message_edit = list(index = 46L, content = "Alternate later question")
  )
  expect_null(session$getOutput("compaction"))
  expect_length(agent$get_turns(), 46L)
  append("Alternate later question")
  alternate <- lapply(agent$get_turns(), ellmer::contents_record)
  expect_length(alternate, 48L)
  session$setInputs(
    chat_message_navigate = list(index = 46L, direction = "prev")
  )
  expect_identical(lapply(agent$get_turns(), ellmer::contents_record), expected)
  session$setInputs(
    chat_message_navigate = list(index = 46L, direction = "next")
  )
  expect_identical(
    lapply(agent$get_turns(), ellmer::contents_record),
    alternate
  )
  expect_identical(effects, 2L)

  for (scope in c("workspace-a", "workspace-b")) {
    fresh <- Agent$new(runtime_chat(server))
    fresh_session <- shiny::MockShinySession$new()
    withr::defer(fresh_session$close())
    shinychat::chat_server(
      "chat",
      fresh,
      history = shinychat::history_options(
        store = shinychat::FileConversationStore$new(file.path(
          directory,
          "history"
        )),
        scope = scope,
        title = NULL
      ),
      session = fresh_session
    )
    fresh_session$setInputs(
      chat_history_browser_token = paste0("browser-", scope),
      chat_history_current_id = original_id
    )
    expect_identical(
      lapply(fresh$get_turns(), ellmer::contents_record),
      if (scope == "workspace-a") alternate else list()
    )
  }
})

test_that("conversation and model views survive repeated compaction and replacement", {
  chat <- runtime_chat(local_runtime_server(list(runtime_reply())))
  agent <- Agent$new(chat, system_prompt = "Host instructions")
  agent$add_turn(
    create_mock_user_turn("Question one"),
    create_mock_assistant_turn("Answer one")
  )
  agent$add_turn(
    create_mock_user_turn("Question two"),
    create_mock_assistant_turn("Answer two")
  )
  original <- agent$get_turns()
  agent$compact(keep_last = 2L, summary = "First summary")
  expect_identical(agent$get_turns(), original)
  expect_identical(agent$turns(), original)
  expect_identical(agent$get_context_turns(), tail(original, 2L))
  with_system <- agent$get_turns(include_system_prompt = TRUE)
  expect_identical(with_system[-1L], original)
  expect_identical(with_system[[1L]]@role, "system")
  expect_match(with_system[[1L]]@text, "First summary", fixed = TRUE)
  agent$add_turn(
    create_mock_user_turn("Question three"),
    create_mock_assistant_turn("Answer three")
  )
  agent$compact(keep_last = 0L, summary = "Second summary")
  expect_length(agent$get_turns(), 6L)
  expect_length(agent$get_context_turns(), 0L)
  expect_identical(agent$last_turn()@text, "Answer three")
  expect_identical(agent$last_turn("user")@text, "Question three")
  clone <- agent$clone()
  clone$set_turns(original[1:2])
  clone$add_turn(
    create_mock_user_turn("Branch question"),
    create_mock_assistant_turn("Branch answer")
  )
  clone$compact(keep_last = 0L, summary = "Branch summary")
  expect_length(clone$get_turns(), 4L)
  expect_identical(clone$last_turn()@text, "Branch answer")
  expect_length(agent$get_turns(), 6L)
  expect_identical(agent$last_turn()@text, "Answer three")
  agent$set_turns(list())
  expect_length(agent$get_turns(), 0L)
  expect_length(agent$get_context_turns(), 0L)
  expect_null(agent$last_turn())
  expect_identical(agent$get_system_prompt(), "Host instructions")
})

test_that("session snapshots retain both views without executable archived tools", {
  directory <- withr::local_tempdir()
  server <- local_runtime_server(list(
    runtime_reply(tool = "run_r_code", arguments = list(code = "plot(1:3)")),
    runtime_reply("A saved plot")
  ))
  agent <- Agent$new(
    runtime_chat(server),
    working_dir = directory,
    permissions = Permissions(r_code = TRUE),
    context_policy = ContextPolicy(
      max_tokens = NULL,
      offload_dir = file.path(directory, "results")
    )
  )
  runtime <- RSession$new(agent)
  withr::defer(runtime$close())
  agent$register_tools(runtime$tools())
  agent$run_sync("Plot the values")
  recorded <- lapply(agent$get_turns(), ellmer::contents_record)
  agent$compact(keep_last = 0L, summary = "Values were plotted.")
  expect_identical(lapply(agent$get_turns(), ellmer::contents_record), recorded)
  path <- file.path(directory, "session.rds")
  suppressMessages(agent$save_session(path))
  runtime$close()
  snapshot <- readRDS(path)
  expect_length(snapshot$turns, 0L)
  expect_length(snapshot$compacted_turns, 4L)
  request <- snapshot$compacted_turns[[2L]]@contents[[1L]]
  result <- snapshot$compacted_turns[[3L]]@contents[[1L]]
  expect_null(request@tool)
  expect_null(result@request@tool)
  expect_match(
    as.character(result@extra$display$html),
    "data:image/png;base64,",
    fixed = TRUE
  )
  restored <- Agent$new(
    runtime_chat(server),
    permissions = permissions_readonly(),
    context_policy = ContextPolicy(
      offload_dir = file.path(directory, "restored")
    )
  )
  suppressMessages(restored$load_session(path))
  expect_identical(
    lapply(restored$get_turns(), ellmer::contents_record),
    recorded
  )
  expect_length(restored$get_context_turns(), 0L)
  expect_identical(restored$get_permission_mode(), "readonly")
  expect_identical("run_r_code" %in% names(restored$get_tools()), FALSE)
  restored$add_turn(
    create_mock_user_turn("Continue"),
    create_mock_assistant_turn("New evidence")
  )
  restored$compact(keep_last = 0L, summary = "Continued")
  expect_length(restored$get_turns(), 6L)
  expect_identical(restored$last_turn()@text, "New evidence")
})

test_that("invalid saved history cannot partially replace a conversation", {
  directory <- withr::local_tempdir()
  agent <- Agent$new(runtime_chat(local_runtime_server(list(runtime_reply()))))
  agent$add_turn(
    create_mock_user_turn("Keep question"),
    create_mock_assistant_turn("Keep answer")
  )
  agent$compact(keep_last = 0L, summary = "Keep summary")
  before <- agent$get_turns()
  path <- file.path(directory, "session.rds")
  suppressMessages(agent$save_session(path))
  payload <- readRDS(path)
  payload$compacted_turns <- list("Invalid turn")
  saveRDS(payload, path)
  failure <- tryCatch(agent$load_session(path), deputy_session_load = identity)
  expect_s3_class(failure, "deputy_session_load")
  expect_match(conditionMessage(failure), "compacted_turns", fixed = TRUE)
  expect_identical(agent$get_turns(), before)
  expect_length(agent$get_context_turns(), 0L)
  expect_match(agent$get_system_prompt(), "Keep summary", fixed = TRUE)
})

test_that("failed context installation leaves the retained transcript unchanged", {
  chat <- runtime_chat(local_runtime_server(list(runtime_reply())))
  agent <- Agent$new(chat, system_prompt = "Original instructions")
  agent$add_turn(
    create_mock_user_turn("First question"),
    create_mock_assistant_turn("First answer")
  )
  agent$add_turn(
    create_mock_user_turn("Second question"),
    create_mock_assistant_turn("Second answer")
  )
  agent$compact(keep_last = 2L, summary = "Existing summary")
  original <- agent$get_turns()
  context <- agent$get_context_turns()
  original_set <- chat$set_system_prompt
  reject <- TRUE
  rlang::env_binding_unlock(chat, "set_system_prompt")
  chat$set_system_prompt <- function(value) {
    if (reject) {
      reject <<- FALSE
      rlang::abort("Injected prompt installation failure")
    }
    original_set(value)
  }
  failure <- tryCatch(
    agent$compact(keep_last = 0L, summary = "Replacement"),
    error = identity
  )
  expect_s3_class(failure, "error")
  expect_identical(agent$get_turns(), original)
  expect_identical(agent$get_context_turns(), context)
  reject <- TRUE
  failure <- tryCatch(agent$set_turns(list()), error = identity)
  expect_s3_class(failure, "error")
  expect_identical(agent$get_turns(), original)
  expect_identical(agent$get_context_turns(), context)
  agent$compact(keep_last = 0L, summary = "Replacement")
  expect_identical(agent$get_turns(), original)
  expect_length(agent$get_context_turns(), 0L)
})
