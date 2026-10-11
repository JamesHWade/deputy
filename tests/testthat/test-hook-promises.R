test_that("tool hook results merge the same whether or not they arrived as promises", {
  pre <- merge_tool_hook_results(
    "PreToolUse",
    list(
      HookResultPreToolUse(permission = "allow", additional_context = "a"),
      HookResultPreToolUse(
        permission = "deny",
        reason = "no",
        continue = FALSE,
        additional_context = "b"
      ),
      NULL
    )
  )
  expect_s7_class(pre, HookResultPreToolUse)
  expect_equal(pre@permission, "deny")
  expect_equal(pre@reason, "no")
  expect_false(pre@continue)
  expect_equal(pre@additional_context, "a\nb")

  post <- merge_tool_hook_results(
    "PostToolUse",
    list(
      HookResultPostToolUse(additional_context = "x"),
      NULL,
      HookResultPostToolUse(
        continue = FALSE,
        stop_reason = "halt",
        additional_context = "y"
      )
    )
  )
  expect_s7_class(post, HookResultPostToolUse)
  expect_false(post@continue)
  expect_equal(post@stop_reason, "halt")
  expect_equal(post@additional_context, "x\ny")
})

test_that("a Notification hook's promise is not waited for, and its rejection is recorded", {
  reject_reason <- NULL
  local_mocked_bindings(
    tool_reject = function(reason) {
      reject_reason <<- reason
    },
    .package = "ellmer"
  )

  captured_callback <- NULL
  chat <- create_mock_chat()
  original_on_tool_request <- chat$on_tool_request
  chat$on_tool_request <- function(callback) {
    captured_callback <<- callback
    original_on_tool_request(callback)
  }
  agent <- Agent$new(
    chat = chat,
    tools = list(tool_run_bash),
    permissions = permissions_plan()
  )
  agent$add_hook(HookMatcher(
    event = "Notification",
    timeout = 0,
    callback = function(message, context) {
      promises::promise(function(resolve, reject) {
        later::later(
          function() reject(rlang::error_cnd(message = "notice failed")),
          0.02
        )
      })
    }
  ))

  expect_no_error(captured_callback(create_mock_tool_request(
    name = "run_bash",
    arguments = list(command = "pwd"),
    id = "call_notification_promise"
  )))
  expect_match(reject_reason, "Plan mode", ignore.case = TRUE)
  expect_length(agent$hooks$last_errors(), 0L)

  for (i in seq_len(100)) {
    later::run_now(0.01)
  }

  expect_length(agent$hooks$last_errors(), 1L)
  expect_match(agent$hooks$last_errors()[[1]]$error, "notice failed")
})

test_that("a ConfigChange hook's promise is not waited for", {
  permissions <- Permissions(
    mode = "standard",
    file_read = FALSE,
    file_write = FALSE,
    bash = FALSE,
    r_code = FALSE,
    web = FALSE,
    install_packages = FALSE
  )
  agent <- Agent$new(
    chat = create_mock_chat(),
    tools = list(tool_read_file),
    permissions = permissions
  )
  seen <- FALSE
  agent$add_hook(HookMatcher(
    event = "ConfigChange",
    timeout = 0,
    callback = function(key, old_value, new_value, context) {
      seen <<- TRUE
      later_value(NULL)
    }
  ))

  expect_invisible(agent$set_permission_mode("readonly"))
  expect_identical(agent$get_permission_mode(), "readonly")
  expect_true(seen)
})
