# Instrumentation is initialized before importing ellmer in a fresh process;
# no test reaches into upstream tracer caches or callback managers.
record_runtime_trace <- function(
  url,
  mode = "tool",
  capture = FALSE,
  conversation_id = NULL,
  compact = FALSE
) {
  skip_if_not_installed("otel")
  skip_if_not_installed("otelsdk")
  callr::r(
    function(path, url, mode, capture, conversation_id, compact) {
      Sys.setenv(
        OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT = if (capture) {
          "true"
        } else {
          "false"
        }
      )
      otelsdk::with_otel_record({
        if (file.exists(file.path(path, "R", "agent.R"))) {
          pkgload::load_all(path, quiet = TRUE)
        } else {
          library(deputy, lib.loc = dirname(path))
        }
        chat <- ellmer::chat_openai_compatible(
          base_url = url,
          credentials = function() "fixture",
          model = "gpt-4o-mini",
          echo = "none"
        )
        if (mode == "delegate") {
          agent <- LeadAgent$new(
            chat,
            sub_agents = list(agent_definition(
              "worker",
              "Worker",
              "private child instructions"
            )),
            permissions = permissions_full()
          )
        } else {
          tool <- ellmer::tool(
            function() "private tool result",
            name = "effect",
            description = "effect"
          )
          permissions <- if (mode %in% c("deny", "override", "override_deny")) {
            Permissions(mode = "readonly", tool_denylist = "effect")
          } else {
            permissions_full()
          }
          agent <- Agent$new(
            chat,
            tools = list(tool),
            permissions = permissions
          )
        }
        if (mode %in% c("override", "override_deny")) {
          agent$add_hook(HookMatcher(
            "PermissionRequest",
            function(...) PermissionResultAllow(),
            timeout = 0
          ))
        }
        if (mode %in% c("hook_deny", "override_deny")) {
          agent$add_hook(HookMatcher(
            "PreToolUse",
            function(...) {
              HookResultPreToolUse(
                permission = "deny",
                reason = "private hook denial"
              )
            },
            timeout = 0
          ))
        }
        if (!is.null(conversation_id)) {
          agent$conversation_id <- conversation_id
        }
        result <- suppressWarnings(agent$run_sync("private user prompt"))
        if (compact) {
          agent$compact(keep_last = 1L)
        }
        list(
          run_id = result$run_id,
          session_id = result$session_id,
          usage = S7::props(result$usage),
          events = result$events
        )
      })
    },
    args = list(
      path = getNamespaceInfo(asNamespace("deputy"), "path"),
      url = url,
      mode = mode,
      capture = capture,
      conversation_id = conversation_id,
      compact = compact
    )
  )
}

test_that("governance wraps upstream model, HTTP, and tool spans without duplication", {
  server <- local_runtime_server(list(
    runtime_reply(tool = "effect"),
    runtime_reply()
  ))
  record <- record_runtime_trace(server$url)
  spans <- record$traces
  run <- spans[["deputy.run"]]
  invoke <- spans[["invoke_agent"]]
  chats <- Filter(function(x) startsWith(x$name, "chat "), spans)
  http <- Filter(function(x) identical(x$name, "POST"), spans)
  tools <- Filter(function(x) startsWith(x$name, "execute_tool "), spans)
  expect_identical(invoke$parent, run$span_id)
  expect_length(chats, 2L)
  expect_length(http, 2L)
  expect_length(tools, 1L)
  expect_true(all(vapply(
    chats,
    function(x) identical(x$parent, invoke$span_id),
    logical(1)
  )))
  expect_true(all(vapply(
    http,
    function(x) x$parent %in% vapply(chats, `[[`, character(1), "span_id"),
    logical(1)
  )))
  expect_identical(run$attributes[["deputy.run.id"]], record$value$run_id)
  expect_identical(
    chats[[1]]$attributes[["gen_ai.conversation.id"]],
    record$value$session_id
  )
  expect_identical(
    run$attributes[["gen_ai.conversation.id"]],
    record$value$session_id
  )
  expect_identical(
    run$attributes[["deputy.session.id"]],
    record$value$session_id
  )
  expect_identical(record$value$usage$requests, 2L)
  serialized <- paste(utils::capture.output(dput(spans)), collapse = "\n")
  expect_false(grepl("private user prompt|private tool result", serialized))
  expect_true(
    "deputy.permission" %in% vapply(run$events, `[[`, character(1), "name")
  )
})

test_that("a run is filed under the host's conversation when the host names one", {
  server <- local_runtime_server(list(
    runtime_reply(tool = "effect"),
    runtime_reply()
  ))
  record <- record_runtime_trace(server$url, conversation_id = "c_host_123")
  spans <- record$traces
  run <- spans[["deputy.run"]]
  chats <- Filter(function(x) startsWith(x$name, "chat "), spans)
  expect_length(chats, 2L)
  expect_identical(run$attributes[["gen_ai.conversation.id"]], "c_host_123")
  expect_true(all(vapply(
    chats,
    function(x) {
      identical(x$attributes[["gen_ai.conversation.id"]], "c_host_123")
    },
    logical(1)
  )))
  # The session stays findable from the run.
  expect_identical(
    run$attributes[["deputy.session.id"]],
    record$value$session_id
  )
})

test_that("compacting between turns stays out of the host's conversation", {
  # A trajectory reader keeps the latest model span per conversation id; a
  # summary request filed under the host's id would replace the conversation.
  server <- local_runtime_server(list(
    runtime_reply(),
    runtime_reply(text = "summary of the earlier turns", stream = FALSE)
  ))
  record <- record_runtime_trace(
    server$url,
    conversation_id = "c_host_123",
    compact = TRUE
  )
  chats <- Filter(function(x) startsWith(x$name, "chat "), record$traces)
  ids <- unname(vapply(
    chats,
    function(x) x$attributes[["gen_ai.conversation.id"]],
    character(1)
  ))
  expect_length(ids, 2L)
  expect_identical(sort(ids), sort(c("c_host_123", record$value$session_id)))
})

test_that("a run keeps the conversation id it started with", {
  chat <- ellmer::chat_openai_compatible(
    base_url = "http://127.0.0.1:9/v1",
    credentials = function() "fixture",
    model = "gpt-4o-mini",
    echo = "none"
  )
  agent <- Agent$new(chat, permissions = permissions_full())
  private <- agent$.__enclos_env__$private
  state <- new.env(parent = emptyenv())
  state$trace_conversation_id <- "c_started"
  private$current_run_state <- state
  withr::defer(private$current_run_state <- NULL)
  # The host cleared its id mid-run (New chat), then a fallback reinstalled
  # the request callbacks.
  agent$conversation_id <- NULL
  install_request_callbacks(agent)
  expect_identical(private$.chat$conversation_id, "c_started")
})

test_that("denials are governance events and content capture remains opt-in", {
  denied <- local_runtime_server(list(
    runtime_reply(tool = "effect"),
    runtime_reply()
  ))
  record <- record_runtime_trace(denied$url, "deny")
  expect_length(
    Filter(function(x) startsWith(x$name, "execute_tool "), record$traces),
    0L
  )
  decisions <- Filter(
    function(x) x$name == "deputy.permission",
    record$traces[["deputy.run"]]$events
  )
  expect_identical(decisions[[1]]$attributes$decision, "deny")
  enabled <- local_runtime_server(list(
    runtime_reply(tool = "effect"),
    runtime_reply()
  ))
  captured <- record_runtime_trace(enabled$url, capture = TRUE)
  model_spans <- Filter(
    function(x) startsWith(x$name, "chat "),
    captured$traces
  )
  expect_match(
    model_spans[[1]]$attributes[["gen_ai.input.messages"]],
    "private user prompt"
  )
  expect_match(
    model_spans[[2]]$attributes[["gen_ai.input.messages"]],
    "private tool result"
  )
  own <- paste(
    utils::capture.output(dput(captured$traces[["deputy.run"]])),
    collapse = "\n"
  )
  expect_false(grepl("private user prompt|private tool result", own))
})

test_that("async delegated runs retain both trace parentage and run correlation", {
  server <- local_runtime_server(list(
    runtime_reply(
      tool = "delegate_to_agent",
      arguments = list(agent_name = "worker", task = "private task")
    ),
    runtime_reply("child finished"),
    runtime_reply("parent finished")
  ))
  record <- record_runtime_trace(server$url, "delegate")
  runs <- Filter(function(x) x$name == "deputy.run", record$traces)
  expect_length(runs, 2L)
  child <- Filter(
    function(x) !is.null(x$attributes[["deputy.parent.run.id"]]),
    runs
  )[[1]]
  parent <- Filter(
    function(x) is.null(x$attributes[["deputy.parent.run.id"]]),
    runs
  )[[1]]
  tool <- record$traces[["execute_tool delegate_to_agent"]]
  expect_identical(child$parent, tool$span_id)
  expect_identical(
    child$attributes[["deputy.parent.run.id"]],
    parent$attributes[["deputy.run.id"]]
  )
  expect_true(nzchar(child$attributes[["deputy.delegation.id"]]))
  expect_identical(record$value$usage$requests, 3L)
  expect_length(
    Filter(function(x) startsWith(x$name, "chat "), record$traces),
    3L
  )
})

test_that("permission events contain only the final Deputy decision", {
  for (mode in c("hook_deny", "override", "override_deny")) {
    server <- local_runtime_server(list(
      runtime_reply(tool = "effect"),
      runtime_reply()
    ))
    record <- record_runtime_trace(server$url, mode)
    decision <- if (mode == "override") "allow" else "deny"
    events <- Filter(function(x) x$type == "permission", record$value$events)
    expect_length(events, 1L)
    expect_identical(events[[1]]$decision, decision)
    traced <- Filter(
      function(x) x$name == "deputy.permission",
      record$traces[["deputy.run"]]$events
    )
    expect_length(traced, 1L)
    expect_identical(traced[[1]]$attributes$decision, decision)
    expect_identical(
      traced[[1]]$attributes$tool_call_id,
      events[[1]]$tool_call_id
    )
    executed <- Filter(
      function(x) startsWith(x$name, "execute_tool "),
      record$traces
    )
    expect_length(executed, as.integer(decision == "allow"))
  }
})
