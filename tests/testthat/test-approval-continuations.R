approval_batch_reply <- function(
  values = c("a", "b", "c"),
  id_prefix = "call_"
) {
  calls <- lapply(seq_along(values), function(index) {
    list(
      index = index - 1L,
      id = paste0(id_prefix, values[[index]]),
      type = "function",
      `function` = list(
        name = "effect",
        arguments = as.character(jsonlite::toJSON(
          list(value = values[[index]]),
          auto_unbox = TRUE
        ))
      )
    )
  })
  chunks <- list(
    list(
      id = "approval_fixture",
      model = "gpt-4o-mini",
      choices = list(list(
        index = 0L,
        delta = list(
          role = "assistant",
          content = NULL,
          tool_calls = calls
        )
      ))
    ),
    list(
      id = "approval_fixture",
      model = "gpt-4o-mini",
      choices = list(list(
        index = 0L,
        delta = list(),
        finish_reason = "tool_calls"
      )),
      usage = list(
        prompt_tokens = 10L,
        completion_tokens = 5L,
        total_tokens = 15L
      )
    )
  )
  list(
    status = 200L,
    headers = list("Content-Type" = "text/event-stream"),
    body = paste0(
      paste0(
        vapply(
          chunks,
          function(chunk) {
            paste0(
              "data: ",
              jsonlite::toJSON(chunk, auto_unbox = TRUE, null = "null"),
              "\n\n"
            )
          },
          character(1)
        ),
        collapse = ""
      ),
      "data: [DONE]\n\n"
    )
  )
}

local_approval_runtime <- function(
  responses = list(approval_batch_reply(), runtime_reply(text = "finished")),
  agent_usage_limits = UsageLimits(),
  run_usage_limits = NULL,
  pause_on_b = TRUE,
  fallback_chats = list(),
  callback = NULL,
  .local_envir = parent.frame()
) {
  directory <- withr::local_tempdir(.local_envir = .local_envir)
  server <- local_runtime_server(responses, .local_envir = .local_envir)
  effects <- new.env(parent = emptyenv())
  effects$values <- character()
  tool <- ellmer::tool(
    function(value) {
      effects$values <- c(effects$values, value)
      paste0("result_", value)
    },
    name = "effect",
    description = "Record an observable effect",
    arguments = list(value = ellmer::type_string()),
    convert = FALSE,
    annotations = ellmer::tool_annotations(
      read_only_hint = FALSE,
      destructive_hint = FALSE,
      open_world_hint = FALSE
    )
  )
  callback <- callback %||%
    function(tool_name, tool_input, context) {
      if (pause_on_b && identical(tool_input$value, "b")) {
        PermissionResultPending("Approve the middle operation")
      } else {
        PermissionResultAllow()
      }
    }
  make_agent <- function(
    permissions = Permissions(can_use_tool = callback),
    tools = list(tool)
  ) {
    Agent$new(
      chat = runtime_chat(server),
      tools = tools,
      permissions = permissions,
      approval_dir = directory,
      working_dir = directory,
      usage_limits = agent_usage_limits,
      fallback_chats = fallback_chats,
      session_id = "approval_session",
      agent_id = "approval_agent"
    )
  }
  agent <- make_agent()
  result <- agent$run_sync("Perform the batch", usage_limits = run_usage_limits)
  pending <- agent$pending_approval()
  list(
    agent = agent,
    result = result,
    pending = pending,
    path = pending$source$path,
    make_agent = make_agent,
    effects = effects,
    server = server,
    tool = tool
  )
}

approval_wire_results <- function(request) {
  Filter(
    function(message) identical(message$role, "tool"),
    request$body$messages
  )
}

test_that("approval journals retain Deputy correlation without valid provider IDs", {
  for (provider_id in list(NULL, list("invalid"))) {
    directory <- withr::local_tempdir()
    agent <- Agent$new(
      chat = create_mock_chat(),
      permissions = Permissions(mode = "full"),
      approval_dir = directory
    )
    private <- agent$.__enclos_env__$private
    request <- create_mock_tool_request()
    attr(request, "id") <- provider_id
    if (is.null(provider_id)) {
      expect_no_error(private$handle_tool_request(request))
    } else {
      expect_warning(private$handle_tool_request(request), "invalid provider")
    }
    call_id <- private$tool_call_records[[1L]]$tool_call_id
    expect_match(call_id, "^tool_")
    expect_identical(private$begin_tool_execution("test_tool"), call_id)
    result <- ellmer::ContentToolResult(value = "done", request = request)
    if (is.null(provider_id)) {
      expect_no_error(private$handle_tool_result(result))
    } else {
      expect_warning(private$handle_tool_result(result), "invalid provider")
    }
    expect_named(private$.approval_journal, call_id)
    expect_identical(private$.approval_journal[[call_id]]$status, "completed")
    expect_true(private$.approval_journal[[call_id]]$executed)
    expect_identical(
      private$.approval_journal[[call_id]]$result$props$value,
      "done"
    )
    expect_null(agent$pending_approval())
  }
})

test_that("approval restart preserves classed session results and checkpoint metadata", {
  directory <- withr::local_tempdir()
  offload_directory <- withr::local_tempdir()
  server <- local_runtime_server(list(
    approval_batch_reply(c("a", "b")),
    runtime_reply(text = "finished")
  ))
  data <- data.frame(
    date = as.Date("2026-01-01") + 0:2,
    group = factor(c("a", "b", "a")),
    value = 1:3
  )
  metadata <- list(
    report = structure(
      list(groups = factor(c("accepted", "pending"))),
      class = "checkpoint_report"
    )
  )
  # Keeping every lifecycle revision would exceed the default 50 MiB store
  # during resume even though each individual state fits comfortably.
  metadata$payload <- rep(as.raw(1), 12 * 1024^2)
  effects <- character()
  tool <- ellmer::tool(
    function(value) {
      effects <<- c(effects, value)
      data
    },
    name = "effect",
    description = "Return a classed result after recording an effect",
    arguments = list(value = ellmer::type_string()),
    convert = FALSE,
    annotations = ellmer::tool_annotations(
      read_only_hint = FALSE,
      destructive_hint = FALSE,
      open_world_hint = FALSE
    )
  )
  make_agent <- function() {
    Agent$new(
      chat = runtime_chat(server),
      tools = list(tool),
      permissions = Permissions(can_use_tool = function(name, input, context) {
        if (identical(input$value, "b")) {
          PermissionResultPending("Review the second effect")
        } else {
          PermissionResultAllow()
        }
      }),
      approval_dir = directory,
      working_dir = directory,
      context_policy = ContextPolicy(
        max_tool_result_bytes = 1,
        offload_dir = offload_directory
      ),
      enable_file_checkpointing = TRUE,
      session_id = "classed_session",
      agent_id = "classed_agent"
    )
  }
  agent <- make_agent()
  agent$checkpoint("classed metadata", metadata)
  result <- agent$run_sync("Perform both effects")
  expect_identical(result$stop_reason, "approval_pending")
  expect_identical(effects, "a")
  path <- agent$pending_approval()$source$path
  saved <- approval_store_read(path)$session
  expect_identical(saved$tool_result_envelopes[[1L]]$value, data)
  expect_identical(
    saved$file_checkpoint_state$checkpoints[[1L]]$metadata,
    metadata
  )
  resumed <- make_agent()
  result <- resumed$resume_approval(path, "approve")
  expect_identical(trimws(result$response), "finished")
  expect_identical(effects, c("a", "b"))
  restored <- resumed$.__enclos_env__$private$build_session_payload()
  expect_identical(restored$tool_result_envelopes[[1L]]$value, data)
  expect_identical(
    restored$file_checkpoint_state$checkpoints[[1L]]$metadata,
    metadata
  )
  expect_identical(approval_read(path)$status, "completed")
})

test_that("session metadata cannot conceal runtime objects in attributes", {
  for (runtime in list(new.env(), function() NULL, stdout())) {
    value <- structure(1, class = "report", runtime = runtime)
    expect_error(
      approval_portable(list(metadata = value), allow_classed = TRUE),
      "runtime objects",
      class = "deputy_approval_error"
    )
  }
})

test_that("approved large outputs can install and use the session result reader", {
  directory <- withr::local_tempdir()
  offload_directory <- withr::local_tempdir()
  respond <- local({
    first <- approval_batch_reply("b")
    second <- runtime_reply(
      tool = "deputy_read_tool_result",
      arguments = list(
        reference = "RESULT_REFERENCE",
        offset = 0,
        max_chars = 100
      )
    )
    final <- runtime_reply(text = "finished reading")
    function(request, count) {
      if (count == 1L) {
        return(first)
      }
      if (count == 2L) {
        results <- Filter(
          function(x) identical(x$role, "tool"),
          request$messages
        )
        lines <- strsplit(results[[1L]]$content, "\n", fixed = TRUE)[[1L]]
        reference <- sub(
          "^reference: ",
          "",
          lines[startsWith(lines, "reference: ")][[1L]]
        )
        second$body <- gsub(
          "RESULT_REFERENCE",
          reference,
          second$body,
          fixed = TRUE
        )
        return(second)
      }
      final
    }
  })
  server <- local_runtime_server(respond)
  effects <- new.env(parent = emptyenv())
  effects$count <- 0L
  payload <- paste(rep("approved output receipt", 4000), collapse = "\n")
  tool <- ellmer::tool(
    function(value) {
      effects$count <- effects$count + 1L
      payload
    },
    name = "effect",
    description = "Return the large approved output",
    arguments = list(value = ellmer::type_string()),
    convert = FALSE,
    annotations = ellmer::tool_annotations(
      read_only_hint = FALSE,
      destructive_hint = FALSE,
      open_world_hint = FALSE
    )
  )
  make_agent <- function() {
    Agent$new(
      chat = runtime_chat(server),
      tools = list(tool),
      permissions = Permissions(
        tool_allowlist = "effect",
        can_use_tool = function(name, input, context) {
          if (name == "effect") {
            PermissionResultPending("Review the output")
          } else {
            PermissionResultAllow()
          }
        }
      ),
      context_policy = ContextPolicy(offload_dir = offload_directory),
      approval_dir = directory,
      working_dir = directory,
      session_id = "large_approval_session",
      agent_id = "large_approval_agent"
    )
  }
  agent <- make_agent()
  expect_identical(
    agent$run_sync("Prepare the output")$stop_reason,
    "approval_pending"
  )
  path <- agent$pending_approval()$source$path
  expect_false(
    "deputy_read_tool_result" %in% names(approval_store_read(path)$tools)
  )
  resumed <- make_agent()
  result <- resumed$resume_approval(path, "approve")
  expect_identical(trimws(result$response), "finished reading")
  expect_identical(effects$count, 1L)
  expect_length(server$requests(), 3L)
  reader_result <- tail(approval_wire_results(server$requests()[[3L]]), 1L)[[
    1L
  ]]
  expect_identical(reader_result$tool_call_id, "call_fixture")
  expect_match(reader_result$content, "approved output receipt")
  expect_true(
    "deputy_read_tool_result" %in% names(approval_store_read(path)$tools)
  )
  expect_identical(approval_read(path)$status, "completed")
})

test_that("resumed effects prevent fallback from discarding the completed result", {
  withr::local_options(ellmer_max_tries = 1)
  backup <- local_runtime_server(list(runtime_reply("unexpected fallback")))
  fixture <- local_approval_runtime(
    responses = list(approval_batch_reply(), runtime_failure()),
    fallback_chats = list(runtime_chat(backup))
  )
  resumed <- fixture$make_agent()
  expect_error(
    resumed$resume_approval(fixture$path, "approve"),
    class = "httr2_http_503"
  )
  expect_identical(fixture$effects$values, c("a", "b"))
  expect_length(backup$requests(), 0L)
  results <- approval_wire_results(fixture$server$requests()[[2L]])
  expect_identical(results[[2L]]$tool_call_id, "call_b")
  expect_identical(results[[2L]]$content, "result_b")
  expect_identical(approval_read(fixture$path)$status, "stopped")
  expect_identical(resumed$last_run()$usage$tool_calls, 2L)
})

test_that("approval suspension preserves a complete batch without running later siblings", {
  fixture <- local_approval_runtime()
  expect_identical(fixture$result$stop_reason, "approval_pending")
  expect_identical(fixture$effects$values, "a")
  expect_s7_class(fixture$pending, ApprovalContinuation)
  expect_identical(fixture$pending$status, "pending")
  expect_identical(fixture$pending$request$tool_input, list(value = "b"))
  expect_identical(
    fixture$pending$effects$call_a$result$props$value,
    "result_a"
  )
  expect_null(fixture$pending$effects$call_c)
  expect_length(fixture$server$requests(), 1L)

  # Recreate the Agent from the public host configuration, without sharing Chat
  # or runtime state with the suspended instance.
  resumed <- fixture$make_agent()
  result <- resumed$resume_approval(fixture$path, "approve")
  expect_identical(trimws(result$response), "finished")
  expect_identical(fixture$effects$values, c("a", "b"))
  expect_identical(approval_read(fixture$path)$status, "completed")
  expect_identical(
    approval_read(fixture$path)$source$session_id,
    "approval_session"
  )

  requests <- fixture$server$requests()
  expect_length(requests, 2L)
  results <- approval_wire_results(requests[[2L]])
  expect_identical(
    vapply(results, `[[`, character(1), "tool_call_id"),
    c("call_a", "call_b", "call_c")
  )
  expect_match(results[[1L]]$content, "result_a")
  expect_match(results[[2L]]$content, "result_b")
  expect_match(results[[3L]]$content, "Not executed")
  requests_with_tools <- Filter(
    function(message) !is.null(message$tool_calls),
    requests[[2L]]$body$messages
  )
  expect_length(requests_with_tools, 1L)
  expect_identical(
    vapply(requests_with_tools[[1L]]$tool_calls, `[[`, character(1), "id"),
    c("call_a", "call_b", "call_c")
  )
  expect_error(
    resumed$resume_approval(fixture$path, "approve"),
    class = "deputy_approval_consumed"
  )
  expect_identical(fixture$effects$values, c("a", "b"))
  expect_length(fixture$server$requests(), 2L)
})

test_that("denial resumes with a correlated result and executes no pending operation", {
  fixture <- local_approval_runtime()
  resumed <- fixture$make_agent()
  result <- resumed$resume_approval(fixture$path, "deny")
  expect_identical(trimws(result$response), "finished")
  expect_identical(fixture$effects$values, "a")
  snapshot <- approval_read(fixture$path)
  expect_identical(snapshot$decision$decision, "deny")
  expect_identical(snapshot$status, "completed")
  expect_false(snapshot$effects$call_b$executed)
  results <- approval_wire_results(fixture$server$requests()[[2L]])
  expect_identical(results[[2L]]$tool_call_id, "call_b")
  expect_match(results[[2L]]$content, "denied")
  expect_match(results[[3L]]$content, "Not executed")
})

test_that("host edits are rechecked and used consistently in the restored request and effect", {
  fixture <- local_approval_runtime()
  checked <- new.env(parent = emptyenv())
  checked$inputs <- list()
  resumed <- fixture$make_agent(
    permissions = Permissions(can_use_tool = function(
      tool_name,
      tool_input,
      context
    ) {
      checked$inputs[[length(checked$inputs) + 1L]] <- tool_input
      PermissionResultAllow()
    })
  )
  result <- resumed$resume_approval(
    fixture$path,
    "approve",
    tool_input = list(value = "edited")
  )
  expect_identical(trimws(result$response), "finished")
  expect_identical(fixture$effects$values, c("a", "edited"))
  expect_true(any(vapply(
    checked$inputs,
    identical,
    logical(1),
    list(value = "edited")
  )))
  expect_identical(
    approval_read(fixture$path)$decision$tool_input,
    list(value = "edited")
  )
  wire <- fixture$server$requests()[[2L]]
  requests <- Filter(
    function(message) !is.null(message$tool_calls),
    wire$body$messages
  )
  expect_identical(
    jsonlite::fromJSON(requests[[1L]]$tool_calls[[2L]]$`function`$arguments),
    list(value = "edited")
  )
  expect_match(approval_wire_results(wire)[[2L]]$content, "result_edited")
})

test_that("current static authority and callback denials still govern host-approved inputs", {
  fixture <- local_approval_runtime()
  resumed <- fixture$make_agent(
    permissions = Permissions(
      tool_denylist = "effect",
      can_use_tool = function(...) PermissionResultAllow()
    )
  )
  result <- resumed$resume_approval(fixture$path, "approve")
  expect_identical(trimws(result$response), "finished")
  expect_identical(fixture$effects$values, "a")
  results <- approval_wire_results(fixture$server$requests()[[2L]])
  expect_match(
    results[[2L]]$content,
    "denied|deny|allow|authority",
    ignore.case = TRUE
  )
  expect_false(approval_read(fixture$path)$effects$call_b$executed)

  fixture2 <- local_approval_runtime()
  resumed2 <- fixture2$make_agent(
    permissions = Permissions(
      can_use_tool = function(...) {
        PermissionResultDeny("Current host refuses this operation")
      }
    )
  )
  resumed2$resume_approval(
    fixture2$path,
    "approve",
    tool_input = list(value = "edited")
  )
  expect_identical(fixture2$effects$values, "a")
  expect_match(
    approval_wire_results(fixture2$server$requests()[[2L]])[[2L]]$content,
    "Current host refuses"
  )
})

test_that("missing callbacks and changed or missing tool definitions cannot consume approvals", {
  fixture <- local_approval_runtime()
  no_callback <- fixture$make_agent(permissions = Permissions())
  expect_error(
    no_callback$resume_approval(fixture$path, "approve"),
    "callback",
    class = "deputy_approval_error"
  )
  expect_identical(approval_read(fixture$path)$status, "pending")
  no_tool <- fixture$make_agent(tools = list())
  expect_error(
    no_tool$resume_approval(fixture$path, "approve"),
    "tool definition",
    class = "deputy_approval_error"
  )
  expect_identical(approval_read(fixture$path)$status, "pending")
  changed <- ellmer::tool(
    function(value) value,
    name = "effect",
    description = "A different definition",
    arguments = list(value = ellmer::type_string()),
    convert = FALSE
  )
  changed_tool <- fixture$make_agent(tools = list(changed))
  expect_error(
    changed_tool$resume_approval(fixture$path, "approve"),
    "tool definition",
    class = "deputy_approval_error"
  )
  expect_identical(approval_read(fixture$path)$status, "pending")
  expect_identical(fixture$effects$values, "a")
  expect_length(fixture$server$requests(), 1L)
  expect_no_error(fixture$make_agent()$resume_approval(fixture$path, "approve"))
  expect_identical(fixture$effects$values, c("a", "b"))
})

test_that("completed and denied operations cannot be replayed by a subsequent model request", {
  fixture <- local_approval_runtime(
    responses = list(
      approval_batch_reply(),
      approval_batch_reply(c("a", "b"), id_prefix = "retry_"),
      runtime_reply(text = "finished")
    )
  )
  expect_warning(
    fixture$make_agent()$resume_approval(fixture$path, "deny"),
    "Failed to evaluate 2 tool calls"
  )
  expect_identical(fixture$effects$values, "a")
  requests <- fixture$server$requests()
  expect_length(requests, 3L)
  results <- tail(approval_wire_results(requests[[3L]]), 2L)
  expect_true(all(vapply(
    results,
    function(result) grepl("already executed or denied", result$content),
    logical(1)
  )))
})

test_that("permission denials before suspension survive a later callback allowance", {
  attempts <- 0L
  fixture <- local_approval_runtime(
    responses = list(
      approval_batch_reply(),
      approval_batch_reply("a", id_prefix = "retry_"),
      runtime_reply(text = "finished")
    ),
    callback = function(tool_name, tool_input, context) {
      if (identical(tool_input$value, "a")) {
        attempts <<- attempts + 1L
        if (attempts == 1L) return(PermissionResultDeny("Refuse a"))
      }
      if (identical(tool_input$value, "b")) {
        PermissionResultPending("Approve b")
      } else {
        PermissionResultAllow()
      }
    }
  )
  signature <- tool_request_signature("effect", list(value = "a"))
  expect_true(
    signature %in% approval_store_read(fixture$path)$denied_signatures
  )
  expect_warning(
    fixture$make_agent()$resume_approval(fixture$path, "approve"),
    "Failed to evaluate 1 tool call"
  )
  expect_identical(fixture$effects$values, "b")
  expect_identical(attempts, 1L)
  result <- tail(approval_wire_results(fixture$server$requests()[[3L]]), 1L)
  expect_match(result[[1L]]$content, "already executed or denied")
})

test_that("permission denials during resume are persisted before a model retry", {
  fixture <- local_approval_runtime(
    responses = list(
      approval_batch_reply(),
      approval_batch_reply("b", id_prefix = "retry_"),
      runtime_reply(text = "finished")
    )
  )
  attempts <- 0L
  resumed <- fixture$make_agent(
    permissions = Permissions(
      can_use_tool = function(tool_name, tool_input, context) {
        attempts <<- attempts + 1L
        if (attempts == 1L) {
          PermissionResultDeny("Refuse the approved operation")
        } else {
          PermissionResultAllow()
        }
      }
    )
  )
  expect_warning(
    resumed$resume_approval(fixture$path, "approve"),
    "Failed to evaluate 1 tool call"
  )
  expect_identical(fixture$effects$values, "a")
  expect_identical(attempts, 1L)
  signature <- tool_request_signature("effect", list(value = "b"))
  expect_true(
    signature %in% approval_store_read(fixture$path)$denied_signatures
  )
  result <- tail(approval_wire_results(fixture$server$requests()[[3L]]), 1L)
  expect_match(result[[1L]]$content, "already executed or denied")
})

check_interrupted_approval <- function(abrupt = FALSE) {
  directory <- withr::local_tempdir()
  receipt <- file.path(directory, "effect-receipt.txt")
  server <- local_runtime_server(list(
    approval_batch_reply("b"),
    runtime_reply(text = "finished")
  ))
  exit_after_effect <- FALSE
  abrupt_exit <- FALSE
  tool <- ellmer::tool(
    function(value) {
      cat(value, "\n", file = receipt, append = TRUE, sep = "")
      if (abrupt_exit) {
        tools::pskill(Sys.getpid(), signal = 9L)
      }
      if (exit_after_effect) {
        quit(save = "no", status = 0, runLast = FALSE)
      }
      value
    },
    name = "effect",
    description = "Write an effect receipt",
    arguments = list(value = ellmer::type_string()),
    convert = FALSE,
    annotations = ellmer::tool_annotations(
      read_only_hint = FALSE,
      destructive_hint = FALSE,
      open_world_hint = FALSE
    )
  )
  agent <- Agent$new(
    chat = runtime_chat(server),
    tools = list(tool),
    permissions = Permissions(can_use_tool = function(...) {
      PermissionResultPending()
    }),
    approval_dir = directory,
    working_dir = directory,
    session_id = "approval_crash_session",
    agent_id = "approval_crash_agent"
  )
  agent$run_sync("Write the receipt")
  path <- agent$pending_approval()$source$path
  expect_false(file.exists(receipt))

  # The child gets only the store path and the host's configuration. It has no
  # access to the suspended Chat, closures, or execution journal in memory.
  child <- callr::r_bg(
    function(package_path, path, directory, receipt, url, abrupt) {
      if (file.exists(file.path(package_path, "R", "agent.R"))) {
        pkgload::load_all(package_path, quiet = TRUE)
      } else {
        library(deputy, lib.loc = dirname(package_path))
      }
      exit_after_effect <- TRUE
      abrupt_exit <- abrupt
      tool <- ellmer::tool(
        function(value) {
          cat(value, "\n", file = receipt, append = TRUE, sep = "")
          if (abrupt_exit) {
            tools::pskill(Sys.getpid(), signal = 9L)
          }
          if (exit_after_effect) {
            quit(save = "no", status = 0, runLast = FALSE)
          }
          value
        },
        name = "effect",
        description = "Write an effect receipt",
        arguments = list(value = ellmer::type_string()),
        convert = FALSE,
        annotations = ellmer::tool_annotations(
          read_only_hint = FALSE,
          destructive_hint = FALSE,
          open_world_hint = FALSE
        )
      )
      restored <- Agent$new(
        chat = ellmer::chat_openai_compatible(
          base_url = url,
          credentials = function() "fixture",
          model = "gpt-4o-mini",
          echo = "none"
        ),
        tools = list(tool),
        permissions = Permissions(can_use_tool = function(...) {
          PermissionResultPending()
        }),
        approval_dir = directory,
        working_dir = directory,
        session_id = "approval_crash_session",
        agent_id = "approval_crash_agent"
      )
      restored$resume_approval(path, "approve")
    },
    args = list(
      getNamespaceInfo(asNamespace("deputy"), "path"),
      path,
      directory,
      receipt,
      server$url,
      abrupt
    ),
    libpath = .libPaths()
  )
  withr::defer(child$kill())
  child$wait(timeout = 10000)
  expect_false(child$is_alive())
  if (!child$get_exit_status() %in% c(0L, -9L)) {
    child$get_result()
  }
  expect_identical(child$get_exit_status(), if (abrupt) -9L else 0L)
  expect_true(file.exists(receipt))
  expect_identical(readLines(receipt), "b")
  snapshot <- approval_read(path)
  expect_identical(
    snapshot$status,
    if (abrupt) "executing" else "indeterminate"
  )
  expect_identical(snapshot$effects$call_b$status, "executing")
  expect_true(snapshot$effects$call_b$executed)
  expect_null(snapshot$effects$call_b$result)
  expect_error(
    agent$resume_approval(path, "approve"),
    class = "deputy_approval_consumed"
  )
  expect_identical(readLines(receipt), "b")
  expect_length(server$requests(), 1L)
}

test_that("graceful process exit during an effect leaves an indeterminate record", {
  check_interrupted_approval()
})

test_that("abrupt process death preserves the executing journal and cannot replay", {
  skip_on_os("windows")
  check_interrupted_approval(abrupt = TRUE)
})

test_that("budget approval requires an explicit allowance bounded by the saved Agent ceiling", {
  fixture <- local_approval_runtime(
    responses = list(
      approval_batch_reply("b"),
      runtime_reply(text = "finished")
    ),
    agent_usage_limits = UsageLimits(max_tool_calls = 5),
    run_usage_limits = UsageLimits(max_tool_calls = 0),
    pause_on_b = FALSE
  )
  expect_identical(fixture$result$stop_reason, "approval_pending")
  expect_identical(fixture$effects$values, character())
  expect_equal(fixture$pending$usage$tool_calls, 1)
  resumed <- fixture$make_agent()
  expect_error(
    resumed$resume_approval(fixture$path, "approve"),
    class = "deputy_approval_budget_exhausted"
  )
  expect_identical(approval_read(fixture$path)$status, "pending")
  expect_length(fixture$server$requests(), 1L)
  result <- resumed$resume_approval(
    fixture$path,
    "approve",
    usage_limits = UsageLimits(max_tool_calls = 2)
  )
  expect_identical(trimws(result$response), "finished")
  expect_identical(fixture$effects$values, "b")
  expect_equal(result$usage$tool_calls, 1)
  snapshot <- approval_read(fixture$path)
  expect_equal(snapshot$usage$tool_calls, 1)
  expect_equal(snapshot$usage_limits$max_tool_calls, 2)

  wider <- local_approval_runtime(
    responses = list(
      approval_batch_reply("b"),
      runtime_reply(text = "finished")
    ),
    agent_usage_limits = UsageLimits(max_tool_calls = 5),
    run_usage_limits = UsageLimits(max_tool_calls = 0),
    pause_on_b = FALSE
  )
  wider$make_agent()$resume_approval(
    wider$path,
    "approve",
    usage_limits = UsageLimits(max_tool_calls = 99)
  )
  expect_equal(approval_read(wider$path)$usage_limits$max_tool_calls, 5)
  expect_identical(wider$effects$values, "b")
})

test_that("denials remain effective across subsequent approval continuations", {
  fixture <- local_approval_runtime(
    responses = list(
      approval_batch_reply(),
      approval_batch_reply("d"),
      approval_batch_reply("b", id_prefix = "retry_"),
      runtime_reply(text = "finished")
    )
  )
  policy <- Permissions(can_use_tool = function(
    tool_name,
    tool_input,
    context
  ) {
    PermissionResultPending("Review this next operation")
  })
  first <- fixture$make_agent(permissions = policy)
  result <- first$resume_approval(fixture$path, "deny")
  expect_identical(result$stop_reason, "approval_pending")
  next_pending <- first$pending_approval()
  expect_identical(next_pending$request$tool_input, list(value = "d"))
  expect_identical(fixture$effects$values, "a")
  next_agent <- fixture$make_agent(permissions = policy)
  expect_warning(
    completed <- next_agent$resume_approval(
      next_pending$source$path,
      "approve"
    ),
    "already executed or denied"
  )
  expect_identical(trimws(completed$response), "finished")
  expect_identical(fixture$effects$values, c("a", "d"))
  expect_match(
    tail(approval_wire_results(fixture$server$requests()[[4L]]), 1L)[[
      1L
    ]]$content,
    "already executed or denied"
  )
})

test_that("approval inspection is read-only and edited inputs must be finite JSON", {
  fixture <- local_approval_runtime()
  snapshot <- approval_read(fixture$path)
  expect_error(snapshot@status <- "completed", "read.only|read only")
  expect_identical(snapshot$request$tool_call_id, "call_b")
  expect_true(snapshot$permissions$callback_required)
  expect_s7_class(snapshot$budget_ceiling, UsageLimits)
  for (value in list(NA_character_, Inf, function() NULL, new.env())) {
    expect_error(
      fixture$make_agent()$resume_approval(
        fixture$path,
        "approve",
        tool_input = list(value = value)
      ),
      class = "deputy_approval_error"
    )
    expect_identical(approval_read(fixture$path)$status, "pending")
  }
  expect_identical(fixture$effects$values, "a")
  expect_length(fixture$server$requests(), 1L)
})

test_that("resumed approvals retain current host context and current hook denials", {
  fixture <- local_approval_runtime()
  seen <- new.env(parent = emptyenv())
  seen$context <- NULL
  seen$hook <- FALSE
  resumed <- Agent$new(
    chat = runtime_chat(fixture$server),
    tools = list(fixture$tool),
    permissions = Permissions(can_use_tool = function(
      tool_name,
      tool_input,
      context
    ) {
      seen$context <- context$run_context
      PermissionResultAllow()
    }),
    approval_dir = dirname(fixture$path),
    working_dir = dirname(fixture$path),
    session_id = "approval_session",
    agent_id = "approval_agent",
    run_context = list(host_marker = "current")
  )
  resumed$add_hook(HookMatcher(event = "PreToolUse", callback = function(...) {
    seen$hook <- TRUE
    HookResultPreToolUse(permission = "deny", reason = "Current hook refuses")
  }))
  resumed$resume_approval(fixture$path, "approve")
  expect_identical(seen$context$host_marker, "current")
  expect_true(seen$hook)
  expect_identical(fixture$effects$values, "a")
  result <- approval_wire_results(fixture$server$requests()[[2L]])[[2L]]
  expect_identical(result$tool_call_id, "call_b")
  expect_match(result$content, "Current hook refuses")
})

test_that("resumed approvals honor stop-after-tool hooks without bypassing denials", {
  for (permission in c("allow", "deny")) {
    fixture <- local_approval_runtime()
    resumed <- fixture$make_agent()
    resumed$add_hook(HookMatcher(
      event = "PreToolUse",
      callback = function(...) {
        HookResultPreToolUse(
          continue = FALSE,
          permission = permission,
          reason = "Current hook decision",
          stop_reason = "stop_after_approved_tool"
        )
      }
    ))
    result <- resumed$resume_approval(fixture$path, "approve")
    expect_identical(result$stop_reason, "stop_after_approved_tool")
    expect_identical(
      fixture$effects$values,
      if (permission == "allow") c("a", "b") else "a"
    )
    expect_length(fixture$server$requests(), 1L)
    snapshot <- approval_read(fixture$path)
    expect_identical(snapshot$status, "stopped")
    expect_identical(snapshot$effects$call_b$executed, permission == "allow")
    if (permission == "allow") {
      expect_identical(snapshot$effects$call_b$result$props$value, "result_b")
    } else {
      expect_match(
        snapshot$effects$call_b$result$props$error,
        "Current hook decision"
      )
    }
  }
})

test_that("an exhausted allowance still permits a correlated denial without another model call", {
  fixture <- local_approval_runtime(
    responses = list(approval_batch_reply("b")),
    agent_usage_limits = UsageLimits(max_tool_calls = 5),
    run_usage_limits = UsageLimits(max_tool_calls = 0),
    pause_on_b = FALSE
  )
  resumed <- fixture$make_agent()
  result <- resumed$resume_approval(fixture$path, "deny")
  expect_identical(result$stop_reason, "tool_call_limit")
  expect_identical(fixture$effects$values, character())
  expect_length(fixture$server$requests(), 1L)
  snapshot <- approval_read(fixture$path)
  expect_identical(snapshot$decision$decision, "deny")
  expect_false(snapshot$effects$call_b$executed)
  expect_match(snapshot$effects$call_b$result$props$error, "host denied")
  result_turn <- tail(resumed$get_turns(), 1L)[[1L]]
  expect_s3_class(result_turn, "ellmer::UserTurn")
  expect_identical(result_turn@contents[[1L]]@request@id, "call_b")
})
