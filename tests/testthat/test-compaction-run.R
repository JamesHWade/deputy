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

test_that("stopped compaction retains settled results through save, load, and resume", {
  withr::local_options(ellmer_max_tries = 1)
  for (outcome in c("failure", "cancel", "budget")) {
    summary <- if (outcome == "failure") {
      runtime_failure()
    } else {
      runtime_reply("Export completed.")
    }
    if (outcome == "cancel") {
      attr(summary, "fixture_delay") <- 0.5
    }
    server <- local_runtime_server(list(
      runtime_reply(tool = "export_findings"),
      summary,
      runtime_reply("Continued without repeating the export.")
    ))
    chat <- runtime_compaction_chat(server, name = "OpenAI")
    chat$token_count <- function(...) {
      if (
        any(vapply(
          list(...),
          inherits,
          logical(1),
          what = "ellmer::ContentToolResult"
        ))
      ) {
        1000
      } else {
        10
      }
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
      context_policy = ContextPolicy(max_tokens = 50),
      usage_limits = UsageLimits(
        max_requests = if (outcome == "budget") 2 else 25
      )
    )
    if (outcome == "cancel") {
      deadline <- Sys.time() + 5
      cancel_summary <- function() {
        if (length(server$requests()) >= 2L) {
          agent$interrupt()
        } else if (Sys.time() < deadline) {
          later::later(cancel_summary, 0.01)
        }
      }
      cancel_timer <- later::later(cancel_summary, 0.01)
    }
    error <- tryCatch(
      agent$run_sync("Perform the approved export"),
      error = identity
    )
    if (outcome == "cancel") {
      cancel_timer()
    }
    if (outcome == "failure") {
      expect_s3_class(error, "deputy_compaction_error")
    }
    result <- agent$last_run()
    expect_identical(
      result$stop_reason,
      switch(
        outcome,
        failure = "error",
        cancel = "interrupted",
        budget = "request_limit"
      )
    )
    expect_identical(result$usage$requests, 2L)
    expect_identical(result$usage$tool_calls, 1L)
    expect_equal(result$usage$total_tokens, if (outcome == "budget") 30 else 15)
    if (outcome == "budget") {
      expect_gt(result$usage$cost_usd, 0)
    } else {
      expect_identical(result$usage$cost_usd, NA_real_)
    }
    turns <- agent$get_turns()
    expect_s3_class(tail(turns, 1L)[[1]], "ellmer::UserTurn")
    results <- Filter(
      function(content) inherits(content, "ellmer::ContentToolResult"),
      unlist(lapply(turns, function(turn) turn@contents), recursive = FALSE)
    )
    expect_length(results, 1L)
    expect_identical(effects, 1L)
    expect_length(server$requests(), 2L)
    # No assistant was synthesized at the stopped dispatch boundary.
    expect_s3_class(tail(turns, 2L)[[1]], "ellmer::AssistantTurn")
    expect_equal(tail(turns, 2L)[[1]]@tokens[["input"]], 10)

    path <- withr::local_tempfile(fileext = ".rds")
    suppressWarnings(suppressMessages(agent$save_session(path)))
    restored <- Agent$new(
      runtime_chat(server, name = "OpenAI"),
      tools = list(tool),
      permissions = permissions_full()
    )
    suppressMessages(restored$load_session(path))
    expect_length(restored$get_turns(), length(turns))
    restored_result <- tail(restored$get_turns(), 1L)[[1]]@contents[[1]]
    expect_s3_class(restored_result, "ellmer::ContentToolResult")
    expect_equal(restored_result@value, results[[1]]@value)
    expect_identical(restored_result@request@id, results[[1]]@request@id)
    counts <- local_runtime_server(rep(
      list(list(
        status = 200L,
        headers = list("Content-Type" = "application/json"),
        body = '{"input_tokens":7}'
      )),
      2L
    ))
    estimator <- Agent$new(ellmer::chat_openai(
      base_url = counts$url,
      model = "gpt-4o-mini",
      credentials = function() "fixture"
    ))
    estimator$set_turns(restored$get_turns())
    estimate_before <- estimator$.__enclos_env__$private$context_token_count(list(
      "Continue"
    ))
    expect_equal(estimate_before, 22)
    expect_match(
      jsonlite::toJSON(counts$requests()[[1]]$body),
      "export-0042",
      fixed = TRUE
    )
    resumed <- restored$run_sync("Continue using the completed export")
    expect_identical(
      trimws(resumed$response),
      "Continued without repeating the export."
    )
    expect_identical(resumed$usage$requests, 1L)
    expect_identical(resumed$usage$tool_calls, 0L)
    expect_equal(resumed$usage$total_tokens, 15)
    expect_gt(resumed$usage$cost_usd, 0)
    expect_identical(effects, 1L)
    messages <- server$requests()[[3]]$body$messages
    wire_results <- Filter(
      function(message) identical(message$role, "tool"),
      messages
    )
    expect_length(wire_results, 1L)
    expect_identical(wire_results[[1]]$tool_call_id, "call_fixture")
    expect_match(
      jsonlite::toJSON(wire_results[[1]]$content),
      "export-0042",
      fixed = TRUE
    )
    estimator$set_turns(restored$get_turns())
    estimate_after <- estimator$.__enclos_env__$private$context_token_count(list(
      "Continue"
    ))
    expect_equal(estimate_after, 22)
    expect_identical(
      vapply(counts$requests(), `[[`, character(1), "path"),
      rep("/v1/responses/input_tokens", 2L)
    )
    expect_equal(
      provider_usage_summary(restored$.__enclos_env__$private$.chat)$input,
      sum(
        vapply(
          Filter(
            function(turn) inherits(turn, "ellmer::AssistantTurn"),
            restored$get_turns()
          ),
          function(turn) turn@tokens[[1L]],
          numeric(1)
        ),
        na.rm = TRUE
      )
    )
  }
})

test_that("host edits during an asynchronous summary reject stale replacement", {
  for (edit in c("turns", "system_prompt")) {
    reply <- runtime_reply("Stale summary")
    attr(reply, "fixture_delay") <- 0.2
    server <- local_runtime_server(list(reply))
    agent <- Agent$new(
      runtime_compaction_chat(server),
      context_policy = ContextPolicy(max_tokens = 50)
    )
    replacement <- list(ellmer::UserTurn("Host replacement"))
    changed <- FALSE
    deadline <- Sys.time() + 5
    edit_host <- function() {
      if (length(server$requests())) {
        if (edit == "turns") {
          agent$set_turns(replacement)
        } else {
          agent$set_system_prompt("New host policy")
        }
        changed <<- TRUE
      } else if (Sys.time() < deadline) {
        later::later(edit_host, 0.01)
      }
    }
    timer <- later::later(edit_host, 0.01)
    error <- tryCatch(agent$run_sync("Continue"), error = identity)
    timer()
    expect_true(changed)
    expect_s3_class(error, "deputy_compaction_conflict")
    if (edit == "turns") {
      expect_identical(agent$get_turns(), replacement)
    } else {
      expect_identical(agent$get_system_prompt(), "New host policy")
    }
    expect_null(agent$last_compaction())
    expect_identical(agent$last_run()$usage$requests, 1L)
    expect_identical(agent$last_run()$stop_reason, "error")
    expect_length(server$requests(), 1L)
  }
})

test_that("host history replacement preserves accrued task and summary usage", {
  reply <- runtime_reply("Stale summary")
  attr(reply, "fixture_delay") <- 0.2
  server <- local_runtime_server(list(
    runtime_reply(tool = "export_findings"),
    reply
  ))
  chat <- runtime_compaction_chat(server, name = "OpenAI")
  chat$token_count <- function(...) if (length(server$requests())) 1000 else 10
  tool <- ellmer::tool(
    function() "export-0042",
    name = "export_findings",
    description = "Export"
  )
  agent <- Agent$new(
    chat,
    tools = list(tool),
    permissions = permissions_full(),
    context_policy = ContextPolicy(max_tokens = 50)
  )
  replacement <- list(ellmer::UserTurn("Host reset"))
  deadline <- Sys.time() + 5
  edit_host <- function() {
    if (length(server$requests()) >= 2L) {
      agent$set_turns(replacement)
    } else if (Sys.time() < deadline) {
      later::later(edit_host, 0.01)
    }
  }
  timer <- later::later(edit_host, 0.01)
  withr::defer(timer())
  error <- tryCatch(agent$run_sync("Export"), error = identity)

  expect_s3_class(error, "deputy_compaction_conflict")
  expect_identical(agent$get_turns(), replacement)
  expect_identical(agent$last_run()$usage$requests, 2L)
  expect_identical(agent$last_run()$usage$tool_calls, 1L)
  expect_equal(agent$last_run()$usage$total_tokens, 30)
  expect_gt(agent$last_run()$usage$cost_usd, 0)
  expect_length(runtime_events(agent, "request_end"), 2L)
  expect_length(runtime_events(agent, "tool_end"), 1L)
  expect_length(server$requests(), 2L)
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
      expect_identical(agent$last_compaction()$run_id, result$run_id)
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

test_that("compaction IDs distinguish automatic no-ops from manual work after a run", {
  server <- local_runtime_server(list(runtime_reply("Task complete")))
  chat <- runtime_compaction_chat(server)
  chat$set_turns(list(
    ellmer::UserTurn("Previous task"),
    ellmer::AssistantTurn("Previous response")
  ))
  agent <- Agent$new(chat, context_policy = ContextPolicy(max_tokens = 50))

  result <- agent$run_sync("Continue")
  expect_identical(agent$last_compaction()$method, "none")
  expect_identical(agent$last_compaction()$run_id, result$run_id)
  expect_length(server$requests(), 1L)

  manual <- agent$compact(keep_last = 0, summary = "Manual continuation")
  expect_identical(manual$method, "custom")
  expect_null(manual$run_id)
  expect_identical(agent$last_run()$run_id, result$run_id)
  expect_null(agent$compact()$run_id)
})
