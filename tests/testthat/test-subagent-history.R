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
    zm = matrix(c(1i, 2i), 1L),
    mn = structure(1:4, dim = c(2L, 2L), names = c("a", "b", "c", "d")),
    ln = structure(list(1, "x"), dim = c(1L, 2L), names = c("p", NA)),
    a1 = array(1:3, dimnames = list(c("a", "b", "c"))),
    p = pairlist(a = 1L, 2, b = list("x", pairlist(c = TRUE))),
    pm = local({
      p <- pairlist(1, "a", TRUE, NULL)
      dim(p) <- c(2L, 2L)
      dimnames(p) <- list(c("r1", "r2"), NULL)
      p
    })
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

test_that("saved numbers read back under a comma decimal locale", {
  old <- Sys.getlocale("LC_NUMERIC")
  withr::defer(suppressWarnings(Sys.setlocale("LC_NUMERIC", old)))
  set <- suppressWarnings(Sys.setlocale("LC_NUMERIC", "de_DE.UTF-8"))
  skip_if_not(nzchar(set), "No German locale is installed.")
  skip_if_not(identical(sprintf("%.1f", 1.5), "1,5"), "printf ignores it.")
  x <- list(
    b = c(1.5, 0.1, -2.25e-300, 1e300, 123456789.125),
    z = complex(real = 0.5, imaginary = -1.25)
  )
  text <- history_json(x)
  expect_no_match(text, ",5\"", fixed = TRUE)
  expect_identical(history_parse(text), x)
})

test_that("finite doubles are saved as their bits", {
  # Literals like 1e300 parse to different bits on arm64, so the bits checked
  # are of values every platform reads exactly.
  expect_identical(
    history_json(list(b = c(1.5, -2))),
    '{"t":"list","v":[{"t":"dbl","v":["0x3ff8000000000000","0xc000000000000000"]}],"n":["b"]}'
  )
  x <- list(b = c(1e300, 0.1, -2.25e-300, 5e-324))
  text <- history_json(x)
  expect_no_match(text, "e+300", fixed = TRUE)
  expect_identical(history_parse(text), x)
  # Version 1 records saved decimal text, which still reads.
  decimal <- '{"t":"list","v":[{"t":"dbl","v":["1.5","-0.25","1000"]}],"n":["b"]}'
  expect_identical(history_parse(decimal), list(b = c(1.5, -0.25, 1000)))
  # Bits saved for a finite value must be one.
  for (bits in c("0x7ff0000000000000", "0x7ff8000000000000", "0x7FF0")) {
    expect_error(
      history_parse(sprintf('{"t":"dbl","v":["%s"]}', bits)),
      "not in a readable form"
    )
  }
})

test_that("strings that aren't UTF-8 keep their bytes and mark", {
  bytes <- rawToChar(as.raw(c(0x61, 0xff, 0x62)))
  Encoding(bytes) <- "bytes"
  native <- rawToChar(as.raw(c(0x63, 0xfe)))
  marked <- rawToChar(as.raw(c(0x64, 0xc3)))
  Encoding(marked) <- "UTF-8"
  x <- list(
    v = c(bytes, native, marked, "é", NA),
    n = stats::setNames(1:2, c(bytes, "ok"))
  )
  text <- history_json(x)
  expect_true(validUTF8(text))
  back <- history_parse(text)
  expect_identical(back, x)
  expect_identical(Encoding(back$v[1:3]), c("bytes", "unknown", "UTF-8"))
  for (bad in c(
    '{"t":"chr","v":[{"b":"YQ==","e":"latin1"}]}',
    '{"t":"chr","v":[{"b":"AA==","e":"bytes"}]}',
    '{"t":"chr","v":[{"e":"bytes","b":"YQ=="}]}'
  )) {
    expect_error(history_parse(bad), "not in a readable form")
  }
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
    '{"t":"cplx","v":[["x","1"]]}',
    '{"t":"pairlist","v":[]}'
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

  # Replacing the turns keeps the conversation; emptying them starts a new one.
  lead$conversation_id <- "conv-a"
  lead$set_turns(lead$get_turns())
  expect_identical(lead$conversation_id, "conv-a")
  lead$set_turns(list())
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
  expect_identical(saved$version, 2L)
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

test_that("saved and live subagents keep to the disclosure bound together", {
  counter <- new.env()
  counter$calls <- 0L
  store <- HistoryTestStore$new(withr::local_tempdir())
  first <- history_lead(history_root_server(), history_sales_server(), counter)
  conversation <- NULL
  history_session(first, store, function(session, chat, saver) {
    conversation <<- history_submit(session, chat, store, "Revenue?")
  })
  second <- history_lead(history_root_server(), history_sales_server(), counter)
  history_session(
    second,
    store,
    function(session, chat, saver) {
      session$setInputs(chat_history_select = list(id = conversation))
      session$flushReact()
      history_submit(session, chat, store, "Again?")
      panel <- session$userData$panel
      session$elapse(200)
      expect_length(panel$views(), 2L)
      # Room for the saved list or the live one, not for both.
      live <- second$inspect_subagents("viewer")
      disclosure <- DelegationDisclosure(
        authorize = function(requester, scope) identical(requester, "viewer"),
        max_bytes = round(length(serialize(live, NULL, version = 3)) * 1.5)
      )
      second$.__enclos_env__$private$.delegation_disclosure <- disclosure
      session$elapse(200)
      views <- panel$views()
      expect_length(views, 1L)
      expect_identical(
        views[[1L]]$outcome$runtime$delegation_id,
        live[[1L]]$outcome$runtime$delegation_id
      )
      expect_no_error(inspection_bound(views, disclosure))
    },
    panel = TRUE
  )
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

test_that("status counts saved subagents only for requesters who may see them", {
  counter <- new.env()
  counter$calls <- 0L
  store <- HistoryTestStore$new(withr::local_tempdir())
  lead <- history_lead(history_root_server(), history_sales_server(), counter)
  history_session(
    lead,
    store,
    function(session, chat, saver) {
      history_submit(session, chat, store, "Revenue?")
      expect_identical(saver$status()$saved, 1L)
      # The requester may read live subagents, not the conversation's saved
      # records.
      lead$.__enclos_env__$private$.delegation_disclosure <-
        DelegationDisclosure(
          authorize = function(requester, scope) {
            identical(requester, "viewer") &&
              is.null(scope$chat_conversation_id)
          }
        )
      status <- saver$status()
      expect_identical(status$saved, 0L)
      expect_identical(
        status$omitted,
        list(running = 0L, transcripts = 0L, children = 0L)
      )
      expect_match(status$error, "not available")
    }
  )
})

test_that("a redactor that removes the conversation keeps live subagents", {
  counter <- new.env()
  counter$calls <- 0L
  store <- HistoryTestStore$new(withr::local_tempdir())
  lead <- history_lead(history_root_server(), history_sales_server(), counter)
  history_session(
    lead,
    store,
    function(session, chat, saver) {
      history_submit(session, chat, store, "Revenue?")
      # The views leave out which conversation a subagent ran in, and the
      # requester may not read the saved records, so only the live
      # subagent can be listed.
      lead$.__enclos_env__$private$.delegation_disclosure <-
        DelegationDisclosure(
          authorize = function(requester, scope) {
            identical(requester, "viewer") &&
              is.null(scope$chat_conversation_id)
          },
          redact = function(view, requester) {
            view$outcome$runtime$host_conversation_id <- NULL
            view
          }
        )
      panel <- session$userData$panel
      session$elapse(200)
      views <- panel$views()
      expect_length(views, 1L)
      expect_null(views[[1L]]$outcome$runtime$host_conversation_id)
      id <- views[[1L]]$outcome$runtime$delegation_id
      session$setInputs(`panel-selected` = id)
      session$elapse(200)
      expect_identical(panel$selected(), id)
      expect_no_match(panel$notice() %||% "", "missing|unavailable")
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
  # Records saved as version 1 still read.
  expect_length(
    reread(within(saved, version <- 1L))$record$history$children,
    1L
  )

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
    version = reread(within(saved, version <- 0L)),
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
    version = subagent_history_version + 1L,
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

test_that("a child the record's bookkeeping pushes over keeps its outcome", {
  counter <- new.env()
  counter$calls <- 0L
  lead <- history_settled_lead("conv-a", counter)
  state <- history_state(lead, "conv-a")
  full <- subagent_history_record(state, "conv-a")
  view <- full$history$children[[1L]]
  stripped <- full
  stripped$history$children[[1L]] <- subagent_history_without_transcript(view)
  stripped$omitted$transcripts <- 1L
  # The child alone fits, and so does the record without its transcript, but
  # not the record with it.
  state$max_bytes <- max(
    nchar(history_json(view), type = "bytes"),
    subagent_history_record_size(stripped)
  )
  expect_lt(state$max_bytes, subagent_history_record_size(full))
  record <- subagent_history_record(state, "conv-a")
  expect_length(record$history$children, 1L)
  expect_null(record$history$children[[1L]]$transcript)
  expect_identical(
    record$history$children[[1L]]$retention$transcript,
    "omitted"
  )
  expect_identical(record$omitted$transcripts, 1L)
  expect_identical(record$omitted$children, 0L)
  expect_lte(subagent_history_record_size(record), state$max_bytes)
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
    max_bytes = scope + costs[[1L]] + floor(costs[[2L]] / 2)
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

test_that("the replay budget counts references as replay marks them", {
  counter <- new.env()
  counter$calls <- 0L
  lead <- history_settled_lead("conv-a", counter)
  references <- lapply(seq_len(200), function(i) {
    list(reference = paste0("ref-", i), availability = "missing")
  })
  disclosure <- function(max_bytes) {
    DelegationDisclosure(
      authorize = function(requester, scope) identical(requester, "viewer"),
      redact = function(view, requester) {
        if (!length(view$outcome$references)) {
          view$outcome$references <- references
        }
        view
      },
      max_bytes = max_bytes
    )
  }
  private <- lead$.__enclos_env__$private
  private$.delegation_disclosure <- disclosure(16 * 1024^2)
  full <- subagent_history_record(history_state(lead, "conv-a"), "conv-a")
  empty <- full$history
  empty$children <- list()
  edge <- length(serialize(empty, NULL, version = 3)) +
    subagent_history_replay_size(full$history$children[[1L]])
  # Replay marks each reference "unresolved", which is longer than "missing":
  # around the edge, a transcript the save keeps is replayed, not dropped.
  for (bound in edge + seq(0, 700, by = 100)) {
    private$.delegation_disclosure <- disclosure(bound)
    state <- history_state(lead, "conv-a")
    record <- subagent_history_record(state, "conv-a")
    state$record <- record
    state$conversation_id <- "conv-a"
    kept <- vapply(
      record$history$children,
      function(view) !is.null(view$transcript),
      logical(1)
    )
    shown <- vapply(
      subagent_history_restored(state),
      function(view) length(view$turns) > 0L,
      logical(1)
    )
    expect_identical(unname(shown), unname(kept))
  }
})

test_that("a selected saved subagent is bounded on its own", {
  counter <- new.env()
  counter$calls <- 0L
  lead <- history_settled_lead("conv-a", counter)
  state <- history_state(lead, "conv-a")
  record <- subagent_history_record(state, "conv-a")
  child <- record$history$children[[1L]]
  other <- child
  other$outcome$runtime$delegation_id <- "deleg_other"
  record$history$children <- list(child, other)
  state$record <- record
  state$conversation_id <- "conv-a"
  id <- child$outcome$runtime$delegation_id
  # As the disclosure bound measures replayed views.
  size <- function(views) {
    payload <- function(value) {
      if (inherits(value, "ellmer::Turn")) {
        return(inspection_record_turn(value))
      }
      if (is.list(value)) lapply(value, payload) else value
    }
    length(serialize(payload(views), NULL, version = 3))
  }
  two <- size(subagent_history_restored(state))
  state$record$history$children <- list(child)
  one <- size(subagent_history_restored(state))
  state$record <- record
  # Now one transcript fits the bound, and two don't.
  lead$.__enclos_env__$private$.delegation_disclosure <- DelegationDisclosure(
    authorize = function(requester, scope) identical(requester, "viewer"),
    max_bytes = (one + two) %/% 2
  )
  turns <- function(views) {
    vapply(views, function(view) length(view$turns), integer(1))
  }
  expect_identical(turns(subagent_history_restored(state)), c(0L, 0L))
  # The panel shows the selected child with its conversation.
  conversation <- list(
    restored = function(transcript = TRUE, ...) {
      subagent_history_restored(state, transcript, ...)
    },
    conversation_id = function() "conv-a"
  )
  shown <- subagent_history_panel_child(conversation, lead, list(), id)
  expect_length(shown, 1L)
  expect_gt(turns(shown), 0L)
  selected <- subagent_history_restored(state, delegation_id = id)
  expect_length(selected, 1L)
  expect_identical(subagent_history_view_id(selected[[1L]]), id)
  expect_gt(turns(selected), 0L)
})
