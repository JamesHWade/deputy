skip_if_not_installed("commonmark")
skip_if_not_installed("xml2")

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
  skip_if_not_installed("shiny")
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
  skip_if_not_installed("shiny")
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
  skip_if_not_installed("shiny")
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
  skip_if_not_installed("shiny")
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
  expect_identical(messages[[1L]]$content[[1L]], "task")
  expect_identical(messages[[2L]]$role, "assistant")
  content <- messages[[2L]]$content
  expect_identical(content[[1L]]$request_id, "tool-1")
  expect_identical(content[[2L]]$request_id, "tool-1")
  expect_identical(content[[2L]]$status, "success")
  expect_identical(content[[2L]]$value, "retained evidence")
  expect_identical(xml2::xml_text(xml2::read_html(content[[3L]])), "answer")
})


test_that("untrusted markdown cannot introduce active HTML", {
  skip_if_not_installed("shiny")
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
  expect_match(
    safe@value[[1L]]@text,
    "<strong>Keep markdown</strong>",
    fixed = TRUE
  )
  expect_match(text@text, "<script>", fixed = TRUE)
  message <- subagent_chat_messages(list(ellmer::AssistantTurn(list(text))))[[
    1L
  ]]
  expect_false(grepl("onerror=|<script>", message$content[[1L]]))
})

test_that("saved nested lineage remains visible without recursive execution", {
  skip_if_not_installed("shiny")
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
  skip_if_not_installed("shiny")
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
  expect_length(
    xml2::xml_find_all(xml2::read_html(safe@text), "//pre/code"),
    1L
  )
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


test_that("demo fingerprints retain failure text without condition environments", {
  fixture <- new.env(parent = globalenv())
  sys.source(
    system.file(
      "examples",
      "subagent-chats",
      "fixture.R",
      package = "deputy",
      mustWork = TRUE
    ),
    fixture
  )
  turn <- function(message, state) {
    error <- simpleError(message)
    error$private <- state
    ellmer::UserTurn(list(ellmer::ContentToolResult(error = error)))
  }
  first <- turn("failed", new.env())
  same <- turn("failed", globalenv())
  changed <- turn("different failure", globalenv())
  expect_identical(
    fixture$child_chat_signature(list(first)),
    fixture$child_chat_signature(list(same))
  )
  expect_false(identical(
    fixture$child_chat_signature(list(first)),
    fixture$child_chat_signature(list(changed))
  ))
})


test_that("changing the requester replaces the event disclosure context", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("shinychat", "0.5.0")
  skip_if_not_installed("bslib")
  requester <- shiny::reactiveVal("first")
  lead <- parallel_test_lead(
    new.env(parent = emptyenv()),
    delegation_disclosure = DelegationDisclosure(
      authorize = function(requester, scope) TRUE,
      redact = function(view, requester) {
        if (
          identical(view$event$type, "text") && identical(requester, "second")
        ) {
          view$event$data$text <- NULL
        }
        view
      }
    )
  )
  lead$parallel_delegate(c(a = "one"))
  id <- lead$list_subagents()$delegation_id[[1L]]
  shiny::testServer(
    subagent_chat_server,
    args = list(lead = lead, requester = requester),
    {
      session$flushReact()
      id <- lead$list_subagents()$delegation_id[[1L]]
      session$setInputs(selected = id)
      session$flushReact()
      expect_identical(selected(), id)
      lead_observe_event(lead, id, AgentEvent("text", text = "first user only"))
      session$elapse(300)
      session$flushReact()
      expect_identical(state$partial, "first user only")
      previous <- state$reader
      requester("second")
      session$elapse(300)
      session$flushReact()
      expect_false(identical(state$reader, previous))
      expect_identical(state$requester, "second")
      expect_identical(state$partial, "")
      lead_observe_event(lead, id, AgentEvent("text", text = "first user only"))
      session$elapse(300)
      session$flushReact()
      expect_identical(state$partial, "")
      expect_length(views(), 1L)
    }
  )
})

test_that("redacted identities do not hide remaining child views", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("shinychat", "0.5.0")
  skip_if_not_installed("bslib")
  owner <- new.env(parent = emptyenv())
  owner$allowed <- TRUE
  owner$hidden <- FALSE
  lead <- chat_fixture_lead(owner, redact = function(view, requester) {
    if (owner$hidden && identical(view$outcome$runtime$agent_name, "a")) {
      view$outcome <- NULL
    } else {
      view$outcome$runtime$status <- NULL
      view$outcome$runtime$agent_name <- NULL
    }
    view
  })
  lead$parallel_delegate(c(a = "one", b = "two"))
  id <- lead$list_subagents()$delegation_id[[1L]]
  shiny::testServer(
    subagent_chat_server,
    args = list(lead = lead, requester = function() owner),
    {
      session$flushReact()
      id <- lead$list_subagents()$delegation_id[[1L]]
      session$setInputs(selected = id)
      session$flushReact()
      expect_length(views(), 2L)
      expect_type(output$details$html, "character")
      owner$hidden <- TRUE
      session$elapse(300)
      session$flushReact()
      expect_length(views(), 1L)
      expect_null(selected())
      expect_match(output$notice, "no longer available")
      expect_type(output$activity$html, "character")
    }
  )
})


test_that("native tool code values and errors preserve literal characters", {
  skip_if_not_installed("shinychat", "0.5.0")
  text <- "<img src=x onerror=bad()> & literal"
  request <- ellmer::ContentToolRequest(
    id = "literal",
    name = "fixture",
    arguments = list()
  )
  for (result in list(
    ellmer::ContentToolResult(text, request = request),
    ellmer::ContentToolResult(NULL, error = text, request = request)
  )) {
    block <- shinychat::contents_shinychat(subagent_chat_safe_content(result))
    expect_identical(block$value_type, "code")
    expect_identical(block$value, text)
  }
})

test_that("sanitized Markdown preserves code and rejects active markup and URLs", {
  skip_if_not_installed("commonmark")
  skip_if_not_installed("xml2")
  source <- paste(
    "**Markdown** and `a < b & c > d`.",
    "",
    "```r",
    "a < b & c > d",
    "```",
    "",
    "    a < b & c > d",
    "",
    '<img src=x onerror="bad()"><script>bad()</script>',
    "",
    "[bad](javascript:alert%281%29) [good](https://example.com)",
    sep = "\n"
  )
  html <- subagent_chat_markdown(source)
  dom <- xml2::read_html(html)
  expect_identical(
    xml2::xml_text(xml2::xml_find_all(dom, "//code")),
    c("a < b & c > d", "a < b & c > d\n", "a < b & c > d\n")
  )
  expect_length(
    xml2::xml_find_all(
      dom,
      "//script|//*[@onerror]|//a[starts-with(@href, 'javascript:')]"
    ),
    0L
  )
  expect_identical(
    xml2::xml_text(xml2::xml_find_first(dom, "//strong")),
    "Markdown"
  )
  expect_identical(
    xml2::xml_attr(xml2::xml_find_all(dom, "//a"), "href"),
    c(NA_character_, "https://example.com")
  )
})

test_that("mutable disclosure re-redacts retained transcript and streamed text", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("shinychat", "0.5.0")
  skip_if_not_installed("bslib")
  owner <- new.env(parent = emptyenv())
  owner$allowed <- TRUE
  owner$hide_text <- FALSE
  owner$hide_history <- FALSE
  lead <- chat_fixture_lead(owner, redact = function(view, requester) {
    if (requester$hide_text && identical(view$kind, "event")) {
      view$event <- NULL
    }
    if (requester$hide_history) {
      view$transcript <- NULL
    }
    view
  })
  lead$parallel_delegate(c(a = "one"))
  before <- lead$usage()
  shiny::testServer(
    subagent_chat_server,
    args = list(lead = lead, requester = function() owner),
    {
      session$flushReact()
      id <- lead$list_subagents()$delegation_id[[1L]]
      session$setInputs(selected = id)
      session$flushReact()
      session$elapse(300)
      session$flushReact()
      lead_observe_event(
        lead,
        id,
        AgentEvent("text", text = "sensitive live text")
      )
      session$elapse(300)
      session$flushReact()
      expect_identical(state$partial, "sensitive live text")
      expect_length(state$rendered$turns, 2L)
      lead_observe_event(lead, id, AgentEvent("text", text = strrep("x", 9000)))
      session$elapse(300)
      session$flushReact()
      expect_lte(nchar(state$partial, type = "bytes"), 8192L)
      expect_match(output$notice, "truncated")
      owner$hide_text <- TRUE
      session$elapse(300)
      session$flushReact()
      expect_identical(state$partial, "")
      owner$hide_history <- TRUE
      session$elapse(300)
      session$flushReact()
      expect_length(state$rendered$turns, 0L)
      expect_length(views(), 1L)
      owner$hide_history <- FALSE
      session$elapse(300)
      session$flushReact()
      expect_length(state$rendered$turns, 2L)
    }
  )
  expect_equal(lead$usage(), before)
})


test_that("mixed native tool evidence keeps Markdown code faithful and markup inert", {
  skip_if_not_installed("shinychat", "0.5.0")
  request <- ellmer::ContentToolRequest(
    id = "mixed",
    name = "fixture",
    arguments = list()
  )
  value <- list(
    ellmer::ContentText("`a < b & c > d`"),
    "<img src=x onerror=bad()>",
    list(nested = "<script>bad()</script>")
  )
  block <- shinychat::contents_shinychat(subagent_chat_safe_content(
    ellmer::ContentToolResult(value, request = request)
  ))
  expect_identical(block$value_type, "content_extra")
  items <- jsonlite::fromJSON(block$value, simplifyVector = FALSE)
  dom <- xml2::read_html(paste(
    vapply(items, function(x) x$value, character(1)),
    collapse = "\n"
  ))
  expect_identical(
    xml2::xml_text(xml2::xml_find_first(dom, "//code")),
    "a < b & c > d"
  )
  expect_length(xml2::xml_find_all(dom, "//script|//*[@onerror]"), 0L)
})


test_that("snapshot refresh retains the current text batch and request boundaries", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("shinychat", "0.5.0")
  skip_if_not_installed("bslib")
  owner <- new.env(parent = emptyenv())
  owner$allowed <- TRUE
  lead <- chat_fixture_lead(owner)
  lead$parallel_delegate(c(a = "one"))
  shiny::testServer(
    subagent_chat_server,
    args = list(lead = lead, requester = function() owner),
    {
      session$flushReact()
      id <- lead$list_subagents()$delegation_id[[1L]]
      session$setInputs(selected = id)
      session$flushReact()
      private <- lead$.__enclos_env__$private
      private$subagent_runs[[id]]$status <- "running"
      private$subagent_runs[[
        id
      ]]$turns <- list(ellmer::UserTurn(list(ellmer::ContentText(
        "new request"
      ))))
      lead_observe_event(lead, id, AgentEvent("request_start"))
      lead_observe_event(lead, id, AgentEvent("text", text = "first chunk"))
      session$elapse(300)
      session$flushReact()
      expect_identical(state$partial, "first chunk")
      lead_observe_event(lead, id, AgentEvent("text", text = " and second"))
      session$elapse(300)
      session$flushReact()
      expect_identical(state$partial, "first chunk and second")
      lead_observe_event(lead, id, AgentEvent("request_end"))
      lead_observe_event(lead, id, AgentEvent("request_start"))
      lead_observe_event(lead, id, AgentEvent("text", text = "next request"))
      session$elapse(300)
      session$flushReact()
      expect_identical(state$partial, "next request")
      lead_observe_status(lead, id, "settled")
      session$elapse(300)
      session$flushReact()
      expect_identical(state$partial, "")
    }
  )
})

test_that("deeply nested Content stays in native code display", {
  skip_if_not_installed("shinychat", "0.5.0")
  request <- ellmer::ContentToolRequest(
    id = "nested",
    name = "fixture",
    arguments = list()
  )
  value <- list(nested = list(ellmer::ContentText("<script>bad()</script>")))
  block <- shinychat::contents_shinychat(subagent_chat_safe_content(ellmer::ContentToolResult(
    value,
    request = request
  )))
  expect_identical(block$value_type, "code")
  expect_false(grepl("<script>", block$value, fixed = TRUE))
})
