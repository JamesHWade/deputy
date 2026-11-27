test_that("stopping the presenter settles the cards it left running", {
  root_server <- local_runtime_server(list(
    runtime_reply(tool = "ask_sales", arguments = list(task = "Sales?")),
    runtime_reply("Lead done.")
  ))
  root <- Agent$new(
    runtime_chat(root_server),
    delegation_disclosure = activity_disclosure()
  )
  sales <- activity_specialist("sales", "60")
  activity_retain(root, sales$agent, "ask_sales")
  root$run_sync("Sales?")
  private <- root$.__enclos_env__$private
  id <- names(private$subagent_runs)[[1L]]
  private$subagent_runs[[id]]$turns <- private$subagent_runs[[id]]$turns[-3L]
  private$subagent_runs[[id]]$completed_at <- as.POSIXct(NA_real_, tz = "UTC")
  activity_enable(root, function() "viewer")
  activity_poll(root)
  shown <- activity_take(root)
  expect_length(shown, 1L)
  activity_disable(root)
  # Stopping again before the reply takes them keeps those results.
  activity_disable(root)
  # The reply still streaming gets the result too, once.
  live <- activity_take(root)
  expect_length(live, 1L)
  expect_identical(live[[1L]]@request@id, shown[[1L]]@id)
  expect_length(activity_take(root), 0L)
  cards <- activity_items(unlist(lapply(
    root$get_turns(),
    function(turn) turn@contents
  )))
  expect_length(cards, 2L)
  expect_s3_class(cards[[2L]], "ellmer::ContentToolResult")
  expect_identical(cards[[2L]]@request@id, shown[[1L]]@id)
  expect_match(cards[[2L]]@value, "activity stopped before this call returned")
  # Stopping again adds nothing.
  activity_disable(root)
  expect_length(activity_take(root), 0L)
  # What one reply left queued never reaches another.
  private$.activity_leftover <- list(run_id = "run_other", queue = shown)
  expect_length(activity_take(root), 0L)
  expect_null(private$.activity_leftover)
  expect_length(
    activity_items(unlist(lapply(
      root$get_turns(),
      function(turn) turn@contents
    ))),
    2L
  )
  # Nor does it reach a conversation that replaced the one it was shown in.
  private$.activity_leftover <- list(
    run_id = private$current_run_id,
    queue = live
  )
  root$set_turns(root$get_turns())
  expect_length(activity_take(root), 0L)
})

test_that("a lead shows activity through one presenter at a time", {
  root_server <- local_runtime_server(list(
    runtime_reply(tool = "ask_sales", arguments = list(task = "Sales?")),
    runtime_reply("Lead done.")
  ))
  root <- Agent$new(
    runtime_chat(root_server),
    delegation_disclosure = activity_disclosure()
  )
  sales <- activity_specialist("sales", "60")
  activity_retain(root, sales$agent, "ask_sales")
  root$run_sync("Sales?")
  private <- root$.__enclos_env__$private
  id <- names(private$subagent_runs)[[1L]]
  private$subagent_runs[[id]]$turns <- private$subagent_runs[[id]]$turns[-3L]
  private$subagent_runs[[id]]$completed_at <- as.POSIXct(NA_real_, tz = "UTC")
  first <- activity_enable(root, function() "viewer")
  activity_poll(root)
  shown <- activity_take(root)
  expect_length(shown, 1L)
  # A second presenter would show the call again and leave this card running.
  expect_error(activity_enable(root, function() "viewer"), "already shown")
  expect_identical(private$.activity, first)
  # Stopped and shown again during the same reply: the new presenter streams
  # the result the stopped one settled.
  activity_disable(root, first)
  second <- activity_enable(root, function() "viewer")
  live <- activity_take(root)
  expect_length(live, 1L)
  expect_s3_class(live[[1L]], "ellmer::ContentToolResult")
  expect_identical(live[[1L]]@request@id, shown[[1L]]@id)
  # Stopping the first presenter again leaves the second running.
  activity_disable(root, first)
  expect_identical(private$.activity, second)
  activity_disable(root, second)
  expect_null(private$.activity)
  # What a stopped presenter left for one reply never reaches the next, even
  # through a presenter shown in between.
  private$.activity_leftover <- list(
    run_id = private$current_run_id,
    queue = live
  )
  third <- activity_enable(root, function() "viewer")
  run_id <- private$current_run_id
  private$current_run_id <- "run_next"
  expect_length(activity_take(root), 0L)
  private$current_run_id <- run_id
  activity_disable(root, third)
})

test_that("a reply's stream reads only the presenter it started with", {
  root_server <- local_runtime_server(list(
    runtime_reply(tool = "ask_sales", arguments = list(task = "Sales?")),
    runtime_reply("Lead done.")
  ))
  root <- Agent$new(
    runtime_chat(root_server),
    delegation_disclosure = activity_disclosure()
  )
  sales <- activity_specialist("sales", "60")
  activity_retain(root, sales$agent, "ask_sales")
  root$run_sync("Sales?")
  private <- root$.__enclos_env__$private
  id <- names(private$subagent_runs)[[1L]]
  private$subagent_runs[[id]]$turns <- private$subagent_runs[[id]]$turns[-3L]
  private$subagent_runs[[id]]$completed_at <- as.POSIXct(NA_real_, tz = "UTC")
  first <- activity_enable(root, function() "viewer")
  activity_poll(root, presenter = first)
  shown <- activity_take(root, first)
  expect_length(shown, 1L)
  # Stopped and replaced during the reply: its stream neither reads with the
  # new presenter nor takes that presenter's cards, only the result the
  # stopped one settled.
  activity_disable(root, first)
  second <- activity_enable(root, function() "viewer")
  activity_poll(root, presenter = first)
  expect_length(second$queue, 0L)
  activity_poll(root, presenter = second)
  expect_length(second$queue, 1L)
  live <- activity_take(root, first)
  expect_length(live, 1L)
  expect_s3_class(live[[1L]], "ellmer::ContentToolResult")
  expect_identical(live[[1L]]@request@id, shown[[1L]]@id)
  expect_length(second$queue, 1L)
  expect_length(activity_take(root, first), 0L)
  activity_disable(root, second)
})

test_that("cards shown before access was lost get a result at the end", {
  root_server <- local_runtime_server(list(
    runtime_reply(tool = "ask_sales", arguments = list(task = "Sales?")),
    runtime_reply("Lead done.")
  ))
  flags <- new.env()
  root <- Agent$new(
    runtime_chat(root_server),
    delegation_disclosure = activity_disclosure(flags)
  )
  sales <- activity_specialist("sales", "60")
  activity_retain(root, sales$agent, "ask_sales")
  root$run_sync("Sales?")
  private <- root$.__enclos_env__$private
  id <- names(private$subagent_runs)[[1L]]
  private$subagent_runs[[id]]$turns <- private$subagent_runs[[id]]$turns[-3L]
  private$subagent_runs[[id]]$completed_at <- as.POSIXct(NA_real_, tz = "UTC")
  activity_enable(root, function() "viewer")
  activity_poll(root)
  shown <- activity_take(root)
  expect_length(shown, 1L)
  # The viewer loses access before the reply ends.
  flags$denied <- TRUE
  activity_poll(root, closing = TRUE)
  settled <- activity_take(root)
  expect_length(settled, 1L)
  expect_s3_class(settled[[1L]], "ellmer::ContentToolResult")
  expect_identical(settled[[1L]]@request@id, shown[[1L]]@id)
  expect_match(settled[[1L]]@value, "could not be read", fixed = TRUE)
  expect_false(is.null(private$.activity$error))
})

test_that("a reply that fails settles the cards it showed", {
  root_server <- local_runtime_server(list(
    runtime_reply(tool = "ask_sales", arguments = list(task = "Sales?")),
    runtime_reply("Lead done.")
  ))
  root <- Agent$new(
    runtime_chat(root_server),
    delegation_disclosure = activity_disclosure()
  )
  sales <- activity_specialist("sales", "60")
  activity_retain(root, sales$agent, "ask_sales")
  root$run_sync("Sales?")
  private <- root$.__enclos_env__$private
  id <- names(private$subagent_runs)[[1L]]
  private$subagent_runs[[id]]$turns <- private$subagent_runs[[id]]$turns[-3L]
  private$subagent_runs[[id]]$completed_at <- as.POSIXct(NA_real_, tz = "UTC")
  activity_enable(root, function() "viewer", 0.05)
  # The lead's stream fails while the call is open, after its run has ended:
  # a poll shows the call first, and the closing poll gives it a result.
  inner <- function() {
    promises::promise(function(resolve, reject) {
      later::later(function() reject(simpleError("provider failed")), 0.3)
    })
  }
  stream <- activity_stream(root, inner, private$.activity)
  seen <- list()
  failure <- NULL
  done <- FALSE
  coro::async(function() {
    tryCatch(
      for (chunk in coro::await_each(stream)) {
        seen[[length(seen) + 1L]] <<- chunk
      },
      error = function(error) failure <<- error
    )
    done <<- TRUE
  })()
  while (!done) {
    later::run_now(0.05)
  }
  expect_match(conditionMessage(failure), "provider failed", fixed = TRUE)
  expect_length(seen, 2L)
  expect_s3_class(seen[[1L]], "ellmer::ContentToolRequest")
  expect_s3_class(seen[[2L]], "ellmer::ContentToolResult")
  expect_identical(seen[[2L]]@request@id, seen[[1L]]@id)
})

test_that("replacing the conversation restarts activity labels", {
  root_server <- local_runtime_server(list(
    runtime_reply(tool = "ask_sales", arguments = list(task = "First")),
    runtime_reply("First answer."),
    runtime_reply(tool = "ask_sales", arguments = list(task = "Second")),
    runtime_reply("Second answer.")
  ))
  root <- Agent$new(
    runtime_chat(root_server),
    delegation_disclosure = activity_disclosure()
  )
  sales <- activity_specialist(
    "sales",
    "60",
    responses = list(
      runtime_reply(tool = "call_measure"),
      runtime_reply("first"),
      runtime_reply(tool = "call_measure"),
      runtime_reply("second")
    )
  )
  activity_retain(root, sales$agent, "ask_sales")
  activity_enable(root, function() "viewer", 0.05)
  label <- function(items) {
    unique(vapply(
      items,
      function(content) content@extra$deputy_activity$label,
      character(1)
    ))
  }
  expect_identical(
    label(activity_items(activity_collect(root, "One"))),
    "sales"
  )
  root$set_turns(list())
  expect_identical(
    label(activity_items(activity_collect(root, "Two"))),
    "sales"
  )
})

test_that("a conversation replaced mid-reply gets none of that reply's calls", {
  root_server <- local_runtime_server(list(
    runtime_reply(tool = "ask_sales", arguments = list(task = "Sales?")),
    runtime_reply("Lead done.")
  ))
  root <- Agent$new(
    runtime_chat(root_server),
    delegation_disclosure = activity_disclosure()
  )
  sales <- activity_specialist("sales", "60")
  activity_retain(root, sales$agent, "ask_sales")
  root$run_sync("Sales?")
  activity_enable(root, function() "viewer")
  # The host replaces the conversation while the reply is still streaming;
  # the new one has a tool turn of its own the cards could attach to.
  root$set_turns(list(
    ellmer::UserTurn(list(ellmer::ContentText("Other?"))),
    ellmer::AssistantTurn(list(
      ellmer::ContentToolRequest("other_call", "other_tool", list())
    ))
  ))
  activity_poll(root, final = TRUE)
  activity_poll(root, closing = TRUE)
  expect_length(activity_take(root), 0L)
  expect_length(
    activity_items(unlist(lapply(
      root$get_turns(),
      function(turn) turn@contents
    ))),
    0L
  )
  activity_disable(root)
})

test_that("loading a session drops activity shown for another conversation", {
  chat <- ellmer::chat_openai(model = "test", credentials = function() "x")
  saved <- Agent$new(chat$clone())
  saved$set_turns(list(
    ellmer::UserTurn(list(ellmer::ContentText("Hi"))),
    ellmer::AssistantTurn(list(ellmer::ContentText("Hello.")))
  ))
  path <- withr::local_tempfile(fileext = ".rds")
  suppressMessages(saved$save_session(path))
  agent <- Agent$new(chat)
  card <- ellmer::ContentToolRequest(
    "deputy_activity_abc_1",
    "call_measure",
    list(),
    extra = list(
      deputy_activity = list(
        format = "deputy_subagent_activity",
        version = 1L,
        activity_id = "deputy_activity_abc_1",
        label = "sales"
      )
    )
  )
  turns <- list(
    ellmer::UserTurn(list(ellmer::ContentText("Go"))),
    ellmer::AssistantTurn(list(ellmer::ContentText("Done."), card))
  )
  agent$set_turns(turns)
  # A load that fails leaves the conversation and its cards.
  broken <- withr::local_tempfile(fileext = ".rds")
  saveRDS(list(schema_version = 3L), broken)
  expect_error(agent$load_session(broken), class = "deputy_error")
  expect_identical(agent$get_turns(), turns)
  suppressMessages(agent$load_session(path))
  shown <- unlist(lapply(agent$get_turns(), function(turn) turn@contents))
  expect_length(shown, 2L)
  expect_false(any(vapply(shown, is_activity_content, logical(1))))
})

test_that("a saved session keeps the subagent activity shown in it", {
  chat <- ellmer::chat_openai(model = "test", credentials = function() "x")
  card <- ellmer::ContentToolRequest(
    "deputy_activity_abc_1",
    "call_measure",
    list(),
    extra = list(
      deputy_activity = list(
        format = "deputy_subagent_activity",
        version = 1L,
        activity_id = "deputy_activity_abc_1",
        label = "sales"
      )
    )
  )
  answer <- ellmer::ContentToolResult(
    "60",
    request = card,
    extra = list(deputy_activity = card@extra$deputy_activity)
  )
  turns <- list(
    ellmer::UserTurn(list(ellmer::ContentText("Go"))),
    ellmer::AssistantTurn(list(ellmer::ContentText("Done."), card, answer))
  )
  saved <- Agent$new(chat$clone())
  saved$set_turns(turns)
  path <- withr::local_tempfile(fileext = ".rds")
  suppressMessages(saved$save_session(path))
  # Beside the conversation, not among the turns the model reads.
  session <- readRDS(path)
  expect_false(any(vapply(
    unlist(lapply(session$turns, function(turn) turn@contents)),
    is_activity_content,
    logical(1)
  )))
  agent <- Agent$new(chat$clone())
  suppressMessages(agent$load_session(path))
  expect_identical(agent$get_turns(), turns)
  context <- unlist(lapply(agent$get_context_turns(), function(turn) {
    turn@contents
  }))
  expect_false(any(vapply(context, is_activity_content, logical(1))))
  # Activity that doesn't fit the turns it's saved with is refused, and
  # nothing is loaded.
  bad <- function(change) {
    session <- readRDS(path)
    session$activity <- change(session$activity)
    file <- withr::local_tempfile(
      fileext = ".rds",
      .local_envir = parent.frame()
    )
    saveRDS(session, file)
    file
  }
  other <- Agent$new(chat$clone())
  for (file in list(
    bad(function(entries) {
      entries[[1L]]$turn <- 1.5
      entries
    }),
    bad(function(entries) {
      entries[[1L]]$turn <- 9L
      entries
    }),
    bad(function(entries) {
      entries[[1L]]$content <- ellmer::ContentText("not a card")
      entries
    })
  )) {
    expect_error(other$load_session(file), class = "deputy_session_load")
    expect_length(other$get_turns(), 0L)
  }
})

test_that("activity a host puts in a user turn is saved and loaded too", {
  chat <- ellmer::chat_openai(model = "test", credentials = function() "x")
  marker <- list(
    format = "deputy_subagent_activity",
    version = 1L,
    activity_id = "deputy_activity_abc_1",
    label = "sales"
  )
  card <- ellmer::ContentToolRequest(
    "deputy_activity_abc_1",
    "call_measure",
    list(),
    extra = list(deputy_activity = marker)
  )
  answer <- ellmer::ContentToolResult(
    "60",
    request = card,
    extra = list(deputy_activity = marker)
  )
  turns <- list(
    ellmer::UserTurn(list(ellmer::ContentText("Go"), answer)),
    ellmer::AssistantTurn(list(ellmer::ContentText("Done."), card))
  )
  path <- withr::local_tempfile(fileext = ".rds")
  round_trip <- function(agent) {
    suppressMessages(agent$save_session(path))
    loaded <- Agent$new(chat$clone())
    suppressMessages(loaded$load_session(path))
    loaded$get_turns()
  }
  set <- Agent$new(chat$clone())
  set$set_turns(turns)
  expect_identical(round_trip(set), turns)
  added <- Agent$new(chat$clone())
  added$add_turn(turns[[1L]], turns[[2L]], log_tokens = FALSE)
  expect_identical(round_trip(added), turns)
})

test_that("a saved session gives a card still waiting a result", {
  chat <- ellmer::chat_openai(model = "test", credentials = function() "x")
  marker <- list(
    format = "deputy_subagent_activity",
    version = 1L,
    activity_id = "deputy_activity_abc_1",
    label = "sales"
  )
  card <- ellmer::ContentToolRequest(
    "deputy_activity_abc_1",
    "call_measure",
    list(),
    extra = list(deputy_activity = marker)
  )
  turns <- list(
    ellmer::UserTurn(list(ellmer::ContentText("Go"))),
    ellmer::AssistantTurn(list(ellmer::ContentText("Working."), card))
  )
  # Saved mid-reply: the call hasn't returned yet.
  saved <- Agent$new(chat$clone())
  saved$set_turns(turns)
  path <- withr::local_tempfile(fileext = ".rds")
  suppressMessages(saved$save_session(path))
  expect_identical(saved$get_turns(), turns)
  agent <- Agent$new(chat$clone())
  suppressMessages(agent$load_session(path))
  contents <- agent$get_turns()[[2L]]@contents
  expect_length(contents, 3L)
  expect_s3_class(contents[[3L]], "ellmer::ContentToolResult")
  expect_identical(contents[[3L]]@request@id, card@id)
  expect_match(contents[[3L]]@value, "saved before this call returned")
})

test_that("a save during a reply takes the results it hasn't shown yet", {
  root_server <- local_runtime_server(list(
    runtime_reply(tool = "ask_sales", arguments = list(task = "Sales?")),
    runtime_reply("Lead done.")
  ))
  root <- Agent$new(
    runtime_chat(root_server),
    delegation_disclosure = activity_disclosure()
  )
  sales <- activity_specialist("sales", "60")
  activity_retain(root, sales$agent, "ask_sales")
  path <- withr::local_tempfile(fileext = ".rds")
  # Saved once the subagent has finished, before the reply shows its result.
  root$add_hook(HookMatcher("PostToolUse", function(tool_name, ...) {
    if (identical(tool_name, "ask_sales")) {
      suppressMessages(root$save_session(path))
    }
    HookResultPostToolUse()
  }))
  # Too long an interval for the reply to look for calls while it waits.
  activity_enable(root, function() "viewer", 30)
  seen <- activity_collect(root, "Sales?")
  saved <- Filter(
    function(entry) inherits(entry$content, "ellmer::ContentToolResult"),
    readRDS(path)$activity
  )
  expect_length(saved, 1L)
  expect_identical(saved[[1L]]$content@request@name, "call_measure")
  expect_null(saved[[1L]]$content@error)
  expect_no_match(
    paste(format(saved[[1L]]$content@value), collapse = "\n"),
    "Not completed"
  )
  # The reply shows the same result.
  shown <- Filter(
    function(content) inherits(content, "ellmer::ContentToolResult"),
    activity_items(seen)
  )
  expect_length(shown, 1L)
  expect_identical(shown[[1L]], saved[[1L]]$content)
})

test_that("a save doesn't show calls from a reply the presenter didn't stream", {
  root_server <- local_runtime_server(list(
    runtime_reply(tool = "ask_sales", arguments = list(task = "Sales?")),
    runtime_reply("Lead done.")
  ))
  root <- Agent$new(
    runtime_chat(root_server),
    delegation_disclosure = activity_disclosure()
  )
  sales <- activity_specialist("sales", "60")
  activity_retain(root, sales$agent, "ask_sales")
  root$run_sync("Sales?")
  # Shown in a chat only after that reply finished.
  activity_enable(root, function() "viewer", 0.05)
  path <- withr::local_tempfile(fileext = ".rds")
  suppressMessages(root$save_session(path))
  expect_null(readRDS(path)$activity)
  expect_length(root$.__enclos_env__$private$.activity_overlay, 0L)
  # So the next reply has none of them to show.
  expect_length(activity_take(root), 0L)
})

test_that("shown activity is kept across a durable approval", {
  directory <- withr::local_tempdir()
  server <- local_runtime_server(list(
    runtime_reply(tool = "effect", arguments = list(value = "b")),
    runtime_reply("finished")
  ))
  tool <- ellmer::tool(
    function(value) paste0("result_", value),
    name = "effect",
    description = "Record an effect.",
    arguments = list(value = ellmer::type_string()),
    convert = FALSE,
    annotations = ellmer::tool_annotations(
      read_only_hint = FALSE,
      destructive_hint = FALSE,
      open_world_hint = FALSE
    )
  )
  make_agent <- function() {
    Agent$new(
      chat = runtime_chat(server),
      tools = list(tool),
      permissions = Permissions(can_use_tool = function(name, input, context) {
        PermissionResultPending("Review the effect")
      }),
      approval_dir = directory,
      working_dir = directory,
      session_id = "activity_approval_session",
      agent_id = "activity_approval_agent"
    )
  }
  marker <- list(
    format = "deputy_subagent_activity",
    version = 1L,
    activity_id = "deputy_activity_abc_1",
    label = "sales"
  )
  card <- ellmer::ContentToolRequest(
    "deputy_activity_abc_1",
    "call_measure",
    list(),
    extra = list(deputy_activity = marker)
  )
  answer <- ellmer::ContentToolResult(
    "60",
    request = card,
    extra = list(deputy_activity = marker)
  )
  earlier <- list(
    ellmer::UserTurn(list(ellmer::ContentText("Sales?"))),
    ellmer::AssistantTurn(list(ellmer::ContentText("60."), card, answer))
  )
  agent <- make_agent()
  agent$set_turns(earlier)
  result <- agent$run_sync("Record it.")
  expect_identical(result$stop_reason, "approval_pending")
  path <- agent$pending_approval()$source$path
  # Resumed by a new agent, as after a restart.
  resumed <- make_agent()
  resumed$resume_approval(path, "approve")
  expect_identical(resumed$get_turns()[[2L]]@contents, earlier[[2L]]@contents)
  context <- unlist(lapply(resumed$get_context_turns(), function(turn) {
    turn@contents
  }))
  expect_false(any(vapply(context, is_activity_content, logical(1))))
})

test_that("shown activity doesn't count toward a fork's size bound", {
  request <- ellmer::ContentToolRequest("call_1", "ask_sales", list())
  marker <- list(
    format = "deputy_subagent_activity",
    version = 1L,
    activity_id = "deputy_activity_abc_1",
    label = "sales"
  )
  shown <- ellmer::ContentToolRequest(
    "deputy_activity_abc_1",
    "call_measure",
    list(),
    extra = list(deputy_activity = marker)
  )
  large <- ellmer::ContentToolResult(
    strrep("x", 200000),
    request = shown,
    extra = list(deputy_activity = marker)
  )
  turns <- list(
    ellmer::UserTurn(list(ellmer::ContentText("Go"))),
    ellmer::AssistantTurn(list(request, shown, large)),
    ellmer::UserTurn(list(ellmer::ContentToolResult(
      "done",
      request = request
    ))),
    ellmer::AssistantTurn(list(ellmer::ContentText("Done.")))
  )
  records <- context_fork_turn_records(turns, 64 * 1024, 64L)
  expect_true("subagent_activity" %in% records$omissions)
  # The same turns as portable records, as a host would save them. A
  # sanitized replay of a record clears the marker, so the cards are found in
  # the records themselves.
  portable <- lapply(turns, ellmer::contents_record)
  records <- context_fork_turn_records(portable, 16 * 1024^2, 64L)
  expect_true("subagent_activity" %in% records$omissions)
  ids <- activity_test_call_ids(lapply(records$records, inspection_replay))
  expect_identical(ids, c("call_1", "call_1"))
  records <- context_fork_turn_records(portable, 64 * 1024, 64L)
  ids <- activity_test_call_ids(lapply(records$records, inspection_replay))
  expect_identical(ids, c("call_1", "call_1"))
})

test_that("context forks never copy shown activity", {
  root_server <- local_runtime_server(list(
    runtime_reply(tool = "ask_sales", arguments = list(task = "Sales?")),
    runtime_reply("Lead done.")
  ))
  root <- Agent$new(
    runtime_chat(root_server),
    delegation_disclosure = activity_disclosure()
  )
  sales <- activity_specialist("sales", "60")
  activity_retain(root, sales$agent, "ask_sales")
  activity_enable(root, function() "viewer", 0.05)
  activity_collect(root, "Sales?")
  turns <- root$get_turns()
  expect_true(any(vapply(
    turns[[2L]]@contents,
    is_activity_content,
    logical(1)
  )))
  records <- context_fork_turn_records(turns, 16 * 1024^2, 64L)
  expect_true("subagent_activity" %in% records$omissions)
  ids <- activity_test_call_ids(lapply(records$records, inspection_replay))
  expect_length(ids, 2L)
  expect_false(any(startsWith(ids, "deputy_activity_")))
})

test_that("the per-reply call limit leaves a marker", {
  local_mocked_bindings(activity_max_calls = 1L)
  root_server <- local_runtime_server(list(
    runtime_reply(tool = "ask_sales", arguments = list(task = "Sales?")),
    runtime_reply("Lead done.")
  ))
  root <- Agent$new(
    runtime_chat(root_server),
    delegation_disclosure = activity_disclosure()
  )
  sales <- activity_specialist(
    "sales",
    "60",
    responses = list(
      runtime_reply(tool = "call_measure"),
      runtime_reply(tool = "call_measure"),
      runtime_reply("done")
    )
  )
  activity_retain(root, sales$agent, "ask_sales")
  activity_enable(root, function() "viewer", 0.05)
  items <- activity_items(activity_collect(root, "Sales?"))
  names <- vapply(
    Filter(function(x) inherits(x, "ellmer::ContentToolRequest"), items),
    function(x) x@name,
    character(1)
  )
  expect_identical(names, c("call_measure", "more_subagent_tool_calls"))
})

test_that("subagent_chat_activity() binds to the chat's own client", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("shinychat", "0.5.0")
  skip_if_not_installed("bslib")
  skip_if_not_installed("commonmark")
  skip_if_not_installed("xml2")
  lead <- Agent$new(
    ellmer::chat_openai(credentials = function() "x", echo = "none"),
    delegation_disclosure = activity_disclosure()
  )
  other <- Agent$new(
    ellmer::chat_openai(credentials = function() "x", echo = "none")
  )
  shiny::testServer(
    function(input, output, session) {
      chat <- shinychat::chat_server("chat", lead, history = FALSE)
      expect_error(
        subagent_chat_activity(list(), lead, function() "viewer"),
        "chat_server"
      )
      expect_error(
        subagent_chat_activity(chat, other, function() "viewer"),
        "client"
      )
      expect_error(subagent_chat_activity(chat, lead, "viewer"), "function")
      expect_error(
        subagent_chat_activity(chat, lead, function() "viewer", 10),
        "at least 50"
      )
      control <- subagent_chat_activity(chat, lead, function() "viewer")
      expect_false(is.null(lead$.__enclos_env__$private$.activity))
      expect_error(
        subagent_chat_activity(chat, lead, function() "viewer"),
        "already shown"
      )
      control$stop()
      expect_null(lead$.__enclos_env__$private$.activity)
      subagent_chat_activity(chat, lead, function() "viewer")
      # The first `stop()` doesn't stop the presenter that replaced it.
      control$stop()
      expect_false(is.null(lead$.__enclos_env__$private$.activity))
    },
    {
      session$flushReact()
    }
  )
  expect_null(lead$.__enclos_env__$private$.activity)
})

test_that("subagent_chat_activity() without a chat shows cards in the app's own stream", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("shinychat", "0.5.0")
  skip_if_not_installed("bslib")
  skip_if_not_installed("commonmark")
  skip_if_not_installed("xml2")
  root_server <- local_runtime_server(list(
    runtime_reply(tool = "ask_sales", arguments = list(task = "Sales?")),
    runtime_reply("Lead done.")
  ))
  root <- Agent$new(
    runtime_chat(root_server),
    delegation_disclosure = activity_disclosure()
  )
  sales <- activity_specialist("sales", "60")
  activity_retain(root, sales$agent, "ask_sales")
  viewer <- function() "viewer"
  # An app that streams the lead's replies into its chat itself, keeping
  # what it hands to the chat.
  host <- new.env()
  host$seen <- list()
  host$done <- FALSE
  shiny::testServer(
    function(input, output, session) {
      expect_error(subagent_chat_activity(requester = viewer), "Agent")
      expect_error(
        subagent_chat_activity(lead = "root", requester = viewer),
        "Agent"
      )
      expect_error(
        subagent_chat_activity(lead = root, requester = "viewer"),
        "function"
      )
      expect_error(
        subagent_chat_activity(NULL, root, viewer, 10),
        "at least 50"
      )
      control <- subagent_chat_activity(lead = root, requester = viewer)
      expect_error(
        subagent_chat_activity(lead = root, requester = viewer),
        "already shown"
      )
      host$control <- control
      shiny::observeEvent(input$chat_user_input, {
        stream <- root$stream_async(input$chat_user_input, stream = "content")
        shown <- coro::async_generator(function() {
          for (chunk in coro::await_each(stream)) {
            host$seen[[length(host$seen) + 1L]] <- chunk
            coro::yield(chunk)
          }
        })
        promises::then(shinychat::chat_append("chat", shown()), function(x) {
          host$done <- TRUE
        })
      })
    },
    {
      session$flushReact()
      session$setInputs(chat_user_input = "Sales?")
      deadline <- Sys.time() + 60
      while (!host$done && Sys.time() < deadline) {
        later::run_now(0.02)
        session$flushReact()
      }
      expect_true(host$done)
      cards <- activity_items(host$seen)
      expect_length(cards, 2L)
      expect_s3_class(cards[[1L]], "ellmer::ContentToolRequest")
      expect_identical(cards[[1L]]@name, "call_measure")
      expect_s3_class(cards[[2L]], "ellmer::ContentToolResult")
      expect_true(all(startsWith(activity_ids(cards), "deputy_activity_")))
      # The cards come before the delegation's own result, in its reply.
      delegated <- which(vapply(
        host$seen,
        function(x) {
          inherits(x, "ellmer::ContentToolResult") &&
            !is_activity_content(x) &&
            identical(x@request@name, "ask_sales")
        },
        logical(1)
      ))
      shown <- which(vapply(host$seen, is_activity_content, logical(1)))
      expect_length(delegated, 1L)
      expect_true(all(shown < delegated))
      # The lead's turns hold them for saving; its model context doesn't.
      turns <- unlist(lapply(root$get_turns(), function(turn) turn@contents))
      context <- unlist(lapply(
        root$get_context_turns(),
        function(turn) turn@contents
      ))
      expect_length(activity_items(turns), 2L)
      expect_length(activity_items(context), 0L)
      host$control$stop()
      expect_null(root$.__enclos_env__$private$.activity)
      subagent_chat_activity(lead = root, requester = viewer)
      expect_false(is.null(root$.__enclos_env__$private$.activity))
    }
  )
  # Ending the session stops it.
  expect_null(root$.__enclos_env__$private$.activity)
})

test_that("subagent_activity_info() describes a shown card", {
  marker <- list(
    format = "deputy_subagent_activity",
    version = 1L,
    activity_id = "deputy_activity_abc_1",
    sequence = 1L,
    label = "sales",
    agent_name = "sales",
    depth = 1L,
    conversation_id = "session_1",
    root_tool_call_id = "call_1"
  )
  shown <- ellmer::ContentToolRequest(
    "deputy_activity_abc_1",
    "call_measure",
    list(),
    extra = list(deputy_activity = marker)
  )
  result <- ellmer::ContentToolResult(
    "60",
    request = shown,
    extra = list(deputy_activity = marker)
  )
  info <- subagent_activity_info(result)
  expect_identical(info$activity_id, "deputy_activity_abc_1")
  expect_identical(info$root_tool_call_id, "call_1")
  expect_identical(info$agent_name, "sales")
  expect_null(info$format)
  expect_null(info$conversation_id)
  expect_identical(subagent_activity_info(shown), info)

  # The lead's own call, and a card whose request isn't its own, are not
  # shown activity.
  expect_null(subagent_activity_info(
    ellmer::ContentToolRequest("call_1", "delegate", list())
  ))
  forged <- ellmer::ContentToolRequest(
    "call_2",
    "call_measure",
    list(),
    extra = list(deputy_activity = marker)
  )
  expect_null(subagent_activity_info(forged))
  expect_null(subagent_activity_info(ellmer::ContentText("text")))
})
