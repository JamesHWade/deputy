microcompact_turns <- function() {
  exchange <- function(id, name, value) {
    request <- ellmer::ContentToolRequest(
      id = id,
      name = name,
      arguments = list()
    )
    list(
      ellmer::AssistantTurn(contents = list(request)),
      ellmer::UserTurn(
        contents = list(
          ellmer::ContentToolResult(value = value, request = request)
        )
      )
    )
  }
  c(
    list(create_mock_user_turn("Q1")),
    exchange("a", "search", "a long search result"),
    exchange("b", "ask_user", "the user's answer"),
    list(create_mock_assistant_turn("A1"), create_mock_user_turn("Q2")),
    exchange("c", "search", "the latest search result"),
    list(create_mock_assistant_turn("A2"))
  )
}

result_values <- function(turns) {
  unlist(lapply(turns, function(turn) {
    lapply(
      Filter(
        function(content) {
          S7::S7_inherits(content, ellmer::ContentToolResult)
        },
        turn@contents
      ),
      function(content) content@value
    )
  }))
}

test_that("microcompact clears old tool results and keeps the named tools and recent turns", {
  chat <- create_compaction_mock_chat()
  chat$set_turns(microcompact_turns())
  agent <- Agent$new(chat = chat)

  out <- agent$microcompact(
    keep_last = 4L,
    keep_tools = "ask_user",
    marker = "[cleared]"
  )

  expect_identical(out$cleared, 1L)
  expect_identical(
    result_values(agent$get_context_turns()),
    c("[cleared]", "the user's answer", "the latest search result")
  )
  # The conversation view keeps the original, as it does after compaction.
  expect_identical(
    result_values(agent$get_turns()),
    c("a long search result", "the user's answer", "the latest search result")
  )
  expect_length(agent$get_turns(), length(microcompact_turns()))

  # Running it again finds nothing new to clear.
  expect_identical(
    agent$microcompact(
      keep_last = 4L,
      keep_tools = "ask_user",
      marker = "[cleared]"
    )$cleared,
    0L
  )
})

test_that("microcompact keeps an earlier compaction summary, unlike set_turns()", {
  chat <- create_compaction_mock_chat()
  chat$set_turns(c(
    list(create_mock_user_turn("Q0"), create_mock_assistant_turn("A0")),
    microcompact_turns()
  ))
  agent <- Agent$new(chat = chat)
  agent$compact(
    keep_last = length(microcompact_turns()),
    summary = "Earlier compacted context"
  )
  prompt <- agent$get_system_prompt()
  expect_match(prompt, "Earlier compacted context", fixed = TRUE)

  agent$microcompact(keep_last = 0L)

  expect_identical(agent$get_system_prompt(), prompt)
  expect_true(all(
    result_values(agent$get_context_turns()) ==
      "[Old tool result cleared to save context.]"
  ))
  expect_identical(
    result_values(agent$get_turns()),
    result_values(microcompact_turns())
  )
})

test_that("microcompact refuses a keep_last that is not a whole number", {
  agent <- Agent$new(chat = create_compaction_mock_chat())
  expect_error(agent$microcompact(keep_last = -1), "whole number")
  expect_error(agent$microcompact(keep_last = 1.5), "whole number")
  expect_error(agent$microcompact(keep_tools = NA_character_), "character")
  expect_error(agent$microcompact(marker = ""), "non-empty")
})

test_that("saved sessions keep cleared originals and set_turns() drops them", {
  chat <- create_compaction_mock_chat()
  chat$set_turns(microcompact_turns())
  agent <- Agent$new(chat = chat)
  agent$microcompact(keep_last = 0L, marker = "[cleared]")
  path <- withr::local_tempfile(fileext = ".rds")
  agent$save_session(path)

  restored <- Agent$new(chat = create_compaction_mock_chat())
  restored$load_session(path)
  expect_identical(
    result_values(restored$get_context_turns()),
    rep("[cleared]", 3L)
  )
  expect_identical(
    result_values(restored$get_turns()),
    result_values(microcompact_turns())
  )

  restored$set_turns(microcompact_turns()[1:3])
  restored$microcompact(keep_last = 0L, marker = "[cleared]")
  restored$set_turns(restored$get_context_turns())
  expect_identical(result_values(restored$get_turns()), "[cleared]")
})

test_that("last_turn() and results without a call id keep their values", {
  # The last user turn holds a cleared result; last_turn() shows the original.
  chat <- ellmer::chat_openai(credentials = function() "unused", echo = "none")
  chat$set_turns(microcompact_turns())
  agent <- Agent$new(chat = chat)
  agent$microcompact(keep_last = 0L, marker = "[cleared]")
  expect_identical(
    result_values(list(agent$last_turn("user"))),
    "the latest search result"
  )

  # A result whose call has no id cannot be restored, so it is not cleared.
  request <- ellmer::ContentToolRequest(
    id = "",
    name = "search",
    arguments = list()
  )
  turns <- list(
    create_mock_user_turn("Q"),
    ellmer::AssistantTurn(contents = list(request)),
    ellmer::UserTurn(
      contents = list(
        ellmer::ContentToolResult(value = "no id", request = request)
      )
    ),
    create_mock_assistant_turn("A")
  )
  chat <- ellmer::chat_openai(credentials = function() "unused", echo = "none")
  chat$set_turns(turns)
  agent <- Agent$new(chat = chat)
  expect_identical(agent$microcompact(keep_last = 0L)$cleared, 0L)
  expect_identical(result_values(agent$get_context_turns()), "no id")
})
