test_that("Agent stream_async is consumed directly by shinychat", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("shinychat")

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
