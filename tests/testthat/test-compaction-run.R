test_that("summary recovery is isolated, accounted, and preserves task fallback", {
  withr::local_options(ellmer_max_tries = 1)
  primary <- local_runtime_server(list(runtime_failure()))
  summary <- local_runtime_server(list(runtime_reply(
    "Keep assay-C-r3, denominator 84; export-0042 is already complete."
  )))
  task <- local_runtime_server(list(runtime_reply(
    "E is eligible; D and F need clarification."
  )))
  chat <- runtime_compaction_chat(primary)
  chat$set_system_prompt("Host policy remains authoritative.")
  callback_calls <- 0L
  chat$on_request_start(function(turns) callback_calls <<- callback_calls + 1L)
  agent <- Agent$new(
    chat,
    fallback_chats = list(runtime_chat(task)),
    context_policy = ContextPolicy(
      max_tokens = 50,
      summary_fallback_chats = list(runtime_chat(summary))
    )
  )
  hooks <- compaction_hook_log(agent)

  result <- agent$run_sync("Continue the review")

  expect_identical(
    trimws(result$response),
    "E is eligible; D and F need clarification."
  )
  expect_identical(result$usage$requests, 4L)
  expect_identical(result$usage$cost_usd, NA_real_)
  expect_equal(result$usage$total_tokens, 30)
  expect_identical(callback_calls, 1L)
  expect_identical(
    hooks$events,
    c(
      "SessionStart",
      "UserPromptSubmit",
      "PreCompact",
      "PostCompact",
      "Stop",
      "SessionEnd"
    )
  )
  expect_identical(unique(hooks$run_ids), result$run_id)
  expect_identical(agent$last_compaction()$run_id, result$run_id)
  expect_identical(agent$last_compaction()$usage$requests, 2L)
  expect_length(agent$last_compaction()$attempts, 2L)
  expect_length(runtime_events(agent, "request_start"), 4L)
  expect_length(runtime_events(agent, "fallback"), 2L)
  summary_request <- summary$requests()[[1]]$body
  expect_null(summary_request$tools)
  expect_length(summary_request$messages, 1L)
  expect_match(
    jsonlite::toJSON(summary_request$messages[[1]]$content),
    "assay-C-r3",
    fixed = TRUE
  )
  task_request <- task$requests()[[1]]$body
  expect_match(
    jsonlite::toJSON(task_request$messages[[1]]$content),
    "Host policy remains authoritative",
    fixed = TRUE
  )
  expect_match(
    jsonlite::toJSON(task_request$messages[[1]]$content),
    "export-0042 is already complete",
    fixed = TRUE
  )
  expect_identical(
    tail(task_request$messages, 1L)[[1]]$content[[1]]$text,
    "Continue the review"
  )
  expect_identical(result$stop_reason, "complete")
})

test_that("failed compaction retains history and a complete terminal lifecycle", {
  withr::local_options(ellmer_max_tries = 1)
  server <- local_runtime_server(list(runtime_failure(401L)))
  backup <- local_runtime_server(list(runtime_reply("must not be requested")))
  chat <- runtime_compaction_chat(server)
  chat$set_system_prompt("Original policy")
  before <- chat$get_turns()
  agent <- Agent$new(
    chat,
    context_policy = ContextPolicy(
      max_tokens = 50,
      summary_fallback_chats = list(runtime_chat(backup))
    )
  )
  hooks <- compaction_hook_log(agent)
  error <- tryCatch(agent$run_sync("Continue"), error = identity)

  expect_s3_class(error, "deputy_compaction_error")
  expect_s3_class(error$parent, "httr2_http_401")
  expect_identical(agent$get_turns(), before)
  expect_identical(agent$get_system_prompt(), "Original policy")
  expect_identical(agent$last_run()$stop_reason, "error")
  expect_identical(agent$last_run()$usage$requests, 1L)
  expect_identical(agent$last_run()$usage$cost_usd, NA_real_)
  expect_identical(
    hooks$events,
    c("SessionStart", "UserPromptSubmit", "PreCompact", "Stop", "SessionEnd")
  )
  expect_identical(unique(hooks$run_ids), agent$last_run()$run_id)
  expect_length(runtime_events(agent, "run_error"), 1L)
  expect_identical(runtime_events(agent, "run_error")[[1]]$phase, "compaction")
  expect_length(backup$requests(), 0L)
  expect_identical(agent$.__enclos_env__$private$run_active, FALSE)
})

test_that("request and unknown-cost limits prevent summary recovery and task dispatch", {
  withr::local_options(ellmer_max_tries = 1)
  for (case in list(
    list(limits = UsageLimits(max_requests = 1), reason = "request_limit"),
    list(limits = UsageLimits(max_cost_usd = 1), reason = "cost_unavailable")
  )) {
    server <- local_runtime_server(list(runtime_failure()))
    backup <- local_runtime_server(list(runtime_reply()))
    chat <- runtime_compaction_chat(server)
    before <- chat$get_turns()
    agent <- Agent$new(
      chat,
      usage_limits = case$limits,
      context_policy = ContextPolicy(
        max_tokens = 50,
        fallback = "text",
        summary_fallback_chats = list(runtime_chat(backup))
      )
    )

    result <- agent$run_sync("Continue")

    expect_identical(result$stop_reason, case$reason)
    expect_identical(result$usage$requests, 1L)
    expect_identical(agent$get_turns(), before)
    expect_length(backup$requests(), 0L)
    expect_null(agent$last_compaction())
    expect_length(runtime_events(agent, "stop"), 1L)
  }
})

test_that("an accepted summary survives a limit before task execution", {
  server <- local_runtime_server(list(runtime_reply(
    "Accepted continuation summary."
  )))
  agent <- Agent$new(
    runtime_compaction_chat(server, name = "OpenAI"),
    usage_limits = UsageLimits(max_requests = 1),
    context_policy = ContextPolicy(max_tokens = 50)
  )

  result <- agent$run_sync("Continue")

  expect_identical(result$stop_reason, "request_limit")
  expect_identical(result$usage$requests, 1L)
  expect_equal(result$usage$total_tokens, 15)
  expect_gt(result$usage$cost_usd, 0)
  expect_null(result$response)
  expect_identical(
    trimws(agent$last_compaction()$summary),
    "Accepted continuation summary."
  )
  expect_length(server$requests(), 1L)
  expect_length(runtime_events(agent, "compaction"), 1L)
})

test_that("summary token and cost overages stop before task execution", {
  for (case in list(
    list(
      limits = UsageLimits(max_input_tokens = 10),
      reason = "input_token_limit"
    ),
    list(
      limits = UsageLimits(max_output_tokens = 5),
      reason = "output_token_limit"
    ),
    list(
      limits = UsageLimits(max_total_tokens = 15),
      reason = "total_token_limit"
    ),
    list(limits = UsageLimits(max_cost_usd = 1e-9), reason = "cost_limit")
  )) {
    server <- local_runtime_server(list(runtime_reply("Accepted summary.")))
    agent <- Agent$new(
      runtime_compaction_chat(server, name = "OpenAI"),
      usage_limits = case$limits,
      context_policy = ContextPolicy(max_tokens = 50)
    )

    result <- agent$run_sync("Continue")

    expect_identical(result$stop_reason, case$reason)
    expect_identical(result$usage$requests, 1L)
    expect_equal(result$usage$total_tokens, 15)
    expect_gt(result$usage$cost_usd, 0)
    expect_length(server$requests(), 1L)
    expect_identical(
      trimws(agent$last_compaction()$summary),
      "Accepted summary."
    )
  }
})

test_that("summary limits signal only after saving terminal run evidence", {
  server <- local_runtime_server(list(runtime_reply("Accepted summary.")))
  agent <- Agent$new(
    runtime_compaction_chat(server),
    usage_limits = UsageLimits(max_requests = 1, on_exceed = "error"),
    context_policy = ContextPolicy(max_tokens = 50)
  )

  error <- tryCatch(agent$run_sync("Continue"), error = identity)

  expect_s3_class(error, "deputy_request_limit")
  expect_identical(agent$last_run()$stop_reason, "request_limit")
  expect_identical(agent$last_run()$usage$requests, 1L)
  expect_length(runtime_events(agent, "stop"), 1L)
  expect_identical(agent$.__enclos_env__$private$run_active, FALSE)
})

test_that("ellmer owns summary transport retries before ordered recovery", {
  server <- local_runtime_server(c(
    rep(list(runtime_failure()), 3),
    list(runtime_reply("Task done"))
  ))
  backup <- local_runtime_server(list(runtime_reply("Recovered summary")))
  agent <- Agent$new(
    runtime_compaction_chat(server),
    context_policy = ContextPolicy(
      max_tokens = 50,
      summary_fallback_chats = list(runtime_chat(backup))
    )
  )

  result <- agent$run_sync("Continue")

  expect_identical(trimws(result$response), "Task done")
  expect_identical(result$usage$requests, 3L)
  expect_identical(agent$last_compaction()$usage$requests, 2L)
  expect_length(server$requests(), 4L)
  expect_length(backup$requests(), 1L)
})

test_that("structured task output follows compaction under the same budget", {
  server <- local_runtime_server(list(
    runtime_reply("Keep the corrected denominator 84."),
    runtime_reply("Task decision prepared."),
    runtime_reply('{"denominator":84}', stream = FALSE)
  ))
  agent <- Agent$new(
    runtime_compaction_chat(server),
    context_policy = ContextPolicy(max_tokens = 50)
  )

  result <- agent$run_sync(
    "Return the corrected denominator",
    type = ellmer::type_object(denominator = ellmer::type_integer())
  )

  expect_equal(result$structured_output$denominator, 84L)
  expect_identical(result$usage$requests, 3L)
  expect_equal(result$usage$total_tokens, 45)
  expect_identical(result$stop_reason, "complete")
})

test_that("successive automatic compactions preserve the summary and reset run usage", {
  server <- local_runtime_server(list(
    runtime_reply("Use assay-C-r3 and preserve export-0042."),
    runtime_reply("First response"),
    runtime_reply("Use assay-C-r3, preserve export-0042, and keep D pending."),
    runtime_reply("Second response")
  ))
  agent <- Agent$new(
    runtime_compaction_chat(server, name = "OpenAI"),
    context_policy = ContextPolicy(max_tokens = 50)
  )

  first <- agent$run_sync("Continue")
  second <- agent$run_sync("Continue again")

  expect_identical(first$usage$requests, 2L)
  expect_identical(second$usage$requests, 2L)
  expect_equal(first$usage$total_tokens, 30)
  expect_equal(second$usage$total_tokens, 30)
  expect_equal(first$usage$cost_usd, second$usage$cost_usd)
  expect_identical(trimws(second$response), "Second response")
  summary_input <- jsonlite::toJSON(server$requests()[[3]]$body$messages)
  expect_match(
    summary_input,
    "Existing summary from earlier compactions",
    fixed = TRUE
  )
  expect_match(summary_input, "preserve export-0042", fixed = TRUE)
  expect_identical(agent$last_compaction()$run_id, second$run_id)
})

test_that("between-round summary failure is a compaction error and cannot replay task effects", {
  withr::local_options(ellmer_max_tries = 1)
  server <- local_runtime_server(list(
    runtime_reply(tool = "export_findings"),
    runtime_failure()
  ))
  backup <- local_runtime_server(list(runtime_reply("unexpected")))
  chat <- runtime_compaction_chat(server)
  chat$token_count <- function(...) if (length(server$requests())) 1000 else 10
  effects <- 0L
  tool <- ellmer::tool(
    function() {
      effects <<- effects + 1L
      "export-0042"
    },
    name = "export_findings",
    description = "Export the findings"
  )
  agent <- Agent$new(
    chat,
    tools = list(tool),
    permissions = permissions_full(),
    fallback_chats = list(runtime_chat(backup)),
    context_policy = ContextPolicy(max_tokens = 50)
  )

  error <- tryCatch(
    agent$run_sync("Perform the approved export"),
    error = identity
  )

  expect_s3_class(error, "deputy_compaction_error")
  expect_identical(agent$last_run()$stop_reason, "error")
  expect_identical(agent$last_run()$usage$requests, 2L)
  expect_identical(agent$last_run()$usage$tool_calls, 1L)
  expect_identical(runtime_events(agent, "run_error")[[1]]$phase, "compaction")
  expect_identical(effects, 1L)
  expect_length(backup$requests(), 0L)
  expect_null(agent$last_compaction())
})

test_that("text recovery preserves failed dispatch accounting without exposing a summary", {
  withr::local_options(ellmer_max_tries = 1)
  server <- local_runtime_server(list(
    runtime_failure(),
    runtime_reply("Task response")
  ))
  agent <- Agent$new(
    runtime_compaction_chat(server),
    context_policy = ContextPolicy(max_tokens = 50, fallback = "text")
  )

  notification <- NULL
  agent$add_hook(HookMatcher$new(
    event = "Notification",
    timeout = 0,
    callback = function(message, context) {
      notification <<- context$code
      NULL
    }
  ))
  result <- agent$run_sync("Continue")

  expect_identical(trimws(result$response), "Task response")
  expect_identical(result$usage$requests, 2L)
  expect_identical(result$usage$cost_usd, NA_real_)
  expect_identical(agent$last_compaction()$method, "text")
  expect_identical(agent$last_compaction()$usage$requests, 1L)
  expect_identical(
    notification,
    "compact_fallback"
  )
  expect_identical(
    paste(
      vapply(runtime_events(agent, "text"), `[[`, character(1), "text"),
      collapse = ""
    ),
    result$response
  )
})

test_that("summary destinations cannot be changed through caller templates or policy snapshots", {
  server <- local_runtime_server(list(runtime_reply()))
  template <- runtime_chat(server, "configured")
  policy <- ContextPolicy(summary_fallback_chats = list(template))
  agent <- Agent$new(runtime_chat(server), context_policy = policy)
  template$set_model("changed-template")
  policy$summary_fallback_chats[[1]]$set_model("changed-policy")
  snapshot <- agent$context_policy
  snapshot$summary_fallback_chats[[1]]$set_model("changed-snapshot")
  expect_identical(
    agent$context_policy$summary_fallback_chats[[1]]$get_model(),
    "configured"
  )
})

test_that("between-round compaction preserves completed effects, tool results, and usage", {
  server <- local_runtime_server(list(
    runtime_reply(tool = "export_findings"),
    runtime_reply("export-0042 completed. Do not repeat the export."),
    runtime_reply("Review complete.")
  ))
  chat <- runtime_compaction_chat(server, name = "OpenAI")
  chat$token_count <- function(...) {
    pending_results <- vapply(
      list(...),
      inherits,
      logical(1),
      what = "ellmer::ContentToolResult"
    )
    if (any(pending_results)) 1000 else 10
  }

  effects <- 0L
  tool <- ellmer::tool(
    function() {
      effects <<- effects + 1L
      "export-0042"
    },
    name = "export_findings",
    description = "Export the findings"
  )
  agent <- Agent$new(
    chat,
    tools = list(tool),
    permissions = permissions_full(),
    context_policy = ContextPolicy(max_tokens = 50)
  )

  result <- agent$run_sync("Perform the approved export")

  expect_identical(trimws(result$response), "Review complete.")
  expect_identical(effects, 1L)
  expect_identical(result$usage$requests, 3L)
  expect_identical(result$usage$tool_calls, 1L)
  expect_equal(result$usage$total_tokens, 45)
  expect_gt(result$usage$cost_usd, 0)
  expect_length(runtime_events(agent, "tool_end"), 1L)
  expect_length(runtime_events(agent, "compaction"), 1L)
  requests <- lapply(server$requests(), `[[`, "body")
  expect_null(requests[[2]]$tools)
  expect_length(requests[[2]]$messages, 1L)
  results <- Filter(
    function(message) identical(message$role, "tool"),
    requests[[3]]$messages
  )
  expect_length(results, 1L)
  expect_identical(results[[1]]$tool_call_id, "call_fixture")
  expect_match(
    jsonlite::toJSON(results[[1]]$content),
    "export-0042",
    fixed = TRUE
  )
})

test_that("a summary cannot unlock task replay after a completed tool", {
  withr::local_options(ellmer_max_tries = 1)
  server <- local_runtime_server(list(
    runtime_reply(tool = "export_findings"),
    runtime_reply("export-0042 completed."),
    runtime_failure()
  ))
  backup <- local_runtime_server(list(runtime_reply("unexpected replay")))
  chat <- runtime_compaction_chat(server)
  chat$token_count <- function(...) if (length(server$requests())) 1000 else 10
  effects <- 0L
  tool <- ellmer::tool(
    function() {
      effects <<- effects + 1L
      "export-0042"
    },
    name = "export_findings",
    description = "Export the findings"
  )
  agent <- Agent$new(
    chat,
    tools = list(tool),
    permissions = permissions_full(),
    fallback_chats = list(runtime_chat(backup)),
    context_policy = ContextPolicy(max_tokens = 50)
  )

  error <- tryCatch(
    agent$run_sync("Perform the approved export"),
    error = identity
  )

  expect_s3_class(error, "httr2_http_503")
  expect_identical(effects, 1L)
  expect_length(backup$requests(), 0L)
  expect_identical(agent$last_run()$usage$requests, 3L)
  expect_identical(agent$last_run()$usage$tool_calls, 1L)
  expect_identical(
    trimws(agent$last_compaction()$summary),
    "export-0042 completed."
  )
})

test_that("cancelling an asynchronous summary preserves history and releases the Agent", {
  reply <- runtime_reply("A late summary must not be installed.")
  attr(reply, "fixture_delay") <- 0.5
  server <- local_runtime_server(list(reply))
  backup <- local_runtime_server(list(runtime_reply("unexpected")))
  chat <- runtime_compaction_chat(server)
  before <- chat$get_turns()
  agent <- Agent$new(
    chat,
    context_policy = ContextPolicy(
      max_tokens = 50,
      fallback = "text",
      summary_fallback_chats = list(runtime_chat(backup))
    )
  )
  hooks <- compaction_hook_log(agent)
  event_loop_progress <- FALSE
  deadline <- Sys.time() + 5
  interrupt_in_flight <- function() {
    if (length(server$requests())) {
      event_loop_progress <<- TRUE
      agent$interrupt()
    } else if (Sys.time() < deadline) {
      later::later(interrupt_in_flight, 0.01)
    }
  }
  cancel_timer <- later::later(interrupt_in_flight, 0.01)
  withr::defer(cancel_timer())

  promise <- agent$run_async("Continue")
  expect_identical(promises::is.promise(promise), TRUE)
  result <- agent$.__enclos_env__$private$resolve_promise(promise)

  expect_identical(event_loop_progress, TRUE)
  expect_identical(result$stop_reason, "interrupted")
  expect_identical(result$usage$requests, 1L)
  expect_identical(result$usage$cost_usd, NA_real_)
  expect_identical(agent$get_turns(), before)
  expect_null(agent$last_compaction())
  expect_length(backup$requests(), 0L)
  expect_identical(
    hooks$events,
    c("SessionStart", "UserPromptSubmit", "PreCompact", "Stop", "SessionEnd")
  )
  expect_identical(agent$.__enclos_env__$private$run_active, FALSE)
})

test_that("compaction hooks can cancel, replace, or fail without losing the run", {
  for (action in c("cancel", "replace", "fail", "interrupt")) {
    server <- local_runtime_server(list(runtime_reply("Task response")))
    chat <- runtime_compaction_chat(server)
    before <- chat$get_turns()
    agent <- Agent$new(chat, context_policy = ContextPolicy(max_tokens = 50))
    agent$add_hook(HookMatcher$new(
      event = "PreCompact",
      timeout = 0,
      callback = function(turns_to_compact, turns_to_keep, context) {
        switch(
          action,
          cancel = list(continue = FALSE),
          replace = list(summary = "A host supplied continuation."),
          fail = cli::cli_abort("Compaction hook failed"),
          interrupt = {
            agent$interrupt()
            NULL
          }
        )
      }
    ))
    error <- tryCatch(agent$run_sync("Continue"), error = identity)
    result <- agent$last_run()

    expect_identical(agent$.__enclos_env__$private$run_active, FALSE)
    expect_length(runtime_events(agent, "stop"), 1L)
    if (action == "cancel") {
      expect_identical(agent$last_compaction()$method, "cancelled")
      expect_identical(agent$get_turns()[seq_along(before)], before)
      expect_identical(result$stop_reason, "complete")
    } else if (action == "replace") {
      expect_identical(agent$last_compaction()$method, "hook")
      expect_identical(result$usage$requests, 1L)
      expect_identical(agent$last_compaction()$usage$requests, 0L)
      expect_identical(result$stop_reason, "complete")
    } else if (action == "fail") {
      expect_identical(result$stop_reason, "complete")
      expect_identical(result$usage$requests, 2L)
      expect_length(agent$hooks$last_errors(), 1L)
      expect_identical(agent$hooks$last_errors()[[1]]$event, "PreCompact")
      expect_match(
        agent$hooks$last_errors()[[1]]$error,
        "Compaction hook failed",
        fixed = TRUE
      )
    } else {
      expect_length(server$requests(), 0L)
      expect_identical(agent$get_turns(), before)
      expect_identical(result$stop_reason, "interrupted")
    }
  }
})
