# Background tasks over real ellmer producers and a local HTTP fixture. Order
# is fixed by gates on the specialists' tools and read from the server's
# arrival log, never from timing: ellmer blocks the R process while a
# streaming response is held, so a held tool is the only point where the lead
# can be shown to act while a specialist is still working.

note_tool <- function(seen = NULL, setup = NULL, name = "lookup_spec") {
  ellmer::tool(
    function() {
      if (!is.null(seen)) {
        current <- setup()
        seen$states <- current$lead$background_tasks()$state
        seen$arrivals <- current$server$arrivals_by_model()
      }
      "spec: tolerance 0.5"
    },
    name = name,
    description = "The lead's own lookup",
    arguments = list(),
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE
    )
  )
}

start_call <- function(agent, task = paste("work for", agent), id = NULL) {
  tool_call(
    "task_start",
    list(agent = agent, task = task),
    id %||% paste0("start_", agent)
  )
}

on_tool <- function(agent, event, pattern, callback) {
  agent$add_hook(HookMatcher(
    event,
    pattern = pattern,
    callback = function(...) {
      callback()
      NULL
    }
  ))
}

test_that("a lead works beside two specialists, then collects, follows up and cancels", {
  analyst_gate <- background_gate()
  reviewer_gate <- background_gate()
  seen <- new.env()
  setup <- background_setup(
    list(
      lead = list(
        runtime_tool_calls_reply(list(
          start_call("analyst", "Summarize the measurements", "c1"),
          start_call("reviewer", "Review the draft", "c2")
        )),
        runtime_tool_calls_reply(list(tool_call("lookup_spec", id = "c3"))),
        runtime_tool_calls_reply(list(tool_call("task_wait", id = "c4"))),
        function(request, ids) {
          runtime_tool_calls_reply(list(list(
            id = "c5",
            name = "task_follow_up",
            arguments = list(
              task_id = ids$analyst[[1L]],
              task = "Add the interval"
            )
          )))
        },
        function(request, ids) {
          runtime_tool_calls_reply(list(
            list(
              id = "c6",
              name = "task_cancel",
              arguments = list(
                task_id = ids$reviewer[[1L]],
                reason = "not needed"
              )
            ),
            list(
              id = "c7",
              name = "task_wait",
              arguments = list(task_ids = list(ids$analyst[[2L]]))
            )
          ))
        },
        runtime_reply("Synthesis: mean 4.2, interval 3.9 to 4.5.")
      ),
      analyst = list(
        runtime_tool_calls_reply(list(tool_call("load_measurements"))),
        runtime_reply("The mean is 4.2."),
        runtime_tool_calls_reply(list(tool_call("load_measurements"))),
        runtime_reply("The interval is 3.9 to 4.5.")
      ),
      reviewer = list(
        runtime_tool_calls_reply(list(tool_call("read_draft"))),
        runtime_reply("must not be requested")
      )
    ),
    analyst_tools = list(
      gated_tool("load_measurements", analyst_gate, "4.1, 4.2, 4.3")
    ),
    reviewer_tools = list(gated_tool("read_draft", reviewer_gate, "draft")),
    lead_tools = list(note_tool(seen, function() setup))
  )
  lead <- setup$lead
  on_tool(lead, "PostToolUse", "^lookup_spec$", function() {
    seen$gate_calls <- c(analyst_gate$calls, reviewer_gate$calls)
    seen$released <- c(analyst_gate$released, reviewer_gate$released)
  })
  # The analyst's tool returns only once the lead is waiting, and the
  # reviewer's only once the lead has asked it to stop.
  on_tool(lead, "PreToolUse", "^task_wait$", analyst_gate$release)
  on_tool(lead, "PostToolUse", "^task_cancel$", reviewer_gate$release)
  reader <- lead$observe_subagents("host")

  result <- lead$run_sync("Produce the report")

  # The lead's own work ran while both specialists were inside their tools:
  # each had made one request, and the lead had already made its second.
  expect_identical(seen$states, c("running", "running"))
  expect_identical(seen$arrivals, c("lead", "analyst", "reviewer", "lead"))
  expect_identical(seen$gate_calls, c(1L, 1L))
  expect_identical(seen$released, c(FALSE, FALSE))
  arrivals <- setup$server$arrivals_by_model()
  expect_gt(which(arrivals == "analyst")[[2L]], which(arrivals == "lead")[[3L]])
  # The cancelled reviewer never asked its model again.
  expect_identical(sum(arrivals == "reviewer"), 1L)
  expect_identical(sum(arrivals == "analyst"), 4L)

  expect_identical(result$stop_reason, "complete")
  expect_match(result$response, "mean 4.2, interval 3.9 to 4.5")
  # The run's usage is the lead's and every task's.
  expect_identical(result$usage$requests, length(arrivals))
  expect_identical(result$usage$requests, 11L)

  # What the lead's model was told at each step.
  results <- model_tool_results(setup$server)
  started <- lapply(results[c("c1", "c2")], jsonlite::fromJSON)
  expect_identical(started$c1$state, "running")
  expect_identical(started$c2$agent, "reviewer")
  first <- jsonlite::fromJSON(results[["c4"]], simplifyVector = FALSE)
  expect_length(first$tasks, 1L)
  expect_identical(first$tasks[[1L]]$task_id, started$c1$task_id)
  expect_identical(first$tasks[[1L]]$state, "completed")
  expect_match(first$tasks[[1L]]$outcome$answer, "mean is 4.2")
  expect_identical(first$still_running, list(started$c2$task_id))
  followed <- jsonlite::fromJSON(results[["c5"]])
  expect_identical(followed$follows, started$c1$task_id)
  cancelled <- jsonlite::fromJSON(results[["c6"]])
  expect_identical(cancelled$state, "cancelling")
  expect_true(cancelled$cancel_requested)
  second <- jsonlite::fromJSON(results[["c7"]], simplifyVector = FALSE)
  expect_match(second$tasks[[1L]]$outcome$answer, "3.9 to 4.5")

  # Task states and ancestry as the host sees them.
  tasks <- lead$background_tasks()
  expect_identical(tasks$agent, c("analyst", "reviewer", "analyst"))
  expect_identical(tasks$state, c("completed", "cancelled", "completed"))
  expect_identical(tasks$stop_reason, c("complete", "cancelled", "complete"))
  expect_identical(tasks$cancel_note, c(NA, "not needed", NA))
  expect_identical(tasks$collected, c(TRUE, FALSE, TRUE))
  expect_identical(tasks$previous_task_id, c(NA, NA, tasks$task_id[[1L]]))
  expect_identical(tasks$parent_run_id, rep(result$run_id, 3L))
  expect_identical(tasks$tool_call_id, c("c1", "c2", "c5"))
  runs <- lead$list_subagents()
  expect_identical(runs$delegation_id, tasks$delegation_id)
  expect_identical(runs$status, c("completed", "stopped", "completed"))
  expect_identical(runs$parent_agent_id, rep(lead$agent_id, 3L))
  expect_identical(runs$parent_run_id, rep(result$run_id, 3L))
  expect_identical(runs$root_agent_id, rep(lead$agent_id, 3L))
  expect_identical(runs$depth, rep(1L, 3L))

  # The follow-up continued the analyst's conversation: its request carried
  # the first task and answer, and its record links to the first delegation.
  analyst_requests <- Filter(
    function(entry) entry$body$model == "analyst",
    setup$server$requests()
  )
  follow_up_body <- jsonlite::toJSON(analyst_requests[[3L]]$body$messages)
  expect_match(follow_up_body, "Summarize the measurements", fixed = TRUE)
  expect_match(follow_up_body, "The mean is 4.2.", fixed = TRUE)
  expect_match(follow_up_body, "Add the interval", fixed = TRUE)
  expect_length(setup$analyst$get_turns(), 8L)
  views <- lead$inspect_subagents("host", transcript = TRUE)
  expect_identical(
    views[[3L]]$outcome$runtime$previous_delegation_id,
    tasks$delegation_id[[1L]]
  )
  expect_identical(views[[2L]]$outcome$runtime$status, "stopped")
  expect_identical(views[[2L]]$outcome$runtime$stop_reason, "cancelled")
  expect_match(views[[1L]]$outcome$answer, "mean is 4.2")
  expect_match(
    jsonlite::toJSON(views[[2L]]$transcript, auto_unbox = TRUE),
    "read_draft"
  )
  expect_error(lead$inspect_subagents("stranger"))

  # The specialists' actual work reached the host as it happened.
  events <- reader$poll()$events
  expect_length(reader$poll()$gaps, 0L)
  tool_events <- Filter(function(event) event$type == "tool_start", events)
  expect_identical(
    vapply(tool_events, function(event) event$agent_name, character(1)),
    c("analyst", "reviewer", "analyst")
  )
  expect_identical(
    unique(vapply(events, function(event) event$parent_run_id, character(1))),
    result$run_id
  )
  expect_setequal(
    unique(vapply(events, function(event) event$delegation_id, character(1))),
    tasks$delegation_id
  )

  expect_background_idle(setup)
  expect_no_error(lead$release_agent(setup$handles[["reviewer"]]))
})

test_that("the lead cannot spend what its tasks have set aside", {
  gate <- background_gate()
  setup <- background_setup(
    list(
      lead = list(
        runtime_tool_calls_reply(list(start_call("analyst"))),
        runtime_tool_calls_reply(list(tool_call("lookup_spec", id = "n1"))),
        runtime_tool_calls_reply(list(tool_call("lookup_spec", id = "n2"))),
        runtime_reply("must not be requested")
      ),
      analyst = list(
        runtime_tool_calls_reply(list(tool_call("load_measurements"))),
        runtime_reply("must not be requested")
      )
    ),
    analyst_tools = list(gated_tool("load_measurements", gate, "data")),
    lead_tools = list(note_tool()),
    lead_limits = UsageLimits(max_requests = 6),
    task_limits = UsageLimits(max_requests = 3)
  )
  lead <- setup$lead
  release_when(gate, function() {
    identical(lead$background_tasks()$state, "cancelling")
  })
  result <- suppressWarnings(lead$run_sync("go"))

  # Six requests in all: three are the analyst's until it settles, so the
  # lead stops after its third.
  expect_identical(result$stop_reason, "request_limit")
  arrivals <- setup$server$arrivals_by_model()
  expect_identical(sum(arrivals == "lead"), 3L)
  expect_identical(sum(arrivals == "analyst"), 1L)
  expect_identical(result$usage$requests, 4L)
  limit <- runtime_events(lead, "stop")[[1L]]$limit
  expect_identical(limit$field, "max_requests")
  expect_equal(limit$limit, 6)
  expect_equal(unname(limit$reserved), 3)
  tasks <- lead$background_tasks()
  expect_identical(tasks$state, "cancelled")
  expect_identical(tasks$stop_reason, "request_limit")
  expect_false(tasks$collected)
  expect_background_idle(setup)
})

test_that("a start that would leave the lead nothing is refused", {
  setup <- background_setup(
    list(
      lead = list(
        runtime_tool_calls_reply(list(start_call("analyst", id = "c1"))),
        runtime_reply("carried on alone")
      ),
      analyst = list(runtime_reply("must not be requested"))
    ),
    lead_limits = UsageLimits(max_requests = 4),
    task_limits = UsageLimits(max_requests = 3)
  )
  result <- suppressWarnings(setup$lead$run_sync("go"))
  expect_identical(result$stop_reason, "complete")
  expect_match(
    model_tool_results(setup$server)[["c1"]],
    "all that is left of the run's max_requests"
  )
  expect_identical(setup$server$arrivals_by_model(), c("lead", "lead"))
  expect_identical(nrow(setup$lead$background_tasks()), 0L)
  expect_identical(nrow(setup$lead$list_subagents()), 0L)
  expect_background_idle(setup)

  # A limit the tasks leave open would be set aside whole.
  setup <- background_setup(
    list(
      lead = list(
        runtime_tool_calls_reply(list(start_call("analyst", id = "c1"))),
        runtime_reply("carried on alone")
      ),
      analyst = list(runtime_reply("must not be requested"))
    ),
    lead_limits = UsageLimits(max_requests = 12, max_total_tokens = 1000),
    task_limits = UsageLimits(max_requests = 3)
  )
  suppressWarnings(setup$lead$run_sync("go"))
  expect_match(
    model_tool_results(setup$server)[["c1"]],
    "max_total_tokens"
  )
  expect_identical(nrow(setup$lead$background_tasks()), 0L)
})

test_that("a task stops at its own allocation and the lead carries on", {
  setup <- background_setup(
    list(
      lead = list(
        runtime_tool_calls_reply(list(start_call("analyst"))),
        runtime_tool_calls_reply(list(tool_call("task_wait", id = "w1"))),
        runtime_reply("reported the shortfall")
      ),
      analyst = list(
        runtime_tool_calls_reply(list(tool_call("load_measurements"))),
        runtime_reply("must not be requested")
      )
    ),
    analyst_tools = list(
      gated_tool("load_measurements", background_gate_open(), "data")
    ),
    task_limits = UsageLimits(max_requests = 1)
  )
  result <- suppressWarnings(setup$lead$run_sync("go"))
  expect_identical(result$stop_reason, "complete")
  waited <- jsonlite::fromJSON(
    model_tool_results(setup$server)[["w1"]],
    simplifyVector = FALSE
  )
  expect_identical(waited$tasks[[1L]]$state, "stopped")
  expect_identical(waited$tasks[[1L]]$stop_reason, "request_limit")
  expect_identical(sum(setup$server$arrivals_by_model() == "analyst"), 1L)
  expect_identical(result$usage$requests, 4L)
  expect_background_idle(setup)
})

test_that("token limits hold across the lead and a running task, within one response each", {
  gate <- background_gate()
  setup <- background_setup(
    list(
      lead = list(
        runtime_tool_calls_reply(list(start_call("analyst"))),
        runtime_tool_calls_reply(list(tool_call("lookup_spec"))),
        runtime_reply("must not be requested")
      ),
      analyst = list(
        runtime_tool_calls_reply(list(tool_call("load_measurements"))),
        runtime_reply("must not be requested")
      )
    ),
    analyst_tools = list(gated_tool("load_measurements", gate, "data")),
    lead_tools = list(note_tool()),
    # Every fixture response reports 15 tokens.
    lead_limits = UsageLimits(max_requests = 12, max_total_tokens = 60),
    task_limits = UsageLimits(max_requests = 3, max_total_tokens = 30)
  )
  lead <- setup$lead
  release_when(gate, function() {
    identical(lead$background_tasks()$state, "cancelling")
  })
  result <- suppressWarnings(lead$run_sync("go"))
  # 30 of the 60 tokens are the task's, so the lead stops at its own 30.
  expect_identical(result$stop_reason, "total_token_limit")
  expect_identical(sum(setup$server$arrivals_by_model() == "lead"), 2L)
  expect_lte(result$usage$total_tokens, 60 + 15)
  expect_background_idle(setup)
})

test_that("narrowing the lead's permissions after dispatch reaches a running task", {
  gate <- background_gate()
  effects <- 0L
  write_report <- ellmer::tool(
    function() {
      effects <<- effects + 1L
      "written"
    },
    name = "write_report",
    description = "Write the report",
    arguments = list()
  )
  setup <- background_setup(
    list(
      lead = list(
        runtime_tool_calls_reply(list(start_call("analyst"))),
        runtime_tool_calls_reply(list(tool_call("task_wait", id = "w1"))),
        runtime_reply("done")
      ),
      analyst = list(
        runtime_tool_calls_reply(list(tool_call("load_measurements"))),
        runtime_tool_calls_reply(list(tool_call("write_report"))),
        runtime_reply("I could not write the report.")
      )
    ),
    analyst_tools = list(
      gated_tool("load_measurements", gate, "data"),
      write_report
    )
  )
  lead <- setup$lead
  forwarded <- character()
  lead$add_hook(HookMatcher(
    "PreToolUse",
    callback = function(tool_name, ...) {
      forwarded <<- c(forwarded, tool_name)
      NULL
    }
  ))
  # The task was started under full permissions. The host narrows the lead
  # while the analyst is inside its first tool.
  on_tool(lead, "PreToolUse", "^task_wait$", function() {
    lead$set_permission_mode("readonly")
    gate$release()
  })
  result <- suppressWarnings(lead$run_sync("go"))
  expect_identical(result$stop_reason, "complete")
  expect_identical(effects, 0L)
  expect_identical(lead$background_tasks()$state, "completed")
  transcript <- jsonlite::toJSON(
    lead$inspect_subagents("host", transcript = TRUE)[[1L]]$transcript,
    auto_unbox = TRUE
  )
  expect_match(transcript, "write_report")
  expect_match(transcript, "readonly|read-only|not allowed")
  # The lead's tool hooks saw the task's calls as well as its own.
  expect_true(all(c("load_measurements", "task_wait") %in% forwarded))
  expect_background_idle(setup)
})

test_that("a lead hook can deny a background task's tool call", {
  gate <- background_gate_open()
  setup <- background_setup(
    list(
      lead = list(
        runtime_tool_calls_reply(list(start_call("reviewer"))),
        runtime_tool_calls_reply(list(tool_call("task_wait"))),
        runtime_reply("done")
      ),
      reviewer = list(
        runtime_tool_calls_reply(list(tool_call("read_draft"))),
        runtime_reply("The draft was withheld.")
      )
    ),
    reviewer_tools = list(gated_tool("read_draft", gate, "draft"))
  )
  setup$lead$add_hook(HookMatcher(
    "PreToolUse",
    pattern = "^read_draft$",
    callback = function(...) {
      HookResultPreToolUse(permission = "deny", reason = "drafts are private")
    }
  ))
  result <- suppressWarnings(setup$lead$run_sync("go"))
  expect_identical(result$stop_reason, "complete")
  expect_identical(gate$calls, 0L)
  expect_identical(setup$lead$background_tasks()$state, "completed")
})

test_that("a read-only lead can run tasks, which are then held to read-only", {
  effects <- 0L
  setup <- background_setup(
    list(
      lead = list(
        runtime_tool_calls_reply(list(start_call("analyst"))),
        runtime_tool_calls_reply(list(tool_call("task_wait"))),
        runtime_reply("done")
      ),
      analyst = list(
        runtime_tool_calls_reply(list(
          tool_call("load_measurements", id = "a1"),
          tool_call("write_report", id = "a2")
        )),
        runtime_reply("Read the data; could not write.")
      )
    ),
    analyst_tools = list(
      gated_tool("load_measurements", background_gate_open(), "data"),
      ellmer::tool(
        function() {
          effects <<- effects + 1L
          "written"
        },
        name = "write_report",
        description = "Write the report",
        arguments = list()
      )
    ),
    permissions = permissions_readonly()
  )
  result <- suppressWarnings(setup$lead$run_sync("go"))
  expect_identical(result$stop_reason, "complete")
  expect_identical(effects, 0L)
  expect_identical(setup$lead$background_tasks()$state, "completed")
  expect_identical(sum(setup$server$arrivals_by_model() == "analyst"), 2L)
})

test_that("task IDs from an earlier run or another owner are refused", {
  gate <- background_gate()
  script <- list(
    lead = list(
      runtime_tool_calls_reply(list(start_call("analyst", id = "c1"))),
      runtime_tool_calls_reply(list(tool_call("ask_other", id = "c2"))),
      runtime_tool_calls_reply(list(tool_call("task_wait", id = "c3"))),
      runtime_reply("first run done"),
      # Second run: the first run's ID no longer names a task.
      function(request, ids) {
        id <- ids$analyst[[1L]]
        runtime_tool_calls_reply(list(
          list(
            id = "s1",
            name = "task_status",
            arguments = list(task_ids = list(id))
          ),
          list(
            id = "s2",
            name = "task_follow_up",
            arguments = list(task_id = id, task = "again")
          ),
          list(id = "s3", name = "task_cancel", arguments = list(task_id = id)),
          list(
            id = "s4",
            name = "task_wait",
            arguments = list(task_ids = list(id))
          ),
          list(id = "s5", name = "task_wait", arguments = list())
        ))
      },
      runtime_reply("second run done")
    ),
    analyst = list(
      runtime_tool_calls_reply(list(tool_call("load_measurements"))),
      runtime_reply("measured")
    ),
    # The other owner tries the lead's live task ID from its own run.
    other = list(
      function(request, ids) {
        prompt <- paste(unlist(request$messages[[1L]]$content), collapse = " ")
        id <- regmatches(prompt, regexpr("task_[0-9a-f-]+", prompt))
        runtime_tool_calls_reply(list(
          list(id = "o1", name = "task_cancel", arguments = list(task_id = id)),
          list(
            id = "o2",
            name = "task_wait",
            arguments = list(task_ids = list(id))
          )
        ))
      },
      runtime_reply("other done")
    ),
    helper = list(runtime_reply("unused"))
  )
  other <- NULL
  setup <- background_setup(
    script,
    analyst_tools = list(gated_tool("load_measurements", gate, "data")),
    lead_tools = list(ellmer::tool(
      function() {
        live <- setup$lead$background_tasks()
        promises::then(
          other$run_async(paste("cancel", live$task_id)),
          function(result) {
            paste("other said:", result$response, "; task", live$state)
          }
        )
      },
      name = "ask_other",
      description = "Ask another owner",
      arguments = list()
    ))
  )
  lead <- setup$lead
  other <- Agent$new(
    runtime_chat(setup$server, model = "other"),
    permissions = permissions_full(),
    usage_limits = UsageLimits(max_requests = 8)
  )
  helper <- other$retain_agent(
    Agent$new(runtime_chat(setup$server, model = "helper")),
    UsageLimits(max_requests = 4)
  )
  other_tools <- background_tools(
    other,
    c(helper = helper),
    UsageLimits(max_requests = 2)
  )
  other$register_tools(other_tools)
  on_tool(lead, "PreToolUse", "^task_wait$", gate$release)

  first <- suppressWarnings(lead$run_sync("go"))
  expect_identical(first$stop_reason, "complete")
  # The other owner could neither see nor cancel the lead's running task.
  refused <- model_tool_results(setup$server, "other")
  expect_match(refused[["o1"]], "Unknown task")
  expect_match(refused[["o2"]], "Unknown task")
  expect_match(model_tool_results(setup$server)[["c2"]], "task running")
  expect_identical(lead$background_tasks()$state, "completed")
  expect_identical(nrow(other$background_tasks()), 0L)

  second <- suppressWarnings(lead$run_sync("again"))
  expect_identical(second$stop_reason, "complete")
  stale <- model_tool_results(setup$server)
  for (call in c("s1", "s2", "s3", "s4")) {
    expect_match(stale[[call]], "Unknown task")
  }
  expect_match(stale[["s5"]], "No background tasks are pending")
  # Nothing ran for the stale ID, and the new run starts with no tasks.
  expect_identical(sum(setup$server$arrivals_by_model() == "analyst"), 2L)
  expect_identical(nrow(lead$background_tasks()), 0L)
  expect_identical(nrow(lead$list_subagents()), 1L)

  # The tools themselves are bound to their owner and to its governed calls.
  expect_error(
    lead$register_tools(other_tools, replace = TRUE),
    class = "deputy_conversation"
  )
  expect_error(
    other_tools$task_status(),
    class = "deputy_background_task"
  )
  expect_error(
    lead$get_tools()[["task_start"]]("analyst", "stolen"),
    class = "deputy_conversation"
  )
  expect_identical(sum(setup$server$arrivals_by_model() == "analyst"), 2L)
})

test_that("tasks for a busy specialist wait their turn and keep its conversation", {
  gate <- background_gate()
  setup <- background_setup(
    list(
      lead = list(
        runtime_tool_calls_reply(list(start_call("analyst", "first", "c1"))),
        function(request, ids) {
          runtime_tool_calls_reply(list(
            list(
              id = "c2",
              name = "task_follow_up",
              arguments = list(task_id = ids$analyst[[1L]], task = "second")
            ),
            list(
              id = "c3",
              name = "task_start",
              arguments = list(agent = "analyst", task = "third")
            )
          ))
        },
        function(request, ids) {
          runtime_tool_calls_reply(list(
            list(
              id = "c4",
              name = "task_cancel",
              arguments = list(task_id = ids$analyst[[3L]])
            ),
            list(id = "c5", name = "task_status", arguments = list()),
            list(
              id = "c6",
              name = "task_wait",
              arguments = list(until = "all")
            )
          ))
        },
        runtime_reply("all collected")
      ),
      analyst = list(
        runtime_tool_calls_reply(list(tool_call("load_measurements"))),
        runtime_reply("first answer"),
        runtime_reply("second answer"),
        runtime_reply("must not be requested")
      )
    ),
    analyst_tools = list(gated_tool("load_measurements", gate, "data")),
    lead_limits = UsageLimits(max_requests = 40)
  )
  lead <- setup$lead
  on_tool(lead, "PreToolUse", "^task_wait$", gate$release)
  result <- suppressWarnings(lead$run_sync("go"))
  expect_identical(result$stop_reason, "complete")

  results <- model_tool_results(setup$server)
  expect_identical(jsonlite::fromJSON(results[["c2"]])$state, "queued")
  expect_identical(jsonlite::fromJSON(results[["c3"]])$state, "queued")
  # A waiting task is cancelled on the spot.
  expect_identical(jsonlite::fromJSON(results[["c4"]])$state, "cancelled")
  status <- jsonlite::fromJSON(results[["c5"]], simplifyVector = FALSE)$tasks
  expect_identical(
    vapply(status, function(task) task$state, character(1)),
    c("running", "queued", "cancelled")
  )
  expect_identical(status[[1L]]$progress$requests, 1L)
  expect_identical(status[[1L]]$progress$tool_calls, 1L)
  collected <- jsonlite::fromJSON(results[["c6"]], simplifyVector = FALSE)
  expect_identical(
    vapply(collected$tasks, function(task) task$state, character(1)),
    c("cancelled", "completed", "completed")
  )
  expect_length(collected$still_running, 0L)

  tasks <- lead$background_tasks()
  expect_identical(tasks$state, c("completed", "completed", "cancelled"))
  expect_identical(tasks$previous_task_id[[2L]], tasks$task_id[[1L]])
  # The cancelled task never ran: no delegation, no request.
  expect_identical(
    lead$list_subagents()$delegation_id,
    tasks$delegation_id[1:2]
  )
  analyst_requests <- Filter(
    function(entry) entry$body$model == "analyst",
    setup$server$requests()
  )
  expect_length(analyst_requests, 3L)
  queued_body <- jsonlite::toJSON(analyst_requests[[3L]]$body$messages)
  expect_match(queued_body, "first answer", fixed = TRUE)
  expect_match(queued_body, "second", fixed = TRUE)
  expect_false(grepl("third", queued_body, fixed = TRUE))
  expect_background_idle(setup)
})

test_that("a failed task is reported as failed and leaves the others alone", {
  setup <- background_setup(
    list(
      lead = list(
        runtime_tool_calls_reply(list(
          start_call("analyst", id = "c1"),
          start_call("reviewer", id = "c2")
        )),
        runtime_tool_calls_reply(list(tool_call(
          "task_wait",
          list(until = "all"),
          "w1"
        ))),
        runtime_reply("reported one failure")
      ),
      analyst = list(runtime_failure(403L)),
      reviewer = list(runtime_reply("the draft is fine"))
    )
  )
  result <- suppressWarnings(setup$lead$run_sync("go"))
  expect_identical(result$stop_reason, "complete")
  waited <- jsonlite::fromJSON(
    model_tool_results(setup$server)[["w1"]],
    simplifyVector = FALSE
  )$tasks
  states <- stats::setNames(
    vapply(waited, function(task) task$state, character(1)),
    vapply(waited, function(task) task$agent, character(1))
  )
  expect_identical(states[["analyst"]], "failed")
  expect_identical(states[["reviewer"]], "completed")
  failed <- waited[[which(names(states) == "analyst")]]
  expect_identical(failed$outcome$runtime$status, "failed")
  expect_identical(failed$outcome$answer, "")
  tasks <- setup$lead$background_tasks()
  expect_identical(tasks$state, c("failed", "completed"))
  expect_identical(setup$lead$list_subagents()$status, c("failed", "completed"))
  # The failed request counts, and the analyst can be given another task.
  expect_identical(result$usage$requests, 5L)
  expect_background_idle(setup)
})

test_that("tasks that settled before a wait arrive together, in settlement order", {
  gate <- background_gate()
  setup <- background_setup(
    list(
      lead = list(
        runtime_tool_calls_reply(list(
          start_call("analyst", id = "c1"),
          start_call("reviewer", id = "c2")
        )),
        runtime_tool_calls_reply(list(tool_call("until_settled"))),
        runtime_tool_calls_reply(list(tool_call("task_wait", id = "w1"))),
        function(request, ids) {
          # Cancelling a finished task changes nothing; waiting again returns
          # at once.
          runtime_tool_calls_reply(list(
            list(
              id = "x1",
              name = "task_cancel",
              arguments = list(task_id = ids$analyst[[1L]])
            ),
            list(id = "w2", name = "task_wait", arguments = list())
          ))
        },
        runtime_reply("done")
      ),
      analyst = list(
        runtime_tool_calls_reply(list(tool_call("load_measurements"))),
        runtime_reply("analysis")
      ),
      reviewer = list(runtime_reply("review"))
    ),
    analyst_tools = list(gated_tool("load_measurements", gate, "data")),
    lead_tools = list(ellmer::tool(
      function() {
        promises::promise(function(resolve, reject) {
          poll <- function() {
            states <- setup$lead$background_tasks()$state
            if (identical(states, c("running", "completed"))) {
              gate$release()
            }
            if (all(states == "completed")) {
              resolve("both settled")
            } else {
              later::later(poll, 0.01)
            }
          }
          poll()
        })
      },
      name = "until_settled",
      description = "The lead's own slow step",
      arguments = list()
    ))
  )
  result <- suppressWarnings(setup$lead$run_sync("go"))
  expect_identical(result$stop_reason, "complete")
  results <- model_tool_results(setup$server)
  waited <- jsonlite::fromJSON(results[["w1"]], simplifyVector = FALSE)
  expect_identical(
    vapply(waited$tasks, function(task) task$agent, character(1)),
    c("reviewer", "analyst")
  )
  expect_length(waited$still_running, 0L)
  late <- jsonlite::fromJSON(results[["x1"]])
  expect_identical(late$state, "completed")
  expect_false(late$cancel_requested)
  again <- jsonlite::fromJSON(results[["w2"]], simplifyVector = FALSE)
  expect_length(again$tasks, 0L)
  expect_match(again$note, "No background tasks are pending")
  expect_identical(setup$lead$background_tasks()$state, rep("completed", 2L))
})

test_that("tasks settling in the same turn of the event loop are collected by one wait", {
  owner <- owned_test_owner()
  first <- owned_test_agent("first")
  second <- owned_test_agent("second")
  handles <- c(
    first = owner$retain_agent(first, UsageLimits(max_requests = 2)),
    second = owner$retain_agent(second, UsageLimits(max_requests = 2))
  )
  background_tools(owner, handles, UsageLimits(max_requests = 1))
  private <- owner$.__enclos_env__$private
  private$run_active <- TRUE
  private$current_run_id <- "run-fixture"
  withr::defer({
    private$run_active <- FALSE
    private$current_run_id <- NULL
  })
  state <- private$.background
  for (name in names(handles)) {
    task <- new.env(parent = emptyenv())
    task$task_id <- paste0("task_", name)
    task$agent <- name
    task$delegation_id <- paste0("delegation_", name)
    task$run_id <- "run-fixture"
    task$settled <- FALSE
    task$collected <- FALSE
    state$tasks[[task$task_id]] <- task
  }
  waited <- NULL
  promises::then(background_wait(owner, NULL), function(payload) {
    waited <<- jsonlite::fromJSON(payload, simplifyVector = FALSE)
  })
  background_settle(owner, state$tasks$task_second, simpleError("refused"))
  background_settle(owner, state$tasks$task_first, simpleError("refused"))
  while (is.null(waited)) {
    later::run_now(0.05)
  }
  expect_identical(
    vapply(waited$tasks, function(task) task$task_id, character(1)),
    c("task_second", "task_first")
  )
  expect_length(waited$still_running, 0L)
})

test_that("a lead that answers early cancels its tasks and waits for them", {
  gate <- background_gate()
  setup <- background_setup(
    list(
      lead = list(
        runtime_tool_calls_reply(list(
          start_call("analyst", "first", "c1"),
          start_call("reviewer", id = "c2")
        )),
        function(request, ids) {
          runtime_tool_calls_reply(list(list(
            id = "c3",
            name = "task_follow_up",
            arguments = list(task_id = ids$analyst[[1L]], task = "second")
          )))
        },
        runtime_reply("answered without collecting"),
        runtime_reply("a later run")
      ),
      analyst = list(
        runtime_tool_calls_reply(list(tool_call("load_measurements"))),
        runtime_reply("resumed and finished")
      ),
      reviewer = list(
        runtime_tool_calls_reply(list(tool_call("read_draft"))),
        runtime_reply("must not be requested")
      )
    ),
    analyst_tools = list(gated_tool("load_measurements", gate, "data")),
    reviewer_tools = list(gated_tool("read_draft", gate, "draft"))
  )
  lead <- setup$lead
  ended <- NULL
  lead$add_hook(HookMatcher(
    "SessionEnd",
    callback = function(context, ...) {
      ended <<- list(
        states = lead$background_tasks()$state,
        requests = context$usage$requests
      )
      NULL
    }
  ))
  release_when(gate, function() {
    identical(
      lead$background_tasks()$state,
      c("cancelling", "cancelling", "cancelled")
    )
  })
  result <- suppressWarnings(lead$run_sync("go"))
  expect_identical(result$stop_reason, "complete")
  expect_match(result$response, "answered without collecting")
  tasks <- lead$background_tasks()
  expect_identical(tasks$state, rep("cancelled", 3L))
  expect_identical(tasks$stop_reason, rep("parent_completed", 3L))
  expect_identical(tasks$collected, rep(FALSE, 3L))
  # The run ended only after its tasks had: the hook saw them settled, and
  # the run's usage has the two requests they made.
  expect_identical(ended$states, rep("cancelled", 3L))
  expect_identical(ended$requests, 5L)
  expect_identical(result$usage$requests, 5L)
  arrivals <- setup$server$arrivals_by_model()
  expect_identical(sum(arrivals == "analyst"), 1L)
  expect_identical(sum(arrivals == "reviewer"), 1L)
  runs <- lead$list_subagents()
  expect_identical(runs$status, c("stopped", "stopped"))
  expect_identical(runs$stop_reason, rep("parent_completed", 2L))
  ending <- lead$inspect_subagents("host")[[1L]]$outcome$runtime
  expect_identical(ending$stop_reason, "parent_completed")
  expect_background_idle(setup)

  # Nothing is left holding the lead or the specialists: the lead runs again,
  # and the host can continue the analyst from where it was stopped.
  later_run <- lead$run_sync("next")
  expect_match(later_run$response, "a later run")
  expect_identical(nrow(lead$background_tasks()), 0L)
  continued <- lead$continue_agent(
    setup$handles[["analyst"]],
    "finish it",
    UsageLimits(max_requests = 2)
  )
  expect_match(continued$response, "resumed and finished")
  expect_no_error(lead$release_agent(setup$handles[["analyst"]]))
  expect_no_error(lead$release_agent(setup$handles[["reviewer"]]))
})

test_that("interrupting the lead stops its tasks before the run returns", {
  gate <- background_gate()
  setup <- background_setup(
    list(
      lead = list(
        runtime_tool_calls_reply(list(start_call("analyst"))),
        runtime_tool_calls_reply(list(tool_call("task_wait"))),
        runtime_reply("must not be requested")
      ),
      analyst = list(
        runtime_tool_calls_reply(list(tool_call("load_measurements"))),
        runtime_reply("must not be requested")
      )
    ),
    analyst_tools = list(gated_tool("load_measurements", gate, "data"))
  )
  lead <- setup$lead
  # The host stops the lead while it waits on a task that is inside a tool.
  on_tool(lead, "PreToolUse", "^task_wait$", function() {
    later::later(function() {
      lead$interrupt("host stopped the lead")
      gate$release()
    })
  })
  result <- suppressWarnings(lead$run_sync("go"))
  expect_identical(result$stop_reason, "host stopped the lead")
  tasks <- lead$background_tasks()
  expect_identical(tasks$state, "cancelled")
  expect_identical(tasks$stop_reason, "host stopped the lead")
  arrivals <- setup$server$arrivals_by_model()
  expect_identical(sum(arrivals == "analyst"), 1L)
  expect_identical(sum(arrivals == "lead"), 2L)
  expect_background_idle(setup)
})

test_that("a lead whose model request fails still settles its tasks", {
  gate <- background_gate()
  setup <- background_setup(
    list(
      lead = list(
        runtime_tool_calls_reply(list(start_call("analyst"))),
        runtime_failure(403L)
      ),
      analyst = list(
        runtime_tool_calls_reply(list(tool_call("load_measurements"))),
        runtime_reply("must not be requested")
      )
    ),
    analyst_tools = list(gated_tool("load_measurements", gate, "data"))
  )
  lead <- setup$lead
  release_when(gate, function() {
    identical(lead$background_tasks()$state, "cancelling")
  })
  expect_error(suppressWarnings(lead$run_sync("go")))
  tasks <- lead$background_tasks()
  expect_identical(tasks$state, "cancelled")
  expect_identical(tasks$stop_reason, "parent_failed")
  expect_identical(sum(setup$server$arrivals_by_model() == "analyst"), 1L)
  expect_background_idle(setup)
  expect_no_error(lead$release_agent(setup$handles[["analyst"]]))
})

test_that("starts beyond max_active or max_tasks are refused", {
  gate <- background_gate()
  setup <- background_setup(
    list(
      lead = list(
        runtime_tool_calls_reply(list(
          start_call("analyst", id = "c1"),
          start_call("reviewer", id = "c2")
        )),
        runtime_tool_calls_reply(list(tool_call("task_wait", id = "w1"))),
        runtime_tool_calls_reply(list(
          start_call("reviewer", id = "c3"),
          tool_call("task_wait", list(until = "all"), "w2")
        )),
        runtime_tool_calls_reply(list(start_call("analyst", id = "c4"))),
        runtime_reply("done")
      ),
      analyst = list(runtime_reply("analysis")),
      reviewer = list(runtime_reply("review"))
    ),
    max_active = 1L,
    max_tasks = 2L
  )
  result <- suppressWarnings(setup$lead$run_sync("go"))
  expect_identical(result$stop_reason, "complete")
  results <- model_tool_results(setup$server)
  expect_match(results[["c2"]], "the most allowed at once")
  expect_identical(jsonlite::fromJSON(results[["c3"]])$state, "running")
  expect_match(results[["c4"]], "limit of 2 background tasks")
  tasks <- setup$lead$background_tasks()
  expect_identical(tasks$agent, c("analyst", "reviewer"))
  expect_identical(tasks$state, c("completed", "completed"))
})

test_that("a LeadAgent runs blocking delegation beside its background tasks", {
  gate <- background_gate()
  script <- list(
    lead = list(
      runtime_tool_calls_reply(list(
        start_call("analyst", id = "c1"),
        tool_call(
          "delegate_to_agent",
          list(agent_name = "checker", task = "Check the units"),
          "c2"
        )
      )),
      runtime_tool_calls_reply(list(tool_call("task_wait", id = "w1"))),
      runtime_reply("combined")
    ),
    analyst = list(
      runtime_tool_calls_reply(list(tool_call("load_measurements"))),
      runtime_reply("analysis")
    ),
    checker = list(runtime_reply("units are consistent"))
  )
  server <- local_scripted_server(script)
  lead <- LeadAgent$new(
    runtime_chat(server, model = "lead"),
    sub_agents = list(agent_definition(
      name = "checker",
      description = "Checks units",
      prompt = "Check units."
    )),
    permissions = permissions_full(),
    usage_limits = UsageLimits(max_requests = 20),
    delegation_policy = DelegationPolicy(
      chat = function(definition, context) {
        runtime_chat(server, model = definition$name)
      }
    ),
    delegation_disclosure = DelegationDisclosure(authorize = function(...) TRUE)
  )
  analyst <- Agent$new(
    runtime_chat(server, model = "analyst"),
    tools = list(gated_tool("load_measurements", gate, "data")),
    permissions = permissions_full(),
    agent_name = "analyst"
  )
  handle <- lead$retain_agent(analyst, UsageLimits(max_requests = 6))
  lead$register_tools(background_tools(
    lead,
    c(analyst = handle),
    UsageLimits(max_requests = 3)
  ))
  on_tool(lead, "PreToolUse", "^task_wait$", gate$release)
  result <- suppressWarnings(lead$run_sync("go"))
  expect_identical(result$stop_reason, "complete")
  results <- model_tool_results(server)
  # The blocking delegation returned its answer while the task was running.
  expect_match(results[["c2"]], "units are consistent")
  arrivals <- server$arrivals_by_model()
  expect_lt(which(arrivals == "checker"), which(arrivals == "analyst")[[2L]])
  expect_identical(lead$background_tasks()$state, "completed")
  expect_setequal(lead$list_subagents()$agent_name, c("analyst", "checker"))
  expect_identical(result$usage$requests, length(arrivals))
})

test_that("background tools are refused where their guarantees do not hold", {
  owner <- owned_test_owner()
  handle <- owner$retain_agent(
    owned_test_agent(),
    UsageLimits(max_requests = 2)
  )
  limits <- UsageLimits(max_requests = 1)
  expect_error(
    background_tools(owner, c(a = "conversation_unknown"), limits),
    class = "deputy_conversation"
  )
  expect_error(
    background_tools(owner, handle, limits),
    class = "deputy_background_task"
  )
  expect_error(
    background_tools(owner, c(a = handle, b = handle), limits),
    class = "deputy_background_task"
  )
  expect_error(background_tools(owner, c(a = handle), limits, max_active = 0))
  expect_error(
    background_tools(owner, c(a = handle), NULL),
    class = "deputy_background_task"
  )
  expect_error(
    background_tools(owner, c(a = handle), limits, descriptions = c(b = "x")),
    class = "deputy_background_task"
  )
  # A retained agent cannot be an owner.
  expect_error(
    background_tools(
      owner$.__enclos_env__$private$owned_conversations[[handle]]$agent,
      c(a = handle),
      limits
    ),
    class = "deputy_conversation"
  )

  tools <- background_tools(owner, c(a = handle), limits)
  expect_named(
    tools,
    c("task_start", "task_follow_up", "task_status", "task_wait", "task_cancel")
  )
  owner$register_tools(tools)
  # An owner with a trusted-results policy cannot take them.
  measure <- ellmer::tool(
    function() "42",
    name = "measure",
    description = "Measure",
    arguments = list(),
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE
    )
  )
  trusted_owner <- owned_test_agent(
    tools = list(measure),
    trusted_results = TrustedResults(measure = measure)
  )
  trusted_handle <- trusted_owner$retain_agent(
    owned_test_agent(
      tools = list(measure),
      trusted_results = TrustedResults(measure = measure)
    ),
    UsageLimits(max_requests = 2)
  )
  expect_error(
    trusted_owner$register_tools(
      background_tools(trusted_owner, c(a = trusted_handle), limits)
    ),
    class = "deputy_tool_registration"
  )
})

test_that("a background task's tool calls show as activity on the call that started it", {
  gate <- background_gate()
  setup <- background_setup(
    list(
      lead = list(
        runtime_tool_calls_reply(list(start_call("analyst", id = "c1"))),
        runtime_tool_calls_reply(list(tool_call("task_wait", id = "w1"))),
        runtime_reply("done")
      ),
      analyst = list(
        runtime_tool_calls_reply(list(tool_call("load_measurements"))),
        runtime_reply("analysis")
      )
    ),
    analyst_tools = list(gated_tool("load_measurements", gate, "data"))
  )
  lead <- setup$lead
  activity_enable(lead, function() "host", 0.05)
  on_tool(lead, "PreToolUse", "^task_wait$", gate$release)
  done <- FALSE
  failure <- NULL
  stream <- lead$stream_async("go", stream = "content")
  coro::async(function() {
    tryCatch(
      for (chunk in coro::await_each(stream)) {
        NULL
      },
      error = function(error) failure <<- error
    )
    done <<- TRUE
  })()
  while (!done) {
    later::run_now(0.05)
  }
  expect_null(failure)
  turns <- lead$get_turns()
  # The cards sit beside the lead's task_start call, where the task began,
  # and never enter the lead's model context.
  started <- turns[[2L]]@contents
  cards <- Filter(is_activity_content, started)
  expect_gte(length(cards), 1L)
  expect_true(any(vapply(
    cards,
    function(card) {
      inherits(card, "ellmer::ContentToolRequest") &&
        identical(card@name, "load_measurements")
    },
    logical(1)
  )))
  context <- unlist(lapply(lead$get_context_turns(), function(turn) {
    turn@contents
  }))
  expect_false(any(vapply(context, is_activity_content, logical(1))))
  expect_identical(lead$background_tasks()$state, "completed")
})
