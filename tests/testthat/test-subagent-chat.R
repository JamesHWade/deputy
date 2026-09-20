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
  owner$hide_type <- FALSE
  owner$hide_history <- FALSE
  lead <- chat_fixture_lead(owner, redact = function(view, requester) {
    if (requester$hide_text && identical(view$kind, "event")) {
      view$event <- NULL
    }
    if (isTRUE(requester$hide_type) && identical(view$kind, "event")) {
      view$event$type <- NULL
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
      owner$hide_type <- TRUE
      session$elapse(300)
      session$flushReact()
      expect_identical(state$partial, "")
      expect_identical(selected(), id)
      owner$hide_type <- FALSE
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
      private$subagent_runs[[id]]$turns <- list(ellmer::AssistantPartialTurn(
        list(ellmer::ContentText("first chunk and second")),
        reason = "interrupted"
      ))
      session$elapse(300)
      session$flushReact()
      expect_identical(state$partial, "")
      messages <- subagent_chat_messages(state$rendered$turns)
      expect_match(
        messages[[1L]]$content[[1L]],
        "first chunk and second",
        fixed = TRUE
      )
      private$subagent_runs[[id]]$turns <- list(ellmer::AssistantTurn(
        list(ellmer::ContentText("first chunk and second"))
      ))
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

test_that("deeply nested Content keeps paths, data, and typed attachments", {
  skip_if_not_installed("shinychat", "0.5.0")
  request <- ellmer::ContentToolRequest(
    id = "nested",
    name = "fixture",
    arguments = list()
  )
  value <- list(
    nested = list(
      text = ellmer::ContentText("<script>bad()</script>"),
      image = ellmer::content_image_url("https://example.com/nested.png"),
      document = ellmer::ContentDocument(
        "text/plain",
        "aGVsbG8=",
        "nested.txt"
      ),
      pdf = ellmer::ContentPDF("application/pdf", "aGVsbG8=", "nested.pdf")
    ),
    ordinary = list(label = "surrounding", count = 2L)
  )
  result <- ellmer::ContentToolResult(value, request = request)
  retained <- ellmer::contents_record(result)
  live <- shinychat::contents_shinychat(subagent_chat_safe_content(result))
  saved_record <- inspection_record_turn(ellmer::UserTurn(list(result)))
  saved_turn <- inspection_replay(saved_record)
  saved <- shinychat::contents_shinychat(
    subagent_chat_safe_content(saved_turn@contents[[1L]])
  )
  items <- jsonlite::fromJSON(live$value, simplifyVector = FALSE)
  text <- paste(
    vapply(
      Filter(function(item) identical(item$type, "text"), items),
      `[[`,
      character(1),
      "value"
    ),
    collapse = "\n"
  )
  expect_identical(live$value_type, "content_extra")
  expect_identical(live$value, saved$value)
  expect_identical(ellmer::contents_record(result), retained)
  expect_match(text, "nested.text", fixed = TRUE)
  expect_match(text, "ordinary.label", fixed = TRUE)
  expect_match(text, "surrounding", fixed = TRUE)
  expect_match(text, "&lt;script&gt;", fixed = TRUE)
  expect_false(grepl("<script>", text, fixed = TRUE))
  expect_true(any(vapply(
    items,
    function(item) {
      identical(item$type, "image") &&
        identical(item$src, "https://example.com/nested.png")
    },
    logical(1)
  )))
  expect_true(any(vapply(
    items,
    function(item) {
      identical(item$type, "pdf") && identical(item$filename, "nested.pdf")
    },
    logical(1)
  )))
  expect_match(text, "Document: nested.txt", fixed = TRUE)
})

test_that("record-shaped ordinary data is not restored as Content", {
  skip_if_not_installed("shinychat", "0.5.0")
  request <- ellmer::ContentToolRequest(
    id = "ordinary",
    name = "fixture",
    arguments = list()
  )
  value <- list(
    nested = list(
      version = 1,
      class = "ellmer::ContentText",
      props = list(text = "ordinary record-shaped data")
    )
  )
  result <- ellmer::ContentToolResult(value, request = request)
  block <- shinychat::contents_shinychat(subagent_chat_safe_content(result))
  expect_identical(block$value_type, "code")
  expect_match(block$value, "ellmer::ContentText", fixed = TRUE)
  expect_identical(result@value, value)
})

test_that("unsupported classed values cannot run display methods", {
  skip_if_not_installed("shinychat", "0.5.0")
  method_name <- "length.application_object"
  had_method <- exists(method_name, envir = globalenv(), inherits = FALSE)
  old_method <- get0(method_name, envir = globalenv(), inherits = FALSE)
  assign(
    method_name,
    function(value) stop("the display must not call length()"),
    envir = globalenv()
  )
  on.exit(
    if (had_method) {
      assign(method_name, old_method, envir = globalenv())
    } else {
      rm(list = method_name, envir = globalenv())
    },
    add = TRUE
  )
  request <- ellmer::ContentToolRequest(
    id = "method",
    name = "fixture",
    arguments = list()
  )
  value <- list(
    nested = list(
      text = ellmer::ContentText("small"),
      ordinary = structure(1, class = "application_object")
    )
  )
  block <- shinychat::contents_shinychat(
    subagent_chat_safe_content(
      ellmer::ContentToolResult(value, request = request)
    )
  )
  expect_match(block$value, "application_object", fixed = TRUE)
  expect_match(block$value, "omitted", fixed = TRUE)
})

test_that("classed nested data keeps live and saved displays identical", {
  skip_if_not_installed("shinychat", "0.5.0")
  request <- ellmer::ContentToolRequest(
    id = "classed",
    name = "fixture",
    arguments = list()
  )
  duration <- as.difftime(c(1, NA), units = "hours")
  value <- list(
    nested = list(
      note = ellmer::ContentText("small"),
      duration = duration,
      frame = data.frame(
        label = c("first", "second"),
        duration = duration,
        stringsAsFactors = FALSE
      )
    )
  )
  result <- ellmer::ContentToolResult(value, request = request)
  live <- shinychat::contents_shinychat(subagent_chat_safe_content(result))
  saved_record <- inspection_record_turn(ellmer::UserTurn(list(result)))
  saved_turn <- inspection_replay(saved_record)
  saved <- shinychat::contents_shinychat(
    subagent_chat_safe_content(saved_turn@contents[[1L]])
  )
  expect_identical(live$value, saved$value)
  expect_match(live$value, "hours", fixed = TRUE)
  expect_match(live$value, "first", fixed = TRUE)
})

test_that("nested Content display has explicit depth and size omissions", {
  skip_if_not_installed("shinychat", "0.5.0")
  request <- ellmer::ContentToolRequest(
    id = "bounded",
    name = "fixture",
    arguments = list()
  )
  deep <- ellmer::ContentText("deep text")
  for (index in seq_len(12L)) {
    deep <- setNames(list(deep), paste0("level", index))
  }
  deep_result <- ellmer::ContentToolResult(
    list(deep = deep),
    request = request
  )
  deep_block <- shinychat::contents_shinychat(
    subagent_chat_safe_content(deep_result)
  )
  expect_match(deep_block$value, "maximum depth", fixed = TRUE)

  large_result <- ellmer::ContentToolResult(
    list(large = list(text = ellmer::ContentText(strrep("x", 10000L)))),
    request = request
  )
  large_block <- shinychat::contents_shinychat(
    subagent_chat_safe_content(large_result)
  )
  expect_match(large_block$value, "content size limit", fixed = TRUE)
})

test_that("nested PDFs keep native metadata and later siblings", {
  skip_if_not_installed("shinychat", "0.5.0")
  request <- ellmer::ContentToolRequest(
    id = "pdf-bound",
    name = "fixture",
    arguments = list()
  )
  result <- ellmer::ContentToolResult(
    list(
      nested = list(
        pdf = ellmer::ContentPDF(
          "application/pdf",
          strrep("x", 20000L),
          "nested.pdf"
        ),
        later = ellmer::ContentText("later sibling")
      )
    ),
    request = request
  )
  block <- shinychat::contents_shinychat(subagent_chat_safe_content(result))
  expect_match(block$value, '"type":"pdf"', fixed = TRUE)
  expect_match(block$value, '"filename":"nested.pdf"', fixed = TRUE)
  expect_match(block$value, "later sibling", fixed = TRUE)
  expect_false(grepl(strrep("x", 20000L), block$value, fixed = TRUE))
})

test_that("long nested PDF filenames are bounded before native rendering", {
  skip_if_not_installed("shinychat", "0.5.0")
  request <- ellmer::ContentToolRequest(
    id = "pdf-name-bound",
    name = "fixture",
    arguments = list()
  )
  long_name <- strrep("f", 20000L)
  result <- ellmer::ContentToolResult(
    list(
      nested = list(
        pdf = ellmer::ContentPDF("application/pdf", "small", long_name)
      )
    ),
    request = request
  )
  block <- shinychat::contents_shinychat(subagent_chat_safe_content(result))
  expect_match(block$value, "content size limit", fixed = TRUE)
  expect_false(grepl(long_name, block$value, fixed = TRUE))
})

test_that("nested data frame support checks are bounded", {
  skip_if_not_installed("shinychat", "0.5.0")
  request <- ellmer::ContentToolRequest(
    id = "frame-bound",
    name = "fixture",
    arguments = list()
  )
  deep_column <- 1L
  for (index in seq_len(32L)) {
    deep_column <- list(deep_column)
  }
  deep_frame <- structure(
    list(column = deep_column),
    class = "data.frame",
    row.names = 1L
  )
  broad_frame <- structure(
    list(column = as.list(seq_len(1000L))),
    class = "data.frame",
    row.names = seq_len(1000L)
  )
  result <- ellmer::ContentToolResult(
    list(
      nested = list(text = ellmer::ContentText("small")),
      deep = deep_frame,
      broad = broad_frame
    ),
    request = request
  )
  block <- shinychat::contents_shinychat(subagent_chat_safe_content(result))
  expect_match(block$value, "data.frame", fixed = TRUE)
  expect_match(block$value, "small", fixed = TRUE)
})

test_that("unsupported data frame columns cannot run display methods", {
  skip_if_not_installed("shinychat", "0.5.0")
  method_name <- "length.appcol"
  had_method <- exists(method_name, envir = globalenv(), inherits = FALSE)
  old_method <- get0(method_name, envir = globalenv(), inherits = FALSE)
  assign(
    method_name,
    function(value) stop("the display must not call column length()"),
    envir = globalenv()
  )
  on.exit(
    if (had_method) {
      assign(method_name, old_method, envir = globalenv())
    } else {
      rm(list = method_name, envir = globalenv())
    },
    add = TRUE
  )
  request <- ellmer::ContentToolRequest(
    id = "frame-method",
    name = "fixture",
    arguments = list()
  )
  frame <- structure(
    list(a = structure(1, class = "appcol")),
    class = "data.frame",
    row.names = 1L
  )
  value <- list(
    nested = list(text = ellmer::ContentText("small")),
    frame = frame
  )
  block <- shinychat::contents_shinychat(
    subagent_chat_safe_content(
      ellmer::ContentToolResult(value, request = request)
    )
  )
  expect_match(block$value, "data.frame", fixed = TRUE)
  expect_match(block$value, "small", fixed = TRUE)
})


test_that("mixed user turns pair tool results while retaining user text", {
  skip_if_not_installed("shinychat", "0.5.0")
  request <- ellmer::ContentToolRequest(
    id = "mixed",
    name = "evidence",
    arguments = list()
  )
  result <- ellmer::ContentToolResult("evidence", request = request)
  messages <- subagent_chat_messages(list(
    ellmer::AssistantTurn(list(request)),
    ellmer::UserTurn(list(ellmer::ContentText("extra context"), result)),
    ellmer::AssistantTurn(list(ellmer::ContentText("answer")))
  ))
  expect_identical(
    vapply(messages, `[[`, character(1), "role"),
    c("assistant", "user", "assistant")
  )
  expect_length(messages[[1L]]$content, 2L)
  expect_identical(messages[[1L]]$content[[1L]]$request_id, "mixed")
  expect_identical(messages[[1L]]$content[[2L]]$request_id, "mixed")
  expect_identical(messages[[1L]]$content[[2L]]$status, "success")
  expect_identical(messages[[2L]]$content[[1L]], "extra context")
})
