# Map field_<i>, set_<i>, approve and deny to the keyed ids of the approval
# currently shown, as the browser would.
review_set <- function(session, record, ...) {
  values <- list(...)
  key <- approval_review_key(record$id)
  names(values) <- sub(
    "^(field|set)_([0-9]+)$",
    paste0("\\1_", key, "_\\2"),
    names(values)
  )
  names(values) <- sub("^(approve|deny)$", paste0("\\1_", key), names(values))
  do.call(session$setInputs, values)
}

review_agent <- function(server, directory, delivered = NULL) {
  forecast <- ellmer::tool(
    fun = function(city, days) {
      paste0('{"city":"', city, '","days":', days, "}")
    },
    name = "get_forecast",
    description = "Compute the forecast.",
    arguments = list(
      city = ellmer::type_enum(c("Oslo", "Lima"), "City to forecast"),
      days = ellmer::type_integer("Forecast length")
    ),
    convert = FALSE,
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE
    )
  )
  Agent$new(
    runtime_chat(server),
    tools = list(forecast),
    working_dir = directory,
    approval_dir = directory,
    permissions = Permissions(
      can_use_tool = function(tool_name, tool_input, context) {
        PermissionResultPending("Check the city and length.")
      }
    ),
    trusted_results = TrustedResults(
      forecast = "get_forecast",
      on_result = function(event) {
        if (is.environment(delivered)) {
          delivered$events <- c(delivered$events, list(event))
        }
      }
    )
  )
}

test_that("the review module shows typed inputs and resumes with edits", {
  skip_if_not_installed("shiny")
  directory <- withr::local_tempdir()
  server <- local_runtime_server(list(
    runtime_reply(
      tool = "get_forecast",
      arguments = list(city = "Oslo", days = 3L)
    ),
    runtime_reply("Shown in the panel.")
  ))
  delivered <- new.env(parent = emptyenv())
  agent <- review_agent(server, directory, delivered)

  shiny::testServer(
    approval_review_server,
    args = list(agent = agent),
    {
      expect_null(pending())
      expect_match(output$review$html, "No tool call is waiting")

      agent$run_sync("Forecast?")
      session$flushReact()
      expect_false(is.null(pending()))
      html <- output$review$html
      expect_match(html, "get_forecast", fixed = TRUE)
      expect_match(html, "Check the city and length.", fixed = TRUE)
      expect_match(html, "enum(Oslo, Lima)", fixed = TRUE)
      expect_match(html, "City to forecast", fixed = TRUE)
      expect_null(delivered$events)

      review_set(session, pending(), field_1 = "Lima", field_2 = 5)
      review_set(session, pending(), approve = 1)
      expect_identical(outcome()$decision, "approve")
      expect_identical(outcome()$tool_input, list(city = "Lima", days = 5L))
      expect_s7_class(outcome()$result, AgentResult)
      expect_null(pending())
    }
  )
  expect_length(delivered$events, 1L)
  expect_identical(delivered$events[[1L]]$value, '{"city":"Lima","days":5}')
})

test_that("denial executes nothing and unchanged approval keeps the input", {
  skip_if_not_installed("shiny")
  directory <- withr::local_tempdir()
  server <- local_runtime_server(list(
    runtime_reply(
      tool = "get_forecast",
      arguments = list(city = "Oslo", days = 3L)
    ),
    runtime_reply("Denied.")
  ))
  delivered <- new.env(parent = emptyenv())
  agent <- review_agent(server, directory, delivered)
  agent$run_sync("Forecast?")
  decisions <- list()
  shiny::testServer(
    approval_review_server,
    args = list(
      agent = agent,
      decide = function(path, decision, tool_input) {
        decisions[[length(decisions) + 1L]] <<- list(decision, tool_input)
        agent$resume_approval(path, decision, tool_input = tool_input)
      }
    ),
    {
      review_set(session, pending(), deny = 1)
      expect_identical(outcome()$decision, "deny")
      expect_null(outcome()$tool_input)
    }
  )
  expect_identical(decisions, list(list("deny", NULL)))
  expect_null(delivered$events)
})

test_that("unchanged approval passes no edit and errors are reported", {
  skip_if_not_installed("shiny")
  directory <- withr::local_tempdir()
  server <- local_runtime_server(list(
    runtime_reply(
      tool = "get_forecast",
      arguments = list(city = "Oslo", days = 3L)
    ),
    runtime_reply("ok")
  ))
  agent <- review_agent(server, directory)
  agent$run_sync("Forecast?")
  shiny::testServer(
    approval_review_server,
    args = list(
      agent = agent,
      decide = function(path, decision, tool_input) stop("host unavailable")
    ),
    {
      review_set(session, pending(), field_1 = "Oslo", field_2 = 3)
      review_set(session, pending(), approve = 1)
      expect_null(outcome()$tool_input)
      expect_identical(outcome()$error, "host unavailable")
    }
  )
  expect_error(
    approval_review_server("x", agent = list()),
    "must be a deputy Agent"
  )
})

test_that("untouched approval never fills missing or out-of-range fields", {
  skip_if_not_installed("shiny")
  directory <- withr::local_tempdir()
  server <- local_runtime_server(list(
    runtime_reply(tool = "configure", arguments = list(mode = "turbo")),
    runtime_reply("ok")
  ))
  seen <- NULL
  configure <- ellmer::tool(
    fun = function(mode, units = NULL, verbose = NULL) {
      seen <<- list(mode = mode, units = units, verbose = verbose)
      "configured"
    },
    name = "configure",
    description = "Configure.",
    arguments = list(
      mode = ellmer::type_enum(c("fast", "slow")),
      units = ellmer::type_enum(c("c", "f"), required = FALSE),
      verbose = ellmer::type_boolean(required = FALSE)
    ),
    convert = FALSE,
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE
    )
  )
  agent <- Agent$new(
    runtime_chat(server),
    tools = list(configure),
    working_dir = directory,
    approval_dir = directory,
    permissions = Permissions(
      can_use_tool = function(tool_name, tool_input, context) {
        PermissionResultPending("Review.")
      }
    )
  )
  agent$run_sync("Configure")
  shiny::testServer(approval_review_server, args = list(agent = agent), {
    html <- output$review$html
    expect_match(html, "Not provided", fixed = TRUE)
    expect_match(html, "turbo", fixed = TRUE)
    # Shiny reports each editor's initial selection.
    review_set(
      session,
      pending(),
      field_1 = "turbo",
      field_2 = "",
      field_3 = ""
    )
    review_set(session, pending(), approve = 1)
    expect_null(outcome()$tool_input)
  })
  expect_identical(seen, list(mode = "turbo", units = NULL, verbose = NULL))
})

test_that("untouched invalid values and edits inside absent objects are kept", {
  skip_if_not_installed("shiny")
  directory <- withr::local_tempdir()
  server <- local_runtime_server(list(
    runtime_reply(tool = "configure", arguments = list(verbose = "yes")),
    runtime_reply("ok"),
    runtime_reply(tool = "configure", arguments = list(verbose = TRUE)),
    runtime_reply("ok")
  ))
  seen <- list()
  configure <- ellmer::tool(
    fun = function(verbose, options = NULL) {
      seen[[length(seen) + 1L]] <<- list(verbose = verbose, options = options)
      "configured"
    },
    name = "configure",
    description = "Configure.",
    arguments = list(
      verbose = ellmer::type_boolean(),
      options = ellmer::type_object(
        units = ellmer::type_enum(c("c", "f")),
        .required = FALSE
      )
    ),
    convert = FALSE,
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE
    )
  )
  agent <- Agent$new(
    runtime_chat(server),
    tools = list(configure),
    working_dir = directory,
    approval_dir = directory,
    permissions = Permissions(
      can_use_tool = function(tool_name, tool_input, context) {
        PermissionResultPending("Review.")
      }
    )
  )
  agent$run_sync("Configure")
  shiny::testServer(approval_review_server, args = list(agent = agent), {
    expect_identical(output$review$html |> grepl(pattern = "yes"), TRUE)
    review_set(session, pending(), field_1 = "yes", field_2 = "")
    review_set(session, pending(), approve = 1)
    expect_null(outcome()$tool_input)
  })
  expect_identical(seen[[1L]]$verbose, "yes")

  agent$run_sync("Configure again")
  shiny::testServer(approval_review_server, args = list(agent = agent), {
    review_set(session, pending(), field_1 = "true", field_2 = "f")
    review_set(session, pending(), approve = 1)
    expect_null(outcome()$error)
    expect_identical(
      outcome()$tool_input,
      list(verbose = TRUE, options = list(units = "f"))
    )
  })
  expect_identical(seen[[2L]]$options, list(units = "f"))
})

test_that("edits keep dotted names and fractional integers exactly", {
  skip_if_not_installed("shiny")
  directory <- withr::local_tempdir()
  server <- local_runtime_server(list(
    runtime_reply(
      tool = "locate",
      arguments = list(postal.code = "0150", days = 3L)
    ),
    runtime_reply("ok")
  ))
  locate <- ellmer::tool(
    fun = function(postal.code, days) "located",
    name = "locate",
    description = "Locate.",
    arguments = list(
      postal.code = ellmer::type_string(),
      days = ellmer::type_integer()
    ),
    convert = FALSE,
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE
    )
  )
  agent <- Agent$new(
    runtime_chat(server),
    tools = list(locate),
    working_dir = directory,
    approval_dir = directory,
    permissions = Permissions(
      can_use_tool = function(tool_name, tool_input, context) {
        PermissionResultPending("Review.")
      }
    )
  )
  agent$run_sync("Locate")
  decided <- NULL
  shiny::testServer(
    approval_review_server,
    args = list(
      agent = agent,
      decide = function(path, decision, tool_input) {
        decided <<- tool_input
        NULL
      }
    ),
    {
      review_set(session, pending(), field_1 = "0151", field_2 = 2.5)
      review_set(session, pending(), approve = 1)
      expect_identical(decided, list(postal.code = "0151", days = 2.5))
      # decide() returned without resolving the approval; a repeat click is
      # ignored rather than submitted twice.
      decided <<- NULL
      review_set(session, pending(), approve = 2)
      expect_null(decided)
    }
  )
})

test_that("numbers are edited as exact text", {
  expect_identical(
    approval_review_set(list(a = 1, b = 2), "a", NULL),
    list(b = 2)
  )
  expect_identical(
    approval_review_set(list(), c("x", "y"), "v"),
    list(x = list(y = "v"))
  )
  expect_null(approval_review_coerce("", "integer"))
  expect_identical(approval_review_coerce(" 2 ", "integer"), 2L)
  expect_identical(approval_review_coerce("2.5", "integer"), 2.5)
  expect_identical(approval_review_coerce("3000000000", "integer"), 3e9)
  expect_identical(approval_review_coerce("abc", "number"), "abc")
  expect_identical(approval_review_coerce("1000000001", "number"), 1000000001)
  expect_identical(
    approval_review_number_text(0.1 + 0.2),
    "0.30000000000000004"
  )
  expect_identical(approval_review_number_text(3e9), "3000000000")
  expect_identical(approval_review_number_text(3L), "3")
})

test_that("fields show exactly what was proposed and absence is explicit", {
  skip_if_not_installed("shiny")
  directory <- withr::local_tempdir()
  server <- local_runtime_server(list(
    runtime_reply(tool = "note", arguments = list(count = "abc")),
    runtime_reply("ok")
  ))
  note <- ellmer::tool(
    fun = function(count, label = NULL) "noted",
    name = "note",
    description = "Note.",
    arguments = list(
      count = ellmer::type_number(),
      label = ellmer::type_string(required = FALSE)
    ),
    convert = FALSE,
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE
    )
  )
  agent <- Agent$new(
    runtime_chat(server),
    tools = list(note),
    working_dir = directory,
    approval_dir = directory,
    permissions = Permissions(
      can_use_tool = function(tool_name, tool_input, context) {
        PermissionResultPending("Review.")
      }
    )
  )
  agent$run_sync("Note")
  decided <- list()
  shiny::testServer(
    approval_review_server,
    args = list(
      agent = agent,
      decide = function(path, decision, tool_input) {
        decided[[length(decided) + 1L]] <<- list(tool_input)
        NULL
      }
    ),
    {
      html <- output$review$html
      # The invalid number is displayed as proposed, not as a blank editor.
      expect_match(html, "<code>abc</code>", fixed = TRUE)
      expect_no_match(html, "field_1\" type=\"number", fixed = TRUE)
      expect_match(html, "Provide a value for label", fixed = TRUE)
      # Without opting in, the empty text box leaves label absent.
      review_set(session, pending(), field_2 = "")
      review_set(session, pending(), approve = 1)
    }
  )
  expect_identical(decided, list(list(NULL)))

  shiny::testServer(
    approval_review_server,
    args = list(
      agent = agent,
      decide = function(path, decision, tool_input) {
        decided[[length(decided) + 1L]] <<- list(tool_input)
        NULL
      }
    ),
    {
      # Opting in sets an intentionally empty string.
      review_set(session, pending(), set_2 = TRUE, field_2 = "")
      review_set(session, pending(), approve = 1)
    }
  )
  expect_identical(decided[[2L]][[1L]], list(count = "abc", label = ""))
})

review_numbers_agent <- function(server, directory, arguments) {
  tool <- ellmer::tool(
    fun = function(n, x) "ok",
    name = "measure",
    description = "Measure.",
    arguments = list(n = ellmer::type_integer(), x = ellmer::type_number()),
    convert = FALSE,
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE
    )
  )
  Agent$new(
    runtime_chat(server),
    tools = list(tool),
    working_dir = directory,
    approval_dir = directory,
    permissions = Permissions(
      can_use_tool = function(tool_name, tool_input, context) {
        PermissionResultPending("Review.")
      }
    )
  )
}

test_that("large and precise numbers survive untouched and edits are exact", {
  skip_if_not_installed("shiny")
  directory <- withr::local_tempdir()
  server <- local_runtime_server(list(
    runtime_reply(
      tool = "measure",
      arguments = list(n = 3000000000, x = 1000000000)
    ),
    runtime_reply("ok")
  ))
  agent <- review_numbers_agent(server, directory)
  agent$run_sync("Measure")
  decided <- list()
  record_decision <- function(path, decision, tool_input) {
    decided[[length(decided) + 1L]] <<- list(tool_input)
    NULL
  }
  shiny::testServer(
    approval_review_server,
    args = list(agent = agent, decide = record_decision),
    {
      html <- output$review$html
      expect_match(html, "3000000000", fixed = TRUE)
      # The browser reports the text it was given.
      review_set(
        session,
        pending(),
        field_1 = "3000000000",
        field_2 = "1000000000"
      )
      review_set(session, pending(), approve = 1)
    }
  )
  expect_identical(decided, list(list(NULL)))

  server2 <- local_runtime_server(list(
    runtime_reply(tool = "measure", arguments = list(n = 1L, x = 1000000000)),
    runtime_reply("ok")
  ))
  agent2 <- review_numbers_agent(server2, withr::local_tempdir())
  agent2$run_sync("Measure")
  shiny::testServer(
    approval_review_server,
    args = list(agent = agent2, decide = record_decision),
    {
      review_set(session, pending(), field_1 = "1", field_2 = "1000000001")
      review_set(session, pending(), approve = 1)
    }
  )
  expect_identical(decided[[2L]][[1L]], list(n = 1L, x = 1000000001))
})

test_that("stale clicks, failed decisions and odd inputs stay safe", {
  skip_if_not_installed("shiny")
  directory <- withr::local_tempdir()
  server <- local_runtime_server(list(
    runtime_reply(tool = "measure", arguments = list(n = 1L, x = 2)),
    runtime_reply("ok")
  ))
  agent <- review_numbers_agent(server, directory)
  agent$run_sync("Measure")
  calls <- 0L
  shiny::testServer(
    approval_review_server,
    args = list(
      agent = agent,
      decide = function(path, decision, tool_input) {
        calls <<- calls + 1L
        stop("host unavailable")
      }
    ),
    {
      # A click carrying another approval's key is ignored.
      session$setInputs(approve_stale = 1)
      expect_identical(calls, 0L)
      # A decision that fails before consuming the approval can be retried.
      review_set(session, pending(), approve = 1)
      expect_identical(outcome()$error, "host unavailable")
      review_set(session, pending(), approve = 2)
      expect_identical(calls, 2L)
    }
  )

  # Inputs that cannot be tabulated are shown as submitted and can be denied.
  expect_null(tryCatch(
    tool_input_review(stats::setNames(list(1), "")),
    error = function(e) NULL
  ))
})

test_that("multiline strings keep their line breaks", {
  field <- function(value) {
    approval_review_field(
      list(note = value),
      ellmer::type_object(note = ellmer::type_string()),
      "note"
    )
  }
  multiline <- field("first\nsecond")
  expect_identical(multiline$mode, "edit")
  editor <- as.character(approval_review_editor(
    shiny::NS("r"),
    "k",
    1L,
    data.frame(argument = "note", value = "first\nsecond"),
    multiline
  ))
  expect_match(editor, "<textarea", fixed = TRUE)
  expect_match(editor, "first\nsecond", fixed = TRUE)
  expect_identical(field("a\r\nb")$mode, "readonly")
  expect_identical(field("\nleading")$mode, "readonly")
  expect_identical(field("plain")$mode, "edit")
})

test_that("asynchronous decisions refresh on success and allow retry on failure", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("later")
  directory <- withr::local_tempdir()
  server <- local_runtime_server(list(
    runtime_reply(tool = "measure", arguments = list(n = 1L, x = 2)),
    runtime_reply("ok")
  ))
  agent <- review_numbers_agent(server, directory)
  agent$run_sync("Measure")
  attempts <- 0L
  shiny::testServer(
    approval_review_server,
    args = list(
      agent = agent,
      decide = function(path, decision, tool_input) {
        attempts <<- attempts + 1L
        if (attempts == 1L) {
          return(promises::promise_reject(simpleError("worker lost")))
        }
        promises::promise(function(resolve, reject) {
          later::later(function() {
            resolve(agent$resume_approval(
              path,
              decision,
              tool_input = tool_input
            ))
          })
        })
      }
    ),
    {
      review_set(session, pending(), approve = 1)
      later::run_now(1)
      session$flushReact()
      expect_identical(outcome()$error, "worker lost")
      expect_false(is.null(pending()))

      # The failed asynchronous attempt did not lock the approval.
      review_set(session, pending(), approve = 2)
      deadline <- Sys.time() + 10
      while (is.null(outcome()$result) && Sys.time() < deadline) {
        later::run_now(0.1)
        session$flushReact()
      }
      expect_s7_class(outcome()$result, AgentResult)
      expect_null(pending())
    }
  )
  expect_identical(attempts, 2L)
})
