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

test_that("paired continuations use real compaction, retrieval and structured output", {
  example <- history_example()
  fixture <- example$history_fixture(1L)
  answer <- c(fixture$expected, list(source_ids = fixture$required_sources))
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
        return(reply(tool = "load_checkpoint", arguments = list(stage = stage)))
      }
      tools <- vapply(
        request$tools,
        function(tool) tool$`function`$name,
        character(1)
      )
      if ("history_read" %in% tools) {
        return(reply(
          tool = "history_read",
          arguments = list(item_id = "assay-C-r3")
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
    max_tokens = 500L
  )
  expect_null(evaluation$failure)
  expect_length(evaluation$trials, 4L)
  expect_identical(
    vapply(evaluation$trials, `[[`, character(1), "strategy"),
    c("summary", "history", "history", "summary")
  )
  for (rows in split(evaluation$trials, rep(1:2, each = 2L))) {
    expect_identical(rows[[1L]]$summary_id, rows[[2L]]$summary_id)
    expect_equal(rows[[1L]]$transitions, 3L)
    expect_identical(
      vapply(rows, function(row) row$score$all_correct, logical(1)),
      c(TRUE, TRUE)
    )
    expect_identical(
      vapply(rows, `[[`, integer(1), "repeated_effects"),
      c(0L, 0L)
    )
  }
  history <- Filter(function(row) row$strategy == "history", evaluation$trials)
  expect_identical(history[[1L]]$history_audit[[1L]]$item_ids, "assay-C-r3")
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
  prompts <- jsonlite::toJSON(server$requests())
  expect_match(prompts, "denominator 84", fixed = TRUE)
  expect_no_match(prompts, "PRIVATE-", fixed = TRUE)
  expect_gt(evaluation$usage$requests, 16L)
  expect_gt(evaluation$usage$cost_usd, 0)
  expect_type(
    jsonlite::toJSON(evaluation, auto_unbox = TRUE, null = "null"),
    "character"
  )
})

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
    DEPUTY_HISTORY_TASK_MODEL = "gpt-5.6-luna"
  )
  path <- system.file(
    "examples",
    "history-recovery",
    "run.R",
    package = "deputy"
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
