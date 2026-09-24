# The host's trusted tool and Agent, sourced by the app and its tests.
# Only forecast_tool() can produce a forecast; the model proposes its inputs.
forecast_table <- function() {
  data.frame(
    city = rep(c("Oslo", "Lima", "Nairobi"), each = 5L),
    day = rep(1:5, times = 3L),
    high_c = c(12, 14, 13, 11, 10, 24, 25, 25, 23, 24, 26, 27, 25, 26, 28),
    low_c = c(4, 6, 5, 3, 2, 17, 18, 18, 17, 16, 14, 15, 14, 13, 15)
  )
}

forecast_tool <- function() {
  ellmer::tool(
    function(city, days) {
      table <- forecast_table()
      if (
        !is.character(city) ||
          length(city) != 1L ||
          !city %in% table$city ||
          !is.numeric(days) ||
          length(days) != 1L ||
          days != round(days) ||
          days < 1 ||
          days > 5
      ) {
        cli::cli_abort("Use a supported city and 1 to 5 days.")
      }
      rows <- table[table$city == city & table$day <= days, ]
      as.character(jsonlite::toJSON(
        list(
          city = city,
          days = as.integer(days),
          daily = rows[c("day", "high_c", "low_c")],
          source = "Synthetic demonstration table bundled with this example"
        ),
        auto_unbox = TRUE,
        dataframe = "rows"
      ))
    },
    name = "get_forecast",
    description = "Produce the forecast for one supported city.",
    arguments = list(
      city = ellmer::type_enum(
        c("Oslo", "Lima", "Nairobi"),
        "City to forecast"
      ),
      days = ellmer::type_integer("Number of days, 1 to 5")
    ),
    # Raw JSON arguments let the reviewer's edits be revalidated on resume.
    convert = FALSE,
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE,
      idempotent_hint = TRUE
    )
  )
}

forecast_agent <- function(chat, approval_dir, on_result) {
  deputy::Agent$new(
    chat = chat,
    tools = list(forecast_tool()),
    system_prompt = paste(
      "You help people check a weather forecast. Call get_forecast with the",
      "city and number of days. Never state forecast numbers yourself; the",
      "user sees the tool's result in a separate panel."
    ),
    working_dir = approval_dir,
    approval_dir = approval_dir,
    usage_limits = deputy::UsageLimits(max_requests = 4L, max_tool_calls = 2L),
    # Every forecast request pauses for human review of its inputs.
    permissions = deputy::Permissions(
      can_use_tool = function(tool_name, tool_input, context) {
        if (identical(tool_name, "get_forecast")) {
          return(deputy::PermissionResultPending(
            "Check the city and number of days before the forecast runs."
          ))
        }
        deputy::PermissionResultDeny("Only get_forecast is available.")
      }
    ),
    # get_forecast is the only producer of forecasts. Its value goes straight
    # to the results card; the model only receives a receipt.
    trusted_results = deputy::TrustedResults(
      forecast = "get_forecast",
      on_result = on_result,
      model_receipt = TRUE
    )
  )
}
