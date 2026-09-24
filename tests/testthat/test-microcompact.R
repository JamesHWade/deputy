microcompact_turns <- function() {
  exchange <- function(id, name, value) {
    request <- ellmer::ContentToolRequest(id = id, name = name, arguments = list())
    list(
      ellmer::AssistantTurn(contents = list(request)),
      ellmer::UserTurn(contents = list(
        ellmer::ContentToolResult(value = value, request = request)
      ))
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
    lapply(Filter(function(content) {
      S7::S7_inherits(content, ellmer::ContentToolResult)
    }, turn@contents), function(content) content@value)
  }))
}

test_that("microcompact clears old tool results and keeps the named tools and recent turns", {
  chat <- create_compaction_mock_chat()
  chat$set_turns(microcompact_turns())
  agent <- Agent$new(chat = chat)

  out <- agent$microcompact(keep_last = 4L, keep_tools = "ask_user", marker = "[cleared]")

  expect_identical(out$cleared, 1L)
  expect_identical(
    result_values(agent$get_turns()),
    c("[cleared]", "the user's answer", "the latest search result")
  )
  expect_length(agent$get_turns(), length(microcompact_turns()))

  # Running it again finds nothing new to clear.
  expect_identical(agent$microcompact(keep_last = 4L, keep_tools = "ask_user", marker = "[cleared]")$cleared, 0L)
})

test_that("microcompact keeps an earlier compaction summary, unlike set_turns()", {
  chat <- create_compaction_mock_chat()
  chat$set_turns(c(
    list(create_mock_user_turn("Q0"), create_mock_assistant_turn("A0")),
    microcompact_turns()
  ))
  agent <- Agent$new(chat = chat)
  agent$compact(keep_last = length(microcompact_turns()), summary = "Earlier compacted context")
  prompt <- agent$get_system_prompt()
  expect_match(prompt, "Earlier compacted context", fixed = TRUE)

  agent$microcompact(keep_last = 0L)

  expect_identical(agent$get_system_prompt(), prompt)
  expect_true(all(result_values(agent$get_turns()) == "[Old tool result cleared to save context.]"))
})

test_that("microcompact refuses a keep_last that is not a whole number", {
  agent <- Agent$new(chat = create_compaction_mock_chat())
  expect_error(agent$microcompact(keep_last = -1), "whole number")
  expect_error(agent$microcompact(keep_last = 1.5), "whole number")
})
