# Defined outside any package, so a recorded note replays from this file.
NoteText <- S7::new_class(
  "NoteText",
  parent = ellmer::ContentText,
  package = NULL
)

is_test_note <- function(content) S7::S7_inherits(content, NoteText)

note_turns <- function() {
  list(
    ellmer::UserTurn(list(ellmer::ContentText("Go"))),
    ellmer::AssistantTurn(list(ellmer::ContentText("Done.")))
  )
}

note_agent <- function(...) {
  Agent$new(
    ellmer::chat_openai(credentials = function() "x", echo = "none"),
    notes = is_test_note,
    ...
  )
}

test_that("a note is shown in its turn but not sent to the model", {
  agent <- note_agent()
  agent$set_turns(note_turns())
  note <- NoteText("Checked: 2 sources")
  agent$add_note(2, note)

  expect_identical(
    agent$get_turns()[[2L]]@contents,
    list(ellmer::ContentText("Done."), note)
  )
  expect_identical(agent$get_context_turns(), note_turns())
  expect_identical(agent$get_turns(notes = FALSE), note_turns())
  expect_identical(agent$last_turn()@contents[[2L]], note)
  expect_identical(agent$usage()$tool_calls, 0L)
})

test_that("set_turns and add_turn keep recognized notes out of the model context", {
  agent <- note_agent()
  shown <- note_turns()
  shown[[2L]]@contents <- c(shown[[2L]]@contents, list(NoteText("Checked")))
  agent$set_turns(shown)
  expect_identical(agent$get_turns(), shown)
  expect_identical(agent$get_context_turns(), note_turns())

  user <- ellmer::UserTurn(list(ellmer::ContentText("Again")))
  assistant <- ellmer::AssistantTurn(list(
    ellmer::ContentText("Done again."),
    NoteText("Not checked")
  ))
  agent$add_turn(user, assistant, log_tokens = FALSE)
  expect_identical(agent$get_turns(), c(shown, list(user, assistant)))
  expect_length(agent$get_context_turns()[[4L]]@contents, 1L)
})

test_that("a conversation recorded and replayed keeps its notes out of the model context", {
  source <- note_agent()
  source$set_turns(note_turns())
  source$add_note(2, NoteText("Checked"))
  records <- lapply(source$get_turns(), ellmer::contents_record)
  replayed <- lapply(
    records,
    ellmer::contents_replay,
    .envir = environment()
  )

  receiver <- note_agent()
  receiver$set_turns(replayed)
  expect_identical(receiver$get_context_turns(), note_turns())
  expect_s7_class(receiver$get_turns()[[2L]]@contents[[2L]], NoteText)
})

test_that("without a notes function, turns are taken as they are", {
  agent <- Agent$new(
    ellmer::chat_openai(credentials = function() "x", echo = "none")
  )
  shown <- note_turns()
  shown[[2L]]@contents <- c(shown[[2L]]@contents, list(NoteText("Checked")))
  agent$set_turns(shown)
  expect_identical(agent$get_context_turns(), shown)
  expect_snapshot(agent$add_note(2, NoteText("Checked")), error = TRUE)
})

test_that("a notes function that fails makes no notes", {
  agent <- Agent$new(
    ellmer::chat_openai(credentials = function() "x", echo = "none"),
    notes = function(content) stop("broken")
  )
  agent$set_turns(note_turns())
  expect_identical(agent$get_context_turns(), note_turns())
})

test_that("add_note() refuses what it could not keep out of the model context", {
  agent <- note_agent()
  agent$set_turns(note_turns())
  expect_snapshot(error = TRUE, {
    agent$add_note(2, ellmer::ContentText("Plain text"))
    agent$add_note(2, "Checked")
    agent$add_note(2, list())
    agent$add_note(3, NoteText("Checked"))
    agent$add_note(1.5, NoteText("Checked"))
  })
  expect_identical(agent$get_turns(), note_turns())
  expect_snapshot(Agent$new(create_mock_chat(), notes = "yes"), error = TRUE)
})

test_that("get_turns() can leave out shown activity and notes", {
  agent <- note_agent()
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
  turns <- note_turns()
  turns[[2L]]@contents <- c(turns[[2L]]@contents, list(shown))
  agent$set_turns(turns)
  note <- NoteText("Checked")
  agent$add_note(2, note)

  expect_identical(
    agent$get_turns(activity = FALSE)[[2L]]@contents,
    list(ellmer::ContentText("Done."), note)
  )
  expect_identical(
    agent$get_turns(notes = FALSE)[[2L]]@contents,
    list(ellmer::ContentText("Done."), shown)
  )
  expect_identical(
    agent$get_turns(activity = FALSE, notes = FALSE),
    note_turns()
  )
  expect_snapshot(agent$get_turns(activity = NA), error = TRUE)
})

test_that("a turn compaction removed from the model context can take a note", {
  chat <- create_mock_chat()
  chat$set_turns(list(
    create_mock_user_turn("First question"),
    create_mock_assistant_turn("First answer"),
    create_mock_user_turn("Second question"),
    create_mock_assistant_turn("Second answer")
  ))
  agent <- Agent$new(chat, notes = is_test_note)
  suppressMessages(agent$compact(keep_last = 2, summary = "Earlier answers."))
  note <- NoteText("Checked")
  agent$add_note(2, note)

  expect_length(agent$get_context_turns(), 2L)
  expect_identical(agent$get_turns()[[2L]]@contents[[2L]], note)
  expect_false(any(vapply(
    agent$get_context_turns(),
    function(turn) any(vapply(turn@contents, is_test_note, logical(1))),
    logical(1)
  )))
})

test_that("a saved session keeps its notes", {
  root <- withr::local_tempdir(pattern = "deputy-session-notes-")
  source <- Agent$new(create_mock_chat(), notes = is_test_note)
  source$set_turns(note_turns())
  note <- NoteText("Checked")
  source$add_note(2, note)
  path <- file.path(root, "session.rds")
  suppressMessages(source$save_session(path))

  # The session lists its notes, so the receiver needs no notes function.
  receiver <- Agent$new(create_mock_chat())
  suppressMessages(receiver$load_session(path))
  expect_identical(receiver$get_turns()[[2L]]@contents[[2L]], note)
  expect_identical(receiver$get_context_turns(), note_turns())
})

test_that("moving to another Chat keeps a note on its own turn", {
  turns <- list(
    ellmer::UserTurn(list(ellmer::ContentText("First"))),
    ellmer::AssistantTurn(list(ellmer::ContentThinking("stopped thinking"))),
    ellmer::UserTurn(list(ellmer::ContentText("Second"))),
    ellmer::AssistantTurn(list(ellmer::ContentText("Done.")))
  )
  agent <- Agent$new(
    ellmer::chat_openai(credentials = function() "unused", echo = "none"),
    notes = is_test_note
  )
  agent$set_turns(turns)
  note <- NoteText("Checked")
  agent$add_note(4, note)
  agent$set_chat(ellmer::chat_anthropic(
    model = "claude-sonnet-4-5",
    credentials = function() "unused",
    echo = "none"
  ))
  moved <- agent$get_turns()
  expect_length(moved, 3L)
  expect_identical(moved[[3L]]@contents[[2L]], note)
})

test_that("reinitializing with another Chat drops its old notes", {
  agent <- note_agent()
  agent$set_turns(note_turns())
  agent$add_note(2, NoteText("Checked"))
  agent$initialize(
    ellmer::chat_openai(credentials = function() "x", echo = "none"),
    notes = is_test_note
  )
  expect_identical(agent$get_turns(), list())
})
