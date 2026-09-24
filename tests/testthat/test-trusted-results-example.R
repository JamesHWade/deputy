forecast_recipe <- function() {
  environment <- new.env(parent = baseenv())
  sys.source(
    system.file(
      "examples",
      "trusted-results",
      "forecast.R",
      package = "deputy"
    ),
    environment
  )
  environment
}

test_that("the forecast recipe publishes only reviewed trusted results", {
  recipe <- forecast_recipe()
  server <- local_runtime_server(list(
    runtime_reply(
      tool = "get_forecast",
      arguments = list(city = "Oslo", days = 3L)
    ),
    runtime_reply("Model commentary: 99 degrees.")
  ))
  delivered <- list()
  directory <- withr::local_tempdir()
  agent <- recipe$forecast_agent(
    runtime_chat(server),
    directory,
    on_result = function(event) delivered[[length(delivered) + 1L]] <<- event
  )
  expect_error(agent$register_tool(tool_run_r_code), "executes model-supplied")
  expect_error(agent$register_tool(tool_write_file), "may write")

  agent$run_sync("Forecast for Oslo")
  pending <- agent$pending_approval()
  expect_identical(pending$request$tool_input, list(city = "Oslo", days = 3L))
  expect_length(delivered, 0L)

  agent$resume_approval(
    pending$source$path,
    "approve",
    tool_input = list(city = "Lima", days = 2L)
  )
  expect_length(delivered, 1L)
  forecast <- jsonlite::fromJSON(delivered[[1L]]$value)
  expect_identical(forecast$city, "Lima")
  expect_identical(forecast$daily$high_c, c(24L, 25L))
})

test_that("the three-area app fills the result panel only from the trusted tool", {
  skip_if_not_installed("shiny")
  skip_if_not_installed("bslib")
  skip_if_not_installed("shinychat", "0.5.0")
  skip_if_not_installed("httpuv")
  directory <- system.file("examples", "trusted-results", package = "deputy")
  withr::local_dir(directory)
  app <- source("app.R", local = TRUE)$value
  shiny::testServer(app, {
    expect_match(output$result$html, "No trusted result yet")

    # shinychat delivers a list of contents, not a bare string.
    session$setInputs(chat_user_input = list("Forecast for Oslo"))
    expect_null(result())
    expect_match(output$result$html, "No trusted result yet")
    expect_false(is.null(agent$pending_approval()))
    expect_identical(fixture$requests(), 1L)

    # Review: shorten the forecast to two days, then approve.
    session$setInputs(`review-field_2` = 2)
    session$setInputs(`review-approve` = 1)
    expect_identical(result()$tool_name, "get_forecast")
    html <- output$result$html
    expect_match(html, "Oslo, 2 days", fixed = TRUE)
    expect_match(html, result()$result_id, fixed = TRUE)
    expect_no_match(html, "99 degrees", fixed = TRUE)
    expect_identical(fixture$requests(), 2L)
    # The continuation finished instead of proposing another call.
    expect_null(review$pending())
    expect_identical(review$outcome()$result$stop_reason, "complete")
    expect_match(
      review$outcome()$result$response,
      "Model commentary",
      fixed = TRUE
    )

    retained <- approval_dir
    session$close()
    expect_false(dir.exists(retained))
  })
})
