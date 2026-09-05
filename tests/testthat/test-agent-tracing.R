# Instrumentation is initialized before importing ellmer in a fresh process;
# no test reaches into upstream tracer caches or callback managers.
record_runtime_trace <- function(url, mode = "tool", capture = FALSE) {
  skip_if_not_installed("otel")
  skip_if_not_installed("otelsdk")
  callr::r(
    function(path, url, mode, capture) {
      Sys.setenv(
        OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT = if (capture) {
          "true"
        } else {
          "false"
        }
      )
      otelsdk::with_otel_record({
        pkgload::load_all(path, quiet = TRUE)
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
          permissions <- if (mode == "deny") {
            Permissions$new(mode = "readonly", tool_denylist = "effect")
          } else {
            permissions_full()
          }
          agent <- Agent$new(
            chat,
            tools = list(tool),
            permissions = permissions
          )
        }
        result <- suppressWarnings(agent$run_sync("private user prompt"))
        list(
          run_id = result$run_id,
          session_id = result$session_id,
          usage = unclass(result$usage),
          events = result$events
        )
      })
    },
    args = list(
      path = pkgload::pkg_path(),
      url = url,
      mode = mode,
      capture = capture
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
  expect_identical(record$value$usage$requests, 2L)
  serialized <- paste(utils::capture.output(dput(spans)), collapse = "\n")
  expect_false(grepl("private user prompt|private tool result", serialized))
  expect_true(
    "deputy.permission" %in% vapply(run$events, `[[`, character(1), "name")
  )
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
