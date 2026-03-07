# Tests for Notification hooks.

create_mock_chat_with_notification_capture <- function() {
  captured_callback <- NULL
  chat <- create_mock_chat()
  original <- chat$on_tool_request

  chat$on_tool_request <- function(callback) {
    captured_callback <<- callback
    original(callback)
  }

  list(
    chat = chat,
    callback = function() captured_callback
  )
}

test_that("HookEvent includes Notification", {
  expect_true("Notification" %in% HookEvent)

  matcher <- HookMatcher$new(
    event = "Notification",
    callback = function(message, context) NULL
  )

  expect_equal(matcher$event, "Notification")
})

test_that("Notification hook fires on permission denial", {
  notices <- list()
  reject_reason <- NULL

  local_mocked_bindings(
    tool_reject = function(reason) {
      reject_reason <<- reason
    },
    .package = "ellmer"
  )

  mock <- create_mock_chat_with_notification_capture()
  agent <- Agent$new(
    chat = mock$chat,
    tools = list(tool_run_bash),
    permissions = permissions_plan()
  )

  agent$add_hook(HookMatcher$new(
    event = "Notification",
    timeout = 0,
    callback = function(message, context) {
      notices <<- c(notices, list(list(message = message, context = context)))
      NULL
    }
  ))

  callback <- mock$callback()
  expect_false(is.null(callback))

  callback(create_mock_tool_request(
    name = "run_bash",
    arguments = list(command = "pwd"),
    id = "call_notification"
  ))

  expect_match(reject_reason, "Plan mode", ignore.case = TRUE)
  expect_length(notices, 1)
  expect_equal(notices[[1]]$context$code, "permission_denied")
  expect_equal(notices[[1]]$context$tool_name, "run_bash")
})
