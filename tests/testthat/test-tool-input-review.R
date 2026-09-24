test_that("tool_input_review pairs values with declared types", {
  arguments <- ellmer::type_object(
    plan = ellmer::type_object(
      treatment = ellmer::type_enum(c("trt1", "trt2"), "Treatment group"),
      units = ellmer::type_string("Units")
    ),
    days = ellmer::type_integer("Days", required = FALSE),
    cities = ellmer::type_array(ellmer::type_string())
  )
  review <- tool_input_review(
    list(
      plan = list(treatment = "trt2", units = "g"),
      cities = list("Oslo", "Lima"),
      extra = TRUE
    ),
    arguments
  )
  expect_identical(
    review$argument,
    c("plan.treatment", "plan.units", "days", "cities", "extra")
  )
  expect_identical(
    review$type,
    c("enum(trt1, trt2)", "string", "integer", "array<string>", NA)
  )
  expect_identical(review$required, c(TRUE, TRUE, FALSE, TRUE, NA))
  expect_identical(review$declared, c(TRUE, TRUE, TRUE, TRUE, FALSE))
  expect_identical(
    review$value,
    c("trt2", "g", NA, "[\"Oslo\",\"Lima\"]", "true")
  )
  expect_identical(review$description[[1L]], "Treatment group")
  expect_identical(attr(review, "paths")[[1L]], c("plan", "treatment"))
  dotted <- tool_input_review(list(postal.code = "0150"))
  expect_identical(attr(dotted, "paths"), list("postal.code"))
})

test_that("tool_input_review works without a declaration and validates input", {
  review <- tool_input_review(list(city = "Oslo"))
  expect_identical(review$argument, "city")
  expect_false(review$declared)
  empty <- tool_input_review(list())
  expect_identical(nrow(empty), 0L)
  expect_named(
    empty,
    c("argument", "type", "required", "declared", "description", "value")
  )
  expect_error(tool_input_review("x"), "named list")
  expect_error(tool_input_review(list(1)), "named list")
  expect_error(tool_input_review(list(), "x"), "TypeObject")
})

test_that("permission callbacks receive the registered argument types", {
  server <- local_runtime_server(list(
    runtime_reply(tool = "forecast", arguments = list(city = "Oslo")),
    runtime_reply("done")
  ))
  seen <- NULL
  forecast <- ellmer::tool(
    fun = function(city) "sunny",
    name = "forecast",
    description = "Forecast.",
    arguments = list(city = ellmer::type_string("City")),
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE
    )
  )
  agent <- Agent$new(
    runtime_chat(server),
    tools = list(forecast),
    permissions = Permissions(
      can_use_tool = function(tool_name, tool_input, context) {
        seen <<- tool_input_review(tool_input, context$tool_arguments)
        PermissionResultAllow()
      }
    )
  )
  agent$run_sync("Forecast?")
  expect_identical(seen$argument, "city")
  expect_identical(seen$type, "string")
  expect_identical(seen$description, "City")
  expect_identical(seen$value, "Oslo")
})
