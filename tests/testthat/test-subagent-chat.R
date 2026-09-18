chat_fixture_lead <- function(
  requester,
  redact = function(view, requester) view
) {
  parallel_test_lead(
    new.env(parent = emptyenv()),
    delegation_disclosure = DelegationDisclosure(
      authorize = function(candidate, scope) {
        identical(candidate, requester) && requester$allowed
      },
      redact = redact
    )
  )
}

test_that("optional child UI composes a labeled read-only native chat", {
  skip_if_not_installed("shinychat", "0.5.0")
  skip_if_not_installed("bslib")
  ui <- as.character(subagent_chat_ui("children"))
  expect_match(ui, "Child conversations")
  expect_match(ui, "Inspect a child conversation")
  expect_match(ui, "deputy-readonly-chat")
  expect_match(ui, "shiny-chat-container")
  expect_match(ui, 'aria-live="polite"', fixed = TRUE)
})

test_that("selection close and saved replay never execute a child", {
  skip_if_not_installed("shinychat", "0.5.0")
  skip_if_not_installed("bslib")
  auth_context <- new.env(parent = emptyenv())
  auth_context$allowed <- TRUE
  lead <- chat_fixture_lead(auth_context)
  lead$parallel_delegate(c(a = "one", b = "two"))
  before <- lead$usage()
  saved <- lead$export_subagents(auth_context)
  history <- shiny::reactiveVal(NULL)
  cancelled <- character()
  shiny::testServer(
    subagent_chat_server,
    args = list(
      lead = lead,
      requester = function() auth_context,
      history = history,
      disclosure = lead$.__enclos_env__$private$.delegation_disclosure,
      scope = saved$scope,
      on_cancel = function(id, requester) cancelled <<- c(cancelled, id)
    ),
    {
      session$flushReact()
      expect_length(views(), 2L)
      id <- lead$list_subagents()$delegation_id[[1L]]
      session$setInputs(selected = id)
      session$flushReact()
      expect_identical(selected(), id)
      expect_match(output$notice, "completed")
      session$setInputs(close = 1L)
      session$flushReact()
      expect_identical(closed(), TRUE)
      expect_null(selected())
      session$setInputs(choice = id)
      session$flushReact()
      expect_identical(closed(), FALSE)
      history(saved)
      session$elapse(300)
      session$flushReact()
      expect_length(views(), 2L)
      expect_length(cancelled, 0L)
      session$setInputs(close = 2L)
      session$flushReact()
      expect_identical(closed(), TRUE)
      auth_context$allowed <- FALSE
      session$elapse(300)
      session$flushReact()
      expect_length(views(), 0L)
      expect_null(selected())
      expect_match(output$notice, "access was denied")
    }
  )
  expect_equal(lead$usage(), before)
})

test_that("activity labels escape hostile task text", {
  skip_if_not_installed("shinychat", "0.5.0")
  skip_if_not_installed("bslib")
  auth_context <- new.env(parent = emptyenv())
  auth_context$allowed <- TRUE
  lead <- chat_fixture_lead(auth_context)
  lead$parallel_delegate(c(a = "<script>window.injected=true</script>"))
  shiny::testServer(
    subagent_chat_server,
    args = list(lead = lead, requester = function() auth_context),
    {
      session$flushReact()
      activity <- output$activity$html
      expect_match(activity, "&lt;script&gt;", fixed = TRUE)
      expect_identical(
        grepl("<script>window.injected", activity, fixed = TRUE),
        FALSE
      )
    }
  )
})

test_that("native replay pairs tool cards across turn boundaries", {
  skip_if_not_installed("shinychat", "0.5.0")
  request <- ellmer::ContentToolRequest(
    id = "tool-1",
    name = "evidence",
    arguments = list()
  )
  result <- ellmer::ContentToolResult("retained evidence", request = request)
  turns <- list(
    ellmer::UserTurn(list(ellmer::ContentText("task"))),
    ellmer::AssistantTurn(list(request)),
    ellmer::UserTurn(list(result)),
    ellmer::AssistantTurn(list(ellmer::ContentText("answer")))
  )
  messages <- subagent_chat_messages(turns)
  expect_length(messages, 2L)
  expect_identical(messages[[2L]]$role, "assistant")
  content <- messages[[2L]]$content
  expect_identical(content[[1L]]$request_id, "tool-1")
  expect_identical(content[[2L]]$request_id, "tool-1")
  expect_identical(content[[2L]]$status, "success")
  expect_identical(content[[2L]]$value, "retained evidence")
  expect_identical(content[[3L]], "answer")
})


test_that("untrusted markdown cannot introduce active HTML", {
  skip_if_not_installed("shinychat", "0.5.0")
  text <- ellmer::ContentText(
    "**Keep markdown** <img src=x onerror='alert(1)'><script>alert(1)</script>"
  )
  request <- ellmer::ContentToolRequest(
    id = "tool",
    name = "evidence",
    arguments = list()
  )
  result <- ellmer::ContentToolResult(list(text), request = request)
  safe <- subagent_chat_safe_content(result)
  expect_match(safe@value[[1L]]@text, "&lt;script&gt;", fixed = TRUE)
  expect_match(safe@value[[1L]]@text, "**Keep markdown**", fixed = TRUE)
  expect_match(text@text, "<script>", fixed = TRUE)
  message <- subagent_chat_messages(list(ellmer::AssistantTurn(list(text))))[[
    1L
  ]]
  expect_match(message$content[[1L]], "&lt;img", fixed = TRUE)
})

test_that("saved nested lineage remains visible without recursive execution", {
  skip_if_not_installed("shinychat", "0.5.0")
  skip_if_not_installed("bslib")
  auth_context <- new.env(parent = emptyenv())
  auth_context$allowed <- TRUE
  lead <- chat_fixture_lead(auth_context)
  lead$parallel_delegate(c(a = "parent evidence"))
  saved <- lead$export_subagents(auth_context)
  child <- saved$children[[1L]]
  child$outcome$runtime$parent_run_id <- "fixture-parent-run"
  child$outcome$runtime$parent_delegation_id <- "fixture-parent-delegation"
  child$outcome$runtime$delegation_id <- "fixture-grandchild"
  child$outcome$runtime$agent_name <- "nested reviewer (fixture)"
  saved$children <- list(child)
  before <- lead$usage()
  shiny::testServer(
    subagent_chat_server,
    args = list(
      lead = lead,
      requester = function() auth_context,
      history = function() saved,
      disclosure = lead$.__enclos_env__$private$.delegation_disclosure,
      scope = saved$scope
    ),
    {
      session$flushReact()
      session$setInputs(selected = "fixture-grandchild")
      session$flushReact()
      expect_match(output$details$html, "fixture-parent-run")
      expect_match(output$details$html, "fixture-parent-delegation")
      expect_match(output$notice, "nested reviewer")
    }
  )
  expect_equal(lead$usage(), before)
})

test_that("native JSON tool content uses safe markdown instead of raw HTML", {
  skip_if_not_installed("shinychat", "0.5.0")
  json <- ellmer::contents_replay(list(
    version = 1,
    class = "ellmer::ContentJson",
    props = list(
      data = list(text = "<img src=x onerror=alert(1)>"),
      string = NULL
    )
  ))
  safe <- subagent_chat_safe_content(json)
  expect_s7_class(safe, ellmer::ContentText)
  expect_match(safe@text, "```json", fixed = TRUE)
  expect_match(safe@text, "&lt;img", fixed = TRUE)
  request <- ellmer::ContentToolRequest(
    id = "json",
    name = "fixture",
    arguments = list()
  )
  expect_no_error(subagent_chat_messages(list(ellmer::UserTurn(list(
    ellmer::ContentToolResult(list(json), request = request)
  )))))
})
