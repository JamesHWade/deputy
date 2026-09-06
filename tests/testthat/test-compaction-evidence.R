test_that("compaction includes tool evidence without private display metadata", {
  server <- local_runtime_server(list(
    runtime_reply(
      tool = "source_read",
      arguments = list(item_id = "assay-C-r3")
    ),
    runtime_reply("Source inspected."),
    runtime_reply("Ready for the next checkpoint."),
    runtime_reply("C uses denominator 84, page 17.", stream = FALSE)
  ))
  source <- ellmer::tool(
    function(item_id) {
      ellmer::ContentToolResult(
        value = "Document assay-C-r3: denominator 84, page 17.",
        extra = list(private_display_metadata = "HOST-ONLY-SECRET")
      )
    },
    name = "source_read",
    description = "Read an evidence source.",
    arguments = list(item_id = ellmer::type_string()),
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE
    )
  )
  agent <- Agent$new(runtime_chat(server), tools = list(source))
  agent$run_sync("Inspect the source.")
  agent$run_sync("Move to the next checkpoint.")
  agent$compact(keep_last = 2L)

  prompt <- jsonlite::toJSON(tail(server$requests(), 1L)[[1]]$body)
  expect_match(
    prompt,
    "Document assay-C-r3: denominator 84, page 17.",
    fixed = TRUE
  )
  expect_match(prompt, "source_read", fixed = TRUE)
  expect_no_match(prompt, "HOST-ONLY-SECRET", fixed = TRUE)
})

test_that("degraded text compaction retains bounded tool evidence", {
  withr::local_options(ellmer_max_tries = 1)
  server <- local_runtime_server(list(
    runtime_reply(tool = "source_read"),
    runtime_reply("Source inspected."),
    runtime_failure(401L)
  ))
  source <- ellmer::tool(
    function() {
      ellmer::ContentToolResult(
        value = list(ellmer::ContentText(
          "Document assay-C-r3: denominator 84, page 17."
        )),
        extra = list(private = "HOST-ONLY-SECRET")
      )
    },
    name = "source_read",
    description = "Read source evidence.",
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE
    )
  )
  agent <- Agent$new(runtime_chat(server), tools = list(source))
  agent$run_sync("Inspect the source.")
  result <- agent$compact(keep_last = 0L, fallback = "text")
  expect_identical(result$method, "text")
  expect_match(result$summary, "denominator 84, page 17", fixed = TRUE)
  expect_no_match(result$summary, "HOST-ONLY-SECRET", fixed = TRUE)
  expect_match(
    agent$get_system_prompt(),
    "denominator 84, page 17",
    fixed = TRUE
  )
  expect_length(server$requests(), 3L)
})

test_that("compaction preserves documented non-string ellmer tool payloads", {
  for (value in list(
    ellmer::ContentText("Evidence: denominator 84, page 17."),
    list(
      ellmer::ContentText("Evidence: denominator 84"),
      ellmer::ContentText("page 17.")
    ),
    c(84L, 17L)
  )) {
    server <- local_runtime_server(list(
      runtime_reply(tool = "source_read"),
      runtime_reply("Source inspected."),
      runtime_reply("C uses denominator 84, page 17.", stream = FALSE)
    ))
    source <- ellmer::tool(
      function() {
        ellmer::ContentToolResult(
          value = value,
          extra = list(private = "HOST-ONLY-SECRET")
        )
      },
      name = "source_read",
      description = "Read source evidence.",
      annotations = ellmer::tool_annotations(
        read_only_hint = TRUE,
        open_world_hint = FALSE
      )
    )
    agent <- Agent$new(
      runtime_chat(server),
      tools = list(source),
      context_policy = ContextPolicy(max_tool_result_bytes = 256L)
    )
    agent$run_sync("Read the source.")
    source_turns <- agent$get_turns()
    agent$compact(keep_last = 0L)
    prompt <- jsonlite::toJSON(tail(server$requests(), 1L)[[1L]]$body)
    expect_match(prompt, "84", fixed = TRUE)
    expect_match(prompt, "17", fixed = TRUE)
    expect_no_match(prompt, "HOST-ONLY-SECRET", fixed = TRUE)
    expect_no_match(prompt, "Tool result offloaded by Deputy", fixed = TRUE)
    expect_identical(source_turns[[3L]]@contents[[1L]]@value, value)
  }
})

test_that("structured tool evidence keeps field names and relationships", {
  withr::local_options(ellmer_max_tries = 1)
  cases <- list(
    list(
      value = list(denominator = 84L, page = 17L),
      json = '{"denominator":84,"page":17}'
    ),
    list(
      value = c(denominator = 84L, page = 17L),
      json = '{"denominator":84,"page":17}'
    ),
    list(
      value = c(study = "C", document = "assay-C-r3"),
      json = '{"study":"C","document":"assay-C-r3"}'
    ),
    list(
      value = list(estimate = 0.123456789),
      json = '{"estimate":0.123456789}'
    ),
    list(
      value = data.frame(
        study = c("C", "D"),
        denominator = c(84L, 23L),
        page = c(17L, 2L)
      ),
      json = paste0(
        '[{"study":"C","denominator":84,"page":17},',
        '{"study":"D","denominator":23,"page":2}]'
      )
    ),
    list(
      value = list(
        finding = list(
          denominator = 84L,
          source = list(document = "C", page = 17L)
        ),
        unresolved = c("D", "F")
      ),
      json = paste0(
        '{"finding":{"denominator":84,"source":{"document":"C","page":17}},',
        '"unresolved":["D","F"]}'
      )
    ),
    list(
      value = list(
        finding = ellmer::ContentText("Denominator 84."),
        citation = ellmer::ContentText("Source C, page 17.")
      ),
      json = '{"finding":"Denominator 84.","citation":"Source C, page 17."}'
    )
  )
  check_case <- function(case, fallback) {
    server <- local_runtime_server(list(
      runtime_reply(tool = "source_read"),
      runtime_reply("Source inspected."),
      if (fallback) {
        runtime_failure(401L)
      } else {
        runtime_reply("Evidence summarized.", stream = FALSE)
      }
    ))
    source <- ellmer::tool(
      function() {
        ellmer::ContentToolResult(
          value = case$value,
          extra = list(private = "HOST-ONLY-SECRET")
        )
      },
      name = "source_read",
      description = "Read structured source evidence.",
      annotations = ellmer::tool_annotations(
        read_only_hint = TRUE,
        open_world_hint = FALSE
      )
    )
    agent <- Agent$new(runtime_chat(server), tools = list(source))
    agent$run_sync("Read the source.")
    source_turns <- agent$get_turns()
    result <- agent$compact(keep_last = 0L, fallback = "text")
    prompt <- paste(
      unlist(lapply(
        tail(server$requests(), 1L)[[1L]]$body$messages,
        `[[`,
        "content"
      )),
      collapse = "\n"
    )
    expect_match(prompt, case$json, fixed = TRUE)
    expect_no_match(prompt, "HOST-ONLY-SECRET", fixed = TRUE)
    expect_identical(source_turns[[3L]]@contents[[1L]]@value, case$value)
    expect_identical(result$method, if (fallback) "text" else "llm")
    if (fallback) {
      expect_match(result$summary, case$json, fixed = TRUE)
      expect_no_match(result$summary, "HOST-ONLY-SECRET", fixed = TRUE)
    }
  }
  for (case in cases) {
    for (fallback in c(FALSE, TRUE)) {
      check_case(case, fallback)
    }
  }
})

test_that("compaction offloads oversized explicit tool results before formatting", {
  withr::local_options(ellmer_max_tries = 1)
  large_text <- paste0(strrep("evidence ", 20000L), "SOURCE-END")
  cases <- list(
    list(value = large_text, evidence = large_text),
    list(
      value = list(source = large_text, page = 17L),
      evidence = list(source = large_text, page = 17L)
    ),
    list(value = ellmer::ContentText(large_text), evidence = large_text),
    list(
      value = list(
        source = ellmer::ContentText(large_text),
        page = ellmer::ContentText("17")
      ),
      evidence = list(source = large_text, page = "17")
    ),
    list(
      value = seq_len(50000L),
      evidence = seq_len(50000L),
      chunk_match = "50000"
    ),
    list(
      value = rep(paste0("evidence ", strrep("x", 500L)), 300L),
      evidence = rep(paste0("evidence ", strrep("x", 500L)), 300L)
    ),
    list(
      value = factor(rep(paste0("evidence ", strrep("x", 500L)), 300L)),
      evidence = factor(rep(paste0("evidence ", strrep("x", 500L)), 300L)),
      chunk_match = "structure"
    )
  )
  check_case <- function(case, fallback) {
    value <- case$value
    directory <- withr::local_tempdir()
    server <- local_runtime_server(list(
      runtime_reply(tool = "source_read"),
      runtime_reply("Source inspected."),
      if (fallback) {
        runtime_failure(401L)
      } else {
        runtime_reply("Evidence summarized.", stream = FALSE)
      },
      runtime_reply("Continuing from the summary."),
      runtime_reply("Summary refreshed.", stream = FALSE)
    ))
    source <- ellmer::tool(
      function() {
        ellmer::ContentToolResult(
          value = value,
          extra = list(private = "HOST-ONLY-SECRET")
        )
      },
      name = "source_read",
      description = "Read source evidence.",
      annotations = ellmer::tool_annotations(
        read_only_hint = TRUE,
        open_world_hint = FALSE
      )
    )
    agent <- Agent$new(
      runtime_chat(server),
      tools = list(source),
      context_policy = ContextPolicy(offload_dir = directory)
    )
    agent$run_sync("Read the source.")
    source_turns <- agent$get_turns()
    result <- agent$compact(keep_last = 0L, fallback = "text")
    prompt <- paste(
      unlist(lapply(
        tail(server$requests(), 1L)[[1L]]$body$messages,
        `[[`,
        "content"
      )),
      collapse = "\n"
    )
    expect_lt(nchar(prompt), 10000L)
    expect_match(prompt, "Tool result offloaded by Deputy", fixed = TRUE)
    expect_no_match(prompt, "SOURCE-END", fixed = TRUE)
    expect_no_match(prompt, "HOST-ONLY-SECRET", fixed = TRUE)
    reference <- regmatches(
      prompt,
      regexpr(
        "deputy://tool-result/result_[a-f0-9]+\\?text_sha256=[a-f0-9]+",
        prompt
      )
    )
    expect_identical(agent$resolve_tool_result(reference), case$evidence)
    expect_identical(source_turns[[3L]]@contents[[1L]]@value, value)
    expect_match(
      agent$get_tools()[["deputy_read_tool_result"]](
        reference,
        max_chars = 64L
      ),
      case$chunk_match %||% "evidence",
      fixed = TRUE
    )
    expect_identical(result$method, if (fallback) "text" else "llm")
    expect_match(result$summary, reference, fixed = TRUE)
    expect_lt(nchar(result$summary), 10000L)
    agent$run_sync("Continue using the source evidence.")
    continuation <- jsonlite::toJSON(tail(server$requests(), 1L)[[1L]]$body)
    expect_match(continuation, reference, fixed = TRUE)
    expect_match(continuation, "deputy_read_tool_result", fixed = TRUE)

    # A later summary can omit references again after the original source
    # turns are gone. The prior accepted reference must still survive.
    refreshed <- agent$compact(keep_last = 0L)
    expect_match(refreshed$summary, reference, fixed = TRUE)
    expect_match(agent$get_system_prompt(), reference, fixed = TRUE)
    expect_identical(agent$resolve_tool_result(reference), case$evidence)
  }
  for (case in cases) {
    for (fallback in c(FALSE, TRUE)) {
      check_case(case, fallback)
    }
  }
})
test_that("compaction bounds real tool-request arguments without losing their payload", {
  withr::local_options(ellmer_max_tries = 1)
  check_case <- function(mode) {
    arguments <- list(
      path = "report.txt",
      text = paste0(strrep("payload ", 30000L), "ARGUMENT-END")
    )
    server <- local_runtime_server(list(
      runtime_reply(tool = "write_file", arguments = arguments),
      runtime_reply("File written."),
      if (mode == "llm") {
        runtime_reply("Write completed.", stream = FALSE)
      } else {
        runtime_failure(401L)
      }
    ))
    directory <- withr::local_tempdir()
    writes <- 0L
    writer <- ellmer::tool(
      function(path, text) {
        writes <<- writes + 1L
        writeLines(text, path)
        "saved"
      },
      name = "write_file",
      description = "Write a local report.",
      arguments = list(
        path = ellmer::type_string(),
        text = ellmer::type_string()
      )
    )
    policy <- ContextPolicy(
      max_tokens = NULL,
      offload_dir = withr::local_tempdir()
    )
    agent <- Agent$new(
      runtime_chat(server),
      tools = list(writer),
      permissions = permissions_full(),
      working_dir = directory,
      context_policy = policy
    )
    agent$run_sync("Write the report.")
    before <- agent$get_turns()
    if (mode == "error") {
      expect_error(
        agent$compact(keep_last = 0L),
        class = "deputy_compaction_error"
      )
      expect_identical(agent$get_turns(), before)
      expect_false("deputy_read_tool_result" %in% names(agent$get_tools()))
      expect_length(
        list.files(tool_result_offload_dir(policy, agent$session_id())),
        0L
      )
    } else {
      result <- agent$compact(keep_last = 0L, fallback = "text")
      expect_identical(result$method, mode)
      reference <- compaction_tool_result_references(result$summary)
      expect_length(reference, 1L)
      expect_identical(
        agent$resolve_tool_result(reference),
        list(arguments = arguments)
      )
      expect_match(
        agent$get_tools()[["deputy_read_tool_result"]](
          reference,
          max_chars = 512L
        ),
        "report.txt",
        fixed = TRUE
      )
    }
    prompt <- jsonlite::toJSON(tail(server$requests(), 1L)[[1L]]$body)
    expect_lt(nchar(prompt), 10000L)
    expect_match(prompt, "write_file", fixed = TRUE)
    expect_no_match(prompt, "ARGUMENT-END", fixed = TRUE)
    expect_identical(writes, 1L)
    expect_identical(
      readLines(file.path(directory, arguments$path)),
      arguments$text
    )
    expect_identical(before[[2L]]@contents[[1L]]@arguments, arguments)
  }
  for (mode in c("llm", "text", "error")) {
    check_case(mode)
  }
})

test_that("aborted compaction removes only provisional evidence files", {
  withr::local_options(ellmer_max_tries = 1)
  check_case <- function(mode) {
    failure <- if (mode == "cancel") {
      reply <- runtime_reply("A summary that will be cancelled.")
      attr(reply, "fixture_delay") <- 0.5
      reply
    } else {
      runtime_failure(401L)
    }
    server <- local_runtime_server(list(
      runtime_reply(tool = "source_read"),
      runtime_reply("Source inspected."),
      failure,
      runtime_reply("Fresh context."),
      runtime_reply("Evidence summarized.", stream = FALSE)
    ))
    value <- strrep("recoverable evidence ", 500L)
    source <- ellmer::tool(
      function() ellmer::ContentToolResult(value = value),
      name = "source_read",
      description = "Read source evidence.",
      annotations = ellmer::tool_annotations(
        read_only_hint = TRUE,
        open_world_hint = FALSE
      )
    )
    chat <- runtime_chat(server)
    rlang::env_binding_unlock(chat, "token_count")
    chat$token_count <- function(...) 10
    agent <- Agent$new(
      chat,
      tools = list(source),
      context_policy = ContextPolicy(
        max_tokens = 50L,
        max_tool_result_bytes = 512L,
        offload_dir = withr::local_tempdir()
      )
    )
    agent$run_sync("Read the source.")
    agent$add_turn(
      ellmer::UserTurn("Plan the next step."),
      ellmer::AssistantTurn("Use the source evidence."),
      log_tokens = FALSE
    )
    before <- agent$get_turns()
    tools_before <- names(agent$get_tools())
    # An unrelated envelope already owned by this session must survive rollback.
    existing <- offload_tool_result(
      "Previously accepted evidence",
      "accepted_source",
      agent$context_policy,
      agent$session_id(),
      agent$agent_id,
      force = TRUE
    )
    files_before <- sort(list.files(dirname(existing$path)))
    if (mode == "manual") {
      expect_error(
        agent$compact(keep_last = 0L),
        class = "deputy_compaction_error"
      )
    } else {
      chat$token_count <- function(...) 1000
      if (mode == "cancel") {
        deadline <- Sys.time() + 5
        cancel <- function() {
          if (length(server$requests()) >= 3L) {
            agent$interrupt()
          } else if (Sys.time() < deadline) {
            later::later(cancel, 0.01)
          }
        }
        timer <- later::later(cancel, 0.01)
        agent$run_sync("Continue.")
        timer()
        expect_identical(agent$last_run()$stop_reason, "interrupted")
      } else {
        expect_error(
          agent$run_sync("Continue."),
          class = "deputy_compaction_error"
        )
      }
    }
    expect_identical(agent$get_turns(), before)
    expect_identical(names(agent$get_tools()), tools_before)
    expect_identical(sort(list.files(dirname(existing$path))), files_before)
    snapshot <- tempfile(fileext = ".rds")
    withr::defer(unlink(snapshot))
    withCallingHandlers(
      agent$save_session(snapshot),
      warning = function(warning) {
        # load_all() exposes a transient package environment in explicit Content.
        if (
          grepl(
            "'package:deputy' may not be available",
            conditionMessage(warning),
            fixed = TRUE
          )
        ) {
          invokeRestart("muffleWarning")
        }
      }
    )
    expect_named(readRDS(snapshot)$tool_result_envelopes, existing$id)
    expect_identical(
      agent$resolve_tool_result(existing$uri),
      "Previously accepted evidence"
    )
    fresh <- agent$clone()
    fresh$set_turns(list())
    fresh$set_tools(list())
    expect_length(fresh$get_tools(), 0L)
    fresh$run_sync("Start fresh.")
    expect_null(tail(server$requests(), 1L)[[1L]]$body$tools)
    # The unchanged original turns can subsequently produce a durable summary.
    result <- agent$compact(keep_last = 0L)
    reference <- compaction_tool_result_references(result$summary)
    expect_length(reference, 1L)
    expect_identical(agent$resolve_tool_result(reference), value)
    expect_true("deputy_read_tool_result" %in% names(agent$get_tools()))
  }
  for (mode in c("manual", "automatic", "cancel")) {
    check_case(mode)
  }
})

test_that("provisional evidence respects concurrent clone and tool ownership", {
  check_case <- function(claim) {
    server <- local_runtime_server(list(runtime_reply(
      "Summary.",
      stream = FALSE
    )))
    value <- strrep("shared evidence ", 100L)
    source <- ellmer::tool(
      function() value,
      name = "source_read",
      description = "Read shared evidence.",
      annotations = ellmer::tool_annotations(
        read_only_hint = TRUE,
        open_world_hint = FALSE
      )
    )
    agent <- Agent$new(
      runtime_chat(server),
      tools = list(source),
      context_policy = ContextPolicy(
        max_tokens = NULL,
        max_tool_result_bytes = 512L,
        offload_dir = withr::local_tempdir()
      )
    )
    request <- ellmer::ContentToolRequest(
      name = "source_read",
      arguments = list(),
      id = "source"
    )
    agent$add_turn(
      ellmer::UserTurn("Read evidence."),
      ellmer::AssistantTurn(contents = list(request)),
      log_tokens = FALSE
    )
    agent$add_turn(
      ellmer::UserTurn(
        contents = list(ellmer::ContentToolResult(
          value = value,
          request = request
        ))
      ),
      ellmer::AssistantTurn("Evidence read."),
      log_tokens = FALSE
    )
    sibling <- agent$clone()
    private <- agent$.__enclos_env__$private
    # Pause the first transaction after its real evidence projection, then let
    # a sibling use the same content-addressed artifact before the first aborts.
    transaction <- private$begin_compaction_artifacts()
    reference <- compaction_tool_result_references(private$compaction_summary_prompt(agent$get_turns()))
    expect_length(reference, 1L)
    if (claim == "abort") {
      other <- sibling$.__enclos_env__$private
      pending <- other$begin_compaction_artifacts()
      expect_match(
        other$compaction_summary_prompt(sibling$get_turns()),
        reference,
        fixed = TRUE
      )
    } else if (claim == "install") {
      installed <- sibling$compact(keep_last = 0L)
      expect_match(
        installed$summary,
        reference,
        fixed = TRUE
      )
    } else {
      expect_match(
        sibling$get_tools()[["source_read"]](),
        reference,
        fixed = TRUE
      )
    }
    private$finish_compaction_artifacts(transaction)
    expect_identical(sibling$resolve_tool_result(reference), value)
    if (claim == "abort") {
      other$finish_compaction_artifacts(pending)
      expect_error(sibling$resolve_tool_result(reference), "not found")
    }
  }
  for (claim in c("abort", "install", "tool")) {
    check_case(claim)
  }
})

test_that("compaction keeps growing recovery sets behind a bounded catalog", {
  withr::local_options(ellmer_max_tries = 1)
  server <- local_runtime_server(c(
    rep(list(runtime_reply("Evidence summarized.", stream = FALSE)), 4L),
    rep(list(runtime_failure(401L)), 2L)
  ))
  policy <- ContextPolicy(
    max_tokens = NULL,
    max_tool_result_bytes = 512L,
    offload_dir = withr::local_tempdir()
  )
  source <- ellmer::tool(
    function(index) paste0("Source ", index, ": ", strrep("evidence ", 300L)),
    name = "source_read",
    description = "Read source evidence.",
    arguments = list(index = ellmer::type_integer()),
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE
    )
  )
  chat <- runtime_chat(server)
  agent <- Agent$new(
    chat,
    tools = list(source),
    context_policy = policy
  )
  snapshot_file <- tempfile(fileext = ".rds")
  early_session <- tempfile(fileext = ".rds")
  withr::defer(unlink(c(snapshot_file, early_session)))
  snapshot <- function() {
    agent$save_session(snapshot_file)
    readRDS(snapshot_file)
  }
  references <- character()
  previous_catalogs <- character()
  for (batch in seq_len(3L)) {
    results <- vapply(
      seq.int((batch - 1L) * 10L + 1L, batch * 10L),
      agent$get_tools()[["source_read"]],
      character(1)
    )
    references <- c(references, compaction_tool_result_references(results))
    expect_length(references, batch * 10L)
    agent$add_turn(
      ellmer::UserTurn("Retain access to these sources."),
      ellmer::AssistantTurn(paste(results, collapse = "\n")),
      log_tokens = FALSE
    )
    keep_last <- if (batch == 2L) 2L else 0L
    if (batch == 2L) {
      agent$add_turn(
        ellmer::UserTurn(paste(
          "Keep this catalog available:",
          previous_catalogs[[1L]]
        )),
        ellmer::AssistantTurn("It remains available."),
        log_tokens = FALSE
      )
      before <- snapshot()
      private <- agent$.__enclos_env__$private
      plan <- private$prepare_compaction(keep_last, NULL, "error", FALSE, NULL)
      generated <- private$generate_compaction_summary(
        plan$turns_to_compact,
        "error"
      )
      original_set_turns <- chat$set_turns
      replace_set_turns <- function(method) {
        unlockBinding("set_turns", chat)
        chat$set_turns <- method
        lockBinding("set_turns", chat)
      }
      reject <- TRUE
      replace_set_turns(function(turns) {
        if (reject) {
          reject <<- FALSE
          cli::cli_abort("Injected installation failure")
        }
        original_set_turns(turns)
      })
      expect_error(
        private$install_compaction(
          plan,
          generated$summary,
          generated$method,
          generated$usage
        ),
        "Injected installation failure"
      )
      replace_set_turns(original_set_turns)
      after <- snapshot()
      expect_identical(agent$get_system_prompt(), before$system_prompt)
      expect_identical(agent$get_turns(), before$turns)
      expect_identical(
        names(after$tool_result_envelopes),
        names(before$tool_result_envelopes)
      )
      expect_identical(
        unclass(agent$resolve_tool_result(previous_catalogs[[1L]])),
        head(references, 10L)
      )
    }
    compacted <- agent$compact(keep_last = keep_last)
    handles <- compaction_tool_result_references(compacted$summary)
    expect_length(handles, 1L)
    expect_lt(nchar(compacted$summary), 600L)
    expect_identical(unclass(agent$resolve_tool_result(handles)), references)
    expect_false(any(
      previous_catalogs %in% unclass(agent$resolve_tool_result(handles))
    ))
    expect_match(
      agent$get_tools()[["deputy_read_tool_result"]](handles, max_chars = 512L),
      references[[1L]],
      fixed = TRUE
    )
    previous_catalogs <- c(previous_catalogs, handles)
    saved <- snapshot()
    expected_catalogs <- if (batch > 1L) 2L else 1L
    expect_length(saved$tool_result_envelopes, batch * 10L + expected_catalogs)
    expect_equal(
      sum(vapply(
        saved$tool_result_envelopes,
        function(envelope) {
          inherits(envelope$value, "deputy_compaction_catalog")
        },
        logical(1)
      )),
      expected_catalogs
    )
    if (batch == 1L) {
      expect_true(file.copy(snapshot_file, early_session))
      sibling <- agent$clone()
      shared <- Agent$new(
        runtime_chat(server),
        context_policy = policy,
        session_id = agent$session_id()
      )
      shared$load_session(early_session)
    }
  }
  expect_identical(
    unclass(sibling$resolve_tool_result(previous_catalogs[[1L]])),
    head(references, 10L)
  )
  expect_match(
    sibling$get_tools()[["deputy_read_tool_result"]](
      previous_catalogs[[1L]],
      max_chars = 512L
    ),
    references[[1L]],
    fixed = TRUE
  )
  sibling <- NULL
  invisible(gc())
  earlier <- Agent$new(
    runtime_chat(server),
    session_id = agent$session_id(),
    context_policy = ContextPolicy(offload_dir = withr::local_tempdir())
  )
  earlier$load_session(early_session)
  expect_identical(
    unclass(earlier$resolve_tool_result(previous_catalogs[[1L]])),
    head(references, 10L)
  )
  agent$add_turn(
    ellmer::UserTurn("Continue."),
    ellmer::AssistantTurn("Continuing."),
    log_tokens = FALSE
  )
  degraded <- agent$compact(keep_last = 0L, fallback = "text")
  expect_identical(degraded$method, "text")
  expect_identical(compaction_tool_result_references(degraded$summary), handles)
  saved <- snapshot()
  expect_length(saved$tool_result_envelopes, 32L)
  expect_identical(
    unclass(shared$resolve_tool_result(previous_catalogs[[1L]])),
    head(references, 10L)
  )
  expect_match(
    shared$get_tools()[["deputy_read_tool_result"]](
      previous_catalogs[[1L]],
      max_chars = 512L
    ),
    references[[1L]],
    fixed = TRUE
  )
  shared <- NULL
  invisible(gc())
  agent$add_turn(
    ellmer::UserTurn("Refresh the summary."),
    ellmer::AssistantTurn("Sources remain recoverable."),
    log_tokens = FALSE
  )
  agent$compact(keep_last = 0L, fallback = "text")
  saved <- snapshot()
  expect_length(saved$tool_result_envelopes, 31L)
  for (reference in head(previous_catalogs, -1L)) {
    expect_error(agent$resolve_tool_result(reference), "not found")
    paths <- file.path(
      policy$offload_dir,
      saved$metadata$session_id,
      paste0(
        parse_tool_result_reference(reference),
        c(".rds", ".txt", ".meta.rds")
      )
    )
    expect_false(any(file.exists(paths)))
  }
  for (index in c(1L, length(references))) {
    expect_identical(
      agent$resolve_tool_result(references[[index]]),
      paste0("Source ", index, ": ", strrep("evidence ", 300L))
    )
  }
  session <- tempfile(fileext = ".rds")
  withr::defer(unlink(session))
  agent$save_session(session)
  restored <- Agent$new(
    runtime_chat(server),
    context_policy = ContextPolicy(
      max_tokens = NULL,
      max_tool_result_bytes = NULL,
      offload_dir = withr::local_tempdir()
    )
  )
  restored$load_session(session)
  expect_identical(unclass(restored$resolve_tool_result(handles)), references)
  expect_match(
    restored$get_tools()[["deputy_read_tool_result"]](
      handles,
      max_chars = 512L
    ),
    references[[1L]],
    fixed = TRUE
  )
  restored$add_turn(
    ellmer::UserTurn("Continue after restore."),
    ellmer::AssistantTurn("Continuing."),
    log_tokens = FALSE
  )
  after_restore <- restored$compact(keep_last = 0L, fallback = "text")
  expect_identical(
    compaction_tool_result_references(after_restore$summary),
    handles
  )
})

test_that("compaction bounds public error diagnostics", {
  withr::local_options(ellmer_max_tries = 1)
  diagnostic <- paste0(strrep("diagnostic ", 20000L), "DIAGNOSTIC-END")
  check_error <- function(error, fallback) {
    server <- local_runtime_server(list(
      runtime_reply(tool = "source_read"),
      runtime_reply("The source request failed."),
      if (fallback) {
        runtime_failure(401L)
      } else {
        runtime_reply("Failure summarized.", stream = FALSE)
      }
    ))
    source <- ellmer::tool(
      function() {
        ellmer::ContentToolResult(
          error = error,
          extra = list(private = "HOST-ONLY-SECRET")
        )
      },
      name = "source_read",
      description = "Read source evidence.",
      annotations = ellmer::tool_annotations(
        read_only_hint = TRUE,
        open_world_hint = FALSE
      )
    )
    agent <- Agent$new(
      runtime_chat(server),
      tools = list(source),
      context_policy = ContextPolicy(offload_dir = withr::local_tempdir())
    )
    expect_warning(
      agent$run_sync("Read the source."),
      "Failed to evaluate 1 tool call"
    )
    result <- agent$compact(keep_last = 0L, fallback = "text")
    prompt <- paste(
      unlist(lapply(
        tail(server$requests(), 1L)[[1L]]$body$messages,
        `[[`,
        "content"
      )),
      collapse = "\n"
    )
    expect_lt(nchar(prompt), 10000L)
    expect_match(prompt, "Error:", fixed = TRUE)
    expect_no_match(prompt, "DIAGNOSTIC-END", fixed = TRUE)
    expect_no_match(prompt, "HOST-ONLY-SECRET", fixed = TRUE)
    reference <- compaction_tool_result_references(prompt)
    expect_length(reference, 1L)
    expect_identical(
      agent$resolve_tool_result(reference),
      list(error = diagnostic)
    )
    expect_match(result$summary, reference, fixed = TRUE)
    expect_identical(result$method, if (fallback) "text" else "llm")
    expect_match(
      agent$get_tools()[["deputy_read_tool_result"]](
        reference,
        max_chars = 64L
      ),
      "diagnostic",
      fixed = TRUE
    )
  }
  for (error in list(diagnostic, simpleError(diagnostic))) {
    for (fallback in c(FALSE, TRUE)) {
      check_error(error, fallback)
    }
  }
})
