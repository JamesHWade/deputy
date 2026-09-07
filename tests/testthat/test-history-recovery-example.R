history_example <- function() {
  env <- new.env(parent = globalenv())
  path <- system.file("examples", "history-recovery", package = "deputy")
  for (file in c("fixture.R", "history.R", "evaluation.R")) {
    sys.source(file.path(path, file), envir = env)
  }
  env
}

test_that("history search and reads cannot cross any host scope", {
  example <- history_example()
  fixture <- example$history_fixture(1L)
  access <- example$history_access(
    fixture$records,
    fixture$scope,
    max_calls = 12L
  )
  expect_identical(jsonlite::fromJSON(access$search("PRIVATE"))$items, list())
  for (id in c(
    "other-reader-secret",
    "other-agent-secret",
    "other-branch-secret",
    "other-conversation-secret",
    "absent"
  )) {
    expect_identical(jsonlite::fromJSON(access$read(id))$status, "not_found")
  }
  found <- jsonlite::fromJSON(access$search("assay-C-r3"))$items
  expect_identical(found$item_id, "assay-C-r3")
  source <- jsonlite::fromJSON(access$read(found$item_id, found$revision))$items
  expect_match(source$text, "denominator 84", fixed = TRUE)
  expect_identical(source$revision, found$revision)
  expect_identical(
    jsonlite::fromJSON(access$read(found$item_id, "old"))$status,
    "stale"
  )
})

test_that("history rejects text changes and fabricated revision hashes", {
  example <- history_example()
  fixture <- example$history_fixture(1L)
  i <- match("assay-C-r3", fixture$records$item_id)
  changed <- fixture$records
  changed$text[[i]] <- "Corrected denominator 85."
  expect_snapshot(error = TRUE, example$history_access(changed, fixture$scope))

  forged <- fixture$records
  forged$revision[[i]] <- strrep("a", 64L)
  expect_snapshot(error = TRUE, example$history_access(forged, fixture$scope))
})

test_that("history validates authorized snapshots and rejects old revisions after refresh", {
  example <- history_example()
  fixture <- example$history_fixture(1L)
  original <- example$history_access(fixture$records, fixture$scope)
  i <- match("assay-C-r3", fixture$records$item_id)
  old_revision <- fixture$records$revision[[i]]
  fixture$records$text[[i]] <- "Corrected denominator 85."
  fixture$records$revision[[i]] <- digest::digest(
    fixture$records$text[[i]],
    algo = "sha256",
    serialize = FALSE
  )
  excluded <- match("other-reader-secret", fixture$records$item_id)
  fixture$records$revision[[excluded]] <- strrep("z", 64L)
  refreshed <- example$history_access(fixture$records, fixture$scope)

  old <- jsonlite::fromJSON(original$read("assay-C-r3", old_revision))
  expect_identical(old$status, "ok")
  expect_match(old$items$text, "denominator 84", fixed = TRUE)
  expect_identical(old$items$revision, old_revision)
  stale <- jsonlite::fromJSON(refreshed$read("assay-C-r3", old_revision))
  expect_identical(stale$status, "stale")
  expect_identical(stale$items, list())
  current <- jsonlite::fromJSON(refreshed$read(
    "assay-C-r3",
    fixture$records$revision[[i]]
  ))
  expect_identical(current$status, "ok")
  expect_identical(current$items$text, "Corrected denominator 85.")
  expect_identical(current$items$revision, fixture$records$revision[[i]])
  expect_identical(
    jsonlite::fromJSON(refreshed$read("other-reader-secret"))$status,
    "not_found"
  )
})

test_that("preparation requires all three authorized checkpoints before creating a chat", {
  example <- history_example()
  fixture <- example$history_fixture(1L)
  missing <- fixture$records[fixture$records$stage != 3L, ]
  alternate <- fixture$records
  alternate$stage <- alternate$stage + 1L
  hidden <- fixture$records
  hidden$owner_id[hidden$stage == 3L] <- "reader-b"
  extra <- fixture$records
  extra$stage[[1L]] <- 4L
  calls <- 0L
  factory <- function(model) {
    calls <<- calls + 1L
    rlang::abort(
      "The model factory must not be called for invalid checkpoints."
    )
  }
  for (records in list(missing, alternate, hidden, extra)) {
    fixture$records <- records
    evaluation <- example$history_evaluate(
      factory,
      fixture,
      trials = 1L,
      helper_models = "fixture",
      task_model = "fixture"
    )
    expect_identical(
      evaluation$failure$class,
      "history_evaluation_wrong_stages"
    )
    expect_identical(evaluation$usage$requests, 0L)
    expect_length(evaluation$runs, 0L)
    expect_length(evaluation$inputs, 0L)
  }
  expect_identical(calls, 0L)
})

test_that("history chunks preserve UTF-8 and enforce whole-payload budgets", {
  example <- history_example()
  fixture <- example$history_fixture(1L)
  text <- paste(rep('café \"quoted\" \\ data\n', 100L), collapse = "")
  fixture$records$text[[1L]] <- text
  fixture$records$revision[[1L]] <- digest::digest(
    text,
    algo = "sha256",
    serialize = FALSE
  )
  access <- example$history_access(
    fixture$records,
    fixture$scope,
    max_calls = 100L,
    max_response_bytes = 300L,
    max_total_bytes = 20000L
  )
  offset <- 0L
  chunks <- character()
  repeat {
    output <- access$read(fixture$records$item_id[[1L]], offset = offset)
    expect_lte(nchar(output, type = "bytes"), 300L)
    item <- jsonlite::fromJSON(output)$items
    chunks <- c(chunks, item$text)
    if (is.na(item$next_offset)) {
      break
    }
    offset <- item$next_offset
  }
  expect_identical(paste0(chunks, collapse = ""), text)
  expect_lte(access$usage()$bytes, 20000L)
  exhausted <- example$history_access(
    fixture$records,
    fixture$scope,
    max_calls = 1L
  )
  exhausted$read("assay-C-r3")
  expect_condition(exhausted$read("assay-C-r3"), class = "ellmer_tool_reject")
  expect_identical(tail(exhausted$audit(), 1L)[[1L]]$status, "budget_exhausted")
  for (case in list(
    list(available = FALSE),
    list(cancelled = function() TRUE),
    list(max_total_bytes = 0L)
  )) {
    blocked <- do.call(
      example$history_access,
      c(list(fixture$records, fixture$scope), case)
    )
    expect_condition(blocked$read("assay-C-r3"), class = "ellmer_tool_reject")
    expect_identical(blocked$usage()$bytes, 0L)
  }
})

for (scenario in c("original", "changed-constraint", "resolved-methods")) {
  test_that(paste("paired continuations preserve the", scenario, "protocol"), {
    example <- history_example()
    fixture <- example$history_fixture(1L, scenario = scenario)
    if (scenario == "changed-constraint") {
      fixture$records$stage <- as.numeric(fixture$records$stage)
    }
    answer <- c(fixture$expected, list(source_ids = fixture$required_sources))
    source_id <- if (scenario == "original") {
      "assay-C-r3"
    } else if (scenario == "changed-constraint") {
      "protocol-all-ages-randomized"
    } else {
      "report-D-F-clarification"
    }
    wire <- local({
      reply <- runtime_reply
      function(request, count) {
        last <- tail(request$messages, 1L)[[1L]]
        content <- jsonlite::toJSON(last$content, auto_unbox = TRUE)
        if (grepl("Summarize the following", content, fixed = TRUE)) {
          return(reply(
            "Adults only. C corrected. D and F pending. Export completed."
          ))
        }
        if (!is.null(request$response_format)) {
          return(reply(
            as.character(jsonlite::toJSON(answer, auto_unbox = TRUE)),
            stream = FALSE
          ))
        }
        if (identical(last$role, "tool")) {
          return(reply("Source inspected."))
        }
        if (grepl("Call load_checkpoint", content, fixed = TRUE)) {
          stage <- as.integer(sub(
            ".*load_checkpoint\\(([0-9]+)\\).*",
            "\\1",
            content
          ))
          return(reply(
            tool = "load_checkpoint",
            arguments = list(stage = stage)
          ))
        }
        tools <- vapply(
          request$tools,
          function(tool) tool$`function`$name,
          character(1)
        )
        if ("history_read" %in% tools) {
          return(reply(
            tool = "history_read",
            arguments = list(item_id = source_id)
          ))
        }
        reply("Ready.")
      }
    })
    server <- local_runtime_server(wire)
    factory <- function(model) {
      chat <- runtime_chat(server, name = "OpenAI")
      counter <- function(..., include = "complete") {
        previous <- sum(nchar(vapply(self$get_turns(), format, character(1))))
        incoming <- sum(nchar(vapply(
          list(...),
          function(x) paste(format(x), collapse = ""),
          character(1)
        )))
        (previous + incoming) / 4
      }
      environment(counter) <- environment(chat$token_count)
      rlang::env_binding_unlock(chat, "token_count")
      chat$token_count <- counter
      chat
    }
    evaluation <- example$history_evaluate(
      factory,
      fixture,
      trials = 2L,
      helper_models = "fixture",
      task_model = "fixture",
      max_tokens = 500L,
      protocols = c("baseline", "budget-aware")
    )
    expect_null(evaluation$failure)
    expect_length(evaluation$effects, 2L)
    expect_length(evaluation$trials, 6L)
    expect_identical(
      vapply(evaluation$trials, `[[`, character(1), "strategy"),
      c("summary", "history", "history", "history", "history", "summary")
    )
    expect_identical(
      vapply(evaluation$trials, `[[`, character(1), "protocol"),
      c(
        "baseline",
        "baseline",
        "budget-aware",
        "baseline",
        "budget-aware",
        "baseline"
      )
    )
    for (rows in split(evaluation$trials, rep(1:2, each = 3L))) {
      expect_length(unique(vapply(rows, `[[`, character(1), "summary_id")), 1L)
      receipt <- rows[[1L]]$completed_effects_before[[1L]]
      expect_identical(receipt$executions, 1L)
      expect_identical(receipt$executor, "host")
      expect_identical(
        receipt$contents,
        c("report,responses,denominator", "C,21,84")
      )
      expect_identical(
        receipt$sha256,
        digest::digest(
          fixture$planned_export$contents,
          algo = "sha256",
          serialize = FALSE
        )
      )
      expect_identical(
        rows[[1L]]$completed_effects_before,
        rows[[2L]]$completed_effects_before
      )
      expect_identical(
        rows[[1L]]$completed_effects_before,
        rows[[3L]]$completed_effects_before
      )
      expect_equal(rows[[1L]]$transitions, 3L)
      expect_identical(
        vapply(rows, function(row) row$score$all_correct, logical(1)),
        c(TRUE, TRUE, TRUE)
      )
      expect_identical(
        vapply(rows, `[[`, integer(1), "repeated_effects"),
        c(0L, 0L, 0L)
      )
    }
    history <- Filter(
      function(row) row$strategy == "history",
      evaluation$trials
    )
    expect_identical(history[[1L]]$history_audit[[1L]]$item_ids, source_id)
    compactions <- unlist(
      lapply(evaluation$runs, function(run) {
        Filter(function(event) event$type == "compaction", run$events)
      }),
      recursive = FALSE
    )
    expect_length(compactions, 6L)
    expect_identical(
      vapply(compactions, function(event) length(event$attempts), integer(1)),
      rep(1L, 6L)
    )
    expect_match(
      paste(example$history_report(evaluation), collapse = "\n"),
      "fixture/2",
      fixed = TRUE
    )
    expect_match(
      paste(example$history_report(evaluation), collapse = "\n"),
      fixture$case_id,
      fixed = TRUE
    )
    prompts <- jsonlite::toJSON(server$requests())
    expect_match(prompts, "denominator 84", fixed = TRUE)
    expect_no_match(prompts, "PRIVATE-", fixed = TRUE)
    if (scenario == "changed-constraint") {
      submitted <- unlist(lapply(evaluation$inputs, `[[`, "prompt"))
      expect_match(
        submitted[grepl("Call load_checkpoint(3)", submitted, fixed = TRUE)][[
          1L
        ]],
        "Host protocol amendment",
        fixed = TRUE
      )
      amendment <- jsonlite::fromJSON(
        example$history_access(fixture$records, fixture$scope)$read(source_id)
      )$items
      expect_match(
        amendment$text,
        "supersedes the adult-only restriction",
        fixed = TRUE
      )
      stale_answer <- answer
      stale_answer$b_eligible <- FALSE
      expect_identical(
        example$history_score(stale_answer, fixture)$checks$current_constraint,
        FALSE
      )
      expect_identical(evaluation$case_id, "assay-review-changed-constraint-v1")
    }
    if (scenario == "resolved-methods") {
      expect_setequal(
        fixture$required_sources,
        c(
          "protocol-adult-randomized",
          "assay-C-r3",
          "export-receipt-0042",
          "report-D-F-clarification"
        )
      )
      reversed <- answer
      reversed$d_status <- "excluded"
      reversed$f_status <- "eligible"
      reversed_score <- example$history_score(reversed, fixture)
      expect_identical(reversed_score$checks$d_classification, FALSE)
      expect_identical(reversed_score$checks$f_classification, FALSE)
      expect_identical(reversed_score$all_correct, FALSE)
      omitted <- answer
      omitted$d_status <- NULL
      omitted$f_status <- NULL
      expect_identical(
        example$history_score(omitted, fixture)$all_correct,
        FALSE
      )
      stale_answer <- answer
      stale_answer$pending_reports <- c("D", "F")
      expect_identical(
        example$history_score(stale_answer, fixture)$checks$unresolved_work,
        FALSE
      )
    }
    expect_gt(evaluation$usage$requests, 16L)
    expect_gt(evaluation$usage$cost_usd, 0)
    json <- jsonlite::toJSON(
      evaluation,
      auto_unbox = TRUE,
      null = "null",
      na = "null"
    )
    expect_type(json, "character")
    saved <- jsonlite::fromJSON(json, simplifyVector = FALSE)
    expect_equal(saved$runs[[1L]]$usage, evaluation$runs[[1L]]$usage)
    expect_equal(saved$trials[[1L]]$usage, evaluation$trials[[1L]]$usage)
    saved_compactions <- Filter(
      function(run) identical(run$compaction$method, "llm"),
      saved$runs
    )
    # The final preparation run in each trial ends with an LLM replacement.
    expect_length(saved_compactions, 2L)
    expect_identical(saved_compactions[[1L]]$compaction$method, "llm")
    expect_gt(saved_compactions[[1L]]$compaction$usage$requests, 0)
    expect_gt(
      saved_compactions[[1L]]$compaction$attempts[[1L]]$usage$requests,
      0
    )
  })
}

test_that("missing history and injected export requests preserve host authority", {
  example <- history_example()
  fixture <- example$history_fixture(1L)
  answer <- c(fixture$expected, list(source_ids = character()))
  prepared <- list(
    system_prompt = "Read-only host policy.",
    turns = list(),
    summary_id = "fixture"
  )
  for (tool in c("history_read", "export_findings")) {
    server <- local_runtime_server(list(
      runtime_reply(
        tool = tool,
        arguments = if (tool == "history_read") {
          list(item_id = "assay-C-r3")
        } else {
          list()
        }
      ),
      runtime_reply("I cannot recover that source or repeat the export."),
      runtime_reply(
        as.character(jsonlite::toJSON(answer, auto_unbox = TRUE)),
        stream = FALSE
      )
    ))
    warnings <- character()
    row <- withCallingHandlers(
      example$history_continue(
        fixture,
        prepared,
        runtime_chat(server),
        example$history_budget(),
        "missing",
        "history",
        available = FALSE
      ),
      warning = function(w) {
        warnings <<- c(warnings, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    )
    expect_length(warnings, 1L)
    expect_identical(row$repeated_effects, 0L)
    expect_identical(row$score$checks$grounded_sources, FALSE)
    expect_identical(row$history_usage$bytes, 0L)
    if (tool == "history_read") {
      expect_identical(row$history_audit[[1L]]$status, "unavailable")
    } else {
      expect_identical(row$attempted_exports, 1L)
    }
  }
})

test_that("experiment interruption retains evidence and prevents later dispatch", {
  example <- history_example()
  fixture <- example$history_fixture(1L)
  server <- local_runtime_server(list(runtime_reply("Checkpoint not loaded.")))
  factory <- function(model) runtime_chat(server)
  cancelled <- example$history_evaluate(
    factory,
    fixture,
    cancelled = function() TRUE
  )
  expect_identical(cancelled$failure$class, "history_evaluation_cancelled")
  expect_identical(cancelled$usage$requests, 0L)
  expect_length(server$requests(), 0L)
  exhausted <- example$history_evaluate(factory, fixture, max_requests = 1L)
  expect_length(server$requests(), 1L)
  expect_identical(exhausted$usage$requests, 1L)
  expect_length(exhausted$runs, 1L)
  expect_length(exhausted$trials, 0L)
  expect_type(exhausted$failure$class, "character")
  unknown <- example$history_evaluate(factory, fixture, max_cost_usd = 1)
  expect_identical(unknown$usage$cost_usd, NA_real_)
  expect_length(unknown$runs, 1L)
  expect_length(server$requests(), 2L)
  saved <- jsonlite::fromJSON(
    jsonlite::toJSON(unknown, auto_unbox = TRUE, null = "null", na = "null"),
    simplifyVector = FALSE
  )
  expect_identical(saved$runs[[1L]]$usage$cost_usd, NULL)
  expect_contains(names(saved$runs[[1L]]$usage), "cost_usd")
  expect_equal(
    saved$runs[[1L]]$usage$requests,
    unknown$runs[[1L]]$usage$requests
  )
})


test_that("live opt-in is explicit and outer errors persist no condition message", {
  example <- history_example()
  withr::local_envvar(DEPUTY_HISTORY_LIVE = NA_character_)
  path <- system.file(
    "examples",
    "history-recovery",
    "run.R",
    package = "deputy"
  )
  expect_condition(sys.source(path, envir = new.env()), class = "rlang_error")
  evaluation <- example$history_evaluate(
    function(model) rlang::abort("CREDENTIAL-BEARING-ERROR"),
    example$history_fixture(1L)
  )
  expect_identical(evaluation$failure, list(class = "rlang_error"))
  expect_no_match(
    jsonlite::toJSON(evaluation),
    "CREDENTIAL-BEARING-ERROR",
    fixed = TRUE
  )
})

test_that("repeated checkpoint requests invalidate preparation without replaying data", {
  example <- history_example()
  server <- local_runtime_server(list(
    runtime_reply(tool = "load_checkpoint", arguments = list(stage = 1L)),
    runtime_reply(tool = "load_checkpoint", arguments = list(stage = 1L)),
    runtime_reply("Checkpoint acknowledged.")
  ))
  warnings <- character()
  evaluation <- withCallingHandlers(
    example$history_evaluate(
      function(model) runtime_chat(server),
      example$history_fixture(1L)
    ),
    warning = function(w) {
      warnings <<- c(warnings, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  expect_length(warnings, 1L)
  expect_identical(
    evaluation$failure$class,
    "history_evaluation_repeated_checkpoint"
  )
  expect_length(evaluation$trials, 0L)
  expect_length(evaluation$runs, 1L)
  expect_length(server$requests(), 3L)
  last <- tail(tail(server$requests(), 1L)[[1L]]$body$messages, 1L)[[1L]]
  expect_match(last$content, "only once", fixed = TRUE)
  expect_no_match(last$content, "denominator 80", fixed = TRUE)
})

test_that("a preparation run cannot consume future checkpoints", {
  example <- history_example()
  server <- local_runtime_server(list(
    runtime_reply(tool = "load_checkpoint", arguments = list(stage = 1L)),
    runtime_reply(tool = "load_checkpoint", arguments = list(stage = 2L)),
    runtime_reply(tool = "load_checkpoint", arguments = list(stage = 3L)),
    runtime_reply("All checkpoints acknowledged.")
  ))
  warnings <- character()
  evaluation <- withCallingHandlers(
    example$history_evaluate(
      function(model) runtime_chat(server),
      example$history_fixture(1L)
    ),
    warning = function(w) {
      warnings <<- c(warnings, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  expect_length(warnings, 1L)
  expect_identical(
    evaluation$failure$class,
    "history_evaluation_wrong_checkpoint"
  )
  expect_length(evaluation$trials, 0L)
  expect_length(evaluation$runs, 1L)
  expect_length(server$requests(), 4L)
  expect_no_match(
    jsonlite::toJSON(server$requests()),
    "denominator 84",
    fixed = TRUE
  )
})

test_that("fractional checkpoint arguments cannot masquerade as loaded sources", {
  example <- history_example()
  server <- local_runtime_server(list(
    runtime_reply(tool = "load_checkpoint", arguments = list(stage = 1.5)),
    runtime_reply("Checkpoint acknowledged.")
  ))
  warnings <- character()
  evaluation <- withCallingHandlers(
    example$history_evaluate(
      function(model) runtime_chat(server),
      example$history_fixture(1L)
    ),
    warning = function(w) {
      warnings <<- c(warnings, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  expect_length(warnings, 1L)
  expect_identical(
    evaluation$failure$class,
    "history_evaluation_wrong_checkpoint"
  )
  expect_length(evaluation$trials, 0L)
  expect_length(evaluation$runs, 1L)
  expect_length(server$requests(), 2L)
})

test_that("invalid experiment limits fail before creating a model client", {
  example <- history_example()
  fixture <- example$history_fixture(1L)
  calls <- 0L
  factory <- function(model) {
    calls <<- calls + 1L
    rlang::abort("The provider factory must not be called for invalid limits.")
  }
  for (limit in list(1.5, "2", NA_real_, Inf, TRUE, NULL, 0L)) {
    expect_condition(
      example$history_evaluate(factory, fixture, max_requests = limit),
      class = "rlang_error"
    )
  }
  for (limit in list("2", NA_real_, Inf, TRUE, 0)) {
    expect_condition(
      example$history_evaluate(factory, fixture, max_cost_usd = limit),
      class = "rlang_error"
    )
  }
  for (limit in list(NULL, 1.5, "2", NA_real_, Inf, TRUE, 0L, 2^31)) {
    expect_error(
      example$history_evaluate(factory, fixture, max_tokens = limit),
      "max_tokens"
    )
  }
  expect_identical(calls, 0L)
})

test_that("invalid model selections cannot produce a zero-work evaluation", {
  example <- history_example()
  fixture <- example$history_fixture(1L)
  calls <- 0L
  factory <- function(model) {
    calls <<- calls + 1L
    rlang::abort("The provider factory must not be called for invalid models.")
  }
  for (models in list(
    character(),
    "",
    " ",
    NA_character_,
    1,
    c("luna", "luna")
  )) {
    expect_error(
      example$history_evaluate(factory, fixture, helper_models = models),
      "helper_models"
    )
  }
  for (model in list(character(), "", NA_character_, c("luna", "terra"))) {
    expect_error(
      example$history_evaluate(factory, fixture, task_model = model),
      "task_model"
    )
  }
  expect_identical(calls, 0L)
})

test_that("invalid live configuration leaves the requested output path available", {
  output <- file.path(withr::local_tempdir(), "pilot")
  withr::local_envvar(
    DEPUTY_HISTORY_LIVE = "yes",
    DEPUTY_HISTORY_MAX_COST_USD = "1",
    DEPUTY_HISTORY_OUTPUT = output,
    DEPUTY_HISTORY_HELPERS = "gpt-5.6-luna",
    DEPUTY_HISTORY_TASK_MODEL = "gpt-5.6-luna",
    DEPUTY_HISTORY_SCENARIO = "original"
  )
  path <- system.file(
    "examples",
    "history-recovery",
    "run.R",
    package = "deputy"
  )
  withr::with_envvar(
    c(DEPUTY_HISTORY_TRIALS = "1", DEPUTY_HISTORY_SCENARIO = "unknown"),
    {
      expect_snapshot(error = TRUE, sys.source(path, envir = new.env()))
      expect_identical(dir.exists(output), FALSE)
    }
  )
  for (trials in c("bad", "", "0", "-1", "1.5", "Inf")) {
    withr::with_envvar(c(DEPUTY_HISTORY_TRIALS = trials), {
      expect_error(sys.source(path, envir = new.env()), "trials")
      expect_false(dir.exists(output))
    })
  }
  withr::with_envvar(
    c(DEPUTY_HISTORY_TRIALS = "1", DEPUTY_HISTORY_HELPERS = ""),
    {
      expect_error(sys.source(path, envir = new.env()), "helper_models")
      expect_false(dir.exists(output))
    }
  )
})


test_that("preparation export writes once and binds the verified receipt", {
  example <- history_example()
  fixture <- example$history_fixture(1L)
  directory <- withr::local_tempdir()
  expect_length(fixture$completed_effects, 0L)
  completed <- example$history_export(fixture, directory)
  expect_identical(
    readLines(file.path(directory, "accepted-findings.csv")),
    c("report,responses,denominator", "C,21,84")
  )
  expect_length(completed$completed_effects, 1L)
  receipt <- completed$completed_effects[[1L]]
  records <- example$history_scope_records(completed$records, completed$scope)
  expect_match(
    records$text[records$item_id == "export-receipt-0042"],
    receipt$sha256,
    fixed = TRUE
  )
  expect_snapshot(error = TRUE, example$history_export(completed, directory))
  other <- withr::local_tempdir()
  error <- tryCatch(example$history_export(completed, other), error = identity)
  expect_s3_class(error, "rlang_error")
  expect_length(list.files(other), 0L)
})


test_that("completed preparation effects survive a later failed checkpoint", {
  example <- history_example()
  fixture <- example$history_fixture(1L)
  server <- local_runtime_server(list(
    runtime_reply(tool = "load_checkpoint", arguments = list(stage = 1L)),
    runtime_reply("First checkpoint loaded."),
    runtime_failure(401L)
  ))
  evaluation <- example$history_evaluate(
    function(model) runtime_chat(server),
    fixture,
    trials = 1L,
    max_tokens = 100000L
  )
  expect_length(evaluation$trials, 0L)
  expect_length(evaluation$effects, 1L)
  expect_identical(evaluation$effects[[1L]]$receipt$executions, 1L)
  expect_identical(evaluation$effects[[1L]]$receipt$executor, "host")
  expect_identical(evaluation$failure$class, "history_evaluation_incomplete")
})


test_that("preparation rejects invalid scoped receipts before writing", {
  example <- history_example()
  fixture <- example$history_fixture(1L)
  index <- match("export-receipt-0042", fixture$records$item_id)
  missing <- fixture
  missing$records <- missing$records[-index, , drop = FALSE]
  duplicate <- fixture
  duplicate$records <- rbind(duplicate$records, duplicate$records[index, ])
  stale <- fixture
  stale$records$text[[index]] <- "Changed without a matching revision."
  wrong_stage <- fixture
  wrong_stage$records$stage[[index]] <- 3L
  for (invalid in list(missing, duplicate, stale, wrong_stage)) {
    directory <- withr::local_tempdir()
    expect_setequal(invalid$records$stage, 1:3)
    error <- tryCatch(
      example$history_export(invalid, directory),
      error = identity
    )
    expect_s3_class(error, "rlang_error")
    expect_length(list.files(directory, all.files = TRUE, no.. = TRUE), 0L)
  }
})

test_that("out-of-scope receipt IDs cannot shadow the authorized receipt", {
  example <- history_example()
  fixture <- example$history_fixture(1L)
  index <- match("export-receipt-0042", fixture$records$item_id)
  for (field in names(fixture$scope)) {
    outside <- fixture$records[index, , drop = FALSE]
    outside[[field]] <- paste0("outside-", fixture$scope[[field]])
    outside$text <- "An unrelated export receipt from another scope."
    outside$revision <- digest::digest(
      outside$text,
      algo = "sha256",
      serialize = FALSE
    )
    mixed <- fixture
    mixed$records <- rbind(outside, fixture$records)
    directory <- withr::local_tempdir()
    completed <- example$history_export(mixed, directory)
    expect_identical(completed$records[1L, ], mixed$records[1L, ])
    expect_identical(names(completed$records), names(mixed$records))
    authorized <- example$history_scope_records(
      completed$records,
      completed$scope
    )
    receipt <- authorized[authorized$item_id == "export-receipt-0042", ]
    expect_equal(nrow(receipt), 1L)
    expect_match(
      receipt$text,
      completed$completed_effects[[1L]]$sha256,
      fixed = TRUE
    )
    expect_identical(
      readLines(file.path(directory, "accepted-findings.csv")),
      c("report,responses,denominator", "C,21,84")
    )
  }
})


test_that("malformed planned export metadata is rejected before writing", {
  example <- history_example()
  fixture <- example$history_fixture(1L)
  invalid_values <- list(
    id = list(
      NULL,
      NA_character_,
      "",
      " ",
      "another-export",
      c("first", "second")
    ),
    version = list(NULL, NA_real_, Inf, 0, 1.5, 2L, "1", c(1L, 2L))
  )
  for (field in names(invalid_values)) {
    for (value in invalid_values[[field]]) {
      invalid <- fixture
      invalid$planned_export[[field]] <- value
      directory <- withr::local_tempdir()
      error <- tryCatch(
        example$history_export(invalid, directory),
        error = identity
      )
      expect_s3_class(error, "rlang_error")
      expect_length(list.files(directory, all.files = TRUE, no.. = TRUE), 0L)
    }
  }
})

test_that("preparation rejects a conflicting expected export before writing", {
  example <- history_example()
  fixture <- example$history_fixture(1L)
  fixture$expected$completed_export_id <- "another-export"
  directory <- withr::local_tempdir()
  expect_error(
    example$history_export(fixture, directory),
    "expected export-0042 ID"
  )
  expect_length(list.files(directory, all.files = TRUE, no.. = TRUE), 0L)
})

test_that("preparation rejects a contradictory export payload before writing", {
  example <- history_example()
  fixture <- example$history_fixture(1L)
  for (contents in c(
    "",
    "report,responses,denominator\nD,21,84\n",
    "report,responses,denominator\nC,21,85\n",
    "report,responses,denominator\r\nC,21,84\r\n"
  )) {
    invalid <- fixture
    invalid$planned_export$contents <- contents
    directory <- withr::local_tempdir()
    expect_error(
      example$history_export(invalid, directory),
      "fixed export receipt digest"
    )
    expect_length(list.files(directory, all.files = TRUE, no.. = TRUE), 0L)
  }
})

test_that("the completed source receipt describes the verified export", {
  example <- history_example()
  fixture <- example$history_fixture(1L)
  index <- match("export-receipt-0042", fixture$records$item_id)
  fixture$records$text[[
    index
  ]] <- "Unverified placeholder: this export contains D."
  fixture$records$revision[[index]] <- digest::digest(
    fixture$records$text[[index]],
    algo = "sha256",
    serialize = FALSE
  )
  directory <- withr::local_tempdir()
  completed <- example$history_export(fixture, directory)
  expect_match(completed$records$text[[index]], "C only", fixed = TRUE)
  expect_false(grepl("Unverified placeholder", completed$records$text[[index]]))
  expect_identical(
    completed$completed_effects[[1L]]$contents,
    c("report,responses,denominator", "C,21,84")
  )
  expect_no_error(example$history_scope_records(
    completed$records,
    completed$scope
  ))
})

history_batch_reply <- function(ids, prefix) {
  reply <- runtime_reply(tool = "history_read")
  chunks <- strsplit(reply$body, "\n\n", fixed = TRUE)[[1L]]
  first <- jsonlite::fromJSON(
    substring(chunks[[1L]], 7L),
    simplifyVector = FALSE
  )
  first$choices[[1L]]$delta$tool_calls <- lapply(seq_along(ids), function(i) {
    list(
      index = i - 1L,
      id = paste0(prefix, i),
      type = "function",
      `function` = list(
        name = "history_read",
        arguments = as.character(jsonlite::toJSON(
          list(item_id = ids[[i]]),
          auto_unbox = TRUE
        ))
      )
    )
  })
  chunks[[1L]] <- paste0(
    "data: ",
    jsonlite::toJSON(first, auto_unbox = TRUE, null = "null")
  )
  reply$body <- paste0(paste(chunks, collapse = "\n\n"), "\n\n")
  reply
}

test_that("budget feedback counts attempts and fits inside the byte ceiling", {
  example <- history_example()
  fixture <- example$history_fixture(1L)
  access <- example$history_access(
    fixture$records,
    fixture$scope,
    max_calls = 2L,
    max_response_bytes = 512L,
    max_total_bytes = 2048L,
    budget_feedback = TRUE
  )
  first <- access$read("assay-C-r3")
  expect_lte(nchar(first, type = "bytes"), 512L)
  expect_identical(jsonlite::fromJSON(first)$budget$remaining_calls, 1L)
  expect_identical(
    jsonlite::fromJSON(first)$budget$remaining_bytes_before_response,
    2048L
  )
  second <- access$search("no-such-evidence")
  expect_identical(jsonlite::fromJSON(second)$items, list())
  expect_identical(jsonlite::fromJSON(second)$budget$remaining_calls, 0L)
  expect_identical(
    jsonlite::fromJSON(second)$budget$remaining_bytes_before_response,
    2048L - nchar(first, type = "bytes")
  )
  expect_condition(access$read("assay-C-r3"), class = "ellmer_tool_reject")
  expect_identical(access$usage()$calls, 3L)
  expect_identical(access$usage()$remaining_calls, 0L)
  expect_identical(
    access$usage()$bytes,
    nchar(first, type = "bytes") + nchar(second, type = "bytes")
  )
  expect_identical(tail(access$audit(), 1L)[[1L]]$bytes, 0L)
  expect_match(access$tools[[1L]]@description, "share 2 calls", fixed = TRUE)
  exhausted <- example$history_access(
    fixture$records,
    fixture$scope,
    max_calls = 6L,
    max_total_bytes = 0L,
    budget_feedback = TRUE
  )
  expect_condition(
    exhausted$read("assay-C-r3"),
    "5 calls and 0 bytes remain",
    class = "ellmer_tool_reject"
  )
  expect_identical(exhausted$usage()$bytes, 0L)
})

test_that("a batch beyond remaining history access still reaches the reserved answer", {
  example <- history_example()
  fixture <- example$history_fixture(1L)
  answer <- c(fixture$expected, list(source_ids = fixture$required_sources))
  prepared <- list(
    system_prompt = "Read-only host policy.",
    turns = list(),
    summary_id = "fixture"
  )
  server <- local_runtime_server(list(
    history_batch_reply(fixture$required_sources[1:4], "first_"),
    history_batch_reply(
      c(
        fixture$required_sources[[5L]],
        "assay-C-r2",
        "quoted-untrusted-instruction"
      ),
      "second_"
    ),
    runtime_reply("Source inspection complete."),
    runtime_reply("Answer from the available evidence."),
    runtime_reply(
      as.character(jsonlite::toJSON(answer, auto_unbox = TRUE)),
      stream = FALSE
    )
  ))
  budget <- example$history_budget()
  row <- suppressWarnings(example$history_continue(
    fixture,
    prepared,
    runtime_chat(server),
    budget,
    "batched",
    "history",
    protocol = "budget-aware"
  ))
  expect_identical(row$score$all_correct, TRUE)
  expect_identical(row$history_usage$calls, 7L)
  expect_identical(tail(row$history_audit, 1L)[[1L]]$status, "budget_exhausted")
  expect_identical(tail(row$history_audit, 1L)[[1L]]$bytes, 0L)
  expect_identical(row$usage$requests, 5L)
  expect_identical(row$usage$tool_calls, 7L)
  expect_identical(row$phase_runs[[2L]]$usage$tool_calls, 0L)
  expect_equal(row$usage$cost_usd, budget$usage()$cost_usd)
  expect_identical(
    vapply(
      tail(server$requests(), 2L),
      function(x) length(x$body$tools),
      integer(1)
    ),
    c(0L, 0L)
  )
  expect_identical(row$repeated_effects, 0L)
})

test_that("retrieval request exhaustion preserves two final requests within eight", {
  example <- history_example()
  fixture <- example$history_fixture(1L)
  answer <- c(fixture$expected, list(source_ids = character()))
  prepared <- list(
    system_prompt = "Read-only host policy.",
    turns = list(),
    summary_id = "fixture"
  )
  server <- local_runtime_server(local({
    reply <- runtime_reply
    function(request, count) {
      if (length(request$tools)) {
        return(reply(
          tool = "history_read",
          arguments = list(item_id = paste0("missing-", count))
        ))
      }
      if (!is.null(request$response_format)) {
        return(reply(
          as.character(jsonlite::toJSON(answer, auto_unbox = TRUE)),
          stream = FALSE
        ))
      }
      reply("Answer using the available context.")
    }
  }))
  row <- example$history_continue(
    fixture,
    prepared,
    runtime_chat(server),
    example$history_budget(),
    "limited",
    "history",
    protocol = "budget-aware"
  )
  expect_identical(row$phase_runs[[1L]]$stop_reason, "request_limit")
  expect_identical(row$phase_runs[[1L]]$usage$requests, 6L)
  expect_identical(row$phase_runs[[2L]]$usage$requests, 2L)
  expect_identical(row$usage$requests, 8L)
  expect_length(server$requests(), 8L)
  expect_type(row$answer, "list")
  expect_identical(row$score$checks$grounded_sources, FALSE)
  expect_identical(row$repeated_effects, 0L)
})

test_that("a blocked final dispatch retains an explicit incomplete continuation", {
  example <- history_example()
  fixture <- example$history_fixture(1L)
  prepared <- list(
    system_prompt = "Read-only host policy.",
    turns = list(),
    summary_id = "fixture"
  )
  server <- local_runtime_server(list(
    runtime_reply(
      tool = "history_read",
      arguments = list(item_id = "assay-C-r3")
    ),
    runtime_reply("There is no remaining history access.")
  ))
  budget <- example$history_budget(cancelled = function() {
    length(budget$records()) > 0L
  })
  row <- suppressWarnings(example$history_continue(
    fixture,
    prepared,
    runtime_chat(server),
    budget,
    "cancelled-answer",
    "history",
    access_limits = list(max_calls = 0L),
    protocol = "budget-aware"
  ))
  expect_null(row$answer)
  expect_identical(row$score$score, 0)
  expect_identical(row$stop_reason, "history_evaluation_cancelled")
  expect_identical(row$history_usage$bytes, 0L)
  expect_identical(row$history_audit[[1L]]$status, "budget_exhausted")
  expect_identical(row$phase_runs[[2L]]$dispatched, FALSE)
  expect_length(server$requests(), 2L)
  expect_identical(row$usage$requests, 2L)
  expect_true(row$attempted)
})

test_that("cancellation before the first request retains an undispatched arm", {
  example <- history_example()
  fixture <- example$history_fixture(1L)
  server <- local_runtime_server(list())
  row <- example$history_continue(
    fixture,
    list(
      system_prompt = "Read-only host policy.",
      turns = list(),
      summary_id = "fixture"
    ),
    runtime_chat(server),
    example$history_budget(cancelled = function() TRUE),
    "cancelled-start",
    "summary"
  )
  expect_false(row$attempted)
  expect_identical(row$usage$requests, 0L)
  expect_null(row$answer)
  expect_identical(row$stop_reason, "history_evaluation_cancelled")
  expect_identical(row$phase_runs[[1L]]$dispatched, FALSE)
  expect_length(server$requests(), 0L)
})

test_that("an oversized provider batch cannot consume the reserved answer phase", {
  example <- history_example()
  fixture <- example$history_fixture(1L)
  answer <- c(fixture$expected, list(source_ids = fixture$required_sources))
  prepared <- list(
    system_prompt = "Read-only host policy.",
    turns = list(),
    summary_id = "fixture"
  )
  server <- local_runtime_server(list(
    history_batch_reply(fixture$required_sources[1:4], "first_"),
    history_batch_reply(
      c(fixture$required_sources[[5L]], "assay-C-r2", paste0("missing-", 1:4)),
      "second_"
    ),
    runtime_reply("Answer from the available evidence."),
    runtime_reply(
      as.character(jsonlite::toJSON(answer, auto_unbox = TRUE)),
      stream = FALSE
    )
  ))
  row <- suppressWarnings(example$history_continue(
    fixture,
    prepared,
    runtime_chat(server),
    example$history_budget(),
    "oversized",
    "history",
    protocol = "budget-aware"
  ))
  expect_identical(row$phase_runs[[1L]]$stop_reason, "tool_call_limit")
  expect_identical(row$phase_runs[[1L]]$tool_call_limit, 8L)
  expect_identical(row$phase_runs[[2L]]$tool_call_limit, 0L)
  expect_identical(row$usage$requests, 4L)
  expect_length(server$requests(), 4L)
  expect_gte(row$usage$tool_calls, 9L)
  expect_identical(
    sum(vapply(
      row$history_audit,
      function(entry) length(entry$item_ids) > 0L,
      logical(1)
    )),
    6L
  )
  expect_identical(row$score$all_correct, TRUE)
  expect_identical(row$repeated_effects, 0L)
})

test_that("unknown or duplicate protocols are rejected before model dispatch", {
  example <- history_example()
  fixture <- example$history_fixture(1L)
  calls <- 0L
  factory <- function(model) {
    calls <<- calls + 1L
    stop("Unexpected model dispatch")
  }
  for (protocols in list(
    character(),
    NA_character_,
    "unknown",
    c("baseline", "baseline")
  )) {
    expect_snapshot(
      error = TRUE,
      example$history_evaluate(factory, fixture, protocols = protocols)
    )
  }
  expect_identical(calls, 0L)
})

test_that("history reporting separates completion latency and source payloads", {
  example <- history_example()
  fixture <- example$history_fixture(1L)
  row <- list(
    helper_model = "fixture",
    strategy = "history",
    protocol = "budget-aware",
    trial_id = "fixture/1",
    answer = fixture$expected,
    score = list(
      score = 1,
      all_correct = TRUE,
      checks = list(grounded_sources = TRUE)
    ),
    duration_seconds = 8,
    stop_reason = "completed",
    usage = list(
      requests = 2L,
      tool_calls = 3L,
      total_tokens = 30,
      cost_usd = 0.01
    ),
    history_usage = list(calls = 3L, bytes = 220L),
    history_audit = list(
      list(
        operation = "search",
        status = "ok",
        item_ids = character(),
        bytes = 20L
      ),
      list(
        operation = "read",
        status = "ok",
        item_ids = "source",
        bytes = 200L
      ),
      list(
        operation = "read",
        status = "budget_exhausted",
        item_ids = character(),
        bytes = 0L
      )
    ),
    completed_effects_before = list(),
    attempted_exports = 2L,
    repeated_effects = 1L
  )
  incomplete <- row
  incomplete$trial_id <- "fixture/2"
  incomplete$answer <- NULL
  incomplete$score <- list(
    score = 0,
    all_correct = FALSE,
    checks = list(grounded_sources = FALSE)
  )
  incomplete$duration_seconds <- 0.2
  incomplete$stop_reason <- "request_limit"
  evaluation <- list(
    trials = list(row, incomplete),
    case_id = fixture$case_id,
    configuration = list(
      trials = 1L,
      helper_models = "fixture",
      continuation_arms = 2L
    ),
    usage = list(requests = 4L, cost_usd = 0.02),
    runs = list()
  )
  report <- paste(example$history_report(evaluation), collapse = "\n")
  expect_match(
    report,
    "| fixture/history/budget-aware | 2 | 2 | 0 | 1 | 0.500 | 1 | 8.00 | 0.20 |",
    fixed = TRUE
  )
  expect_match(
    report,
    "| fixture/1 | history/budget-aware | none | 3 | 0 | 1 | 220 | 0 | 2 | 1 |",
    fixed = TRUE
  )
  expect_match(
    report,
    "Expected 2 continuations; attempted 2; missing 0 (0 undispatched, 0 not recorded).",
    fixed = TRUE
  )

  never <- incomplete
  never$trial_id <- "fixture/3"
  never$attempted <- FALSE
  never$usage$requests <- 0L
  never$duration_seconds <- 0
  never$stop_reason <- "history_evaluation_cancelled"
  blocked_reference <- never
  blocked_reference$trial_id <- row$trial_id
  blocked_reference$strategy <- "summary"
  blocked_reference$protocol <- "baseline"
  blocked_baseline <- never
  blocked_baseline$trial_id <- incomplete$trial_id
  blocked_baseline$protocol <- "baseline"
  started_reference <- row
  started_reference$trial_id <- incomplete$trial_id
  started_reference$strategy <- "summary"
  started_reference$protocol <- "baseline"
  evaluation$trials <- list(
    row,
    incomplete,
    never,
    blocked_reference,
    blocked_baseline,
    started_reference
  )
  evaluation$configuration$trials <- 3L
  evaluation$configuration$continuation_arms <- 3L
  partial <- paste(example$history_report(evaluation), collapse = "\n")
  expect_match(
    partial,
    "| fixture/history/budget-aware | 3 | 2 | 1 | 1 | 0.500 | 1 | 8.00 | 0.20 |",
    fixed = TRUE
  )
  expect_match(
    partial,
    "| fixture/history/baseline | 1 | 0 | 1 | 0 | not observed | 0 | not observed | not observed |",
    fixed = TRUE
  )
  expect_match(
    partial,
    "| fixture/1 | budget-aware | missing comparison | missing comparison |",
    fixed = TRUE
  )
  expect_match(
    partial,
    "| fixture/2 | baseline | missing comparison | missing comparison |",
    fixed = TRUE
  )
  expect_match(
    partial,
    "| fixture/3 | history/budget-aware | FALSE | missing | not scored | 0 |",
    fixed = TRUE
  )
  expect_match(
    partial,
    "Expected 9 continuations; attempted 3; missing 6 (3 undispatched, 3 not recorded).",
    fixed = TRUE
  )
})
