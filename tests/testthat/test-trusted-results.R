trusted_test_chat <- function() {
  ellmer::chat_openai(
    credentials = function() "test",
    model = "gpt-4o-mini",
    echo = "none"
  )
}

trusted_forecast_tool <- function(value = '{"high_c":21,"low_c":12}') {
  ellmer::tool(
    fun = function(city) value,
    name = "get_forecast",
    description = "Compute the forecast.",
    arguments = list(city = ellmer::type_string("City name")),
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE
    )
  )
}

trusted_closed_tool <- function(name = "list_cities", ...) {
  ellmer::tool(
    fun = function() c("Oslo", "Lima"),
    name = name,
    description = "List supported cities.",
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE,
      ...
    )
  )
}

trusted_unannotated_tool <- function(name = "note") {
  ellmer::tool(
    fun = function() "ok",
    name = name,
    description = "Unannotated local tool."
  )
}

test_that("TrustedResults validates one tool per result type", {
  policy <- TrustedResults(forecast = "get_forecast", model_receipt = TRUE)
  expect_s7_class(policy, TrustedResults)
  expect_identical(policy$results, c(forecast = "get_forecast"))
  expect_true(policy$model_receipt)
  expect_error(policy@results <- c(x = "y"), "read-only")

  expect_error(TrustedResults(), "named")
  expect_error(TrustedResults("get_forecast"), "named")
  expect_error(TrustedResults(`bad type` = "tool"), "letters")
  expect_error(TrustedResults(a = "tool", a = "other"), "only once")
  expect_error(TrustedResults(a = "tool", b = "tool"), "more than one")
  expect_error(TrustedResults(a = c("x", "y")), "one tool")
  expect_error(TrustedResults(a = "t", on_result = "f"), "function")
  expect_error(TrustedResults(a = "t", exempt_tools = "t"), "also be listed")
  expect_error(TrustedResults(a = "t", model_receipt = NA), "TRUE or FALSE")
})

test_that("the complete registry is checked at every publication", {
  policy <- TrustedResults(forecast = "get_forecast")
  agent <- Agent$new(
    trusted_test_chat(),
    tools = list(trusted_forecast_tool(), trusted_closed_tool()),
    trusted_results = policy
  )
  expect_identical(agent$trusted_results, policy)
  expect_error(agent$trusted_results <- NULL, "immutable")

  before <- names(agent$get_tools())
  expect_error(
    agent$register_tool(trusted_unannotated_tool()),
    class = "deputy_tool_registration"
  )
  expect_error(agent$register_tool(tool_run_r_code), "executes model-supplied")
  expect_error(agent$register_tool(tool_run_bash), "executes model-supplied")
  expect_error(
    agent$set_tools(list(trusted_forecast_tool(), tool_write_file)),
    "may write or reach the open world"
  )
  # An explicit destructive claim stays restrictive despite read_only_hint.
  expect_error(
    agent$register_tool(trusted_closed_tool("purge", destructive_hint = TRUE)),
    "may write or reach the open world"
  )
  expect_identical(names(agent$get_tools()), before)

  # A replacement cannot sneak a bypass under an existing trusted name.
  code_named <- ellmer::tool(
    fun = function(code) code,
    name = "get_forecast",
    description = "Pretend forecast.",
    arguments = list(code = ellmer::type_string())
  )
  attr(code_named, "deputy_workspace_runner") <- function(...) NULL
  expect_error(
    agent$register_tool(code_named, replace = TRUE),
    "must be a local function tool"
  )

  expect_error(
    Agent$new(
      trusted_test_chat(),
      tools = list(trusted_forecast_tool(), tool_run_r_code),
      trusted_results = policy
    ),
    "executes model-supplied"
  )
  expect_error(
    Agent$new(trusted_test_chat(), trusted_results = list()),
    "TrustedResults object"
  )
})

test_that("explicit exemptions cover local tools but never code execution", {
  policy <- TrustedResults(
    forecast = "get_forecast",
    exempt_tools = c("note", "run_r_code")
  )
  agent <- Agent$new(
    trusted_test_chat(),
    tools = list(trusted_forecast_tool(), trusted_unannotated_tool("note")),
    trusted_results = policy
  )
  expect_named(agent$get_tools(), c("get_forecast", "note"))
  expect_error(agent$register_tool(tool_run_r_code), "executes model-supplied")

  mcp_like <- trusted_unannotated_tool("note")
  attr(mcp_like, "deputy_tool_source") <- list(
    type = "mcp",
    server = "remote",
    tool = "note"
  )
  expect_error(
    agent$register_tool(mcp_like, replace = TRUE),
    "Only local function tools"
  )
})

test_that("trusted tools must be local function tools", {
  forecast <- trusted_forecast_tool()
  attr(forecast, "deputy_tool_source") <- list(
    type = "mcp",
    server = "remote",
    tool = "get_forecast"
  )
  expect_error(
    Agent$new(
      trusted_test_chat(),
      tools = list(forecast),
      trusted_results = TrustedResults(forecast = "get_forecast")
    ),
    "must be a local function tool"
  )
})

test_that("clones keep the policy and its registry check", {
  agent <- Agent$new(
    trusted_test_chat(),
    tools = list(trusted_forecast_tool()),
    trusted_results = TrustedResults(forecast = "get_forecast")
  )
  copy <- agent$clone()
  expect_identical(copy$trusted_results, agent$trusted_results)
  expect_error(copy$register_tool(tool_run_bash), "executes model-supplied")
})

test_that("trusted values reach the host verbatim before model text", {
  server <- local_runtime_server(list(
    runtime_reply(tool = "get_forecast", arguments = list(city = "Oslo")),
    runtime_reply("It will be 99 degrees.")
  ))
  delivered <- list()
  agent <- Agent$new(
    runtime_chat(server),
    tools = list(trusted_forecast_tool()),
    trusted_results = TrustedResults(
      forecast = "get_forecast",
      on_result = function(event) {
        delivered[[length(delivered) + 1L]] <<- event
      }
    )
  )
  # A hook rewriting tool_end output cannot alter the trusted channel.
  agent$add_hook(HookMatcher(
    "PostToolUse",
    callback = function(tool_name, tool_result, tool_error, context) {
      HookResultPostToolUse(updated_tool_output = "rewritten")
    }
  ))
  result <- agent$run_sync("Forecast for Oslo?")

  trusted <- result_trusted_results(result)
  expect_length(trusted, 1L)
  event <- trusted[[1L]]
  expect_identical(event$type, "trusted_result")
  expect_identical(event$result_type, "forecast")
  expect_identical(event$tool_name, "get_forecast")
  expect_identical(event$value, '{"high_c":21,"low_c":12}')
  expect_identical(event$arguments, list(city = "Oslo"))
  expect_match(event$result_id, "^result_")
  expect_identical(event$run_id, result$run_id)
  expect_identical(
    event$tool_call_id,
    result_tool_results(result)[[1L]]$tool_call_id
  )
  expect_identical(result_tool_results(result)[[1L]]$tool_result, "rewritten")
  expect_length(result_trusted_results(result, "forecast"), 1L)
  expect_length(result_trusted_results(result, "other"), 0L)
  expect_error(result_trusted_results(result, 1), "non-empty string")

  expect_length(delivered, 1L)
  expect_identical(delivered[[1L]], event)
  types <- vapply(result$events, function(e) e$type, character(1))
  expect_lt(
    which(types == "trusted_result"),
    which(types == "tool_end")
  )
  expect_match(result$response, "It will be 99 degrees.", fixed = TRUE)
})

test_that("model receipts withhold trusted values from the conversation", {
  server <- local_runtime_server(list(
    runtime_reply(tool = "get_forecast", arguments = list(city = "Lima")),
    runtime_reply("See the forecast panel.")
  ))
  agent <- Agent$new(
    runtime_chat(server),
    tools = list(trusted_forecast_tool('{"high_c":31415}')),
    trusted_results = TrustedResults(
      forecast = "get_forecast",
      model_receipt = TRUE
    )
  )
  result <- agent$run_sync("Forecast for Lima?")
  event <- result_trusted_results(result)[[1L]]
  expect_identical(event$value, '{"high_c":31415}')

  sent <- paste(
    vapply(
      server$requests(),
      function(request) paste(deparse(request), collapse = ""),
      character(1)
    ),
    collapse = ""
  )
  expect_match(sent, event$result_id, fixed = TRUE)
  expect_no_match(sent, "31415", fixed = TRUE)
})

test_that("a failed host callback becomes a tool error for the model", {
  server <- local_runtime_server(list(
    runtime_reply(tool = "get_forecast", arguments = list(city = "Oslo")),
    runtime_reply("Could not show it.")
  ))
  notices <- list()
  agent <- Agent$new(
    runtime_chat(server),
    tools = list(trusted_forecast_tool('{"high_c":27182}')),
    trusted_results = TrustedResults(
      forecast = "get_forecast",
      on_result = function(event) stop("panel unavailable")
    )
  )
  agent$add_hook(HookMatcher(
    "Notification",
    callback = function(message, context) {
      notices[[length(notices) + 1L]] <<- context
      NULL
    }
  ))
  expect_warning(
    result <- agent$run_sync("Forecast?"),
    "could not be delivered"
  )
  expect_length(result_trusted_results(result), 1L)
  end <- result_tool_results(result)[[1L]]
  expect_false(is.null(end$tool_error))
  codes <- vapply(notices, function(x) x$code %||% "", character(1))
  expect_true("trusted_result_delivery_failed" %in% codes)

  sent <- paste(
    vapply(
      server$requests(),
      function(request) paste(deparse(request), collapse = ""),
      character(1)
    ),
    collapse = ""
  )
  expect_no_match(sent, "27182", fixed = TRUE)
  expect_no_match(sent, "panel unavailable", fixed = TRUE)
})

test_that("failed trusted tools produce no trusted result", {
  failing <- ellmer::tool(
    fun = function(city) stop("no data"),
    name = "get_forecast",
    description = "Compute the forecast.",
    arguments = list(city = ellmer::type_string()),
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE
    )
  )
  server <- local_runtime_server(list(
    runtime_reply(tool = "get_forecast", arguments = list(city = "Oslo")),
    runtime_reply("Failed.")
  ))
  called <- FALSE
  agent <- Agent$new(
    runtime_chat(server),
    tools = list(failing),
    trusted_results = TrustedResults(
      forecast = "get_forecast",
      on_result = function(event) called <<- TRUE
    )
  )
  expect_warning(result <- agent$run_sync("Forecast?"), "no data")
  expect_length(result_trusted_results(result), 0L)
  expect_false(called)
})

test_that("reviewed inputs reach the trusted tool through durable approval", {
  directory <- withr::local_tempdir()
  server <- local_runtime_server(list(
    runtime_reply(tool = "get_forecast", arguments = list(city = "Oslo")),
    runtime_reply("Shown in the panel.")
  ))
  delivered <- list()
  forecast <- ellmer::tool(
    fun = function(city) paste0('{"city":"', city, '","high_c":21}'),
    name = "get_forecast",
    description = "Compute the forecast.",
    arguments = list(city = ellmer::type_string()),
    convert = FALSE,
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE
    )
  )
  agent <- Agent$new(
    runtime_chat(server),
    tools = list(forecast),
    working_dir = directory,
    approval_dir = directory,
    permissions = Permissions(
      can_use_tool = function(tool_name, tool_input, context) {
        PermissionResultPending("Review the city.")
      }
    ),
    trusted_results = TrustedResults(
      forecast = "get_forecast",
      on_result = function(event) {
        delivered[[length(delivered) + 1L]] <<- event
      },
      model_receipt = TRUE
    )
  )
  agent$run_sync("Forecast?")
  pending <- agent$pending_approval()
  expect_false(is.null(pending))
  expect_length(delivered, 0L)

  agent$resume_approval(
    pending$source$path,
    "approve",
    tool_input = list(city = "Lima")
  )
  expect_length(delivered, 1L)
  expect_identical(delivered[[1L]]$arguments, list(city = "Lima"))
  expect_identical(delivered[[1L]]$value, '{"city":"Lima","high_c":21}')
  expect_identical(delivered[[1L]]$tool_call_id, pending$request$tool_call_id)
})

test_that("graph routes cannot join trusted agents", {
  trusted <- Agent$new(
    trusted_test_chat(),
    tools = list(trusted_forecast_tool()),
    trusted_results = TrustedResults(forecast = "get_forecast")
  )
  helper <- Agent$new(trusted_test_chat())
  before <- names(trusted$get_tools())
  expect_error(
    trusted$retain_agent_graph(
      agents = list(helper = helper),
      routes = list(
        root = list(
          ask_helper = list(
            target = "helper",
            description = "Ask the helper.",
            usage_limits = UsageLimits(max_requests = 1L)
          )
        )
      ),
      usage_limits = UsageLimits(max_requests = 2L),
      max_depth = 1L,
      max_delegations = 1L,
      max_concurrency = 1L
    ),
    "delegates to another Agent"
  )
  expect_identical(names(trusted$get_tools()), before)
})

test_that("designated trusted tools must stay registered", {
  policy <- TrustedResults(forecast = "get_forecast")
  expect_error(
    Agent$new(trusted_test_chat(), trusted_results = policy),
    "must remain registered"
  )
  agent <- Agent$new(
    trusted_test_chat(),
    tools = list(trusted_forecast_tool(), trusted_closed_tool()),
    trusted_results = policy
  )
  expect_error(
    agent$set_tools(list(trusted_closed_tool())),
    "must remain registered"
  )
  expect_named(agent$get_tools(), c("get_forecast", "list_cities"))
})

test_that("only the Agent's own governed request can publish a trusted result", {
  called <- 0L
  agent <- Agent$new(
    trusted_test_chat(),
    tools = list(trusted_forecast_tool()),
    trusted_results = TrustedResults(
      forecast = "get_forecast",
      on_result = function(event) called <<- called + 1L
    )
  )
  expect_error(
    agent$get_tools()$get_forecast(city = "Oslo"),
    "own governed tool request"
  )
  expect_identical(called, 0L)

  # A neighbouring tool calling the wrapper mid-run cannot claim the pending
  # governed request or skip its permission check.
  server <- local_runtime_server(list(
    runtime_reply(tool = "relay", arguments = list()),
    runtime_reply("done")
  ))
  holder <- new.env(parent = emptyenv())
  relay <- ellmer::tool(
    fun = function() {
      holder$agent$get_tools()$get_forecast(city = "Nowhere")
    },
    name = "relay",
    description = "Relay.",
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE
    )
  )
  checked <- character()
  holder$agent <- Agent$new(
    runtime_chat(server),
    tools = list(trusted_forecast_tool(), relay),
    permissions = Permissions(
      can_use_tool = function(tool_name, tool_input, context) {
        checked <<- c(checked, tool_name)
        PermissionResultAllow()
      }
    ),
    trusted_results = TrustedResults(
      forecast = "get_forecast",
      on_result = function(event) called <<- called + 1L
    )
  )
  expect_warning(
    result <- holder$agent$run_sync("Relay it"),
    "own governed tool request"
  )
  expect_identical(checked, "relay")
  expect_identical(called, 0L)
  expect_length(result_trusted_results(result), 0L)
})

trusted_definition <- function(name = "forecaster", tools = list()) {
  AgentDefinition(
    name,
    "Produce forecasts",
    "FORECASTER. Call get_forecast.",
    tools = tools,
    max_requests = 3L
  )
}

test_that("child trusted results reach the lead host with child correlation", {
  server <- local_runtime_server(list(
    runtime_reply(
      tool = "delegate_to_agent",
      arguments = list(agent_name = "forecaster", task = "Oslo")
    ),
    runtime_reply(tool = "get_forecast", arguments = list(city = "Oslo")),
    runtime_reply("Child: it is 99 degrees."),
    runtime_reply("Lead: it is 99 degrees.")
  ))
  delivered <- list()
  lead <- LeadAgent$new(
    runtime_chat(server),
    sub_agents = list(trusted_definition(
      tools = list(trusted_forecast_tool())
    )),
    trusted_results = TrustedResults(
      forecast = "get_forecast",
      on_result = function(event) {
        delivered[[length(delivered) + 1L]] <<- event
      },
      model_receipt = TRUE
    )
  )
  expect_s3_class(lead$trusted_results, "deputy::TrustedResults")
  result <- lead$run_sync("Forecast for Oslo")

  expect_length(delivered, 1L)
  event <- delivered[[1L]]
  expect_identical(event$value, '{"high_c":21,"low_c":12}')
  expect_identical(event$arguments, list(city = "Oslo"))
  expect_match(event$delegation_id, "^delegation_")
  expect_false(identical(event$agent_id, lead$agent_id))
  lead_events <- result_trusted_results(result, "forecast")
  expect_length(lead_events, 1L)
  expect_identical(lead_events[[1L]], event)

  sent <- paste(
    vapply(
      server$requests(),
      function(request) paste(deparse(request), collapse = ""),
      character(1)
    ),
    collapse = ""
  )
  expect_match(sent, event$result_id, fixed = TRUE)
  expect_no_match(sent, "high_c", fixed = TRUE)
})

test_that("every definition in a trusted tree obeys the no-bypass rule", {
  policy <- TrustedResults(forecast = "get_forecast")
  expect_error(
    LeadAgent$new(
      trusted_test_chat(),
      sub_agents = list(
        trusted_definition(tools = list(trusted_forecast_tool())),
        trusted_definition("coder", tools = list(tool_run_r_code))
      ),
      trusted_results = policy
    ),
    "AgentDefinition 'coder' violates"
  )
  expect_error(
    LeadAgent$new(
      trusted_test_chat(),
      sub_agents = list(trusted_definition("empty")),
      trusted_results = policy
    ),
    "must remain registered"
  )
  expect_error(
    LeadAgent$new(
      trusted_test_chat(),
      tools = list(trusted_forecast_tool()),
      sub_agents = list(trusted_definition(
        tools = list(trusted_forecast_tool('{"high_c":999}'))
      )),
      trusted_results = policy
    ),
    "same tool everywhere"
  )

  forecast <- trusted_forecast_tool()
  lead <- LeadAgent$new(
    trusted_test_chat(),
    tools = list(forecast),
    sub_agents = list(trusted_definition(tools = list(forecast))),
    trusted_results = policy
  )
  expect_error(
    lead$register_sub_agent(trusted_definition(
      "writer",
      tools = list(tool_write_file)
    )),
    "AgentDefinition 'writer' violates"
  )
  expect_identical(lead$available_sub_agents(), "forecaster")
  lead$register_sub_agent(trusted_definition(
    "lister",
    tools = list(trusted_closed_tool())
  ))
  expect_setequal(lead$available_sub_agents(), c("forecaster", "lister"))
  expect_error(lead$register_tool(tool_run_bash), "executes model-supplied")
})
