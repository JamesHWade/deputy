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

test_that("partial turns and nested results keep only public inspectable content", {
  request <- ellmer::ContentToolRequest(
    id = "tool",
    name = "fixture",
    arguments = list(),
    extra = list(private = "secret")
  )
  result <- ellmer::ContentToolResult(
    list(
      ellmer::ContentThinking("hidden thought"),
      ellmer::ContentText("retained evidence"),
      ellmer::ContentToolResult(
        list(
          ellmer::ContentThinking("nested thought"),
          ellmer::ContentText("nested evidence")
        ),
        request = request
      )
    ),
    request = request
  )
  partial <- ellmer::AssistantPartialTurn(
    list(ellmer::ContentText("partial answer")),
    reason = "interrupted"
  )
  record <- inspection_record_turn(ellmer::UserTurn(list(result)))
  text <- jsonlite::toJSON(record, auto_unbox = TRUE)
  expect_false(grepl(
    "secret|hidden thought|nested thought|ContentThinking",
    text
  ))
  replay <- inspection_replay(record)
  expect_identical(replay@contents[[1L]]@request@extra, list())
  expect_identical(replay@contents[[1L]]@value[[1L]]@text, "retained evidence")
  restored <- inspection_replay(inspection_record_turn(partial))
  expect_s7_class(restored, ellmer::AssistantPartialTurn)
  expect_identical(restored@reason, "interrupted")
  expect_identical(restored@text, "partial answer")
})

test_that("released structured and uploaded content replay through public records", {
  server <- local_runtime_server(list(runtime_reply(
    '{"status":"ok"}',
    stream = FALSE
  )))
  chat <- runtime_chat(server)
  chat$chat_structured(
    "extract",
    type = ellmer::type_object(status = ellmer::type_string())
  )
  turn <- tail(chat$get_turns(), 1L)[[1L]]
  replay <- inspection_replay(inspection_record_turn(turn))
  expect_equal(ellmer::contents_record(replay), inspection_record_turn(turn))
  json <- ellmer::contents_replay(list(
    version = 1,
    class = "ellmer::ContentJson",
    props = list(data = list(status = "ok"), string = NULL)
  ))
  request <- ellmer::ContentToolRequest(
    id = "json",
    name = "fixture",
    arguments = list()
  )
  result <- ellmer::ContentToolResult(list(json), request = request)
  expect_no_error(inspection_replay(inspection_record_turn(ellmer::UserTurn(list(
    result
  )))))
  upload <- ellmer::ContentUploaded(
    uri = "fixture:document",
    mime_type = "text/plain",
    provider = "fixture",
    extra = list(private = "omitted")
  )
  restored <- inspection_replay(inspection_record_turn(ellmer::UserTurn(list(
    upload
  ))))
  expect_identical(restored@contents[[1L]]@uri, "fixture:document")
  expect_identical(restored@contents[[1L]]@extra, list())
})

test_that("artifact reads use host storage after reference disclosure", {
  lead <- inspection_lead(
    context_policy = ContextPolicy(offload_dir = withr::local_tempdir())
  )
  resolve_async_value(lead$get_tools()$delegate_to_agent(
    "a",
    strrep("x", 9000)
  ))
  id <- lead$list_subagents()$delegation_id
  lead$.__enclos_env__$private$.delegation_disclosure <- inspection_policy(
    redact = function(view, requester) {
      if (!is.null(view$outcome)) {
        view$outcome$references <- lapply(
          view$outcome$references,
          function(ref) {
            ref$storage_session_id <- NULL
            ref
          }
        )
      }
      view
    }
  )
  reference <- lead$inspect_subagents("owner", id)[[1L]]$outcome$references[[
    1L
  ]]
  expect_null(reference$storage_session_id)
  chunk <- lead$read_subagent_result("owner", id, reference$reference)
  expect_match(chunk$result, "xxxx", fixed = TRUE)
  expect_error(
    lead$read_subagent_result("other", id, reference$reference),
    class = "deputy_delegation_disclosure"
  )
})

test_that("payload record-shaped objects stay data and classed results project portably", {
  invoice <- list(version = 1, class = "invoice", props = list(total = 42))
  lookalike <- list(
    version = 1,
    class = "ellmer::ContentText",
    props = list(text = "literal data")
  )
  request <- ellmer::ContentToolRequest(
    id = "data",
    name = "fixture",
    arguments = invoice
  )
  for (value in list(invoice, lookalike)) {
    turn <- ellmer::UserTurn(list(ellmer::ContentToolResult(
      value,
      request = request
    )))
    restored <- inspection_replay(inspection_record_turn(turn))
    expect_identical(restored@contents[[1L]]@value, value)
    expect_identical(restored@contents[[1L]]@request@arguments, invoice)
  }
  json <- ellmer::contents_replay(list(
    version = 1,
    class = "ellmer::ContentJson",
    props = list(data = list(), string = NULL)
  ))
  json@data <- invoice
  restored <- inspection_replay(inspection_record_turn(ellmer::AssistantTurn(list(
    json
  ))))
  expect_identical(restored@contents[[1L]]@data, invoice)
  frame <- data.frame(value = c(1, 2), label = factor(c("a", "b")))
  restored <- inspection_replay(inspection_record_turn(ellmer::UserTurn(list(ellmer::ContentToolResult(
    frame,
    request = request
  )))))
  expect_type(restored@contents[[1L]]@value, "character")
  expect_equal(
    jsonlite::fromJSON(restored@contents[[1L]]@value),
    transform(frame, label = as.character(label))
  )
  source <- ellmer::WebSource(url = "https://example.com", title = "Evidence")
  citation <- ellmer::ContentCitation(source = source)
  restored <- inspection_replay(inspection_record_turn(ellmer::AssistantTurn(list(
    citation
  ))))
  expect_identical(restored@contents[[1L]]@source@url, source@url)
})


test_that("mixed tool payloads retain typed content and literal record-shaped data", {
  lookalike <- list(
    version = 1,
    class = "ellmer::ContentText",
    props = list(text = "ordinary metadata")
  )
  value <- list(
    image = ellmer::ContentImageRemote(
      url = "https://example.com/evidence.png"
    ),
    caption = "Evidence",
    metadata = lookalike,
    nested = list(NULL, ellmer::ContentText("typed note"), lookalike)
  )
  result <- ellmer::ContentToolResult(value)
  restored <- inspection_replay(inspection_record_turn(ellmer::UserTurn(list(
    result
  ))))
  actual <- restored@contents[[1L]]@value
  expect_s7_class(actual$image, ellmer::ContentImageRemote)
  expect_identical(actual$image@url, value$image@url)
  expect_identical(actual$caption, "Evidence")
  expect_identical(actual$metadata, lookalike)
  expect_identical(actual$nested[[1L]], NULL)
  expect_identical(actual$nested[[2L]]@text, "typed note")
  expect_identical(actual$nested[[3L]], lookalike)
})


test_that("history redaction has the final say on artifact availability", {
  lead <- inspection_lead()
  lead$parallel_delegate(c(a = "one"))
  history <- lead$export_subagents("owner")
  history$children[[1L]]$outcome$references <- list(list(
    reference = "fixture",
    availability = "available"
  ))
  policy <- inspection_policy(redact = function(view, requester) {
    expect_identical(view$outcome$references[[1L]]$availability, "unresolved")
    view$outcome$references[[1L]]$availability <- NULL
    view
  })
  restored <- delegation_history(history, "owner", policy, history$scope)
  expect_null(restored[[1L]]$outcome$references[[1L]]$availability)
  expect_identical(restored[[1L]]$outcome$references[[1L]]$reference, "fixture")
})


test_that("UTF-8 answer truncation claims artifacts independently of compaction", {
  lead <- inspection_lead(
    context_policy = ContextPolicy(offload_dir = withr::local_tempdir())
  )
  lead$parallel_delegate(c(a = "one"))
  id <- lead$list_subagents()$delegation_id
  text <- iconv(strrep("é", 4100), from = "UTF-8", to = "latin1")
  expect_lt(nchar(text, type = "bytes"), 8192)
  expect_gt(nchar(enc2utf8(text), type = "bytes"), 8192)
  private <- lead$.__enclos_env__$private
  transaction <- private$begin_compaction_artifacts()
  artifact <- offload_tool_result(
    enc2utf8(text),
    "delegate_to_agent",
    lead$context_policy,
    lead$session_id(),
    lead$agent_id,
    force = TRUE
  )
  private$track_compaction_artifact(artifact)
  expect_length(private$.compaction_catalog_registry$provisional, 1L)
  private$subagent_runs[[id]]$result <- text
  lead_prepare_outcome(lead, id)
  expect_true(private$subagent_runs[[id]]$answer_truncated)
  expect_lte(nchar(private$subagent_runs[[id]]$answer, type = "bytes"), 8192)
  expect_length(private$.compaction_catalog_registry$provisional, 0L)
  private$finish_compaction_artifacts(transaction)
  expect_identical(lead$resolve_tool_result(artifact$uri), enc2utf8(text))
})

test_that("unsupported S7 payloads do not hide sibling histories", {
  lead <- inspection_lead()
  lead$parallel_delegate(c(a = "one", b = "two"))
  id <- lead$list_subagents()$delegation_id[[1L]]
  Payload <- S7::new_class(
    "PrivateFixturePayload",
    properties = list(secret = S7::class_character)
  )
  private <- lead$.__enclos_env__$private
  private$subagent_runs[[
    id
  ]]$turns <- list(ellmer::UserTurn(list(ellmer::ContentToolResult(Payload(
    secret = "private fixture"
  )))))
  views <- lead$inspect_subagents("owner", transcript = TRUE)
  expect_length(views, 2L)
  expect_match(
    views[[1L]]$turns[[1L]]@contents[[1L]]@value,
    "Unsupported tool payload omitted",
    fixed = TRUE
  )
  expect_false(grepl(
    "private fixture",
    jsonlite::toJSON(lead$export_subagents("owner"), auto_unbox = TRUE),
    fixed = TRUE
  ))
  expect_length(views[[2L]]$turns, 2L)
})
