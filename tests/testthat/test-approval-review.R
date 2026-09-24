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
