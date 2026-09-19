descendant_observation_disclosure <- function(authorize = NULL) {
  DelegationDisclosure(
    authorize = authorize %||%
      function(requester, scope) {
        identical(requester, "owner")
      }
  )
}

descendant_observation_lead <- function(
  delegation_observation = DelegationObservation(),
  delegation_disclosure = descendant_observation_disclosure()
) {
  parallel_test_lead(
    new.env(parent = emptyenv()),
    delegation_observation = delegation_observation,
    delegation_disclosure = delegation_disclosure
  )
}

descendant_observation_record <- function(
  lead,
  id,
  agent_name,
  parent_delegation_id = NULL,
  depth = NULL,
  root_agent_id = NULL
) {
  now <- Sys.time()
  list(
    agent_name = agent_name,
    agent_id = paste0("agent-", agent_name),
    parent_agent_id = lead$agent_id,
    task = paste("task", agent_name),
    session_id = paste0("session-", agent_name),
    run_id = paste0("run-", agent_name),
    parent_run_id = "run-root",
    parent_delegation_id = parent_delegation_id,
    depth = depth,
    root_agent_id = root_agent_id,
    delegation_id = id,
    tool_call_id = paste0("tool-", agent_name),
    run_context = list(),
    admitted_at = now,
    started_at = now,
    completed_at = now,
    status = "completed",
    stop_reason = "complete",
    error = NULL,
    hook_error = NULL,
    cleanup_error = NULL,
    observation_error = NULL,
    result = paste("answer", agent_name),
    answer = paste("answer", agent_name),
    answer_truncated = FALSE,
    references = list(),
    artifacts = list(),
    usage = AgentUsage(),
    agent_result = NULL,
    turns = list(),
    manifest = NULL,
    working_context = NULL,
    artifact_routing = NULL,
    conversation_handle = NULL,
    previous_delegation_id = NULL
  )
}

descendant_observation_insert <- function(lead, records) {
  names(records) <- vapply(records, `[[`, character(1), "delegation_id")
  lead$.__enclos_env__$private$subagent_runs <- records
  invisible(lead)
}

test_that("root observation and inspection retain descendant ancestry", {
  lead <- descendant_observation_lead()
  root_id <- lead$agent_id
  descendant_observation_insert(
    lead,
    list(
      parent = descendant_observation_record(
        lead,
        "delegation-parent",
        "analyst",
        depth = 1L,
        root_agent_id = root_id
      ),
      grandchild = descendant_observation_record(
        lead,
        "delegation-grandchild",
        "reviewer",
        parent_delegation_id = "delegation-parent",
        depth = 2L,
        root_agent_id = root_id
      )
    )
  )

  buffer <- lead$.__enclos_env__$private$.delegation_buffer
  reader <- lead$observe_subagents(
    "owner",
    after = list(stream_id = buffer$stream_id, sequence = 0)
  )
  lead_observe_event(
    lead,
    "delegation-parent",
    AgentEvent("text", text = "parent")
  )
  lead_observe_event(
    lead,
    "delegation-grandchild",
    AgentEvent("text", text = "grandchild")
  )

  update <- reader$poll()
  expect_identical(
    vapply(update$events, `[[`, numeric(1), "sequence"),
    c(1, 2)
  )
  expect_identical(
    vapply(update$events, `[[`, character(1), "delegation_id"),
    c("delegation-parent", "delegation-grandchild")
  )
  expect_null(update$events[[1]]$parent_delegation_id)
  expect_identical(update$events[[2]]$parent_delegation_id, "delegation-parent")
  expect_identical(update$events[[2]]$depth, 2L)
  expect_identical(update$events[[2]]$root_agent_id, root_id)

  views <- lead$inspect_subagents("owner")
  expect_identical(
    vapply(
      views,
      function(view) view$outcome$runtime$delegation_id,
      character(1)
    ),
    c("delegation-parent", "delegation-grandchild")
  )
  expect_null(views[[1]]$outcome$runtime$parent_delegation_id)
  expect_identical(
    views[[2]]$outcome$runtime$parent_delegation_id,
    "delegation-parent"
  )
  expect_identical(views[[2]]$outcome$runtime$depth, 2L)
  expect_identical(views[[2]]$outcome$runtime$root_agent_id, root_id)

  selected <- lead$inspect_subagents("owner", "delegation-grandchild")
  expect_length(selected, 1L)
  expect_identical(
    subagent_chat_lineage(selected[[1]]$outcome$runtime),
    paste(
      "Depth 2",
      "Parent delegation delegation-parent",
      paste0("Root ", root_id),
      sep = " \u00b7 "
    )
  )
  expect_identical(
    subagent_chat_lineage(selected[[1]]$outcome$runtime, compact = TRUE),
    "Depth 2"
  )
})

test_that("root subscriptions report ordered gaps and recover with a snapshot", {
  requester <- new.env(parent = emptyenv())
  requester$allowed <- TRUE
  disclosure <- descendant_observation_disclosure(function(requester, scope) {
    isTRUE(requester$allowed)
  })
  lead <- descendant_observation_lead(
    DelegationObservation(
      max_events = 2L,
      max_bytes = 4096,
      max_event_bytes = 2048
    ),
    disclosure
  )
  root_id <- lead$agent_id
  descendant_observation_insert(
    lead,
    lapply(
      seq_len(3L),
      function(index) {
        id <- paste0("delegation-", index)
        descendant_observation_record(
          lead,
          id,
          paste0("worker-", index),
          depth = 1L,
          root_agent_id = root_id
        )
      }
    ) |>
      stats::setNames(paste0("delegation-", seq_len(3L)))
  )

  buffer <- lead$.__enclos_env__$private$.delegation_buffer
  reader <- lead$observe_subagents(
    requester,
    after = list(stream_id = buffer$stream_id, sequence = 0)
  )
  for (index in seq_len(3L)) {
    lead_observe_event(
      lead,
      paste0("delegation-", index),
      AgentEvent("text", text = paste0("event-", index))
    )
  }

  requester$allowed <- FALSE
  denied <- tryCatch(reader$poll(), error = identity)
  expect_s3_class(denied, "deputy_delegation_disclosure")
  requester$allowed <- TRUE

  update <- reader$poll()
  expect_identical(update$gaps, list(list(from = 1, to = 1)))
  expect_identical(
    vapply(update$events, `[[`, numeric(1), "sequence"),
    c(2, 3)
  )
  snapshot <- reader$snapshot()
  expect_length(snapshot$children, 3L)
  expect_identical(snapshot$cursor$sequence, 3)
  expect_identical(
    snapshot$children[[3]]$outcome$runtime$root_agent_id,
    root_id
  )
})

test_that("legacy records and saved views keep missing ancestry optional", {
  lead <- descendant_observation_lead()
  descendant_observation_insert(
    lead,
    list(
      legacy = descendant_observation_record(
        lead,
        "delegation-legacy",
        "legacy"
      )
    )
  )

  buffer <- lead$.__enclos_env__$private$.delegation_buffer
  reader <- lead$observe_subagents(
    "owner",
    after = list(stream_id = buffer$stream_id, sequence = 0)
  )
  lead_observe_event(
    lead,
    "delegation-legacy",
    AgentEvent("text", text = "legacy")
  )
  event <- reader$poll()$events[[1L]]
  expect_null(event$parent_delegation_id)
  expect_null(event$depth)
  expect_null(event$root_agent_id)

  view <- lead$inspect_subagents("owner")[[1]]
  expect_null(view$outcome$runtime$parent_delegation_id)
  expect_null(view$outcome$runtime$depth)
  expect_null(view$outcome$runtime$root_agent_id)

  saved <- lead$export_subagents("owner")
  saved$children[[1]]$outcome$runtime[c(
    "parent_delegation_id",
    "depth",
    "root_agent_id"
  )] <- NULL
  restored <- delegation_history(
    saved,
    "owner",
    descendant_observation_disclosure(),
    saved$scope
  )
  expect_null(restored[[1]]$outcome$runtime$parent_delegation_id)
  expect_null(restored[[1]]$outcome$runtime$depth)
  expect_null(restored[[1]]$outcome$runtime$root_agent_id)
})
