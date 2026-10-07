history_disclosure <- function(state = NULL) {
  DelegationDisclosure(
    authorize = function(requester, scope) {
      identical(requester, "viewer") && !isTRUE(state$denied)
    }
  )
}

history_measure_tool <- function(value, counter) {
  ellmer::tool(
    function() {
      counter$calls <- counter$calls + 1L
      ellmer::ContentToolResult(
        value = value,
        extra = list(
          display = list(
            title = "Ran a trusted calculation",
            html = paste0("<div class=\"measure\">", value, "</div>")
          ),
          commons_tag = "A"
        )
      )
    },
    name = "call_measure",
    description = "Run a registered measure.",
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE
    )
  )
}

# A lead with one retained specialist behind `ask_sales`. Pass `NULL` servers
# for a lead that must never call a model.
history_lead <- function(
  root,
  sales,
  counter,
  scope = list(owner_id = "u1"),
  state = NULL,
  value = 60
) {
  offline <- list(url = "http://127.0.0.1:9/v1")
  lead <- Agent$new(
    runtime_chat(root %||% offline),
    delegation_disclosure = history_disclosure(state),
    delegation_scope = scope
  )
  specialist <- Agent$new(
    runtime_chat(sales %||% offline),
    tools = list(history_measure_tool(value, counter)),
    agent_name = "sales"
  )
  handle <- lead$retain_agent(specialist, UsageLimits(max_requests = 8))
  lead$register_tool(delegation_tool(
    lead,
    handle,
    "ask_sales",
    "Ask the sales specialist.",
    UsageLimits(max_requests = 4)
  ))
  lead
}

history_root_server <- function(.local_envir = parent.frame()) {
  local_runtime_server(
    list(
      runtime_reply(tool = "ask_sales", arguments = list(task = "Revenue?")),
      runtime_reply("Lead: revenue is 60.")
    ),
    .local_envir = .local_envir
  )
}

history_sales_server <- function(.local_envir = parent.frame()) {
  local_runtime_server(
    list(
      runtime_reply(tool = "call_measure"),
      runtime_reply("Total revenue is 60.")
    ),
    .local_envir = .local_envir
  )
}

# shinychat's file store, keeping each record as it reads back from disk.
HistoryTestStore <- R6::R6Class(
  "HistoryTestStore",
  inherit = shinychat::ConversationStore,
  public = list(
    inner = NULL,
    saved = list(),
    initialize = function(dir) {
      self$inner <- shinychat::FileConversationStore$new(dir)
    },
    list = function(partition) self$inner$list(partition),
    get = function(partition, id) self$inner$get(partition, id),
    put = function(partition, record) {
      self$inner$put(partition, record)
      self$saved[[record$id]] <- self$inner$get(partition, record$id)
      invisible(NULL)
    },
    delete = function(partition, id) self$inner$delete(partition, id)
  )
)

history_wait <- function(session, done, timeout = 60) {
  deadline <- Sys.time() + timeout
  while (!isTRUE(done())) {
    if (Sys.time() > deadline) {
      cli::cli_abort("Timed out waiting for the chat.")
    }
    later::run_now(0.02)
    session$flushReact()
  }
}

history_submit <- function(session, chat, store, text) {
  before <- shiny::isolate(chat$history$conversation_id())
  count <- if (is.null(before)) 0L else store$saved[[before]]$response_count
  session$setInputs(chat_user_input = text)
  history_wait(session, function() {
    id <- shiny::isolate(chat$history$conversation_id())
    !is.null(id) &&
      (store$saved[[id]]$response_count %||% 0L) > count &&
      identical(shiny::isolate(chat$status()), "idle")
  })
  shiny::isolate(chat$history$conversation_id())
}

# Run `body(session, chat, saver)` in a Shiny session whose chat runs `lead`
# with history kept in `store`.
history_session <- function(lead, store, body, panel = FALSE) {
  skip_if_not_installed("shiny")
  skip_if_not_installed("shinychat", "0.5.0")
  skip_if_not_installed("bslib")
  shiny::testServer(
    function(input, output, session) {
      chat <- shinychat::chat_server(
        "chat",
        lead,
        history = shinychat::history_options(
          restore_mode = "none",
          store = store,
          scope = "test",
          title = NULL
        )
      )
      subagent_chat_activity(chat, lead, function() "viewer")
      saver <- subagent_chat_history(chat, lead, function() "viewer")
      session$userData$chat <- chat
      session$userData$saver <- saver
      if (panel) {
        session$userData$panel <- subagent_chat_server(
          "panel",
          lead,
          function() "viewer",
          conversation = saver,
          poll_interval = 100L
        )
      }
    },
    {
      session$flushReact()
      body(session, session$userData$chat, session$userData$saver)
    }
  )
}

history_results <- function(turns) {
  contents <- unlist(lapply(turns, function(turn) turn@contents))
  Filter(function(x) inherits(x, "ellmer::ContentToolResult"), contents)
}

history_state <- function(lead, conversation_id, requester = "viewer") {
  chat <- new.env()
  chat$client <- lead
  chat$history <- new.env()
  chat$history$conversation_id <- function() conversation_id
  state <- new.env()
  state$chat <- chat
  state$lead <- lead
  state$requester <- function() requester
  state$max_bytes <- 16 * 1024^2
  state$conversation_id <- NULL
  state$record <- NULL
  state$envelope <- NULL
  state$kept <- NULL
  state$error <- NULL
  state
}

# A settled delegation started while `lead` answered in `conversation_id`.
history_settled_lead <- function(
  conversation_id,
  counter,
  .local_envir = parent.frame()
) {
  lead <- history_lead(
    history_root_server(.local_envir),
    history_sales_server(.local_envir),
    counter
  )
  lead$conversation_id <- conversation_id
  lead$run_sync("Revenue?")
  lead
}

test_that("saved records round-trip exactly through JSON stores", {
  x <- list(
    a = 1L,
    b = c(1.5, NA, NaN, Inf, -Inf, 0.1, -0, 1e300, 5e-324),
    c = c("x", NA, "é"),
    d = list(NULL, list(), stats::setNames(list(), character()), TRUE, NA),
    m = matrix(1:6, 2, dimnames = list(c("r1", "r2"), NULL)),
    e = character(),
    f = integer(),
    h = c(a = 1L, b = NA),
    r = as.raw(c(0, 255, 16)),
    r0 = raw(0),
    rl = as.raw(rep(1:255, 3)),
    z = c(1 + 2i, NA, complex(real = NaN, imaginary = Inf), -0.1 + 1e300i),
    zm = matrix(c(1i, 2i), 1L)
  )
  expect_identical(history_parse(history_json(x)), x)
  stored <- jsonlite::toJSON(
    list(values = list(data = history_json(x), version = 1L)),
    auto_unbox = TRUE,
    null = "null",
    digits = 17,
    force = TRUE
  )
  back <- jsonlite::fromJSON(stored, simplifyVector = FALSE)$values
  expect_identical(history_parse(back$data), x)
})

test_that("decoding builds only portable data", {
  bad <- c(
    '{"t":"closure","v":[]}',
    '{"t":"S4","v":[]}',
    '{"t":"chr","v":[1]}',
    '{"t":"dbl","v":["1;system(\\"id\\")"]}',
    '{"t":"int","v":["99999999999"]}',
    '{"t":"list","v":[],"x":1}',
    '{"t":"lgl","v":["TRUE"]}',
    '{"t":"chr","v":["a"],"d":["2"]}',
    '{"t":"null","v":[]}',
    '{"t":"raw","v":["!!!!"]}',
    '{"t":"raw","v":["AAA"]}',
    '{"t":"raw","v":["AA==","AA=="]}',
    '{"t":"cplx","v":[["1"]]}',
    '{"t":"cplx","v":[{"re":"1","im":"2"}]}',
    '{"t":"cplx","v":[["x","1"]]}'
  )
  for (text in bad) {
    expect_error(history_parse(text), "not in a readable form")
  }
  deep <- '{"t":"null"}'
  for (i in 1:70) {
    deep <- paste0('{"t":"list","v":[', deep, "]}")
  }
  expect_error(history_parse(deep), "not in a readable form")
  expect_error(history_json(list(f = identity)), "not in a readable form")
  expect_error(history_json(factor("a")), "not in a readable form")
})

test_that("delegations record the conversation the lead answered in", {
  counter <- new.env()
  counter$calls <- 0L
  lead <- history_lead(
    history_root_server(),
    history_sales_server(),
    counter
  )
  expect_null(lead$conversation_id)
  expect_error(lead$conversation_id <- 1, "one non-empty string")
  expect_error(lead$conversation_id <- c("a", "b"), "one non-empty string")
  expect_error(lead$conversation_id <- "", "one non-empty string")
  lead$conversation_id <- "conv-a"
  lead$run_sync("Revenue?")
  view <- lead$inspect_subagents("viewer")[[1L]]
  expect_identical(view$outcome$runtime$host_conversation_id, "conv-a")
  # The model's copy of the outcome leaves out the host's identity.
  results <- history_results(lead$get_context_turns())
  expect_false(any(grepl(
    "conv-a",
    vapply(
      results,
      function(result) paste(result@value, collapse = ""),
      character(1)
    )
  )))
  lead$conversation_id <- NULL
  expect_null(lead$conversation_id)
})

test_that("subagent records are saved with the conversation and restored read-only", {
  counter <- new.env()
  counter$calls <- 0L
  store <- HistoryTestStore$new(withr::local_tempdir())
  lead <- history_lead(
    history_root_server(),
    history_sales_server(),
    counter
  )
  conversation <- NULL
  history_session(lead, store, function(session, chat, saver) {
    conversation <<- history_submit(session, chat, store, "Revenue?")
    status <- saver$status()
    expect_identical(status$conversation_id, conversation)
    expect_identical(status$saved, 1L)
    expect_null(status$error)
  })
  expect_identical(counter$calls, 1L)
  saved <- store$saved[[conversation]]$values$deputy_subagents
  expect_identical(saved$format, "deputy_conversation_subagents")
  expect_identical(saved$version, 1L)
  expect_identical(saved$conversation_id, conversation)
  expect_type(saved$data, "character")

  # A new session and a new lead that can't reach a model.
  restored_lead <- history_lead(NULL, NULL, counter)
  history_session(restored_lead, store, function(session, chat, saver) {
    session$setInputs(chat_history_select = list(id = conversation))
    session$flushReact()
    expect_identical(saver$status()$saved, 1L)
    views <- saver$restored()
    expect_length(views, 1L)
    view <- views[[1L]]
    expect_identical(view$outcome$runtime$agent_name, "sales")
    expect_identical(view$outcome$runtime$status, "completed")
    expect_identical(view$outcome$runtime$host_conversation_id, conversation)
    expect_identical(view$retention$execution, "read_only")
    result <- history_results(view$turns)[[1L]]
    expect_identical(result@extra$display$title, "Ran a trusted calculation")
    expect_identical(result@extra$commons_tag, "A")
    expect_identical(view$retention$transcript, "included")
    listed <- saver$restored(transcript = FALSE)[[1L]]
    expect_length(listed$turns, 0L)
    expect_identical(listed$retention$transcript, "not_requested")
    # The subagent's cards are back in the shown conversation only.
    shown <- unlist(lapply(restored_lead$get_turns(), function(t) t@contents))
    context <- unlist(lapply(
      restored_lead$get_context_turns(),
      function(t) t@contents
    ))
    expect_true(any(vapply(shown, is_activity_content, logical(1))))
    expect_false(any(vapply(context, is_activity_content, logical(1))))
    # Restoring creates no live subagent and runs nothing.
    expect_length(restored_lead$inspect_subagents("viewer"), 0L)
  })
  expect_identical(counter$calls, 1L)
})

test_that("a restored conversation keeps its saved subagents as it continues", {
  counter <- new.env()
  counter$calls <- 0L
  store <- HistoryTestStore$new(withr::local_tempdir())
  first <- history_lead(history_root_server(), history_sales_server(), counter)
  conversation <- NULL
  history_session(first, store, function(session, chat, saver) {
    conversation <<- history_submit(session, chat, store, "Revenue?")
  })
  second <- history_lead(history_root_server(), history_sales_server(), counter)
  history_session(second, store, function(session, chat, saver) {
    session$setInputs(chat_history_select = list(id = conversation))
    session$flushReact()
    expect_identical(
      history_submit(session, chat, store, "Again?"),
      conversation
    )
    expect_identical(saver$status()$saved, 2L)
  })
  third <- history_lead(NULL, NULL, counter)
  history_session(third, store, function(session, chat, saver) {
    session$setInputs(chat_history_select = list(id = conversation))
    session$flushReact()
    views <- saver$restored(transcript = FALSE)
    ids <- vapply(
      views,
      function(view) view$outcome$runtime$delegation_id,
      character(1)
    )
    expect_length(unique(ids), 2L)
    expect_identical(
      ids[[1L]],
      first$inspect_subagents("viewer")[[1L]]$outcome$runtime$delegation_id
    )
  })
  expect_identical(counter$calls, 2L)
})

test_that("each conversation saves only its own subagents", {
  counter <- new.env()
  counter$calls <- 0L
  store <- HistoryTestStore$new(withr::local_tempdir())
  root <- local_runtime_server(list(
    runtime_reply(tool = "ask_sales", arguments = list(task = "One?")),
    runtime_reply("Lead: one."),
    runtime_reply(tool = "ask_sales", arguments = list(task = "Two?")),
    runtime_reply("Lead: two.")
  ))
  sales <- local_runtime_server(list(
    runtime_reply(tool = "call_measure"),
    runtime_reply("One is 60."),
    runtime_reply(tool = "call_measure"),
    runtime_reply("Two is 60.")
  ))
  lead <- history_lead(root, sales, counter)
  ids <- character()
  history_session(
    lead,
    store,
    function(session, chat, saver) {
      ids[["one"]] <<- history_submit(session, chat, store, "One?")
      session$setInputs(chat_history_new = 1L)
      session$flushReact()
      expect_null(saver$restored())
      ids[["two"]] <<- history_submit(session, chat, store, "Two?")
      panel <- session$userData$panel
      session$elapse(200)
      views <- panel$views()
      expect_length(views, 1L)
      expect_identical(
        views[[1L]]$outcome$runtime$host_conversation_id,
        ids[["two"]]
      )
      # Opening the first conversation shows its subagent instead.
      session$setInputs(chat_history_select = list(id = ids[["one"]]))
      session$elapse(200)
      views <- panel$views()
      expect_length(views, 1L)
      expect_identical(
        views[[1L]]$outcome$runtime$host_conversation_id,
        ids[["one"]]
      )
    },
    panel = TRUE
  )
  expect_false(identical(ids[["one"]], ids[["two"]]))
  for (name in names(ids)) {
    record <- history_parse(
      store$saved[[ids[[name]]]]$values$deputy_subagents$data
    )
    expect_length(record$history$children, 1L)
    expect_identical(
      record$history$children[[1L]]$outcome$runtime$host_conversation_id,
      ids[[name]]
    )
  }
})

test_that("other conversations' subagents don't crowd out the open one", {
  counter <- new.env()
  counter$calls <- 0L
  store <- HistoryTestStore$new(withr::local_tempdir())
  root <- local_runtime_server(list(
    runtime_reply(tool = "ask_sales", arguments = list(task = "One?")),
    runtime_reply("Lead: one."),
    runtime_reply(tool = "ask_sales", arguments = list(task = "Two?")),
    runtime_reply("Lead: two.")
  ))
  sales <- local_runtime_server(list(
    runtime_reply(tool = "call_measure"),
    runtime_reply("One is 60."),
    runtime_reply(tool = "call_measure"),
    runtime_reply("Two is 60.")
  ))
  lead <- history_lead(root, sales, counter)
  history_session(
    lead,
    store,
    function(session, chat, saver) {
      history_submit(session, chat, store, "One?")
      # Room for one subagent's view, not for two.
      one <- length(serialize(
        lead$inspect_subagents("viewer"),
        NULL,
        version = 3
      ))
      lead$.__enclos_env__$private$.delegation_disclosure <-
        DelegationDisclosure(
          authorize = function(requester, scope) identical(requester, "viewer"),
          max_bytes = round(one * 1.5)
        )
      session$setInputs(chat_history_new = 1L)
      session$flushReact()
      two <- history_submit(session, chat, store, "Two?")
      expect_error(
        lead$inspect_subagents("viewer"),
        class = "deputy_disclosure_bound"
      )
      panel <- session$userData$panel
      session$elapse(200)
      views <- panel$views()
      expect_length(views, 1L)
      expect_identical(views[[1L]]$outcome$runtime$host_conversation_id, two)
    },
    panel = TRUE
  )
})

test_that("other conversations' events don't crowd out the open one", {
  counter <- new.env()
  counter$calls <- 0L
  store <- HistoryTestStore$new(withr::local_tempdir())
  root <- local_runtime_server(list(
    runtime_reply(tool = "ask_sales", arguments = list(task = "One?")),
    runtime_reply("Lead: one."),
    runtime_reply(tool = "ask_sales", arguments = list(task = "Two?")),
    runtime_reply("Lead: two.")
  ))
  sales <- local_runtime_server(list(
    runtime_reply(tool = "call_measure"),
    runtime_reply("One is 60."),
    runtime_reply(tool = "call_measure"),
    runtime_reply("Two is 60.")
  ))
  lead <- history_lead(root, sales, counter)
  history_session(
    lead,
    store,
    function(session, chat, saver) {
      history_submit(session, chat, store, "One?")
      first <- lead$list_subagents()$delegation_id[[1L]]
      session$setInputs(chat_history_new = 1L)
      session$flushReact()
      two <- history_submit(session, chat, store, "Two?")
      panel <- session$userData$panel
      session$elapse(200)
      expect_length(panel$views(), 1L)
      id <- panel$views()[[1L]]$outcome$runtime$delegation_id
      session$setInputs(`panel-selected` = id)
      session$elapse(200)
      expect_identical(panel$selected(), id)
      # A burst of events from the first conversation's subagent, more than
      # the disclosure bound holds at once.
      lead$.__enclos_env__$private$.delegation_disclosure <-
        DelegationDisclosure(
          authorize = function(requester, scope) identical(requester, "viewer"),
          max_bytes = length(serialize(panel$views(), NULL, version = 3)) +
            20000
        )
      for (i in seq_len(40L)) {
        lead_observe_event(
          lead,
          first,
          list(
            type = "text",
            data = list(text = strrep("x", 20000L)),
            timestamp = Sys.time()
          )
        )
      }
      session$elapse(200)
      views <- panel$views()
      expect_length(views, 1L)
      expect_identical(views[[1L]]$outcome$runtime$host_conversation_id, two)
      # The open subagent stays selected, with no failure shown.
      expect_identical(panel$selected(), id)
      expect_no_match(panel$notice() %||% "", "unavailable")
    },
    panel = TRUE
  )
})

test_that("the subagent panel shows saved subagents read-only", {
  counter <- new.env()
  counter$calls <- 0L
  store <- HistoryTestStore$new(withr::local_tempdir())
  lead <- history_lead(history_root_server(), history_sales_server(), counter)
  conversation <- NULL
  history_session(lead, store, function(session, chat, saver) {
    conversation <<- history_submit(session, chat, store, "Revenue?")
  })
  restored <- history_lead(NULL, NULL, counter)
  history_session(
    restored,
    store,
    function(session, chat, saver) {
      panel <- session$userData$panel
      session$elapse(200)
      expect_length(panel$views(), 0L)
      session$setInputs(chat_history_select = list(id = conversation))
      session$elapse(200)
      views <- panel$views()
      expect_length(views, 1L)
      id <- views[[1L]]$outcome$runtime$delegation_id
      session$setInputs(`panel-selected` = id)
      session$elapse(200)
      expect_identical(panel$selected(), id)
      expect_match(panel$notice(), "sales")
      expect_match(panel$notice(), "completed")
    },
    panel = TRUE
  )
  expect_identical(counter$calls, 1L)
})

test_that("saved subagents show to a requester who can't see live ones", {
  counter <- new.env()
  counter$calls <- 0L
  store <- HistoryTestStore$new(withr::local_tempdir())
  lead <- history_lead(history_root_server(), history_sales_server(), counter)
  conversation <- NULL
  history_session(lead, store, function(session, chat, saver) {
    conversation <<- history_submit(session, chat, store, "Revenue?")
  })
  # The reopening session may read saved conversations, not live subagents.
  restored <- history_lead(NULL, NULL, counter)
  restored$.__enclos_env__$private$.delegation_disclosure <-
    DelegationDisclosure(
      authorize = function(requester, scope) {
        identical(requester, "viewer") && !is.null(scope$chat_conversation_id)
      }
    )
  history_session(
    restored,
    store,
    function(session, chat, saver) {
      panel <- session$userData$panel
      session$setInputs(chat_history_select = list(id = conversation))
      session$elapse(200)
      views <- panel$views()
      expect_length(views, 1L)
      id <- views[[1L]]$outcome$runtime$delegation_id
      session$setInputs(`panel-selected` = id)
      session$elapse(200)
      expect_identical(panel$selected(), id)
      expect_match(panel$notice(), "sales")
    },
    panel = TRUE
  )
  expect_identical(counter$calls, 1L)
})

test_that("live subagents show to a requester who can't see saved ones", {
  counter <- new.env()
  counter$calls <- 0L
  store <- HistoryTestStore$new(withr::local_tempdir())
  lead <- history_lead(history_root_server(), history_sales_server(), counter)
  history_session(
    lead,
    store,
    function(session, chat, saver) {
      history_submit(session, chat, store, "Revenue?")
      expect_length(saver$restored(), 1L)
      # The requester may read live subagents, not the conversation's
      # saved records.
      lead$.__enclos_env__$private$.delegation_disclosure <-
        DelegationDisclosure(
          authorize = function(requester, scope) {
            identical(requester, "viewer") &&
              is.null(scope$chat_conversation_id)
          }
        )
      panel <- session$userData$panel
      session$elapse(200)
      views <- panel$views()
      expect_length(views, 1L)
      id <- views[[1L]]$outcome$runtime$delegation_id
      session$setInputs(`panel-selected` = id)
      session$elapse(200)
      expect_identical(panel$selected(), id)
      expect_no_match(panel$notice() %||% "", "unavailable")
    },
    panel = TRUE
  )
})

test_that("saved records that fail their checks are not read", {
  counter <- new.env()
  counter$calls <- 0L
  lead <- history_settled_lead("conv-a", counter)
  state <- history_state(lead, "conv-a")
  values <- subagent_history_save(state, list())
  saved <- values$deputy_subagents
  expect_null(state$error)
  record <- history_parse(saved$data)

  reread <- function(envelope, conversation = "conv-a", target = lead) {
    fresh <- history_state(target, conversation)
    subagent_history_restore(fresh, list(deputy_subagents = envelope))
    fresh
  }
  expect_length(reread(saved)$record$history$children, 1L)

  tampered <- function(change) {
    copy <- record
    copy <- change(copy)
    envelope <- saved
    envelope$data <- history_json(copy)
    envelope
  }
  cases <- list(
    other_conversation = reread(saved, "conv-b"),
    running = reread(tampered(function(x) {
      x$history$children[[1L]]$outcome$runtime$status <- "running"
      x
    })),
    scope = reread(tampered(function(x) {
      x$history$scope$owner_id <- "u2"
      x
    })),
    transcript = reread(tampered(function(x) {
      x$history$children[[1L]]$transcript[[1L]]$class <- "base::function"
      x
    })),
    text = reread(within(saved, data <- "not json")),
    codec = reread(within(saved, codec <- "rds")),
    keys = reread(tampered(function(x) {
      x$keys <- c(x$keys, x$keys)
      x
    }))
  )
  for (name in names(cases)) {
    fresh <- cases[[name]]
    if (identical(name, "other_conversation")) {
      expect_null(fresh$record)
      expect_match(fresh$error, "could not be read")
      next
    }
    expect_null(fresh$record)
    expect_match(fresh$error, "could not be read")
    # The next save starts from the conversation's live subagents only.
    expect_null(fresh$envelope)
  }

  # A lead whose delegation scope changed doesn't read them either.
  other <- history_lead(NULL, NULL, counter, scope = list(owner_id = "u2"))
  expect_null(reread(saved, target = other)$record)
})

test_that("records from a newer format are kept unchanged", {
  counter <- new.env()
  counter$calls <- 0L
  lead <- history_settled_lead("conv-a", counter)
  state <- history_state(lead, "conv-a")
  newer <- list(
    format = "deputy_conversation_subagents",
    version = 2L,
    data = "{}"
  )
  subagent_history_restore(state, list(deputy_subagents = newer))
  expect_match(state$error, "newer version")
  expect_null(subagent_history_restored(state))
  expect_identical(
    subagent_history_save(state, list())$deputy_subagents,
    newer
  )
  # Another conversation saves its own record, and keeps it.
  state$chat$history$conversation_id <- function() "conv-b"
  lead$conversation_id <- "conv-b"
  saved <- subagent_history_save(state, list())$deputy_subagents
  expect_identical(saved$conversation_id, "conv-b")
  expect_identical(
    subagent_history_save(state, list())$deputy_subagents,
    saved
  )
})

test_that("records stay within max_bytes and count what was left out", {
  counter <- new.env()
  counter$calls <- 0L
  lead <- history_settled_lead("conv-a", counter)
  state <- history_state(lead, "conv-a")
  full <- subagent_history_record(state, "conv-a")
  expect_identical(
    full$omitted,
    list(running = 0L, transcripts = 0L, children = 0L, earlier = 0L)
  )
  view <- full$history$children[[1L]]
  without <- nchar(
    history_json(subagent_history_without_transcript(view)),
    type = "bytes"
  )
  # The smallest record leaves the child out and names it as pending.
  empty <- full
  empty$history$children <- list()
  empty$keys <- character()
  empty$pending <- full$keys
  empty$omitted$children <- 1L
  base <- subagent_history_record_size(empty)
  # A bound too small for the record without children saves nothing.
  state$max_bytes <- base - 1
  expect_error(subagent_history_record(state, "conv-a"), "can't be saved")
  # Room for the child without its transcript.
  state$max_bytes <- base + without + 256
  trimmed <- subagent_history_record(state, "conv-a")
  expect_identical(trimmed$omitted$transcripts, 1L)
  expect_null(trimmed$history$children[[1L]]$transcript)
  expect_identical(
    trimmed$history$children[[1L]]$retention$transcript,
    "omitted"
  )
  # No room for the child at all.
  state$max_bytes <- base + without / 2
  dropped <- subagent_history_record(state, "conv-a")
  expect_identical(dropped$omitted$children, 1L)
  expect_length(dropped$history$children, 0L)
  expect_length(dropped$keys, 0L)
  expect_identical(dropped$pending, full$keys)
  # Whatever the bound, the whole record fits it and reads back.
  full_size <- subagent_history_record_size(full)
  for (bound in round(seq(base, full_size + 64, length.out = 12))) {
    state$max_bytes <- bound
    record <- subagent_history_record(state, "conv-a")
    expect_lte(subagent_history_record_size(record), bound)
    envelope <- subagent_history_envelope(record)
    expect_identical(
      subagent_history_read(envelope, lead, "conv-a", bound),
      record
    )
  }
})

test_that("saved records stay within what the lead's disclosure can replay", {
  counter <- new.env()
  counter$calls <- 0L
  lead <- history_lead(
    local_runtime_server(list(
      runtime_reply(tool = "ask_sales", arguments = list(task = "One")),
      runtime_reply("First."),
      runtime_reply(tool = "ask_sales", arguments = list(task = "Two")),
      runtime_reply("Second.")
    )),
    local_runtime_server(list(
      runtime_reply(tool = "call_measure"),
      runtime_reply("one"),
      runtime_reply(tool = "call_measure"),
      runtime_reply("two")
    )),
    counter
  )
  lead$conversation_id <- "conv-a"
  lead$run_sync("One")
  lead$run_sync("Two")
  state <- history_state(lead, "conv-a")
  full <- subagent_history_record(state, "conv-a")
  expect_length(full$history$children, 2L)
  costs <- vapply(full$history$children, subagent_history_replay_size, 1)
  private <- lead$.__enclos_env__$private
  # Room to replay one child's transcript, not both.
  scope <- length(serialize(
    subagent_history_scope(lead, "conv-a"),
    NULL,
    version = 3
  ))
  private$.delegation_disclosure <- DelegationDisclosure(
    authorize = function(requester, scope) identical(requester, "viewer"),
    max_bytes = scope + costs[[1L]] + costs[[2L]] / 2
  )
  record <- subagent_history_record(state, "conv-a")
  expect_length(record$history$children, 2L)
  expect_identical(record$omitted$transcripts, 1L)
  expect_null(record$history$children[[2L]]$transcript)
  state$record <- record
  state$conversation_id <- "conv-a"
  views <- subagent_history_restored(state)
  expect_length(views, 2L)
  expect_length(
    views[[1L]]$turns,
    length(full$history$children[[1L]]$transcript)
  )
  expect_length(views[[2L]]$turns, 0L)
  # Listed without transcripts: one left out on request, one the save omitted.
  listed <- subagent_history_restored(state, transcript = FALSE)
  expect_identical(
    vapply(listed, function(view) view$retention$transcript, ""),
    c("not_requested", "omitted")
  )

  # A record saved under a larger bound still reads back, without transcripts.
  state$record <- full
  views <- subagent_history_restored(state)
  expect_length(views, 2L)
  expect_identical(
    vapply(views, function(view) view$retention$transcript, ""),
    c("omitted", "omitted")
  )
  expect_identical(lengths(lapply(views, function(view) view$turns)), c(0L, 0L))
  # A bound tightened below the outcomes themselves shows those that fit.
  shown <- integer()
  listed <- integer()
  for (bound in round(seq(scope + costs[[1L]], scope, length.out = 24))) {
    private$.delegation_disclosure <- DelegationDisclosure(
      authorize = function(requester, scope) identical(requester, "viewer"),
      max_bytes = bound
    )
    shown <- c(shown, length(subagent_history_restored(state)))
    # Listed without transcripts, they stay marked as left out on request.
    views <- subagent_history_restored(state, transcript = FALSE)
    listed <- c(listed, length(views))
    expect_identical(
      vapply(views, function(view) view$retention$transcript, ""),
      rep("not_requested", length(views))
    )
  }
  expect_identical(shown, sort(shown, decreasing = TRUE))
  expect_true(all(c(2L, 1L, 0L) %in% shown))
  expect_true(1L %in% listed)
})

test_that("a tightened bound is searched, not tried one child at a time", {
  counter <- new.env()
  counter$calls <- 0L
  lead <- history_settled_lead("conv-a", counter)
  state <- history_state(lead, "conv-a")
  record <- subagent_history_record(state, "conv-a")
  child <- subagent_history_without_transcript(record$history$children[[1L]])
  record$history$children <- rep(list(child), 64L)
  record$keys <- vapply(
    seq_len(64L),
    function(i) subagent_history_key(as.character(i)),
    ""
  )
  state$record <- record
  state$conversation_id <- "conv-a"
  open <- DelegationDisclosure(
    authorize = function(requester, scope) TRUE,
    max_bytes = 1e9
  )
  sized <- function(n) {
    history <- record$history
    history$children <- history$children[seq_len(n)]
    views <- delegation_history(
      history,
      "viewer",
      open,
      subagent_history_scope(lead, "conv-a")
    )
    max(
      length(serialize(history, NULL, version = 3)),
      length(serialize(views, NULL, version = 3))
    )
  }
  reads <- 0L
  lead$.__enclos_env__$private$.delegation_disclosure <- DelegationDisclosure(
    authorize = function(requester, scope) {
      reads <<- reads + 1L
      identical(requester, "viewer")
    },
    max_bytes = sized(10L)
  )
  expect_length(subagent_history_restored(state), 10L)
  expect_lte(reads, 10L)
})

test_that("raw tool results are saved and read back", {
  counter <- new.env()
  counter$calls <- 0L
  bytes <- as.raw(c(137, 80, 78, 71))
  lead <- history_lead(
    history_root_server(),
    history_sales_server(),
    counter,
    value = bytes
  )
  lead$conversation_id <- "conv-a"
  lead$run_sync("Revenue?")
  state <- history_state(lead, "conv-a")
  record <- subagent_history_record(state, "conv-a")
  expect_length(record$history$children, 1L)
  read <- subagent_history_read(
    subagent_history_envelope(record),
    lead,
    "conv-a",
    state$max_bytes
  )
  expect_identical(read, record)
  state$record <- read
  state$conversation_id <- "conv-a"
  result <- history_results(subagent_history_restored(state)[[1L]]$turns)[[1L]]
  expect_identical(result@value, bytes)
})

test_that("a disclosure bound below the record's own size saves nothing", {
  counter <- new.env()
  counter$calls <- 0L
  lead <- history_settled_lead("conv-a", counter)
  scope <- length(serialize(
    subagent_history_scope(lead, "conv-a"),
    NULL,
    version = 3
  ))
  empty <- length(serialize(
    list(
      schema_version = 1L,
      settled = TRUE,
      scope = subagent_history_scope(lead, "conv-a"),
      children = list()
    ),
    NULL,
    version = 3
  ))
  lead$.__enclos_env__$private$.delegation_disclosure <- DelegationDisclosure(
    authorize = function(requester, scope) identical(requester, "viewer"),
    max_bytes = (scope + empty) %/% 2
  )
  state <- history_state(lead, "conv-a")
  expect_error(subagent_history_record(state, "conv-a"), "can't be saved")
  # Room for the record but not for this child's outcome: the child is left
  # out and counted.
  lead$.__enclos_env__$private$.delegation_disclosure <- DelegationDisclosure(
    authorize = function(requester, scope) identical(requester, "viewer"),
    max_bytes = empty + 64
  )
  record <- subagent_history_record(state, "conv-a")
  expect_length(record$history$children, 0L)
  expect_identical(record$omitted$children, 1L)
})

test_that("a scope larger than max_bytes saves no record", {
  counter <- new.env()
  counter$calls <- 0L
  lead <- history_lead(
    history_root_server(),
    history_sales_server(),
    counter,
    scope = list(owner_id = strrep("u", 4096))
  )
  lead$conversation_id <- "conv-a"
  lead$run_sync("Revenue?")
  state <- history_state(lead, "conv-a")
  state$max_bytes <- 1024
  values <- subagent_history_save(state, list(other = "kept"))
  expect_null(values$deputy_subagents)
  expect_identical(values$other, "kept")
  expect_match(state$error, "can't be saved")
})

test_that("saved children are redacted again with the current policy", {
  counter <- new.env()
  counter$calls <- 0L
  flags <- new.env()
  flags$strict <- FALSE
  disclosure <- DelegationDisclosure(
    authorize = function(requester, scope) identical(requester, "viewer"),
    redact = function(view, requester) {
      if (isTRUE(flags$strict)) {
        view$outcome$answer <- "[withheld]"
        view$outcome$runtime$delegation_id <- NULL
      }
      view
    }
  )
  lead <- history_settled_lead("conv-a", counter)
  lead$.__enclos_env__$private$.delegation_disclosure <- disclosure
  saved <- subagent_history_save(history_state(lead, "conv-a"), list())
  record <- history_parse(saved$deputy_subagents$data)
  expect_match(record$history$children[[1L]]$outcome$answer, "60")

  # Reopened later under a stricter policy, with nothing live.
  flags$strict <- TRUE
  later <- history_lead(NULL, NULL, counter)
  later$.__enclos_env__$private$.delegation_disclosure <- disclosure
  state <- history_state(later, "conv-a")
  subagent_history_restore(state, saved)
  expect_length(state$record$history$children, 1L)
  resaved <- subagent_history_save(state, list())$deputy_subagents
  child <- history_parse(resaved$data)$history$children[[1L]]
  expect_identical(child$outcome$answer, "[withheld]")
  expect_null(child$outcome$runtime$delegation_id)
  # Without an ID, the child still reads back and keeps its key.
  subagent_history_restore(state, list(deputy_subagents = resaved))
  expect_length(state$record$history$children, 1L)
  expect_identical(state$record$keys, record$keys)
})

test_that("a transcript the redactor removes is saved as omitted", {
  counter <- new.env()
  counter$calls <- 0L
  flags <- new.env()
  flags$strip <- TRUE
  disclosure <- DelegationDisclosure(
    authorize = function(requester, scope) identical(requester, "viewer"),
    redact = function(view, requester) {
      if (isTRUE(flags$strip)) {
        view$transcript <- NULL
      }
      view
    }
  )
  counts <- function(transcripts = 0L) {
    list(running = 0L, transcripts = transcripts, children = 0L)
  }
  child_of <- function(saved) {
    history_parse(saved$deputy_subagents$data)$history$children[[1L]]
  }
  lead <- history_settled_lead("conv-a", counter)
  lead$.__enclos_env__$private$.delegation_disclosure <- disclosure
  # A live child.
  state <- history_state(lead, "conv-a")
  child <- child_of(subagent_history_save(state, list()))
  expect_identical(subagent_history_status(state)$omitted, counts(1L))
  expect_null(child$transcript)
  expect_identical(child$retention$transcript, "omitted")

  # A saved child, reopened where the redactor now removes its transcript.
  flags$strip <- FALSE
  saved <- subagent_history_save(history_state(lead, "conv-a"), list())
  expect_identical(child_of(saved)$retention$transcript, "included")
  flags$strip <- TRUE
  later <- history_lead(NULL, NULL, counter)
  later$.__enclos_env__$private$.delegation_disclosure <- disclosure
  state <- history_state(later, "conv-a")
  subagent_history_restore(state, saved)
  child <- child_of(subagent_history_save(state, list()))
  expect_identical(subagent_history_status(state)$omitted, counts(1L))
  expect_null(child$transcript)
  expect_identical(child$retention$transcript, "omitted")
})

test_that("children left out stay counted when another session saves", {
  counter <- new.env()
  counter$calls <- 0L
  lead <- history_settled_lead("conv-a", counter)
  private <- lead$.__enclos_env__$private
  id <- names(private$subagent_runs)[[1L]]
  finished <- private$subagent_runs[[id]]$completed_at
  counts <- function(running = 0L, children = 0L) {
    list(running = running, transcripts = 0L, children = children)
  }
  # Saved while the subagent was still running.
  private$subagent_runs[[id]]$completed_at <- as.POSIXct(NA_real_, tz = "UTC")
  state <- history_state(lead, "conv-a")
  running <- subagent_history_save(state, list())
  expect_identical(subagent_history_status(state)$omitted, counts(running = 1L))
  # The same lead reopens it once the subagent has finished: the subagent is
  # saved and not counted as left out.
  private$subagent_runs[[id]]$completed_at <- finished
  subagent_history_restore(state, running)
  subagent_history_save(state, list())
  expect_identical(subagent_history_status(state)$saved, 1L)
  expect_identical(subagent_history_status(state)$omitted, counts())
  # A later session can't find that subagent: every save still counts it.
  later <- history_lead(NULL, NULL, counter)
  state <- history_state(later, "conv-a")
  subagent_history_restore(state, running)
  expect_identical(subagent_history_status(state)$omitted, counts(running = 1L))
  subagent_history_save(state, list())
  expect_identical(
    subagent_history_status(state)$omitted,
    counts(children = 1L)
  )
  again <- subagent_history_save(state, list())
  expect_identical(
    subagent_history_status(state)$omitted,
    counts(children = 1L)
  )
  third <- history_lead(NULL, NULL, counter)
  state <- history_state(third, "conv-a")
  subagent_history_restore(state, again)
  subagent_history_save(state, list())
  expect_identical(
    subagent_history_status(state)$omitted,
    counts(children = 1L)
  )
  # Counts that don't add up are not read.
  record <- history_parse(again$deputy_subagents$data)
  record$omitted$earlier <- 2L
  tampered <- subagent_history_envelope(record)
  state <- history_state(third, "conv-a")
  subagent_history_restore(state, list(deputy_subagents = tampered))
  expect_null(state$record)
  expect_match(state$error, "could not be read")
})

test_that("children left out stay counted after the lead releases them", {
  counter <- new.env()
  counter$calls <- 0L
  lead <- history_settled_lead("conv-a", counter)
  private <- lead$.__enclos_env__$private
  id <- names(private$subagent_runs)[[1L]]
  counts <- function(running = 0L, children = 0L) {
    list(running = running, transcripts = 0L, children = children)
  }
  # Saved while the subagent was still running.
  private$subagent_runs[[id]]$completed_at <- as.POSIXct(NA_real_, tz = "UTC")
  state <- history_state(lead, "conv-a")
  subagent_history_save(state, list())
  expect_identical(subagent_history_status(state)$omitted, counts(running = 1L))
  # Released with its records before the next save, which can neither save
  # it nor count it as running: it stays counted as left out.
  lead$release_agent(names(private$owned_conversations)[[1L]])
  expect_length(private$subagent_runs, 0L)
  subagent_history_save(state, list())
  expect_identical(subagent_history_status(state)$saved, 0L)
  expect_identical(
    subagent_history_status(state)$omitted,
    counts(children = 1L)
  )
  expect_length(state$record$pending, 0L)
  subagent_history_save(state, list())
  expect_identical(
    subagent_history_status(state)$omitted,
    counts(children = 1L)
  )
})

test_that("saved children reach no one the conversation refuses", {
  counter <- new.env()
  counter$calls <- 0L
  lead <- history_settled_lead("conv-a", counter)
  saved <- subagent_history_save(history_state(lead, "conv-a"), list())
  # Reopened by a requester who may inspect the lead's live subagents but not
  # this conversation's saved history.
  redacted <- 0L
  disclosure <- DelegationDisclosure(
    authorize = function(requester, scope) {
      identical(requester, "viewer") && is.null(scope$chat_conversation_id)
    },
    redact = function(view, requester) {
      redacted <<- redacted + 1L
      view
    }
  )
  later <- history_lead(NULL, NULL, counter)
  later$.__enclos_env__$private$.delegation_disclosure <- disclosure
  state <- history_state(later, "conv-a")
  subagent_history_restore(state, saved)
  resaved <- subagent_history_save(state, list())
  expect_identical(redacted, 0L)
  expect_identical(
    history_parse(resaved$deputy_subagents$data),
    history_parse(saved$deputy_subagents$data)
  )
  expect_false(is.null(subagent_history_status(state)$error))
})

test_that("saved children stay with the scope they were saved under", {
  counter <- new.env()
  counter$calls <- 0L
  scope <- list(owner_id = "u1", conversation_id = "c1")
  lead <- history_lead(
    history_root_server(),
    history_sales_server(),
    counter,
    scope = scope
  )
  lead$conversation_id <- "conv-a"
  lead$run_sync("Revenue?")
  saved <- subagent_history_save(history_state(lead, "conv-a"), list())
  redacted <- 0L
  disclosure <- DelegationDisclosure(
    authorize = function(requester, scope) identical(requester, "viewer"),
    redact = function(view, requester) {
      redacted <<- redacted + 1L
      view
    }
  )
  # Reopened by a lead with nothing live, which then moves to another scope.
  later <- LeadAgent$new(
    runtime_chat(list(url = "http://127.0.0.1:9/v1")),
    delegation_scope = scope,
    delegation_disclosure = disclosure
  )
  state <- history_state(later, "conv-a")
  subagent_history_restore(state, saved)
  expect_length(state$record$history$children, 1L)
  later$set_delegation_sources(
    scope = list(owner_id = "u2", conversation_id = "c2")
  )
  resaved <- subagent_history_save(state, list())$deputy_subagents
  record <- history_parse(resaved$data)
  expect_identical(redacted, 0L)
  expect_length(record$history$children, 0L)
  expect_identical(record$history$scope$owner_id, "u2")
  expect_identical(record$omitted$children, 0L)
  expect_null(subagent_history_status(state)$error)
})

test_that("a reopened conversation saves without access to live subagents", {
  counter <- new.env()
  counter$calls <- 0L
  lead <- history_settled_lead("conv-a", counter)
  saved <- subagent_history_save(history_state(lead, "conv-a"), list())
  # A new lead whose disclosure allows the conversation's scope but not its
  # own live one, with a stricter redactor.
  later <- history_lead(NULL, NULL, counter)
  later$.__enclos_env__$private$.delegation_disclosure <- DelegationDisclosure(
    authorize = function(requester, scope) {
      identical(requester, "viewer") && !is.null(scope$chat_conversation_id)
    },
    redact = function(view, requester) {
      view$outcome$answer <- "[withheld]"
      view
    }
  )
  state <- history_state(later, "conv-a")
  subagent_history_restore(state, saved)
  resaved <- subagent_history_save(state, list())$deputy_subagents
  expect_null(subagent_history_status(state)$error)
  child <- history_parse(resaved$data)$history$children[[1L]]
  expect_identical(child$outcome$answer, "[withheld]")
})

test_that("a saved child its live record can't show again is counted once", {
  counter <- new.env()
  counter$calls <- 0L
  lead <- history_settled_lead("conv-a", counter)
  state <- history_state(lead, "conv-a")
  subagent_history_save(state, list())
  expect_identical(subagent_history_status(state)$saved, 1L)
  counts <- function(children = 0L) {
    list(running = 0L, transcripts = 0L, children = children)
  }
  # The disclosure bound tightens below the child's outcome while it is
  # still live: its saved copy goes, and it is left out once.
  empty <- length(serialize(
    list(
      schema_version = 1L,
      settled = TRUE,
      scope = subagent_history_scope(lead, "conv-a"),
      children = list()
    ),
    NULL,
    version = 3
  ))
  private <- lead$.__enclos_env__$private
  private$.delegation_disclosure <- DelegationDisclosure(
    authorize = function(requester, scope) identical(requester, "viewer"),
    max_bytes = empty + 100
  )
  resaved <- subagent_history_save(state, list())$deputy_subagents
  expect_null(subagent_history_status(state)$error)
  expect_identical(subagent_history_status(state)$saved, 0L)
  expect_identical(subagent_history_status(state)$omitted, counts(1L))
  subagent_history_restore(state, list(deputy_subagents = resaved))
  expect_false(is.null(state$record))
  # Saved again once the bound allows it, with nothing left out.
  private$.delegation_disclosure <- history_disclosure()
  subagent_history_save(state, list())
  expect_identical(subagent_history_status(state)$saved, 1L)
  expect_identical(subagent_history_status(state)$omitted, counts())
})

test_that("a save the requester may not see keeps the last good record", {
  counter <- new.env()
  counter$calls <- 0L
  lead <- history_settled_lead("conv-a", counter)
  state <- history_state(lead, "conv-a")
  saved <- subagent_history_save(state, list())$deputy_subagents
  state$requester <- function() "intruder"
  values <- subagent_history_save(state, list(other = 1))
  expect_identical(values$deputy_subagents, saved)
  expect_identical(values$other, 1)
  expect_match(state$error, "not authorized")
  # A conversation with nothing saved yet saves nothing.
  fresh <- history_state(lead, "conv-a", requester = "intruder")
  expect_null(subagent_history_save(fresh, list())$deputy_subagents)
})

test_that("subagent_chat_history() checks its arguments", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("shinychat", "0.5.0")
  skip_if_not_installed("bslib")
  lead <- Agent$new(
    ellmer::chat_openai(credentials = function() "x", echo = "none"),
    delegation_disclosure = history_disclosure()
  )
  other <- Agent$new(
    ellmer::chat_openai(credentials = function() "x", echo = "none")
  )
  shiny::testServer(
    function(input, output, session) {
      chat <- shinychat::chat_server("chat", lead, history = FALSE)
      expect_error(
        subagent_chat_history(list(), lead, function() "viewer"),
        "chat_server"
      )
      expect_error(
        subagent_chat_history(chat, other, function() "viewer"),
        "client"
      )
      expect_error(subagent_chat_history(chat, lead, "viewer"), "function")
      expect_error(
        subagent_chat_history(chat, lead, function() "viewer", 10),
        "at least 1024"
      )
      expect_error(
        subagent_chat_server(
          "panel",
          lead,
          function() "viewer",
          conversation = list()
        ),
        "subagent_chat_history"
      )
      saver <- subagent_chat_history(chat, lead, function() "viewer")
      expect_null(saver$restored())
      expect_null(saver$status()$conversation_id)
    },
    {
      session$flushReact()
    }
  )
})
