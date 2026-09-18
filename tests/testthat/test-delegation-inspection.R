inspection_policy <- function(redact = function(view, requester) view, ...) {
  DelegationDisclosure(
    authorize = function(requester, scope) identical(requester, "owner"),
    redact = redact,
    ...
  )
}

inspection_lead <- function(...) {
  parallel_test_lead(
    new.env(parent = emptyenv()),
    delegation_disclosure = inspection_policy(),
    ...
  )
}

test_that("compact outcomes separate runtime facts from child answers", {
  lead <- inspection_lead(usage_limits = UsageLimits(max_total_tokens = 1))
  response <- resolve_async_value(lead$get_tools()$delegate_to_agent(
    "a",
    "task"
  ))
  outcome <- jsonlite::fromJSON(response, simplifyVector = FALSE)
  expect_identical(outcome$answer, "a task")
  expect_identical(outcome$runtime$status, "stopped")
  expect_identical(outcome$runtime$stop_reason, "total_token_limit")
  expect_identical(outcome$runtime$task_success, "not_assessed")
  expect_null(outcome$claims$missing_evidence)
  expect_null(outcome$claims$unresolved_work)
  expect_null(outcome$transcript)
  before <- lead$get_context_turns()
  view <- lead$inspect_subagents("owner", transcript = TRUE)[[1L]]
  expect_identical(
    view$outcome$runtime$delegation_id,
    lead$list_subagents()$delegation_id
  )
  expect_length(view$turns, 2L)
  expect_s7_class(view$turns[[1L]], ellmer::UserTurn)
  expect_identical(view$retention$execution, "read_only")
  expect_equal(view$usage$total_tokens, 15)
  expect_equal(view$usage, view$cumulative_usage)
  view$turns[[1L]]@contents <- list(ellmer::ContentText("changed"))
  expect_equal(lead$get_context_turns(), before)
  expect_match(format(lead$get_subagent_messages()[[1L]][[1L]]), "task")
})

test_that("authorization precedes lookup and redaction precedes content delivery", {
  calls <- 0L
  lead <- parallel_test_lead(
    new.env(parent = emptyenv()),
    delegation_disclosure = DelegationDisclosure(
      authorize = function(requester, scope) identical(requester, "owner"),
      redact = function(view, requester) {
        calls <<- calls + 1L
        view$task <- "redacted"
        view$manifest <- NULL
        view$transcript <- NULL
        view$outcome$answer <- "redacted"
        view
      }
    )
  )
  resolve_async_value(lead$get_tools()$delegate_to_agent("a", "private"))
  for (id in list(NULL, "missing", lead$list_subagents()$delegation_id)) {
    failure <- tryCatch(
      lead$inspect_subagents("other", id, TRUE),
      error = identity
    )
    expect_s3_class(failure, "deputy_delegation_disclosure")
  }
  expect_identical(calls, 0L)
  view <- lead$inspect_subagents("owner", transcript = TRUE)[[1L]]
  expect_identical(view$task, "redacted")
  expect_length(view$turns, 0L)
  expect_null(view$manifest)
  expect_identical(lead$inspect_subagents("owner", "missing"), list())
  expect_identical(calls, 1L)
  denied <- parallel_test_lead(new.env(parent = emptyenv()))
  expect_snapshot(error = TRUE, denied$inspect_subagents("owner"))
})

test_that("batch outcomes retain failures and repeated specialist identities", {
  lead <- inspection_lead()
  first <- lead$parallel_delegate(c(a = "one", b = "two"))
  second <- lead$parallel_delegate(c(a = "again"))
  expect_s7_class(first$outcomes$a, DelegationOutcome)
  expect_snapshot(error = TRUE, first$outcomes$a@answer <- "altered")
  ids <- vapply(
    lead$inspect_subagents("owner"),
    function(x) x$outcome$runtime$conversation_id,
    character(1)
  )
  expect_length(unique(ids), 3L)
  expect_identical(first$outcomes$a$answer, "a one")
  expect_identical(second$outcomes$a$answer, "a again")
})

test_that("large UTF-8 answers are bounded and artifacts remain scoped", {
  lead <- inspection_lead(
    context_policy = ContextPolicy(offload_dir = withr::local_tempdir())
  )
  resolve_async_value(lead$get_tools()$delegate_to_agent(
    "a",
    strrep("é", 6000)
  ))
  view <- lead$inspect_subagents("owner")[[1L]]
  expect_lte(nchar(view$outcome$answer, type = "bytes"), 8192L)
  expect_identical(view$outcome$runtime$answer_truncated, TRUE)
  ref <- view$outcome$references[[1L]]
  expect_identical(ref$availability, "available")
  expect_identical(ref$verification, "not_assessed")
  expect_identical(ref$approval, "not_granted")
  expect_identical(ref$delegation_id, view$outcome$runtime$delegation_id)
  chunk <- lead$read_subagent_result("owner", ref$delegation_id, ref$reference)
  expect_type(chunk$result, "character")
  expect_snapshot(
    error = TRUE,
    lead$read_subagent_result("other", ref$delegation_id, ref$reference)
  )
  unrelated <- inspection_lead()
  expect_snapshot(
    error = TRUE,
    unrelated$read_subagent_result("owner", ref$delegation_id, ref$reference)
  )
  directory <- tool_result_offload_dir(lead$context_policy, lead$session_id())
  unlink(directory, recursive = TRUE)
  expect_identical(
    lead$inspect_subagents("owner")[[1L]]$outcome$references[[1L]]$availability,
    "missing"
  )
})

test_that("settled history replays without providers or executable tools", {
  lead <- inspection_lead()
  lead$parallel_delegate(c(a = "one", b = "two"))
  snapshot <- unserialize(serialize(lead$export_subagents("owner"), NULL))
  views <- delegation_history(
    snapshot,
    "owner",
    inspection_policy(),
    snapshot$scope
  )
  expect_length(views, 2L)
  expect_length(views[[1L]]$turns, 2L)
  expect_identical(
    views[[1L]]$outcome$runtime$conversation_id,
    lead$list_subagents()$session_id[[1L]]
  )
  expect_snapshot(
    error = TRUE,
    delegation_history(snapshot, "other", inspection_policy(), snapshot$scope)
  )
  expect_snapshot(
    error = TRUE,
    delegation_history(
      snapshot,
      "owner",
      inspection_policy(),
      list(owner_id = "different")
    )
  )
  snapshot$children[[1L]]$transcript[[1L]]$class <- "base::system"
  expect_snapshot(
    error = TRUE,
    delegation_history(snapshot, "owner", inspection_policy(), snapshot$scope)
  )
})

test_that("public history omits hidden thinking and raw provider payloads", {
  turn <- ellmer::AssistantTurn(list(ellmer::ContentText(
    "<script>alert(1)</script>"
  )))
  turn@json <- list(private = "hidden")
  record <- inspection_record_turn(turn)
  expect_identical(record$props$json, list())
  replay <- inspection_replay(record)
  expect_identical(replay@contents[[1L]]@text, "<script>alert(1)</script>")
  expect_snapshot(
    error = TRUE,
    inspection_portable(list(callback = function() NULL))
  )
})

test_that("failed responders preserve sibling inspection and unknown cost", {
  state <- new.env(parent = emptyenv())
  lead <- parallel_test_lead(state, delegation_disclosure = inspection_policy())
  state$fail <- "b"
  batch <- lead$parallel_delegate(c(a = "one", b = "two"))
  expect_identical(batch$outcomes$b$runtime$status, "failed")
  expect_identical(batch$outcomes$a$runtime$status, "completed")
  views <- lead$inspect_subagents("owner")
  expect_identical(views[[2L]]$outcome$runtime$status, "failed")
  expect_match(views[[2L]]$errors$error, "deterministic responder failure")
  expect_identical(views[[1L]]$outcome$runtime$task_success, "not_assessed")
})

test_that("tool artifacts retain tool and child provenance through public replay", {
  server <- local_runtime_server(list(
    runtime_reply(tool = "effect"),
    runtime_reply("done")
  ))
  called <- 0L
  tool <- ellmer::tool(
    function() {
      called <<- called + 1L
      strrep("data", 3000)
    },
    name = "effect",
    description = "Fixture result",
    arguments = list()
  )
  lead <- LeadAgent$new(
    runtime_chat(server),
    permissions = permissions_full(),
    sub_agents = list(agent_definition("a", "A", "worker", tools = list(tool))),
    context_policy = ContextPolicy(
      max_tool_result_bytes = 1024,
      offload_dir = withr::local_tempdir()
    ),
    delegation_disclosure = inspection_policy()
  )
  resolve_async_value(lead$get_tools()$delegate_to_agent("a", "task"))
  view <- lead$inspect_subagents("owner", transcript = TRUE)[[1L]]
  ref <- view$outcome$references[[1L]]
  expect_identical(ref$source, "tool_result")
  expect_identical(ref$tool_name, "effect")
  expect_identical(ref$agent_id, view$outcome$runtime$agent_id)
  expect_identical(ref$run_id, view$outcome$runtime$run_id)
  expect_identical(ref$availability, "available")
  expect_match(
    lead$read_subagent_result("owner", ref$delegation_id, ref$reference)$result,
    "data"
  )
  history <- lead$export_subagents("owner")
  restored <- delegation_history(
    history,
    "owner",
    inspection_policy(),
    history$scope
  )
  requests <- Filter(
    function(content) inherits(content, "ellmer::ContentToolRequest"),
    unlist(
      lapply(restored[[1L]]$turns, function(turn) turn@contents),
      recursive = FALSE
    )
  )
  expect_length(requests, 1L)
  expect_null(requests[[1L]]@tool)
  expect_identical(called, 1L)
  expect_identical(
    restored[[1L]]$outcome$references[[1L]]$availability,
    "unresolved"
  )
})

test_that("disclosure is bounded and active histories cannot be restored", {
  lead <- inspection_lead()
  lead$parallel_delegate(c(a = "one"))
  history <- lead$export_subagents("owner")
  expect_snapshot(
    error = TRUE,
    delegation_history(
      history,
      "owner",
      inspection_policy(max_bytes = 64),
      history$scope
    )
  )
  history$children[[1L]]$outcome$runtime$status <- "running"
  expect_snapshot(
    error = TRUE,
    delegation_history(history, "owner", inspection_policy(), history$scope)
  )
})

test_that("inspection keeps full history separate after compaction", {
  server <- local_runtime_server(list(
    runtime_reply("answer"),
    runtime_reply("COMPACTED", stream = FALSE)
  ))
  definition <- agent_definition("a", "A", "role")
  lead <- LeadAgent$new(
    runtime_chat(server),
    sub_agents = list(definition),
    delegation_disclosure = inspection_policy(),
    context_policy = ContextPolicy(offload_dir = withr::local_tempdir())
  )
  private <- lead$.__enclos_env__$private
  correlation <- private$claim_delegation()
  id <- lead_admit_delegation(lead, definition, "task", correlation)
  child <- private$create_sub_agent(definition, correlation)
  withr::defer(release_delegation_binding(lead, id))
  prepared <- resolve_delegation_input(lead, definition, "task")
  manifest <- prepare_delegation_manifest(lead, definition, prepared, child)
  lead_bind_delegation(lead, id, child, manifest)
  result <- child$run_sync(manifest$message)
  child$compact(keep_last = 0L)
  lead_settle_delegation(lead, id, child, result)
  before <- child$get_context_turns()
  view <- lead$inspect_subagents("owner", id, TRUE)[[1L]]
  expect_length(view$turns, 2L)
  expect_equal(child$get_context_turns(), before)
  expect_length(before, 0L)
  expect_identical(view$manifest$message, manifest$message)
  history <- lead$export_subagents("owner", id)
  expect_length(
    delegation_history(history, "owner", inspection_policy(), history$scope)[[
      1L
    ]]$turns,
    2L
  )
})

test_that("explicit claims and omitted references cannot change runtime truth", {
  record <- list(
    delegation_id = "d",
    status = "stopped",
    stop_reason = "turn_limit",
    result = "Everything is approved",
    references = rep(list(list(reference = "ref")), 12L),
    agent_result = AgentResult(
      structured_output = list(
        missing_evidence = "assay not available",
        unresolved_work = "repeat assay"
      )
    )
  )
  outcome <- delegation_outcome(record, compact = TRUE)
  expect_identical(outcome$runtime$status, "stopped")
  expect_identical(outcome$runtime$omitted_references, 4L)
  expect_length(outcome$references, 8L)
  expect_identical(outcome$claims$unresolved_work, "repeat assay")
  expect_identical(outcome$runtime$task_success, "not_assessed")
})


test_that("tool failures replay as portable errors without condition environments", {
  request <- ellmer::ContentToolRequest(
    id = "failed-tool",
    name = "fixture",
    arguments = list()
  )
  result <- ellmer::ContentToolResult(
    value = NULL,
    error = simpleError("fixture failure"),
    request = request
  )
  replay <- inspection_replay(inspection_record_turn(ellmer::UserTurn(list(
    result
  ))))
  expect_identical(replay@contents[[1L]]@error, "fixture failure")
  expect_identical(replay@contents[[1L]]@request@id, "failed-tool")
  expect_null(replay@contents[[1L]]@request@tool)
})

test_that("compact truncation always keeps the retained full-answer locator", {
  references <- c(
    rep(list(list(source = "tool_result", reference = "tool")), 9),
    list(list(source = "delegation_answer", reference = "full-answer"))
  )
  outcome <- delegation_outcome(
    list(answer = "bounded", answer_truncated = TRUE, references = references),
    compact = TRUE
  )
  expect_length(outcome$references, 8L)
  expect_identical(outcome$references[[1L]]$reference, "full-answer")
  expect_identical(outcome$runtime$omitted_references, 2L)
})

test_that("inspection bounds the final replayed disclosure", {
  lead <- inspection_lead()
  lead$parallel_delegate(c(a = strrep("text", 500)))
  raw <- lead_inspect_subagents(lead, "owner", NULL, TRUE)
  limit <- length(serialize(raw, NULL, version = 3)) + 1
  lead$.__enclos_env__$private$.delegation_disclosure <- inspection_policy(
    max_bytes = limit
  )
  expect_no_error(lead_inspect_subagents(lead, "owner", NULL, TRUE))
  expect_error(
    lead$inspect_subagents("owner", transcript = TRUE),
    "exceeds max_bytes"
  )
})

test_that("export settlement cannot be changed or broken by redaction", {
  lead <- inspection_lead()
  lead$parallel_delegate(c(a = "settled"))
  policy <- inspection_policy(redact = function(view, requester) {
    view$outcome <- NULL
    view
  })
  lead$.__enclos_env__$private$.delegation_disclosure <- policy
  saved <- lead$export_subagents("owner")
  expect_true(saved$settled)
  expect_null(saved$children[[1L]]$outcome)
  restored <- delegation_history(saved, "owner", policy, saved$scope)
  expect_null(restored[[1L]]$outcome)
  expect_length(restored[[1L]]$turns, 2L)
  lead$.__enclos_env__$private$.delegation_disclosure <- inspection_policy(
    redact = function(view, requester) {
      view$outcome$runtime$status <- "completed"
      view
    }
  )
  private <- lead$.__enclos_env__$private
  lead_admit_delegation(
    lead,
    agent_definition("a", "A", "role"),
    "queued",
    private$claim_delegation()
  )
  expect_error(lead$export_subagents("owner"), "Only settled")
})

test_that("disclosure sizing counts replayed content without R class metadata", {
  turn <- ellmer::UserTurn(list(ellmer::ContentText(strrep("data", 1000))))
  record <- inspection_record_turn(turn)
  payload <- list(transcript = list(record), turns = list(record))
  bytes <- length(serialize(payload, NULL, version = 3))
  view <- list(transcript = list(record), turns = list(turn))
  expect_no_error(inspection_bound(view, inspection_policy(max_bytes = bytes)))
  expect_error(
    inspection_bound(view, inspection_policy(max_bytes = bytes - 1)),
    "exceeds max_bytes"
  )
})
