observation_disclosure <- function(redact = function(view, requester) view) {
  DelegationDisclosure(
    authorize = function(requester, scope) identical(requester, "owner"),
    redact = redact
  )
}

observation_lead <- function(state = new.env(parent = emptyenv()), ...) {
  parallel_test_lead(
    state,
    delegation_disclosure = observation_disclosure(),
    ...
  )
}

test_that("independent cursors observe one concurrent execution in stable order", {
  state <- new.env(parent = emptyenv())
  lead <- observation_lead(state)
  state$hold_a_until_b <- TRUE
  first <- lead$observe_subagents("owner")
  second <- lead$observe_subagents("owner")
  initial <- first$snapshot()
  expect_length(initial$children, 0L)
  expect_identical(initial$cursor$sequence, 0)
  lead$parallel_delegate(c(a = "one", b = "two"))
  a <- first$poll()
  b <- second$poll()
  expect_identical(a, b)
  expect_length(a$gaps, 0L)
  sequences <- vapply(a$events, function(x) x$sequence, numeric(1))
  expect_identical(sequences, as.numeric(seq_along(sequences)))
  expect_identical(state$completed, c("b", "a"))
  expect_length(Filter(function(x) x$type == "settled", a$events), 2L)
  expect_length(first$poll()$events, 0L)
  expect_length(state$started, 2L)
  recovered <- lead$observe_subagents("owner", after = a$cursor)
  expect_length(recovered$poll()$events, 0L)
  state$hold_a_until_b <- FALSE
  lead$parallel_delegate(c(a = "again"))
  next_events <- recovered$poll()$events
  expect_identical(
    all(vapply(
      next_events,
      function(x) x$sequence > max(sequences),
      logical(1)
    )),
    TRUE
  )
  ids <- unique(vapply(
    c(a$events, next_events),
    function(x) x$delegation_id,
    character(1)
  ))
  expect_length(ids, 3L)
  expect_length(unique(lead$list_subagents()$session_id), 3L)
})

test_that("overflow is bounded and reports gaps without stalling children", {
  lead <- observation_lead(
    delegation_observation = DelegationObservation(
      max_events = 3L,
      max_bytes = 4096,
      max_event_bytes = 2048
    )
  )
  observer <- lead$observe_subagents("owner")
  lead$parallel_delegate(c(a = "one", b = "two"))
  buffer <- lead$.__enclos_env__$private$.delegation_buffer
  expect_lte(length(buffer$events), 3L)
  expect_lte(sum(buffer$sizes), 4096)
  result <- observer$poll()
  expect_length(result$gaps, 1L)
  expect_identical(result$gaps[[1L]]$from, 1)
  expect_identical(result$events[[1L]]$sequence, result$gaps[[1L]]$to + 1)
  snapshot <- observer$snapshot(transcript = TRUE)
  expect_length(snapshot$children, 2L)
  expect_length(snapshot$children[[1L]]$transcript, 2L)
  expect_length(observer$poll()$events, 0L)
  id <- lead$list_subagents()$delegation_id[[1L]]
  lead_observe_event(lead, id, AgentEvent("text", text = strrep("x", 10000)))
  oversized <- observer$poll()$events[[1L]]
  expect_identical(oversized$data$content_omitted, "oversized")
  expect_lte(sum(buffer$sizes), 4096)
})

test_that("closing observers never cancels work and redaction errors are read-local", {
  state <- new.env(parent = emptyenv())
  broken <- TRUE
  lead <- parallel_test_lead(
    state,
    delegation_disclosure = observation_disclosure(
      redact = function(view, requester) {
        if (identical(view$kind, "event") && broken) {
          cli::cli_abort("observer failed")
        }
        view
      }
    )
  )
  detached <- lead$observe_subagents("owner")
  reader <- lead$observe_subagents("owner")
  detached$close()
  detached$close()
  lead$parallel_delegate(c(a = "one", b = "two"))
  expect_snapshot(error = TRUE, detached$poll())
  expect_snapshot(error = TRUE, reader$poll())
  expect_identical(lead$list_subagents()$status, c("completed", "completed"))
  broken <- FALSE
  expect_gt(length(reader$poll()$events), 0L)
  expect_length(state$started, 2L)
})

test_that("authorization is rechecked on reads and foreign cursors disclose nothing", {
  requester <- new.env(parent = emptyenv())
  requester$allowed <- TRUE
  lead <- parallel_test_lead(
    new.env(parent = emptyenv()),
    delegation_disclosure = DelegationDisclosure(authorize = function(
      requester,
      scope
    ) {
      isTRUE(requester$allowed)
    })
  )
  reader <- lead$observe_subagents(requester)
  cursor <- reader$snapshot()$cursor
  requester$allowed <- FALSE
  expect_snapshot(error = TRUE, reader$poll())
  expect_snapshot(error = TRUE, reader$snapshot(TRUE))
  requester$allowed <- TRUE
  clone <- lead$clone()
  expect_snapshot(
    error = TRUE,
    clone$observe_subagents(requester, after = cursor)
  )
  expect_identical(reader$poll()$cursor, cursor)
  denied <- observation_lead()
  expect_snapshot(
    error = TRUE,
    denied$observe_subagents("other", "missing", cursor)
  )
})

test_that("public tool observations retain pairing and hide hidden reasoning", {
  server <- local_runtime_server(list(
    runtime_reply(tool = "effect"),
    runtime_reply("done")
  ))
  tool <- ellmer::tool(
    function() "result",
    name = "effect",
    description = "Fixture",
    arguments = list()
  )
  lead <- LeadAgent$new(
    runtime_chat(server),
    permissions = permissions_full(),
    sub_agents = list(agent_definition("a", "A", "worker", tools = list(tool))),
    delegation_disclosure = observation_disclosure()
  )
  reader <- lead$observe_subagents("owner")
  resolve_async_value(lead$get_tools()$delegate_to_agent("a", "task"))
  events <- reader$poll()$events
  starts <- Filter(function(x) x$type == "tool_start", events)
  ends <- Filter(function(x) x$type == "tool_end", events)
  expect_length(starts, 1L)
  expect_length(ends, 1L)
  expect_identical(starts[[1L]]$tool_call_id, ends[[1L]]$tool_call_id)
  expect_lt(starts[[1L]]$sequence, ends[[1L]]$sequence)
  expect_identical(
    starts[[1L]]$conversation_id,
    lead$list_subagents()$session_id
  )
  expect_identical(starts[[1L]]$run_id, lead$list_subagents()$run_id)
  expect_length(Filter(function(x) x$type == "settled", events), 1L)
  before <- reader$poll()$cursor
  id <- lead$list_subagents()$delegation_id
  thinking <- ellmer::ContentThinking("private thought")
  lead_observe_event(lead, id, AgentEvent("content", content = thinking))
  expect_identical(reader$poll()$cursor, before)
})

test_that("targeted cancellation and view selection are separate operations", {
  lead <- observation_lead()
  reader <- lead$observe_subagents("owner")
  lead$add_hook(HookMatcher("SubagentStart", callback = function(context, ...) {
    if (context$child_agent_name == "a") {
      lead$interrupt_subagent(context$delegation_id, "host_cancelled")
    }
    NULL
  }))
  batch <- lead$parallel_delegate(c(a = "cancel", b = "finish"))
  expect_identical(batch$status, c(a = "not_started", b = "completed"))
  runs <- lead$list_subagents()
  expect_identical(runs$stop_reason, c("host_cancelled", "complete"))
  events <- reader$poll()
  selected <- lead$observe_subagents(
    "owner",
    runs$delegation_id[[2L]],
    after = list(stream_id = events$cursor$stream_id, sequence = 0)
  )
  expect_identical(
    unique(vapply(
      selected$poll()$events,
      function(x) x$delegation_id,
      character(1)
    )),
    runs$delegation_id[[2L]]
  )
  expect_identical(lead$interrupt_subagent(runs$delegation_id[[2L]]), FALSE)
})

test_that("released ellmer concurrent children use only the runtime stream consumer", {
  server <- local_parallel_server()
  lead <- LeadAgent$new(
    ellmer::chat_openai_compatible(
      base_url = server$url,
      model = "gpt-4o-mini",
      credentials = function() "fixture",
      echo = "none"
    ),
    sub_agents = list(
      agent_definition("a", "A", "A"),
      agent_definition("b", "B", "B")
    ),
    delegation_disclosure = observation_disclosure()
  )
  one <- lead$observe_subagents("owner")
  two <- lead$observe_subagents("owner")
  lead$parallel_delegate(c(a = "one", b = "two"))
  events <- one$poll()
  expect_identical(events, two$poll())
  expect_length(server$requests(), 2L)
  expect_length(Filter(function(x) x$type == "settled", events$events), 2L)
  snapshot <- one$snapshot(TRUE)
  expect_length(snapshot$children[[1L]]$transcript, 2L)
  expect_length(server$requests(), 2L)
})

test_that("observation failures never leak reservations or prevent settlement", {
  lead <- observation_lead()
  local_mocked_bindings(lead_observe_event = function(...) {
    cli::cli_abort("fixture observation error")
  })
  batch <- lead$parallel_delegate(c(a = "one", b = "two"))
  expect_identical(batch$status, c(a = "completed", b = "completed"))
  expect_identical(
    lead$list_subagents()$observation_error,
    rep("fixture observation error", 2L)
  )
  expect_length(lead$.__enclos_env__$private$delegation_usage_reservations, 0L)
  expect_length(lead$.__enclos_env__$private$delegation_bindings, 0L)
})

test_that("lineage fixtures retain parent identities without enabling recursive work", {
  lead <- observation_lead()
  lead$parallel_delegate(c(a = "one"))
  reader <- lead$observe_subagents("owner")
  id <- lead$list_subagents()$delegation_id
  private <- lead$.__enclos_env__$private
  private$subagent_runs[[id]]$parent_agent_id <- "fixture-intermediate-child"
  private$subagent_runs[[id]]$parent_run_id <- "fixture-intermediate-run"
  private$subagent_runs[[id]]$tool_call_id <- "fixture-parent-tool"
  lead_observe_status(lead, id, "settled")
  event <- reader$poll()$events[[1L]]
  expect_identical(event$parent_agent_id, "fixture-intermediate-child")
  expect_identical(event$parent_run_id, "fixture-intermediate-run")
  expect_identical(event$parent_tool_call_id, "fixture-parent-tool")
})

test_that("failure envelopes retain bounded text without condition internals", {
  error <- simpleError(strrep("failure ", 300))
  error$private <- new.env(parent = emptyenv())
  for (type in c("request_error", "run_error", "fallback")) {
    payload <- observation_payload(AgentEvent(
      type,
      condition = error,
      request = new.env()
    ))
    expect_match(payload$message, "failure")
    expect_lte(nchar(payload$message, type = "bytes"), 1024L)
    expect_null(payload$condition)
    expect_null(payload$request)
    expect_no_error(inspection_portable(payload))
  }
})

test_that("queued cancellation does not publish running or invoke start hooks", {
  state <- new.env(parent = emptyenv())
  lead <- observation_lead(state)
  reader <- lead$observe_subagents("owner")
  hooks <- character()
  lead$add_hook(HookMatcher("SubagentStart", callback = function(context, ...) {
    hooks <<- c(hooks, context$child_agent_name)
    if (context$child_agent_name == "a") {
      queued <- lead$list_subagents()
      lead$interrupt_subagent(
        queued$delegation_id[queued$agent_name == "b"],
        "cancelled_while_queued"
      )
    }
    NULL
  }))
  batch <- lead$parallel_delegate(c(a = "run", b = "cancel"), max_active = 1L)
  expect_identical(batch$status, c(a = "completed", b = "not_started"))
  expect_identical(hooks, "a")
  expect_identical(state$started, "a")
  runs <- lead$list_subagents()
  b <- runs[runs$agent_name == "b", ]
  expect_identical(b$stop_reason, "cancelled_while_queued")
  expect_true(is.na(b$started_at))
  events <- Filter(
    function(x) identical(x$delegation_id, b$delegation_id),
    reader$poll()$events
  )
  expect_false(any(vapply(events, function(x) x$type == "running", logical(1))))
  expect_length(Filter(function(x) x$type == "settled", events), 1L)
  expect_length(lead$.__enclos_env__$private$delegation_usage_reservations, 0L)
  expect_length(lead$.__enclos_env__$private$delegation_bindings, 0L)
})

test_that("oversized content is omitted before public-record materialization", {
  result <- ellmer::ContentToolResult(strrep("large payload", 100000))
  event <- AgentEvent("content", content = result)
  local_mocked_bindings(inspection_record_turn = function(...) {
    stop("must not materialize")
  })
  payload <- observation_payload(event, max_bytes = 2048L)
  expect_identical(payload$content_omitted, "oversized")
  expect_identical(payload$recover, "snapshot")
  expect_false(observation_payload_fits(rep(list(1), 10000), 2048L))
  expect_true(observation_payload_fits(list(text = "small"), 2048L))
})

test_that("queued cancellation survives a batch request-limit exit", {
  lead <- observation_lead()
  reader <- lead$observe_subagents("owner")
  lead$add_hook(HookMatcher("SubagentStart", callback = function(context, ...) {
    runs <- lead$list_subagents()
    lead$interrupt_subagent(
      runs$delegation_id[runs$agent_name == "b"],
      "specific_cancel"
    )
    NULL
  }))
  lead$parallel_delegate(
    c(a = "run", b = "cancel"),
    max_active = 1L,
    usage_limits = UsageLimits(max_requests = 1L)
  )
  b <- lead$list_subagents()
  b <- b[b$agent_name == "b", ]
  expect_identical(b$stop_reason, "specific_cancel")
  settled <- Filter(
    function(x) {
      x$type == "settled" && identical(x$delegation_id, b$delegation_id)
    },
    reader$poll()$events
  )
  expect_length(settled, 1L)
  expect_identical(settled[[1L]]$data$stop_reason, "specific_cancel")
})


test_that("factor labels are bounded before text projection", {
  local_mocked_bindings(inspection_record_turn = function(...) {
    stop("must not materialize")
  })
  for (value in list(
    factor(strrep("x", 100000)),
    factor(rep(strrep("x", 100), 100))
  )) {
    event <- AgentEvent("content", content = ellmer::ContentToolResult(value))
    expect_identical(
      observation_payload(event, max_bytes = 2048L)$content_omitted,
      "oversized"
    )
  }
  expect_true(observation_payload_fits(factor(c("a", "b", NA)), 2048L))
})


test_that("fallback observations retain selected fallback and incurred usage", {
  usage <- AgentUsage(input_tokens = 10, output_tokens = 5)
  condition <- simpleError("primary failed")
  condition$private <- globalenv()
  payload <- observation_payload(AgentEvent(
    "fallback",
    fallback_index = 2L,
    usage = usage,
    condition = condition,
    provider = "fixture",
    model = "fallback",
    request = globalenv()
  ))
  expect_identical(payload$fallback_index, 2L)
  expect_equal(payload$usage$total_tokens, 15)
  expect_identical(payload$message, "primary failed")
  expect_null(payload$condition)
  expect_null(payload$request)
})


test_that("envelope metadata is bounded before serialization", {
  lead <- observation_lead()
  lead$parallel_delegate(c(a = "one"))
  id <- lead$list_subagents()$delegation_id[[1L]]
  private <- lead$.__enclos_env__$private
  private$subagent_runs[[id]]$agent_name <- strrep("x", 1000000)
  reader <- lead$observe_subagents("owner")
  expect_no_error(lead_observe_event(
    lead,
    id,
    AgentEvent("text", text = "small")
  ))
  expect_length(reader$poll()$gaps, 1L)
})

test_that("small data frame observations retain a portable projection", {
  frame <- data.frame(value = 1:2, group = factor(c("a", "b")))
  payload <- observation_payload(AgentEvent(
    "tool_end",
    value = frame,
    tool_name = "fixture"
  ))
  expect_identical(payload$tool_name, "fixture")
  expect_equal(
    jsonlite::fromJSON(payload$value),
    transform(frame, group = as.character(group))
  )
  names(frame) <- rep(strrep("x", 1000), 2)
  expect_false(observation_payload_fits(frame[rep(1L, 100), ], 2048))
})
