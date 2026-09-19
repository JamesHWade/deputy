owned_test_agent <- function(text = "answer", ...) {
  chat <- create_mock_chat()
  chat$stream_async <- function(prompt, ...) {
    coro::async_generator(function() {
      chat$set_turns(c(chat$get_turns(), list(create_mock_user_turn(prompt))))
      coro::yield(ellmer::ContentText(text))
      chat$set_turns(c(
        chat$get_turns(),
        list(create_mock_assistant_turn(text))
      ))
    })()
  }
  Agent$new(chat, ...)
}

owned_test_owner <- function(...) {
  owned_test_agent(
    delegation_disclosure = DelegationDisclosure(
      authorize = function(requester, scope) identical(requester, "owner")
    ),
    ...
  )
}
