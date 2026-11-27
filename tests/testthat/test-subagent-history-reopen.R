test_that("a saved child is chosen without reading live records", {
  counter <- new.env()
  counter$calls <- 0L
  lead <- history_settled_lead("conv-a", counter)
  state <- history_state(lead, "conv-a")
  state$record <- subagent_history_record(state, "conv-a")
  state$conversation_id <- "conv-a"
  id <- state$record$history$children[[1L]]$outcome$runtime$delegation_id
  conversation <- list(
    restored = function(transcript = TRUE, ...) {
      subagent_history_restored(state, transcript, ...)
    },
    conversation_id = function() "conv-a"
  )
  # No live view was allowed, so the lead's records aren't consulted.
  local_mocked_bindings(
    subagent_history_records = function(...) stop("live records read")
  )
  shown <- subagent_history_panel_child(conversation, lead, list(), id)
  expect_length(shown, 1L)
  expect_identical(subagent_history_view_id(shown[[1L]]), id)
})

test_that("a save error is reported only under the scope it was met in", {
  counter <- new.env()
  counter$calls <- 0L
  lead <- history_settled_lead("conv-a", counter)
  private <- lead$.__enclos_env__$private
  private$.delegation_disclosure <- DelegationDisclosure(
    authorize = function(requester, scope) identical(requester, "viewer"),
    redact = function(view, requester) stop("old scope detail")
  )
  state <- history_state(lead, "conv-a")
  subagent_history_save(state, list())
  expect_match(subagent_history_status(state)$error, "old scope detail")
  # The lead moves to another scope before the next save.
  private$delegation_scope <- list(owner_id = "u2")
  expect_null(subagent_history_status(state)$error)
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

test_that("status doesn't count a record saved under another scope", {
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
  # This requester may see only the scope the lead moves to.
  later <- LeadAgent$new(
    runtime_chat(list(url = "http://127.0.0.1:9/v1")),
    delegation_scope = scope,
    delegation_disclosure = DelegationDisclosure(
      authorize = function(requester, scope) {
        identical(requester, "viewer") && identical(scope$owner_id, "u2")
      }
    )
  )
  state <- history_state(later, "conv-a")
  subagent_history_restore(state, saved)
  expect_length(state$record$history$children, 1L)
  later$set_delegation_sources(
    scope = list(owner_id = "u2", conversation_id = "c2")
  )
  status <- subagent_history_status(state)
  expect_identical(status$saved, 0L)
  expect_identical(
    status$omitted,
    list(running = 0L, transcripts = 0L, children = 0L)
  )
  expect_null(status$error)
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

test_that("a resave redacts saved references as replay marks them", {
  counter <- new.env()
  counter$calls <- 0L
  lead <- history_settled_lead("conv-a", counter)
  disclosure <- DelegationDisclosure(
    authorize = function(requester, scope) identical(requester, "viewer"),
    redact = function(view, requester) {
      if (!length(view$outcome$references)) {
        view$outcome$references <- list(list(
          reference = "deputy://tool-result/ref-1",
          availability = "available",
          locator = "/private/results/ref-1.rds"
        ))
      }
      # A reference that can't be resolved loses its locator.
      view$outcome$references <- lapply(
        view$outcome$references,
        function(ref) {
          if (identical(ref$availability, "unresolved")) {
            ref$locator <- NULL
          }
          ref
        }
      )
      view
    }
  )
  lead$.__enclos_env__$private$.delegation_disclosure <- disclosure
  saved <- subagent_history_save(history_state(lead, "conv-a"), list())
  later <- history_lead(NULL, NULL, counter)
  later$.__enclos_env__$private$.delegation_disclosure <- disclosure
  state <- history_state(later, "conv-a")
  subagent_history_restore(state, saved)
  resaved <- subagent_history_save(state, list())$deputy_subagents
  child <- history_parse(resaved$data)$history$children[[1L]]
  reference <- child$outcome$references[[1L]]
  expect_identical(reference$availability, "unresolved")
  expect_null(reference$locator)
})

test_that("a transcript the current redactor removes is marked on restore", {
  counter <- new.env()
  counter$calls <- 0L
  lead <- history_settled_lead("conv-a", counter)
  state <- history_state(lead, "conv-a")
  subagent_history_save(state, list())
  # The policy changes after the save: transcripts are no longer shown.
  lead$.__enclos_env__$private$.delegation_disclosure <- DelegationDisclosure(
    authorize = function(requester, scope) identical(requester, "viewer"),
    redact = function(view, requester) {
      view$transcript <- NULL
      view
    }
  )
  views <- subagent_history_restored(state)
  expect_length(views, 1L)
  expect_length(views[[1L]]$turns, 0L)
  expect_identical(views[[1L]]$retention$transcript, "omitted")
})

test_that("a save without live access doesn't depend on live subagents", {
  counter <- new.env()
  counter$calls <- 0L
  lead <- history_settled_lead("conv-a", counter)
  private <- lead$.__enclos_env__$private
  state <- history_state(lead, "conv-a")
  counts <- function(children = 0L) {
    list(running = 0L, transcripts = 0L, children = children)
  }
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
  # The child doesn't fit the disclosure bound, so it is left out.
  private$.delegation_disclosure <- DelegationDisclosure(
    authorize = function(requester, scope) identical(requester, "viewer"),
    max_bytes = empty + 100
  )
  subagent_history_save(state, list())
  expect_identical(subagent_history_status(state)$omitted, counts(1L))
  # A requester allowed the conversation but not the lead's live scope saves
  # as with no subagents here, and the child left out still waits.
  private$.delegation_disclosure <- DelegationDisclosure(
    authorize = function(requester, scope) {
      identical(requester, "viewer") && !is.null(scope$chat_conversation_id)
    },
    max_bytes = empty + 100
  )
  subagent_history_save(state, list())
  expect_null(subagent_history_status(state)$error)
  expect_identical(subagent_history_status(state)$omitted, counts(1L))
  quiet <- history_state(lead, "conv-b")
  subagent_history_save(quiet, list())
  expect_null(subagent_history_status(quiet)$error)
  # Saved once a save may read it, and not also counted as left out.
  private$.delegation_disclosure <- history_disclosure()
  subagent_history_save(state, list())
  expect_identical(subagent_history_status(state)$saved, 1L)
  expect_identical(subagent_history_status(state)$omitted, counts())
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

test_that("a new conversation's failed first save reports its error", {
  counter <- new.env()
  counter$calls <- 0L
  lead <- history_settled_lead("conv-a", counter)
  open <- new.env()
  open$id <- "conv-a"
  state <- history_state(lead, "conv-a")
  state$chat$history$conversation_id <- function() open$id
  subagent_history_save(state, list())
  expect_identical(subagent_history_status(state)$saved, 1L)
  open$id <- "conv-b"
  state$max_bytes <- 16
  values <- subagent_history_save(state, list(other = 1))
  expect_null(values$deputy_subagents)
  status <- subagent_history_status(state)
  expect_identical(status$conversation_id, "conv-b")
  expect_identical(status$saved, 0L)
  expect_match(status$error, "can't be saved")
  expect_null(subagent_history_restored(state))
  # The next save that works clears it.
  state$max_bytes <- 16 * 1024^2
  expect_type(subagent_history_save(state, list())$deputy_subagents, "list")
  expect_null(subagent_history_status(state)$error)
})

test_that("subagent_chat_history() checks its arguments", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("shinychat", "0.5.0")
  skip_if_not_installed("bslib")
  skip_if_not_installed("commonmark")
  skip_if_not_installed("xml2")
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

# Apps that run the lead's replies themselves -------------------------------

# A Shiny session whose app streams `lead`'s replies into the chat itself and
# keeps conversations with `chat_enable_history()`, as an app without
# `chat_server()` does. The app numbers its own conversations: a reply in an
# empty conversation starts a new one, and each conversation's ID is saved
# with it and set again when it is reopened (by `reopen(values)`, which reads
# the saved ID by default). With `explicit`, Deputy reads the open
# conversation's ID from the app instead of from `lead$conversation_id`.
host_history_session <- function(
  lead,
  store,
  body,
  explicit = FALSE,
  reopen = function(values) values$host_conversation,
  prefix = "host-"
) {
  skip_if_not_installed("shiny")
  skip_if_not_installed("shinychat", "0.5.0")
  skip_if_not_installed("bslib")
  skip_if_not_installed("commonmark")
  skip_if_not_installed("xml2")
  host <- new.env()
  host$id <- NULL
  host$count <- 0L
  host$replies <- 0L
  host$seen <- list()
  shiny::testServer(
    function(input, output, session) {
      user <- function() "viewer"
      host$activity <- subagent_chat_activity(lead = lead, requester = user)
      host$saver <- subagent_chat_history(
        lead = lead,
        requester = user,
        conversation_id = if (explicit) function() host$id
      )
      shinychat::chat_enable_history(
        "chat",
        lead,
        on_save = function(values) {
          values$host_conversation <- host$id
          host$saver$on_save(values)
        },
        on_restore = function(values) {
          host$id <- reopen(values)
          if (!explicit) {
            lead$conversation_id <- host$id
          }
          host$saver$on_restore(values)
        },
        options = shinychat::history_options(
          restore_mode = "none",
          store = store,
          scope = "test",
          title = NULL
        )
      )
      shiny::observeEvent(input$chat_user_input, {
        if (!length(lead$get_turns())) {
          host$count <- host$count + 1L
          host$id <- paste0(prefix, host$count)
        }
        lead$conversation_id <- host$id
        stream <- lead$stream_async(input$chat_user_input, stream = "content")
        # Keep what the app hands to the chat.
        shown <- coro::async_generator(function() {
          for (chunk in coro::await_each(stream)) {
            host$seen[[length(host$seen) + 1L]] <- chunk
            coro::yield(chunk)
          }
        })
        promises::then(shinychat::chat_append("chat", shown()), function(x) {
          host$replies <- host$replies + 1L
        })
      })
    },
    {
      session$flushReact()
      body(session, host)
    }
  )
  host
}

host_history_submit <- function(session, host, text) {
  before <- host$replies
  session$setInputs(chat_user_input = text)
  history_wait(session, function() host$replies > before)
  host$id
}

# The record shinychat saved for the conversation the app calls `host_id`.
host_history_record <- function(store, host_id) {
  for (record in store$saved) {
    if (identical(record$values$host_conversation, host_id)) {
      return(record)
    }
  }
  NULL
}

test_that("subagent_chat_history() without a chat saves through the app's history", {
  counter <- new.env()
  counter$calls <- 0L
  store <- HistoryTestStore$new(withr::local_tempdir())
  lead <- history_lead(history_root_server(), history_sales_server(), counter)
  host_history_session(lead, store, function(session, host) {
    expect_identical(host_history_submit(session, host, "Revenue?"), "host-1")
    # The subagent's call reached the chat in the stream the app consumed,
    # and is in the lead's turns, which shinychat saves.
    shown <- Filter(is_activity_content, host$seen)
    expect_length(shown, 2L)
    expect_s3_class(shown[[1L]], "ellmer::ContentToolRequest")
    expect_identical(shown[[1L]]@name, "call_measure")
    expect_s3_class(shown[[2L]], "ellmer::ContentToolResult")
    turns <- unlist(lapply(lead$get_turns(), function(turn) turn@contents))
    expect_length(Filter(is_activity_content, turns), 2L)
    status <- host$saver$status()
    expect_identical(status$conversation_id, "host-1")
    expect_identical(status$saved, 1L)
    expect_null(status$error)
    expect_identical(host$saver$conversation_id(), "host-1")
    expect_length(host$saver$restored(), 1L)
  })
  expect_null(lead$.__enclos_env__$private$.activity)
  expect_identical(counter$calls, 1L)
  record <- host_history_record(store, "host-1")
  saved <- record$values$deputy_subagents
  expect_identical(saved$format, "deputy_conversation_subagents")
  expect_identical(saved$conversation_id, "host-1")
  children <- history_parse(saved$data)$history$children
  expect_length(children, 1L)
  expect_identical(
    children[[1L]]$outcome$runtime$host_conversation_id,
    "host-1"
  )

  # A new session and a lead that can't reach a model.
  restored_lead <- history_lead(NULL, NULL, counter)
  host_history_session(restored_lead, store, function(session, host) {
    expect_null(host$saver$restored())
    session$setInputs(chat_history_select = list(id = record$id))
    session$flushReact()
    expect_identical(restored_lead$conversation_id, "host-1")
    status <- host$saver$status()
    expect_identical(status$conversation_id, "host-1")
    expect_identical(status$saved, 1L)
    expect_null(status$error)
    views <- host$saver$restored()
    expect_length(views, 1L)
    view <- views[[1L]]
    expect_identical(view$outcome$runtime$agent_name, "sales")
    expect_identical(view$outcome$runtime$host_conversation_id, "host-1")
    expect_identical(view$retention$execution, "read_only")
    expect_identical(view$retention$transcript, "included")
    result <- history_results(view$turns)[[1L]]
    expect_identical(result@extra$display$title, "Ran a trusted calculation")
    # The cards are back in the shown conversation only.
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

  # Records saved under another conversation are not read.
  elsewhere <- history_lead(NULL, NULL, counter)
  host_history_session(
    elsewhere,
    store,
    function(session, host) {
      session$setInputs(chat_history_select = list(id = record$id))
      session$flushReact()
      expect_null(host$saver$restored())
      status <- host$saver$status()
      expect_identical(status$conversation_id, "host-other")
      expect_identical(status$saved, 0L)
      expect_match(status$error, "could not be read")
    },
    reopen = function(values) "host-other"
  )
  expect_identical(counter$calls, 1L)
})

test_that("without a chat, each conversation saves only its own subagents", {
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
  host_history_session(lead, store, function(session, host) {
    expect_identical(host_history_submit(session, host, "One?"), "host-1")
    expect_length(host$saver$restored(), 1L)
    session$setInputs(chat_history_new = 1L)
    session$flushReact()
    # A new chat empties the lead, which leaves no conversation open until
    # the app names the next one: the first conversation's subagent is no
    # longer shown, and nothing is saved under its ID.
    expect_null(lead$conversation_id)
    expect_null(host$saver$conversation_id())
    expect_null(host$saver$restored())
    expect_identical(host$saver$on_save(list(other = 1)), list(other = 1))
    expect_identical(host_history_submit(session, host, "Two?"), "host-2")
    views <- host$saver$restored()
    expect_length(views, 1L)
    expect_identical(views[[1L]]$outcome$runtime$host_conversation_id, "host-2")
    # Reopening the first conversation reads its subagent instead.
    one <- host_history_record(store, "host-1")
    session$setInputs(chat_history_select = list(id = one$id))
    session$flushReact()
    expect_identical(lead$conversation_id, "host-1")
    expect_identical(host$saver$status()$saved, 1L)
    views <- host$saver$restored()
    expect_length(views, 1L)
    expect_identical(views[[1L]]$outcome$runtime$host_conversation_id, "host-1")
  })
  expect_identical(counter$calls, 2L)
  for (id in c("host-1", "host-2")) {
    saved <- host_history_record(store, id)$values$deputy_subagents
    expect_identical(saved$conversation_id, id)
    children <- history_parse(saved$data)$history$children
    expect_length(children, 1L)
    expect_identical(children[[1L]]$outcome$runtime$host_conversation_id, id)
  }
})

test_that("subagent_chat_history() reads the open conversation from conversation_id", {
  counter <- new.env()
  counter$calls <- 0L
  store <- HistoryTestStore$new(withr::local_tempdir())
  lead <- history_lead(history_root_server(), history_sales_server(), counter)
  host_history_session(
    lead,
    store,
    function(session, host) {
      expect_identical(host_history_submit(session, host, "Revenue?"), "app-1")
      # The app's function decides which conversation is open, whatever the
      # lead was last told.
      lead$conversation_id <- "unrelated"
      expect_identical(host$saver$conversation_id(), "app-1")
      expect_identical(host$saver$status()$saved, 1L)
      expect_length(host$saver$restored(), 1L)
      # A save for another conversation leaves this one's subagent out.
      host$id <- "app-2"
      values <- host$saver$on_save(list(other = 1))
      expect_identical(values$other, 1)
      expect_identical(values$deputy_subagents$conversation_id, "app-2")
      expect_length(
        history_parse(values$deputy_subagents$data)$history$children,
        0L
      )
      host$id <- "app-1"
    },
    explicit = TRUE,
    prefix = "app-"
  )
  record <- host_history_record(store, "app-1")
  expect_identical(record$values$deputy_subagents$conversation_id, "app-1")

  # Reopened, the lead isn't told the conversation; the app's function is
  # read instead.
  restored_lead <- history_lead(NULL, NULL, counter)
  host_history_session(
    restored_lead,
    store,
    function(session, host) {
      session$setInputs(chat_history_select = list(id = record$id))
      session$flushReact()
      expect_null(restored_lead$conversation_id)
      expect_identical(host$saver$status()$conversation_id, "app-1")
      views <- host$saver$restored()
      expect_length(views, 1L)
      expect_identical(
        views[[1L]]$outcome$runtime$host_conversation_id,
        "app-1"
      )
      expect_identical(views[[1L]]$retention$execution, "read_only")
      expect_length(restored_lead$inspect_subagents("viewer"), 0L)
    },
    explicit = TRUE
  )

  # Records saved under another conversation are not read.
  elsewhere <- history_lead(NULL, NULL, counter)
  host_history_session(
    elsewhere,
    store,
    function(session, host) {
      session$setInputs(chat_history_select = list(id = record$id))
      session$flushReact()
      expect_null(host$saver$restored())
      status <- host$saver$status()
      expect_identical(status$conversation_id, "app-other")
      expect_identical(status$saved, 0L)
      expect_match(status$error, "could not be read")
    },
    explicit = TRUE,
    reopen = function(values) "app-other"
  )
  expect_identical(counter$calls, 1L)
})

test_that("subagent_chat_history() without a chat checks its arguments", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("shinychat", "0.5.0")
  skip_if_not_installed("bslib")
  skip_if_not_installed("commonmark")
  skip_if_not_installed("xml2")
  lead <- Agent$new(
    ellmer::chat_openai(credentials = function() "x", echo = "none"),
    delegation_disclosure = history_disclosure()
  )
  viewer <- function() "viewer"
  shiny::testServer(
    function(input, output, session) {
      chat <- shinychat::chat_server("chat", lead, history = FALSE)
      expect_error(
        subagent_chat_history(chat, lead, viewer, conversation_id = viewer),
        "not both"
      )
      expect_error(subagent_chat_history(requester = viewer), "Agent")
      expect_error(
        subagent_chat_history(lead = "lead", requester = viewer),
        "Agent"
      )
      expect_error(
        subagent_chat_history(lead = lead, requester = "viewer"),
        "function"
      )
      expect_error(
        subagent_chat_history(lead = lead, requester = viewer, max_bytes = 10),
        "at least 1024"
      )
      expect_error(
        subagent_chat_history(
          lead = lead,
          requester = viewer,
          conversation_id = "conv-a"
        ),
        "conversation_id"
      )
      # Given the chat, Deputy registers its callbacks there itself.
      expect_named(
        subagent_chat_history(chat, lead, viewer),
        c("restored", "status", "conversation_id")
      )
      saver <- subagent_chat_history(lead = lead, requester = viewer)
      expect_named(
        saver,
        c("restored", "status", "conversation_id", "on_save", "on_restore")
      )
      # No open conversation: nothing is saved, read or restored.
      expect_null(saver$conversation_id())
      expect_identical(saver$on_save(list(other = 1)), list(other = 1))
      expect_null(saver$on_restore(list()))
      expect_null(saver$restored())
      expect_null(saver$status()$conversation_id)
      # An ID that isn't one is reported as such.
      odd <- subagent_chat_history(
        lead = lead,
        requester = viewer,
        conversation_id = function() 1
      )
      expect_error(odd$status(), "conversation_id")
      expect_identical(odd$on_save(list(other = 1)), list(other = 1))
    },
    {
      session$flushReact()
    }
  )
})
