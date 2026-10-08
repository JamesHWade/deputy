commons_example_directory <- function() {
  source <- test_path("..", "..", "inst", "examples", "commons-subagents")
  if (dir.exists(source)) {
    return(normalizePath(source))
  }
  system.file(
    "examples",
    "commons-subagents",
    package = "deputy",
    mustWork = TRUE
  )
}

commons_example_environment <- function() {
  environment <- new.env(parent = as.environment("package:deputy"))
  directory <- commons_example_directory()
  sys.source(file.path(directory, "fixture.R"), envir = environment)
  sys.source(file.path(directory, "workflow.R"), envir = environment)
  environment
}

commons_example_skip <- function() {
  skip_if_not_installed("commons")
  skip_if_not_installed("callr")
  skip_if_not_installed("httpuv")
  skip_if_not(capabilities("png"), "PNG graphics are unavailable")
}

# A running example: its local server, a workflow and cleanup.
commons_example_local <- function(
  slow = 0.5,
  on_result = function(event) NULL,
  .local_envir = parent.frame()
) {
  example <- commons_example_environment()
  fixture <- example$commons_local_fixture(delay = 0.01, slow = slow)
  withr::defer(fixture$close(), envir = .local_envir)
  workflow <- example$commons_example_workflow(fixture, on_result = on_result)
  withr::defer(
    example$commons_example_release(workflow),
    envir = .local_envir
  )
  list(example = example, fixture = fixture, workflow = workflow)
}

# Runs the event loop until `ready()` is true, failing the test after
# `seconds` instead of hanging it.
commons_wait <- function(ready, what, seconds = 60) {
  deadline <- Sys.time() + seconds
  while (!ready()) {
    if (Sys.time() > deadline) {
      cli::cli_abort("{what} took more than {seconds} seconds.")
    }
    later::run_now(0.02)
  }
}

commons_collect <- function(agent, task) {
  stream <- agent$stream_async(task, stream = "content")
  seen <- list()
  done <- FALSE
  failure <- NULL
  coro::async(function() {
    tryCatch(
      for (chunk in coro::await_each(stream)) {
        seen[[length(seen) + 1L]] <<- chunk
      },
      error = function(error) failure <<- error
    )
    done <<- TRUE
  })()
  commons_wait(function() done, "The reply")
  if (!is.null(failure)) {
    rlang::cnd_signal(failure)
  }
  seen
}

commons_cards <- function(contents) {
  Filter(is_activity_content, contents)
}

commons_label <- function(card) card@extra$deputy_activity$label

commons_results_by_label <- function(cards) {
  results <- Filter(
    function(card) inherits(card, "ellmer::ContentToolResult"),
    cards
  )
  split(results, vapply(results, commons_label, character(1)))
}

test_that("concurrent Commons specialists, a grandchild and a failure share one conversation", {
  commons_example_skip()
  skip_if_not_installed("xml2")
  local <- commons_example_local()
  workflow <- local$workflow
  root <- workflow$root
  activity_enable(root, function() "demo-user", 0.02)
  warnings <- character()
  seen <- withCallingHandlers(
    commons_collect(root, "Report revenue by region and on-time delivery."),
    warning = function(warning) {
      warnings <<- c(warnings, conditionMessage(warning))
      invokeRestart("muffleWarning")
    }
  )
  expect_match(paste(warnings, collapse = "\n"), "Subagent 'ops' failed")

  # Each measure ran once and reached the root once, from its own agent.
  expect_identical(workflow$effects$runs, 4L)
  events <- workflow$delivered$events
  expect_length(events, 4L)
  expect_length(unique(vapply(events, function(e) e$result_id, "")), 4L)
  from <- vapply(events, function(e) e$agent_name, character(1))
  expect_setequal(from, c("sales", "sales", "ops", "auditor"))
  expect_identical(
    unique(vapply(events, function(e) e$tool_fingerprint, "")),
    approval_tool_fingerprint(workflow$tools$call_measure)
  )
  auditor <- events[[which(from == "auditor")]]
  expect_identical(auditor$parent_agent_id, workflow$agents$sales$agent_id)
  expect_identical(
    sort(vapply(events, function(e) e$arguments$name, character(1))),
    c("on_time_rate", "revenue_by_region", "revenue_chart", "total_revenue")
  )

  # The cards: who made each call, paired, with Commons' displays intact
  # and inert.
  cards <- commons_cards(seen)
  results <- commons_results_by_label(cards)
  expect_setequal(names(results), c("sales", "ops", "auditor (via sales)"))
  expect_length(results$sales, 3L)
  expect_length(results$ops, 1L)
  expect_length(results[["auditor (via sales)"]], 1L)
  requests <- Filter(
    function(card) inherits(card, "ellmer::ContentToolRequest"),
    cards
  )
  expect_setequal(
    unname(vapply(requests, function(card) card@id, character(1))),
    unname(vapply(
      Filter(function(card) inherits(card, "ellmer::ContentToolResult"), cards),
      function(card) card@request@id,
      character(1)
    ))
  )
  html <- vapply(
    results$sales,
    function(card) card@extra$display$html %||% "",
    character(1)
  )
  expect_true(any(grepl("<table", html, fixed = TRUE)))
  expect_true(any(grepl("East", html, fixed = TRUE)))
  expect_true(any(grepl(
    "<img src=\"data:image/png;base64,",
    html,
    fixed = TRUE
  )))
  for (card in Filter(
    function(card) inherits(card, "ellmer::ContentToolResult"),
    cards
  )) {
    shown <- paste(unlist(card@extra$display), collapse = " ")
    expect_no_match(shown, "<script|\\son[a-z]+=|https?://")
  }
  measures <- Filter(
    function(card) identical(card@request@name, "call_measure"),
    Filter(function(card) inherits(card, "ellmer::ContentToolResult"), cards)
  )
  expect_length(measures, 4L)
  expect_identical(
    unique(vapply(measures, function(card) card@extra$commons_tag, "")),
    "A"
  )
  lineage <- results[["auditor (via sales)"]][[1L]]@extra$deputy_activity
  rows <- root$list_subagents()
  expect_identical(lineage$depth, 2L)
  expect_identical(
    lineage$parent_delegation_id,
    rows$delegation_id[rows$agent_name == "sales"]
  )

  # The failed specialist leaves the rest of the reply standing.
  expect_identical(rows$status[rows$agent_name == "ops"], "failed")
  expect_identical(rows$status[rows$agent_name == "sales"], "completed")
  expect_match(root$last_turn()@text, "operations check failed")
  expect_false(any(vapply(
    unlist(lapply(root$get_context_turns(), function(turn) turn@contents)),
    is_activity_content,
    logical(1)
  )))
})

test_that("a second delegation to the same Commons specialist is numbered", {
  commons_example_skip()
  local <- commons_example_local()
  root <- local$workflow$root
  activity_enable(root, function() "demo-user", 0.02)
  suppressWarnings(commons_collect(
    root,
    "Report revenue by region and on-time delivery."
  ))
  again <- commons_cards(commons_collect(root, "Ask sales again."))
  expect_identical(unique(vapply(again, commons_label, "")), "sales #2")
  expect_length(local$workflow$delivered$events, 5L)
})

test_that("cancelling a slow Commons specialist stops only that work", {
  commons_example_skip()
  local <- commons_example_local(slow = 0.5)
  root <- local$workflow$root
  activity_enable(root, function() "demo-user", 0.02)
  stream <- root$stream_async(
    "Run a slow operations check.",
    stream = "content"
  )
  seen <- list()
  done <- FALSE
  coro::async(function() {
    for (chunk in coro::await_each(stream)) {
      seen[[length(seen) + 1L]] <<- chunk
    }
    done <<- TRUE
  })()
  deadline <- Sys.time() + 10
  repeat {
    later::run_now(0.02)
    rows <- root$list_subagents()
    if (any(rows$agent_name == "ops" & rows$status == "running")) {
      break
    }
    if (Sys.time() > deadline) {
      cli::cli_abort("The operations specialist never started.")
    }
  }
  root$interrupt_subagent(
    rows$delegation_id[rows$agent_name == "ops"],
    "user_cancelled"
  )
  suppressWarnings(commons_wait(function() done, "The cancelled reply", 30))
  rows <- root$list_subagents()
  expect_identical(rows$status, "stopped")
  expect_identical(rows$stop_reason, "user_cancelled")
  expect_length(local$workflow$delivered$events, 0L)
  expect_identical(local$workflow$effects$runs, 0L)
  expect_match(root$last_turn()@text, "stopped before it finished")
})

test_that("a reopened conversation shows the same cards and records and runs nothing", {
  commons_example_skip()
  skip_if_not_installed("shiny")
  skip_if_not_installed("shinychat", "0.5.0")
  skip_if_not_installed("bslib")
  skip_if_not_installed("commonmark")
  skip_if_not_installed("xml2")
  example <- commons_example_environment()
  fixture <- example$commons_local_fixture(delay = 0.01)
  withr::defer(fixture$close())
  effects <- example$commons_example_effects()
  store <- shinychat::FileConversationStore$new(withr::local_tempdir())
  options <- shinychat::history_options(
    restore_mode = "none",
    store = store,
    scope = "demo",
    title = NULL
  )
  session_with <- function(workflow, body) {
    shiny::testServer(
      function(input, output, session) {
        root <- workflow$root
        chat <- shinychat::chat_server("chat", root, history = options)
        subagent_chat_activity(chat, root, function() "demo-user", 50L)
        session$userData$chat <- chat
        session$userData$saved <- subagent_chat_history(
          chat,
          root,
          function() "demo-user"
        )
      },
      {
        session$flushReact()
        body(session, session$userData$chat, session$userData$saved)
      }
    )
  }
  recorded_cards <- function(root) {
    lapply(
      commons_cards(unlist(lapply(root$get_turns(), function(turn) {
        turn@contents
      }))),
      ellmer::contents_record
    )
  }

  # The app's own list of trusted results, updated as the app updates it.
  trusted <- example$commons_example_results()
  first <- example$commons_example_workflow(
    fixture,
    effects,
    on_result = trusted$on_result
  )
  withr::defer(example$commons_example_release(first))
  conversation <- NULL
  live <- NULL
  live_turns <- NULL
  warnings <- character()
  withCallingHandlers(
    session_with(first, function(session, chat, saved) {
      session$setInputs(
        chat_user_input = "Report revenue by region and on-time delivery."
      )
      deadline <- Sys.time() + 60
      while (
        is.null(shiny::isolate(chat$history$conversation_id())) ||
          !identical(shiny::isolate(chat$status()), "idle") ||
          !identical(saved$status()$saved, 3L)
      ) {
        if (Sys.time() > deadline) {
          cli::cli_abort("The reply was never saved.")
        }
        later::run_now(0.02)
        session$flushReact()
      }
      conversation <<- shiny::isolate(chat$history$conversation_id())
      live <<- recorded_cards(first$root)
      live_turns <<- lapply(first$root$get_turns(), ellmer::contents_record)
    }),
    warning = function(warning) {
      warnings <<- c(warnings, conditionMessage(warning))
      invokeRestart("muffleWarning")
    }
  )
  expect_match(paste(warnings, collapse = "\n"), "Subagent 'ops' failed")
  expect_length(live, 10L)
  expect_length(live_turns, 4L)
  # Every measure reached the app's list once, so every call succeeded.
  expect_length(shiny::isolate(trusted$results()), 4L)
  shown <- Filter(
    function(card) identical(card$class, "ellmer::ContentToolResult"),
    live
  )
  expect_length(shown, 5L)
  expect_true(all(vapply(
    shown,
    function(card) is.null(card$props$error),
    logical(1)
  )))
  runs <- effects$runs
  requests <- length(fixture$requests())
  expect_identical(runs, 4L)

  # A new session with new agents opens the saved conversation.
  second <- example$commons_example_workflow(fixture, effects)
  withr::defer(example$commons_example_release(second))
  # Reading the saved conversation back raises no warnings either.
  expect_no_warning(session_with(second, function(session, chat, saved) {
    session$setInputs(chat_history_select = list(id = conversation))
    session$flushReact()
    # Every turn comes back, the failed delegation's tool error included.
    expect_identical(
      lapply(second$root$get_turns(), ellmer::contents_record),
      live_turns
    )
    expect_identical(recorded_cards(second$root), live)
    views <- saved$restored(transcript = FALSE)
    names <- vapply(views, function(view) view$outcome$runtime$agent_name, "")
    expect_setequal(names, c("sales", "ops", "auditor"))
    status <- vapply(views, function(view) view$outcome$runtime$status, "")
    expect_identical(status[names == "ops"], "failed")
    by_name <- stats::setNames(views, names)
    expect_identical(
      by_name$auditor$outcome$runtime$parent_delegation_id,
      by_name$sales$outcome$runtime$delegation_id
    )
    sales <- saved$restored()[[which(names == "sales")]]
    shown <- unlist(lapply(sales$turns, function(turn) turn@contents))
    displays <- Filter(
      function(content) inherits(content, "ellmer::ContentToolResult"),
      shown
    )
    expect_true(any(vapply(
      displays,
      function(content) {
        grepl("data:image/png;base64,", content@extra$display$html %||% "")
      },
      logical(1)
    )))
  }))
  # Reopening ran nothing and delivered nothing again.
  expect_identical(effects$runs, runs)
  expect_identical(length(fixture$requests()), requests)
  expect_length(second$delivered$events, 0L)
  expect_length(second$root$list_subagents()$delegation_id, 0L)
})

test_that("a failed delivery reaches each Commons specialist as a tool error", {
  commons_example_skip()
  attempts <- 0L
  local <- commons_example_local(on_result = function(event) {
    attempts <<- attempts + 1L
    stop("results store offline")
  })
  root <- local$workflow$root
  activity_enable(root, function() "demo-user", 0.02)
  seen <- suppressWarnings(commons_collect(
    root,
    "Report revenue by region and on-time delivery."
  ))
  expect_identical(attempts, 4L)
  expect_length(local$workflow$delivered$events, 4L)
  measures <- Filter(
    function(card) {
      inherits(card, "ellmer::ContentToolResult") &&
        identical(card@request@name, "call_measure")
    },
    commons_cards(seen)
  )
  expect_length(measures, 4L)
  for (card in measures) {
    expect_match(card@error, "could not be delivered")
  }
})

test_that("Commons specialists outside the strict configuration are refused", {
  commons_example_skip()
  example <- commons_example_environment()
  fixture <- example$commons_local_fixture(delay = 0.01)
  withr::defer(fixture$close())
  data <- example$commons_example_data()
  layer <- example$commons_example_layer(
    data,
    example$commons_example_effects()
  )
  pool <- example$commons_example_chat(fixture, "pool", data, layer)
  tools <- example$commons_strict_tools(pool)
  root <- Agent$new(
    fixture$chat("root"),
    trusted_results = TrustedResults(measure = tools$call_measure)
  )
  graph <- function(specialist) {
    root$retain_agent_graph(
      agents = list(sales = specialist),
      routes = list(
        root = list(
          ask_sales = list(
            target = "sales",
            description = "Ask sales.",
            usage_limits = UsageLimits(max_requests = 2)
          )
        )
      ),
      usage_limits = UsageLimits(max_requests = 4),
      max_depth = 1L,
      max_delegations = 2L,
      max_concurrency = 1L
    )
  }
  # Commons as it ships: its SQL and R tools could compute anything.
  ordinary <- Agent$new(example$commons_example_chat(
    fixture,
    "sales",
    data,
    layer
  ))
  expect_error(graph(ordinary), class = "deputy_tool_registration")
  # Strict, but with its own call_measure rather than the pool's.
  own <- example$commons_example_chat(fixture, "sales", data, layer)
  own$set_tools(example$commons_strict_tools(own))
  expect_error(
    graph(Agent$new(own)),
    "must be the tool named in the policy"
  )
  expect_length(root$get_tools(), 0L)
  expect_length(root$.__enclos_env__$private$owned_conversations, 0L)
})
