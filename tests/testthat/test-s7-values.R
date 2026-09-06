test_that("S7 hook properties remain frozen when initialized with NULL", {
  hook <- HookMatcher("Stop", function(...) NULL)
  expect_s7_class(hook, HookMatcher)
  expect_null(hook@pattern)
  expect_snapshot(error = TRUE, hook@pattern <- "^write")
})

test_that("S7 event records freeze their envelope and payload", {
  event <- AgentEvent("text", text = "original")
  expect_s7_class(event, AgentEvent)
  expect_identical(event@data, list(text = "original"))
  expect_identical(event$text, "original")
  expect_null(event$absent)
  payload <- event@data
  payload$text <- "copy"
  expect_identical(event$text, "original")
  expect_snapshot(error = TRUE, event@data$text <- "replacement")
})

test_that("S7 events validate their type and payload names", {
  expect_snapshot(error = TRUE, AgentEvent(NA_character_))
  expect_snapshot(error = TRUE, AgentEvent(""))
  expect_snapshot(error = TRUE, AgentEvent(c("start", "stop")))
  expect_snapshot(error = TRUE, AgentEvent("text", "unnamed"))
  expect_snapshot(error = TRUE, AgentEvent("text", text = "a", text = "b"))
  expect_snapshot(error = TRUE, AgentEvent("text", timestamp = Sys.time()))
  expect_snapshot(error = TRUE, AgentEvent("text", data = list()))
})

test_that("S7 events compose ellmer content and turns without changing them", {
  content <- ellmer::ContentText("provider content")
  turn <- ellmer::AssistantTurn(list(content))
  condition <- simpleError("provider diagnostic")
  event <- AgentEvent(
    "turn",
    turn = turn,
    content = content,
    condition = condition
  )
  expect_identical(event$turn, turn)
  expect_identical(event$content, content)
  expect_identical(event$condition, condition)
  expect_identical(S7::S7_inherits(event, ellmer::Content), FALSE)
  expect_identical(S7::S7_inherits(event, ellmer::Turn), FALSE)
  output <- capture.output(print(event))
  expect_match(
    paste(output, collapse = "\n"),
    "<ellmer::ContentText>",
    fixed = TRUE
  )
  expect_match(
    paste(output, collapse = "\n"),
    "<ellmer::AssistantTurn>",
    fixed = TRUE
  )
})

test_that("read-only records preserve caller-owned callback and payload state", {
  state <- new.env(parent = emptyenv())
  state$count <- 0L
  hook <- HookMatcher("Stop", function(...) state$count <- state$count + 1L)
  registry <- HookRegistry$new()
  registry$add(hook)
  registry$fire("Stop", reason = "complete", context = list())
  expect_identical(state$count, 1L)
  event <- AgentEvent("custom", state = state)
  state$count <- 2L
  expect_identical(event$state$count, 2L)
})

test_that("serialized S7 values dispatch after loading Deputy in a fresh process", {
  path <- tempfile(fileext = ".rds")
  on.exit(unlink(path), add = TRUE)
  saveRDS(
    list(
      event = AgentEvent("text", text = "restored"),
      hook = HookMatcher("Stop", function(...) NULL),
      result = AgentResult(
        response = "restored result",
        turns = list(ellmer::AssistantTurn(list(ellmer::ContentText(
          "source"
        )))),
        events = list(AgentEvent("text", text = "restored chunk")),
        run_context = list(revision = "v1")
      ),
      policy = Permissions(
        file_write = normalizePath(tempdir(), winslash = "/"),
        tool_denylist = "run_bash",
        can_use_tool = function(...) {
          deputy::PermissionResultDeny(reason = "restored veto")
        }
      )
    ),
    path
  )
  result <- callr::r(
    function(path, package_path) {
      if (file.exists(file.path(package_path, "R", "agent.R"))) {
        pkgload::load_all(package_path, quiet = TRUE)
      } else {
        library(deputy, lib.loc = dirname(package_path))
      }
      values <- readRDS(path)
      list(
        result_class = S7::S7_inherits(values$result, AgentResult),
        policy_class = S7::S7_inherits(values$policy, Permissions),
        turn_class = S7::S7_inherits(values$result$turns[[1L]], ellmer::Turn),
        chunks = result_text_chunks(values$result),
        run_context = values$result$run_context,
        result_output = capture.output(print(values$result)),
        policy_output = capture.output(print(values$policy)),
        callback_reason = permissions_check(
          values$policy,
          "read_file",
          list()
        )$reason,
        gating_reason = permissions_check(
          values$policy,
          "run_bash",
          list()
        )$reason,
        grant = values$policy$file_write,
        result_frozen = tryCatch(
          {
            S7::prop(values$result, "structured_output") <- "changed"
            FALSE
          },
          error = function(error) grepl("read-only", conditionMessage(error))
        ),
        policy_frozen = tryCatch(
          {
            S7::prop(values$policy, "tool_allowlist") <- "read_file"
            FALSE
          },
          error = function(error) grepl("read-only", conditionMessage(error))
        ),
        event_class = S7::S7_inherits(values$event, AgentEvent),
        hook_class = S7::S7_inherits(values$hook, HookMatcher),
        event_output = capture.output(print(values$event)),
        hook_output = capture.output(print(values$hook)),
        matches = hook_matches(values$hook),
        frozen = tryCatch(
          {
            S7::prop(values$hook, "pattern") <- "new"
            FALSE
          },
          error = function(error) grepl("read-only", conditionMessage(error))
        )
      )
    },
    args = list(
      path = path,
      package_path = getNamespaceInfo(asNamespace("deputy"), "path")
    )
  )
  expect_identical(result$result_class, TRUE)
  expect_identical(result$policy_class, TRUE)
  expect_identical(result$turn_class, TRUE)
  expect_identical(result$chunks, "restored chunk")
  expect_identical(result$run_context, list(revision = "v1"))
  expect_match(
    paste(result$result_output, collapse = "\n"),
    "restored result",
    fixed = TRUE
  )
  expect_match(
    paste(result$policy_output, collapse = "\n"),
    "<Permissions>",
    fixed = TRUE
  )
  expect_identical(result$callback_reason, "restored veto")
  expect_match(result$gating_reason, "denylist", fixed = TRUE)
  expect_identical(result$grant, normalizePath(tempdir(), winslash = "/"))
  expect_identical(result$result_frozen, TRUE)
  expect_identical(result$policy_frozen, TRUE)
  expect_identical(result$event_class, TRUE)
  expect_identical(result$hook_class, TRUE)
  expect_match(
    paste(result$event_output, collapse = "\n"),
    "restored",
    fixed = TRUE
  )
  expect_match(
    paste(result$hook_output, collapse = "\n"),
    "<HookMatcher>",
    fixed = TRUE
  )
  expect_identical(result$matches, TRUE)
  expect_identical(result$frozen, TRUE)
})
