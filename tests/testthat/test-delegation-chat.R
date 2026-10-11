# A responder chat from the parallel fixture that reports its own provider,
# model and request parameters, as a host-built client would.
factory_chat <- function(
  state,
  params = list(),
  model = "gateway-model",
  provider = "Gateway"
) {
  chat <- create_parallel_chat(state)
  gateway <- create_mock_provider(name = provider, model = model)
  chat$get_provider <- function() gateway
  chat$get_model <- function() model
  chat$get_model_object <- function() {
    ellmer::Model(name = model, params = params)
  }
  chat
}

delegate_run <- function(lead, name = "a", task = "task") {
  response <- resolve_async_value(
    lead$get_tools()$delegate_to_agent(name, task),
    max_polls = 10000L
  )
  jsonlite::fromJSON(response)$answer
}

test_that("a chat function builds the subagent's chat", {
  state <- new.env(parent = emptyenv())
  calls <- list()
  lead_chat <- create_parallel_chat(state)
  lead_chat$clone <- function(deep = FALSE) stop("the lead's chat was copied")
  lead <- LeadAgent$new(
    lead_chat,
    sub_agents = list(agent_definition(
      "a",
      "Searches",
      "a",
      params = ellmer::params(reasoning_effort = "low")
    )),
    delegation_scope = list(
      owner_id = "owner-a",
      conversation_id = "conversation-a"
    ),
    delegation_policy = DelegationPolicy(
      chat = function(definition, context) {
        calls[[length(calls) + 1L]] <<- list(
          definition = definition,
          context = context
        )
        chat <- factory_chat(state, params = definition$params)
        # Leftovers Deputy must clear before the subagent starts.
        chat$set_turns(list(create_mock_user_turn("LEFTOVER")))
        chat$set_tools(list(ellmer::tool(
          function() "ok",
          name = "leftover",
          description = "Left by the host",
          arguments = list()
        )))
        chat
      }
    )
  )

  expect_identical(delegate_run(lead, task = "Find papers"), "a Find papers")
  expect_length(calls, 1L)
  expect_identical(calls[[1]]$definition$name, "a")
  expect_identical(
    calls[[1]]$definition$params,
    list(reasoning_effort = "low")
  )
  context <- calls[[1]]$context
  expect_identical(context$agent_name, "a")
  expect_identical(context$scope$owner_id, "owner-a")
  expect_identical(context$parent_agent_id, lead$agent_id)
  expect_true(is_nonempty_string(context$delegation_id))
  expect_identical(context$run_context$role, "a")
  expect_identical(state$inputs$a$turns, list())
  expect_length(state$inputs$a$tools, 0L)

  manifest <- lead$get_subagent_contexts()[[1L]]
  expect_identical(manifest$schema_version, 2L)
  expect_identical(manifest$provider, "Gateway")
  expect_identical(manifest$model, "gateway-model")
  expect_identical(manifest$params, list(reasoning_effort = "low"))
  expect_identical(manifest$policies$binding$chat, "host factory")
  redacted <- lead$get_subagent_contexts(redact = TRUE)[[1L]]
  expect_identical(redacted$provider, "Gateway")
  expect_identical(redacted$params, list(reasoning_effort = "low"))
  expect_identical(redacted$policies$binding$chat, "host factory")
})

test_that("named param values are recorded without their names", {
  state <- new.env(parent = emptyenv())
  lead <- LeadAgent$new(
    create_parallel_chat(state),
    sub_agents = list(agent_definition("a", "A", "a")),
    delegation_policy = DelegationPolicy(chat = function(definition, context) {
      factory_chat(
        state,
        params = ellmer::params(stop_sequences = c(first = "END"))
      )
    })
  )

  expect_identical(delegate_run(lead), "a task")
  expect_identical(
    lead$get_subagent_contexts()[[1L]]$params,
    list(stop_sequences = "END")
  )
})

test_that("a chat function builds parallel_delegate() responders", {
  state <- new.env(parent = emptyenv())
  efforts <- c(a = "low", b = "high", c = "medium")
  lead <- parallel_test_lead(
    state,
    delegation_policy = DelegationPolicy(chat = function(definition, context) {
      factory_chat(
        state,
        params = ellmer::params(reasoning_effort = efforts[[definition$name]])
      )
    })
  )

  result <- lead$parallel_delegate(c(a = "one", b = "two"))
  expect_identical(sort(state$completed), c("a", "b"))
  params <- lapply(lead$get_subagent_contexts(), function(manifest) {
    manifest$params$reasoning_effort
  })
  expect_setequal(unlist(params), c("low", "high"))
})

test_that("a failing or invalid chat function stops the delegation first", {
  returns <- list(
    function(state, lead_chat) stop("gateway down"),
    function(state, lead_chat) "not a chat",
    function(state, lead_chat) lead_chat,
    function(state, lead_chat) Agent$new(chat = factory_chat(state))
  )
  for (build in returns) {
    state <- new.env(parent = emptyenv())
    lead_chat <- create_parallel_chat(state)
    lead <- LeadAgent$new(
      lead_chat,
      sub_agents = list(agent_definition("a", "A", "a")),
      delegation_policy = DelegationPolicy(chat = function(
        definition,
        context
      ) {
        build(state, lead_chat)
      })
    )
    failure <- tryCatch(delegate_run(lead), error = identity)
    expect_s3_class(failure, "deputy_delegation_binding")
    expect_identical(state$started, character())
    expect_identical(lead$list_subagents()$stop_reason, "setup_error")
  }

  # Returning the lead itself (an Agent is also a "Chat") must not clear it.
  state <- new.env(parent = emptyenv())
  lead <- LeadAgent$new(
    create_parallel_chat(state),
    sub_agents = list(agent_definition("a", "A", "a")),
    delegation_policy = DelegationPolicy(chat = function(definition, context) {
      lead
    })
  )
  lead$set_turns(list(create_mock_user_turn("KEEP")))
  tools <- names(lead$get_tools())
  failure <- tryCatch(delegate_run(lead), error = identity)
  expect_s3_class(failure, "deputy_delegation_binding")
  expect_identical(
    ellmer::contents_text(lead$get_turns()[[1L]]),
    "KEEP"
  )
  expect_identical(names(lead$get_tools()), tools)

  # A chat another agent already runs on can't be handed to a subagent.
  state <- new.env(parent = emptyenv())
  in_use <- ellmer::chat_openai(model = "m", credentials = function() "k")
  owner <- Agent$new(chat = in_use)
  lead <- LeadAgent$new(
    create_parallel_chat(state),
    sub_agents = list(agent_definition("a", "A", "a")),
    delegation_policy = DelegationPolicy(chat = function(definition, context) {
      in_use
    })
  )
  failure <- tryCatch(delegate_run(lead), error = identity)
  expect_s3_class(failure, "deputy_delegation_binding")
  expect_identical(state$started, character())

  expect_snapshot(error = TRUE, DelegationPolicy(chat = "gateway"))
})

test_that("a provider/model definition's params reach ellmer::chat()", {
  state <- new.env(parent = emptyenv())
  seen <- NULL
  local_mocked_bindings(
    chat = function(name, ..., params = NULL) {
      seen <<- list(name = name, params = params)
      factory_chat(state, params = params %||% list(), model = "gpt-test")
    },
    .package = "ellmer"
  )
  lead <- LeadAgent$new(
    create_parallel_chat(state),
    sub_agents = list(agent_definition(
      "a",
      "A",
      "a",
      model = "openai/gpt-test",
      params = ellmer::params(max_tokens = 50L, reasoning_effort = "low")
    ))
  )

  expect_identical(delegate_run(lead), "a task")
  expect_identical(seen$name, "openai/gpt-test")
  expect_identical(
    seen$params,
    list(max_tokens = 50L, reasoning_effort = "low")
  )
  manifest <- lead$get_subagent_contexts()[[1L]]
  expect_identical(
    manifest$params,
    list(max_tokens = 50L, reasoning_effort = "low")
  )
  expect_identical(manifest$policies$binding$chat, "default")

  # Without params the call is as before.
  seen <- NULL
  lead <- LeadAgent$new(
    create_parallel_chat(state),
    sub_agents = list(agent_definition("a", "A", "a", model = "openai/gpt-x"))
  )
  delegate_run(lead)
  expect_identical(seen, list(name = "openai/gpt-x", params = NULL))
})

test_that("params for a copy of the lead's chat need a chat function", {
  params <- ellmer::params(reasoning_effort = "low")
  inherit <- agent_definition("a", "A", "a", params = params)
  bare <- agent_definition(
    "b",
    "B",
    "b",
    model = "cheap-model",
    params = params
  )

  for (definition in list(inherit, bare)) {
    expect_error(
      LeadAgent$new(create_mock_chat(), sub_agents = list(definition)),
      class = "deputy_delegation_binding"
    )
    lead <- LeadAgent$new(create_mock_chat())
    expect_error(
      lead$register_sub_agent(definition),
      class = "deputy_delegation_binding"
    )
    expect_length(lead$sub_agent_defs, 0L)
  }
  expect_snapshot(
    error = TRUE,
    LeadAgent$new(create_mock_chat(), sub_agents = list(inherit))
  )

  remote <- agent_definition(
    "c",
    "C",
    "c",
    model = "openai/gpt-test",
    params = params
  )
  lead <- LeadAgent$new(create_mock_chat(), sub_agents = list(remote))
  expect_length(lead$sub_agent_defs, 1L)
  lead <- LeadAgent$new(
    create_mock_chat(),
    sub_agents = list(inherit, bare),
    delegation_policy = DelegationPolicy(chat = function(definition, context) {
      create_mock_chat()
    })
  )
  expect_length(lead$sub_agent_defs, 2L)
})

test_that("definition params are validated, printed and kept by copies", {
  definition <- agent_definition(
    "a",
    "A",
    "a",
    model = "openai/gpt-test",
    params = ellmer::params(
      reasoning_effort = "low",
      stop_sequences = c("x", "y")
    )
  )
  expect_identical(
    definition$params,
    list(stop_sequences = c("x", "y"), reasoning_effort = "low")
  )
  expect_identical(agent_definition("a", "A", "a")$params, list())
  fields <- S7::props(definition)
  expect_identical(do.call(agent_definition, fields), definition)
  expect_snapshot(print(definition))

  expect_snapshot(error = TRUE, agent_definition("a", "A", "a", params = "low"))
  expect_snapshot(
    error = TRUE,
    agent_definition("a", "A", "a", params = list(temperature = -1))
  )
  expect_snapshot(
    error = TRUE,
    agent_definition("a", "A", "a", params = ellmer::params(foo = 1))
  )
})

test_that("manifests rebuild from their records", {
  state <- new.env(parent = emptyenv())
  lead <- LeadAgent$new(
    create_parallel_chat(state),
    sub_agents = list(agent_definition("a", "A", "a"))
  )
  delegate_run(lead)
  manifest <- lead$get_subagent_contexts()[[1L]]
  record <- S7::props(manifest)
  expect_identical(do.call(DelegationManifest, record), manifest)

  record$schema_version <- 1L
  expect_error(do.call(DelegationManifest, record), "Unsupported")
})
