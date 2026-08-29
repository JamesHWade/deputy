test_that("Agent stream_async is consumed directly by shinychat", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("shinychat")
  skip_if_not(
    "chat_server" %in% getNamespaceExports("shinychat"),
    "shinychat::chat_server() is not available"
  )

  chat <- create_mock_chat()
  chat$stream_async <- function(
    ...,
    tool_mode = c("concurrent", "sequential"),
    stream = c("text", "content"),
    controller = NULL
  ) {
    coro::async_generator(function() {
      coro::yield(ellmer::ContentText("Governed reply"))
    })()
  }
  agent <- Agent$new(
    chat = chat,
    context_policy = ContextPolicy(max_tokens = NULL)
  )
  session <- shiny::MockShinySession$new()
  module <- shinychat::chat_server(
    "chat",
    agent,
    session = session
  )

  expect_s3_class(agent, "Chat")
  expect_identical(module$client, agent)

  appended <- shinychat::chat_append(
    "chat",
    agent$stream_async("Hello", stream = "content"),
    session = session
  )

  expect_true(promises::is.promising(appended))
  expect_no_error(resolve_async_value(appended))
  expect_s3_class(agent$last_run(), "AgentResult")
  expect_identical(agent$last_run()$response, "Governed reply")
})

test_that("shinychat attachment content reaches the wrapped Chat unchanged", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("shinychat")

  received <- NULL
  chat <- create_mock_chat()
  chat$stream_async <- function(
    ...,
    tool_mode = c("concurrent", "sequential"),
    stream = c("text", "content"),
    controller = NULL
  ) {
    received <<- list(...)
    coro::async_generator(function() {
      coro::yield(ellmer::ContentText("Attachment received"))
    })()
  }
  agent <- Agent$new(
    chat = chat,
    context_policy = ContextPolicy(max_tokens = NULL)
  )
  session <- shiny::MockShinySession$new()
  input <- list(
    ellmer::ContentText("Review the attachment"),
    ellmer::ContentText("attachment payload")
  )

  appended <- shinychat::chat_append(
    "chat",
    agent$stream_async(input, stream = "content"),
    session = session
  )
  resolve_async_value(appended)

  expect_length(received, 1L)
  expect_identical(received[[1L]], input)
})

test_that("Agent implements structured ellmer Chat methods through the kernel", {
  chat <- create_mock_chat()
  chat$chat_structured_async <- function(
    ...,
    type,
    echo = "none",
    convert = TRUE
  ) {
    promises::promise_resolve(list(answer = "governed"))
  }
  agent <- Agent$new(
    chat = chat,
    context_policy = ContextPolicy(max_tokens = NULL)
  )
  type <- ellmer::type_object(answer = ellmer::type_string())

  value <- agent$chat_structured("Question", type = type)

  expect_identical(value, list(answer = "governed"))
  expect_s3_class(agent$last_run(), "AgentResult")
  expect_identical(
    agent$last_run()$structured_output,
    list(answer = "governed")
  )
})

test_that("Agent clone isolates the wrapped Chat state", {
  chat <- create_mock_chat()
  chat$set_turns(list(create_mock_user_turn("Keep me")))
  agent <- Agent$new(chat = chat)

  cloned <- agent$clone()
  cloned$set_turns(list())

  expect_s3_class(cloned, "Chat")
  expect_length(agent$get_turns(), 1L)
  expect_length(cloned$get_turns(), 0L)
})

test_that("Agent clone preserves additional tool observers", {
  chat <- create_compaction_mock_chat()
  agent <- Agent$new(chat = chat)
  remove_observer <- agent$on_tool_request(function(request) invisible(NULL))

  cloned <- agent$clone()
  clone_counts <- cloned$.__enclos_env__$private$.chat$callback_counts()
  remove_observer()
  original_counts <- agent$.__enclos_env__$private$.chat$callback_counts()

  expect_identical(unname(clone_counts[["request"]]), 2L)
  expect_identical(unname(original_counts[["request"]]), 1L)
})
