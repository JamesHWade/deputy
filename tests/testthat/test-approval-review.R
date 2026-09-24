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

      session$setInputs(field_1 = "Lima", field_2 = 5)
      session$setInputs(approve = 1)
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
      session$setInputs(deny = 1)
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
      session$setInputs(field_1 = "Oslo", field_2 = 3)
      session$setInputs(approve = 1)
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
    session$setInputs(field_1 = "turbo", field_2 = "", field_3 = "")
    session$setInputs(approve = 1)
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
    session$setInputs(field_1 = "yes", field_2 = "")
    session$setInputs(approve = 1)
    expect_null(outcome()$tool_input)
  })
  expect_identical(seen[[1L]]$verbose, "yes")

  agent$run_sync("Configure again")
  shiny::testServer(approval_review_server, args = list(agent = agent), {
    session$setInputs(field_1 = "true", field_2 = "f")
    session$setInputs(approve = 1)
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
      session$setInputs(field_1 = "0151", field_2 = 2.5)
      session$setInputs(approve = 1)
      expect_identical(decided, list(postal.code = "0151", days = 2.5))
      # decide() returned without resolving the approval; a repeat click is
      # ignored rather than submitted twice.
      decided <<- NULL
      session$setInputs(approve = 2)
      expect_null(decided)
    }
  )
})

test_that("clearing a number removes the field", {
  expect_identical(
    approval_review_set(list(a = 1, b = 2), "a", NULL),
    list(b = 2)
  )
  expect_identical(
    approval_review_set(list(), c("x", "y"), "v"),
    list(x = list(y = "v"))
  )
  expect_null(approval_review_coerce(NA, ellmer::type_integer()))
  expect_identical(approval_review_coerce(2, ellmer::type_integer()), 2L)
  expect_identical(approval_review_coerce(2.5, ellmer::type_integer()), 2.5)
})
