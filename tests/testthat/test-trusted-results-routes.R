routes_measure_tool <- function(value = 60, counter = NULL) {
  ellmer::tool(
    function() {
      if (!is.null(counter)) {
        counter$calls <- counter$calls + 1L
      }
      value
    },
    name = "call_measure",
    description = "Run a registered measure.",
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE
    )
  )
}

routes_read_tool <- function(name = "search_pool", read_only = TRUE) {
  ellmer::tool(
    function() "north, south",
    name = name,
    description = "List what can be measured.",
    annotations = ellmer::tool_annotations(
      read_only_hint = read_only,
      open_world_hint = FALSE
    )
  )
}

routes_offline_chat <- function() {
  ellmer::chat_openai(
    credentials = function() "test",
    model = "gpt-4o-mini",
    echo = "none"
  )
}

# A root whose policy names `measure` as the one producer of "measure".
routes_root <- function(chat, measure, deliveries, ...) {
  Agent$new(
    chat,
    trusted_results = TrustedResults(
      measure = measure,
      on_result = function(event) {
        deliveries$events[[length(deliveries$events) + 1L]] <- event
      },
      ...
    )
  )
}

routes_deliveries <- function() {
  deliveries <- new.env()
  deliveries$events <- list()
  deliveries
}

routes_sales_server <- function(.local_envir = parent.frame()) {
  local_runtime_server(
    list(
      runtime_reply(tool = "call_measure"),
      runtime_reply("Total revenue is 60.")
    ),
    .local_envir = .local_envir
  )
}

routes_route <- function(root, handle, name = "ask_sales") {
  root$register_tool(delegation_tool(
    root,
    handle,
    name,
    "Ask the sales specialist.",
    UsageLimits(max_requests = 4)
  ))
}

routes_request_text <- function(server) {
  vapply(
    server$requests(),
    function(request) {
      as.character(jsonlite::toJSON(request, auto_unbox = TRUE))
    },
    character(1)
  )
}

test_that("a tool given to TrustedResults is its one explicit producer", {
  measure <- routes_measure_tool()
  policy <- TrustedResults(measure = measure, other = "list_cities")
  expect_identical(
    policy$results,
    c(measure = "call_measure", other = "list_cities")
  )
  expect_identical(policy$producers$measure, measure)
  expect_null(policy$producers$other)
  expect_snapshot(print(policy))
  expect_error(TrustedResults(measure = list()), "or be the tool itself")

  # A tool taken from an agent names its source, not the agent's wrapper.
  agent <- Agent$new(routes_offline_chat(), tools = list(measure))
  wrapped <- agent$get_tools()$call_measure
  expect_false(identical(wrapped, measure))
  expect_identical(TrustedResults(measure = wrapped)$producers$measure, measure)

  # Another tool with the producer's name is not the producer.
  expect_error(
    Agent$new(
      routes_offline_chat(),
      tools = list(routes_measure_tool(61)),
      trusted_results = TrustedResults(measure = measure)
    ),
    "must be the tool named in the policy"
  )
  # The producer itself is accepted, and needn't be registered here.
  expect_no_error(Agent$new(
    routes_offline_chat(),
    tools = list(routes_read_tool()),
    trusted_results = TrustedResults(measure = measure)
  ))
})

test_that("a retained specialist's results reach the root once, with its identity", {
  deliveries <- routes_deliveries()
  counter <- new.env()
  counter$calls <- 0L
  measure <- routes_measure_tool(60, counter)
  root_server <- local_runtime_server(list(
    runtime_reply(tool = "ask_sales", arguments = list(task = "Revenue?")),
    runtime_reply("Lead: revenue is ready.")
  ))
  sales_server <- routes_sales_server()
  root <- routes_root(
    runtime_chat(root_server),
    measure,
    deliveries,
    model_receipt = TRUE
  )
  sales <- Agent$new(
    runtime_chat(sales_server),
    tools = list(measure, routes_read_tool()),
    agent_name = "sales"
  )
  handle <- root$retain_agent(sales, UsageLimits(max_requests = 8))
  routes_route(root, handle)
  result <- root$run_sync("Revenue?")

  expect_identical(counter$calls, 1L)
  expect_length(deliveries$events, 1L)
  event <- deliveries$events[[1L]]
  expect_identical(event$value, 60)
  expect_identical(event$result_type, "measure")
  expect_identical(event$agent_id, sales$agent_id)
  expect_identical(event$agent_name, "sales")
  expect_identical(event$session_id, sales$session_id())
  expect_identical(event$parent_agent_id, root$agent_id)
  expect_identical(event$parent_run_id, result$run_id)
  expect_identical(event$tool_call_id, "call_fixture")
  expect_match(event$delegation_id, "^delegation_")
  expect_match(event$run_id, "^run_")
  expect_false(identical(event$run_id, result$run_id))
  expect_identical(event$tool_fingerprint, approval_tool_fingerprint(measure))
  # Recorded once in the root's run, and in the specialist's own run.
  expect_length(result_trusted_results(result), 1L)
  expect_identical(
    result_trusted_results(result)[[1L]]$result_id,
    event$result_id
  )
  # With receipts, the specialist's model never saw the value.
  requests <- routes_request_text(sales_server)
  expect_match(requests[[2L]], event$result_id, fixed = TRUE)
  expect_false(any(grepl("\"content\":\"60\"", requests, fixed = TRUE)))
})

test_that("specialists that could bypass the producer are not retained", {
  measure <- routes_measure_tool()
  root <- routes_root(routes_offline_chat(), measure, routes_deliveries())
  retain <- function(...) {
    specialist <- Agent$new(routes_offline_chat(), tools = list(...))
    error <- expect_error(
      root$retain_agent(specialist, UsageLimits(max_requests = 4)),
      class = "deputy_tool_registration"
    )
    # Nothing was installed on the specialist and nothing retained.
    private <- specialist$.__enclos_env__$private
    expect_null(private$.trusted_results)
    expect_null(private$.conversation_owner)
    expect_length(root$.__enclos_env__$private$owned_conversations, 0L)
    conditionMessage(error)
  }
  expect_match(retain(measure, tool_run_r_code), "executes model-supplied")
  expect_match(
    retain(measure, routes_read_tool("lookup", read_only = FALSE)),
    "may write or reach the open world"
  )
  expect_match(
    retain(ellmer::tool(
      function() "ok",
      name = "note",
      description = "Unannotated."
    )),
    "may write or reach the open world"
  )
  # A different tool under the producer's name is not the producer.
  expect_match(
    retain(routes_measure_tool(61)),
    "must be the tool named in the policy"
  )
})

test_that("roots reaching retained agents name their producers explicitly", {
  measure <- routes_measure_tool()
  root <- Agent$new(
    routes_offline_chat(),
    tools = list(measure),
    trusted_results = TrustedResults(measure = "call_measure")
  )
  specialist <- Agent$new(routes_offline_chat(), tools = list(measure))
  expect_error(
    root$retain_agent(specialist, UsageLimits(max_requests = 4)),
    "need explicit producers"
  )
})

test_that("only Deputy's own routes to admitted agents are accepted", {
  measure <- routes_measure_tool()
  root <- routes_root(routes_offline_chat(), measure, routes_deliveries())
  other <- Agent$new(routes_offline_chat())
  stranger <- Agent$new(routes_offline_chat(), tools = list(measure))
  foreign <- other$retain_agent(stranger, UsageLimits(max_requests = 4))
  before <- names(root$get_tools())
  # A route built for another owner.
  expect_error(
    root$register_tool(delegation_tool(
      other,
      foreign,
      "ask_stranger",
      "Ask.",
      UsageLimits(max_requests = 1)
    )),
    "Delegation tools may only be registered|delegates to another Agent"
  )
  # A plain tool posing as delegation.
  alias <- ellmer::tool(
    function(task) "done",
    name = "delegate_to_agent",
    description = "Delegate.",
    arguments = list(task = ellmer::type_string("Task")),
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE
    )
  )
  expect_error(root$register_tool(alias), "delegates to another Agent")
  # A route whose handle was released is no longer admitted.
  specialist <- Agent$new(routes_offline_chat(), tools = list(measure))
  handle <- root$retain_agent(specialist, UsageLimits(max_requests = 4))
  route <- delegation_tool(
    root,
    handle,
    "ask_sales",
    "Ask.",
    UsageLimits(max_requests = 1)
  )
  root$release_agent(handle)
  expect_error(root$register_tool(route), "delegates to another Agent")
  # Code execution stays out beside admitted routes.
  handle <- root$retain_agent(specialist, UsageLimits(max_requests = 4))
  routes_route(root, handle)
  expect_error(
    root$register_tool(tool_run_r_code),
    "executes model-supplied"
  )
  expect_identical(names(root$get_tools()), c(before, "ask_sales"))
})

test_that("retained agents can't give one result type two producers", {
  measure <- routes_measure_tool(60)
  audit_tool <- function(value) {
    ellmer::tool(
      function() value,
      name = "run_audit",
      description = "Run the audit.",
      annotations = ellmer::tool_annotations(
        read_only_hint = TRUE,
        open_world_hint = FALSE
      )
    )
  }
  audit <- audit_tool("audited")
  specialist <- function(tool, ...) {
    Agent$new(
      routes_offline_chat(),
      tools = list(measure, tool),
      trusted_results = TrustedResults(...)
    )
  }
  root <- routes_root(routes_offline_chat(), measure, routes_deliveries())
  root$retain_agent(
    specialist(audit, audit = audit),
    UsageLimits(max_requests = 4)
  )
  # Another specialist's own producer for the same type is refused.
  other_audit <- audit_tool("other")
  other <- specialist(other_audit, audit = other_audit)
  expect_error(
    root$retain_agent(other, UsageLimits(max_requests = 4)),
    "different producer in another retained agent"
  )
  expect_null(other$.__enclos_env__$private$.trusted_root)
  # So is the same producer under another type.
  expect_error(
    root$retain_agent(
      specialist(audit, check = audit),
      UsageLimits(max_requests = 4)
    ),
    "two result types"
  )
  # The same producer for the same type is fine.
  expect_no_error(root$retain_agent(
    specialist(audit, audit = audit),
    UsageLimits(max_requests = 4)
  ))
})

test_that("a name a retained agent designates is that tool across the tree", {
  measure <- routes_measure_tool(60)
  audit_tool <- function(value) {
    ellmer::tool(
      function() value,
      name = "run_audit",
      description = "Run the audit.",
      annotations = ellmer::tool_annotations(
        read_only_hint = TRUE,
        open_world_hint = FALSE
      )
    )
  }
  audit <- audit_tool("audited")
  plain <- audit_tool("plain")
  auditor <- function() {
    Agent$new(
      routes_offline_chat(),
      tools = list(measure, audit),
      trusted_results = TrustedResults(audit = audit)
    )
  }
  plain_agent <- function() {
    Agent$new(routes_offline_chat(), tools = list(measure, plain))
  }
  root <- function() {
    routes_root(routes_offline_chat(), measure, routes_deliveries())
  }
  # The owner already has another tool under the name.
  owner <- root()
  owner$register_tool(plain)
  expect_error(
    owner$retain_agent(auditor(), UsageLimits(max_requests = 4)),
    "same tool everywhere"
  )
  expect_length(owner$.__enclos_env__$private$owned_conversations, 0L)
  # Or registers one while the agent is retained.
  owner <- root()
  owner$retain_agent(auditor(), UsageLimits(max_requests = 4))
  expect_error(owner$register_tool(plain), "same tool everywhere")
  expect_false("run_audit" %in% names(owner$get_tools()))
  # Another retained agent has one, retained before or after.
  owner <- root()
  owner$retain_agent(plain_agent(), UsageLimits(max_requests = 4))
  expect_error(
    owner$retain_agent(auditor(), UsageLimits(max_requests = 4)),
    "same tool everywhere"
  )
  owner <- root()
  owner$retain_agent(auditor(), UsageLimits(max_requests = 4))
  expect_error(
    owner$retain_agent(plain_agent(), UsageLimits(max_requests = 4)),
    "same tool everywhere"
  )
  expect_length(owner$.__enclos_env__$private$owned_conversations, 1L)
})

test_that("a retained agent's designated names hold in a lead's definitions", {
  measure <- routes_measure_tool(60)
  audit_tool <- function(value) {
    ellmer::tool(
      function() value,
      name = "run_audit",
      description = "Run the audit.",
      annotations = ellmer::tool_annotations(
        read_only_hint = TRUE,
        open_world_hint = FALSE
      )
    )
  }
  audit <- audit_tool("audited")
  plain <- audit_tool("plain")
  auditor <- function() {
    Agent$new(
      routes_offline_chat(),
      tools = list(measure, audit),
      trusted_results = TrustedResults(audit = audit)
    )
  }
  checker <- function() {
    AgentDefinition(
      "checker",
      "Checks figures.",
      "CHECKER.",
      tools = list(plain),
      max_requests = 2L
    )
  }
  lead <- function(...) {
    LeadAgent$new(
      routes_offline_chat(),
      trusted_results = TrustedResults(measure = measure),
      ...
    )
  }
  # A definition already holds another tool under the name.
  owner <- lead(sub_agents = list(checker()))
  expect_error(
    owner$retain_agent(auditor(), UsageLimits(max_requests = 4)),
    "same tool everywhere"
  )
  expect_length(owner$.__enclos_env__$private$owned_conversations, 0L)
  # Or one is registered while the agent is retained.
  owner <- lead()
  owner$retain_agent(auditor(), UsageLimits(max_requests = 4))
  expect_error(owner$register_sub_agent(checker()), "same tool everywhere")
  expect_false("checker" %in% owner$available_sub_agents())
})

test_that("releasing a retained agent removes its routes from the owner", {
  measure <- routes_measure_tool(60)
  root <- routes_root(routes_offline_chat(), measure, routes_deliveries())
  handle <- root$retain_agent(
    Agent$new(routes_offline_chat(), tools = list(measure)),
    UsageLimits(max_requests = 4)
  )
  routes_route(root, handle)
  expect_true("ask_sales" %in% names(root$get_tools()))
  root$release_agent(handle)
  expect_false("ask_sales" %in% names(root$get_tools()))
  # The owner's registry still accepts tools.
  expect_no_error(root$register_tool(routes_read_tool()))
  # The same holds for an owner without a policy.
  plain <- Agent$new(routes_offline_chat())
  handle <- plain$retain_agent(
    Agent$new(routes_offline_chat(), tools = list(routes_measure_tool(1))),
    UsageLimits(max_requests = 4)
  )
  routes_route(plain, handle)
  plain$release_agent(handle)
  expect_false("ask_sales" %in% names(plain$get_tools()))
})

test_that("a retained producer can't be swapped after admission", {
  measure <- routes_measure_tool()
  root <- routes_root(routes_offline_chat(), measure, routes_deliveries())
  specialist <- Agent$new(routes_offline_chat(), tools = list(measure))
  handle <- root$retain_agent(specialist, UsageLimits(max_requests = 4))
  # The owner holds the conversation, so its host can't change its tools.
  expect_error(
    specialist$set_tools(list(routes_measure_tool(61))),
    "current owner"
  )
  private <- specialist$.__enclos_env__$private
  # A pinned producer changed underneath is caught before the next task.
  pinned <- private$.trusted_sources
  private$.trusted_sources$call_measure <- routes_measure_tool(61)
  expect_error(
    root$continue_agent(handle, "Again?", UsageLimits(max_requests = 2)),
    "policy changed"
  )
  private$.trusted_sources <- pinned
  # So is a registry changed underneath.
  private$.chat$set_tools(list(private$adapt_tool(routes_measure_tool(61))))
  expect_error(
    root$continue_agent(handle, "Again?", UsageLimits(max_requests = 2)),
    "must be the tool named in the policy"
  )
})

test_that("an executing producer must be the pinned tool", {
  measure <- routes_measure_tool()
  agent <- Agent$new(
    routes_offline_chat(),
    tools = list(measure),
    trusted_results = TrustedResults(measure = measure)
  )
  private <- agent$.__enclos_env__$private
  impostor <- routes_measure_tool(61)
  expect_error(
    private$execute_tool(impostor, list(), "call_1"),
    "can only run through its own governed tool request"
  )
})

test_that("a retained agent's own policy is kept alongside the root's", {
  deliveries <- routes_deliveries()
  own <- list()
  measure <- routes_measure_tool(60)
  audit <- ellmer::tool(
    function() "audited",
    name = "run_audit",
    description = "Run the audit.",
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE
    )
  )
  notes <- ellmer::tool(
    function() "saved",
    name = "save_note",
    description = "Save a note.",
    annotations = ellmer::tool_annotations(read_only_hint = FALSE)
  )
  specialist_policy <- TrustedResults(
    audit = "run_audit",
    on_result = function(event) own[[length(own) + 1L]] <<- event,
    exempt_tools = "save_note"
  )
  # The root doesn't exempt save_note, so the specialist can't keep it.
  root <- routes_root(routes_offline_chat(), measure, deliveries)
  blocked <- Agent$new(
    routes_offline_chat(),
    tools = list(measure, audit, notes),
    trusted_results = specialist_policy
  )
  expect_error(
    root$retain_agent(blocked, UsageLimits(max_requests = 4)),
    "may write or reach the open world"
  )
  # A conflicting producer for the root's result type is refused.
  conflicting <- Agent$new(
    routes_offline_chat(),
    tools = list(routes_measure_tool(61), audit),
    trusted_results = TrustedResults(measure = "call_measure")
  )
  expect_error(
    root$retain_agent(conflicting, UsageLimits(max_requests = 4)),
    "different producer"
  )

  root_server <- local_runtime_server(list(
    runtime_reply(tool = "ask_sales", arguments = list(task = "Audit?")),
    runtime_reply("Lead: done.")
  ))
  sales_server <- local_runtime_server(list(
    runtime_tool_calls_reply(list(
      list(id = "call_m", name = "call_measure", arguments = list()),
      list(id = "call_a", name = "run_audit", arguments = list())
    )),
    runtime_reply("Measured and audited.")
  ))
  root <- routes_root(
    runtime_chat(root_server),
    measure,
    deliveries,
    exempt_tools = "save_note"
  )
  specialist <- Agent$new(
    runtime_chat(sales_server),
    tools = list(measure, audit, notes),
    trusted_results = specialist_policy
  )
  handle <- root$retain_agent(specialist, UsageLimits(max_requests = 8))
  routes_route(root, handle)
  result <- root$run_sync("Audit?")
  types <- function(events) {
    sort(vapply(events, function(event) event$result_type, character(1)))
  }
  # Each publication reaches the root once and the specialist's host once.
  expect_identical(types(deliveries$events), c("audit", "measure"))
  expect_identical(types(own), c("audit", "measure"))
  expect_identical(types(result_trusted_results(result)), c("audit", "measure"))
  # Release gives the specialist its own policy back.
  root$release_agent(handle)
  private <- specialist$.__enclos_env__$private
  expect_identical(private$.trusted_results, specialist_policy)
  expect_false(isTRUE(private$.trusted_tree_member))
  expect_null(private$.trusted_root)
})

test_that("a failed root delivery becomes a tool error, delivered once", {
  calls <- 0L
  measure <- routes_measure_tool(60)
  root_server <- local_runtime_server(list(
    runtime_reply(tool = "ask_sales", arguments = list(task = "Revenue?")),
    runtime_reply("Lead: no number.")
  ))
  sales_server <- routes_sales_server()
  root <- Agent$new(
    runtime_chat(root_server),
    trusted_results = TrustedResults(
      measure = measure,
      on_result = function(event) {
        calls <<- calls + 1L
        stop("store offline")
      }
    )
  )
  sales <- Agent$new(runtime_chat(sales_server), tools = list(measure))
  handle <- root$retain_agent(sales, UsageLimits(max_requests = 8))
  routes_route(root, handle)
  expect_warning(
    result <- root$run_sync("Revenue?"),
    "could not be delivered"
  )
  expect_identical(calls, 1L)
  # The event is recorded once, and the specialist's model got an error.
  expect_length(result_trusted_results(result), 1L)
  requests <- routes_request_text(sales_server)
  expect_match(requests[[2L]], "could not be delivered", fixed = TRUE)
  expect_false(grepl("store offline", requests[[2L]], fixed = TRUE))
  expect_identical(nrow(root$list_subagents()), 1L)
})

test_that("a retained agent's own host gets a result the root failed to take", {
  calls <- 0L
  own <- list()
  measure <- routes_measure_tool(60)
  root_server <- local_runtime_server(list(
    runtime_reply(tool = "ask_sales", arguments = list(task = "Revenue?")),
    runtime_reply("Lead: no number.")
  ))
  sales_server <- routes_sales_server()
  root <- Agent$new(
    runtime_chat(root_server),
    trusted_results = TrustedResults(
      measure = measure,
      on_result = function(event) {
        calls <<- calls + 1L
        stop("store offline")
      }
    )
  )
  sales <- Agent$new(
    runtime_chat(sales_server),
    tools = list(measure),
    trusted_results = TrustedResults(
      measure = measure,
      on_result = function(event) own[[length(own) + 1L]] <<- event
    )
  )
  handle <- root$retain_agent(sales, UsageLimits(max_requests = 8))
  routes_route(root, handle)
  expect_warning(
    result <- root$run_sync("Revenue?"),
    "could not be delivered"
  )
  expect_identical(calls, 1L)
  expect_length(own, 1L)
  expect_identical(own[[1L]]$result_type, "measure")
  # The delivery still failed, so the specialist's model got an error.
  requests <- routes_request_text(sales_server)
  expect_match(requests[[2L]], "could not be delivered", fixed = TRUE)
})

test_that("permissions and hooks still decide whether the producer runs", {
  deliveries <- routes_deliveries()
  counter <- new.env()
  counter$calls <- 0L
  measure <- routes_measure_tool(60, counter)
  root_server <- local_runtime_server(list(
    runtime_reply(tool = "ask_sales", arguments = list(task = "Revenue?")),
    runtime_reply("Lead: denied.")
  ))
  sales_server <- routes_sales_server()
  root <- routes_root(runtime_chat(root_server), measure, deliveries)
  seen <- NULL
  root$add_hook(HookMatcher(
    "PreToolUse",
    pattern = "call_measure",
    callback = function(tool_name, tool_input, context) {
      seen <<- context$tool_arguments
      HookResultPreToolUse(permission = "deny", reason = "Needs review.")
    }
  ))
  sales <- Agent$new(runtime_chat(sales_server), tools = list(measure))
  handle <- root$retain_agent(sales, UsageLimits(max_requests = 8))
  routes_route(root, handle)
  expect_warning(root$run_sync("Revenue?"), "Needs review")
  expect_identical(counter$calls, 0L)
  expect_length(deliveries$events, 0L)
  # The root's review hook saw the typed arguments of the specialist's call.
  expect_s7_class(seen, ellmer::TypeObject)
})

test_that("graph descendants publish to the root once", {
  deliveries <- routes_deliveries()
  counter <- new.env()
  counter$calls <- 0L
  measure <- routes_measure_tool(60, counter)
  root_server <- local_runtime_server(list(
    runtime_reply(tool = "ask_analyst", arguments = list(task = "Revenue?")),
    runtime_reply("Root: revenue is ready.")
  ))
  analyst_server <- local_runtime_server(list(
    runtime_reply(tool = "ask_sales", arguments = list(task = "Measure it.")),
    runtime_reply("Analyst: sales measured it.")
  ))
  sales_server <- routes_sales_server()
  root <- routes_root(runtime_chat(root_server), measure, deliveries)
  analyst <- Agent$new(
    runtime_chat(analyst_server),
    tools = list(routes_read_tool()),
    agent_name = "analyst"
  )
  sales <- Agent$new(
    runtime_chat(sales_server),
    tools = list(measure),
    agent_name = "sales"
  )
  route <- function(target) {
    list(
      target = target,
      description = paste("Ask", target),
      usage_limits = UsageLimits(max_requests = 4)
    )
  }
  root$retain_agent_graph(
    agents = list(analyst = analyst, sales = sales),
    routes = list(
      root = list(ask_analyst = route("analyst")),
      analyst = list(ask_sales = route("sales"))
    ),
    usage_limits = UsageLimits(max_requests = 12),
    max_depth = 2L,
    max_delegations = 4L,
    max_concurrency = 2L
  )
  result <- root$run_sync("Revenue?")
  expect_identical(counter$calls, 1L)
  expect_length(deliveries$events, 1L)
  event <- deliveries$events[[1L]]
  expect_identical(event$agent_id, sales$agent_id)
  expect_identical(event$parent_agent_id, analyst$agent_id)
  records <- root$list_subagents()
  expect_identical(
    event$delegation_id,
    records$delegation_id[records$agent_name == "sales"]
  )
  expect_length(result_trusted_results(result), 1L)
  # The graph is released as one, giving each member its own policy back.
  root$release_agent_graph()
  expect_null(sales$.__enclos_env__$private$.trusted_results)
  expect_null(analyst$.__enclos_env__$private$.trusted_root)
})

test_that("a graph with a weaker member is not set up at all", {
  measure <- routes_measure_tool()
  root <- routes_root(routes_offline_chat(), measure, routes_deliveries())
  before <- names(root$get_tools())
  analyst <- Agent$new(routes_offline_chat(), tools = list(routes_read_tool()))
  coder <- Agent$new(routes_offline_chat(), tools = list(tool_run_r_code))
  expect_error(
    root$retain_agent_graph(
      agents = list(analyst = analyst, coder = coder),
      routes = list(
        root = list(
          ask_analyst = list(
            target = "analyst",
            description = "Ask.",
            usage_limits = UsageLimits(max_requests = 1)
          )
        )
      ),
      usage_limits = UsageLimits(max_requests = 2),
      max_depth = 1L,
      max_delegations = 1L,
      max_concurrency = 1L
    ),
    "executes model-supplied"
  )
  expect_identical(names(root$get_tools()), before)
  expect_length(root$.__enclos_env__$private$owned_conversations, 0L)
  expect_null(analyst$.__enclos_env__$private$.trusted_results)
  expect_null(analyst$.__enclos_env__$private$.conversation_owner)
})

test_that("a route reaches only what its caller's policy allows", {
  measure <- routes_measure_tool()
  fetch <- ellmer::tool(
    function() "fetched",
    name = "fetch_rates",
    description = "Fetch exchange rates.",
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = TRUE
    )
  )
  route <- function(target) {
    list(
      target = target,
      description = paste("Ask", target),
      usage_limits = UsageLimits(max_requests = 1)
    )
  }
  graph <- function(root, routes) {
    root$retain_agent_graph(
      agents = list(
        # Declines the root's exemption for `fetch_rates`.
        strict = Agent$new(
          routes_offline_chat(),
          tools = list(measure),
          trusted_results = TrustedResults(measure = measure)
        ),
        loose = Agent$new(routes_offline_chat(), tools = list(measure, fetch))
      ),
      routes = routes,
      usage_limits = UsageLimits(max_requests = 4),
      max_depth = 2L,
      max_delegations = 2L,
      max_concurrency = 1L
    )
  }
  root <- routes_root(
    routes_offline_chat(),
    measure,
    routes_deliveries(),
    exempt_tools = "fetch_rates"
  )
  # The strict member can't reach the tool it declined through the other.
  expect_error(
    graph(
      root,
      list(
        root = list(ask_strict = route("strict")),
        strict = list(ask_loose = route("loose"))
      )
    ),
    "fetch_rates"
  )
  expect_length(root$.__enclos_env__$private$owned_conversations, 0L)
  # The root, whose policy exempts it, still reaches it.
  expect_no_error(graph(
    root,
    list(root = list(ask_strict = route("strict"), ask_loose = route("loose")))
  ))
  root$release_agent_graph()
})

test_that("a member's route runs its target under the member's result types", {
  deliveries <- routes_deliveries()
  own <- list()
  measure <- routes_measure_tool(60)
  audit <- ellmer::tool(
    function() "audited",
    name = "run_audit",
    description = "Run the audit.",
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE
    )
  )
  root_server <- local_runtime_server(list(
    runtime_reply(tool = "ask_analyst", arguments = list(task = "Audit?")),
    runtime_reply("Root: audited.")
  ))
  analyst_server <- local_runtime_server(list(
    runtime_reply(tool = "ask_auditor", arguments = list(task = "Run it.")),
    runtime_reply("Analyst: the auditor ran it.")
  ))
  auditor_server <- local_runtime_server(list(
    runtime_reply(tool = "run_audit"),
    runtime_reply("Auditor: done.")
  ))
  root <- routes_root(runtime_chat(root_server), measure, deliveries)
  # The analyst's own policy makes run_audit the producer of "audit"; the
  # auditor holds that tool and has no policy of its own.
  analyst <- Agent$new(
    runtime_chat(analyst_server),
    tools = list(routes_read_tool()),
    agent_name = "analyst",
    trusted_results = TrustedResults(
      audit = audit,
      on_result = function(event) own[[length(own) + 1L]] <<- event
    )
  )
  auditor <- Agent$new(
    runtime_chat(auditor_server),
    tools = list(audit),
    agent_name = "auditor"
  )
  route <- function(target) {
    list(
      target = target,
      description = paste("Ask", target),
      usage_limits = UsageLimits(max_requests = 4)
    )
  }
  root$retain_agent_graph(
    agents = list(analyst = analyst, auditor = auditor),
    routes = list(
      root = list(ask_analyst = route("analyst")),
      analyst = list(ask_auditor = route("auditor"))
    ),
    usage_limits = UsageLimits(max_requests = 12),
    max_depth = 2L,
    max_delegations = 4L,
    max_concurrency = 2L
  )
  admitted <- auditor$.__enclos_env__$private$.trusted_results
  result <- root$run_sync("Audit?")
  # Reached through the analyst, the auditor publishes the analyst's type:
  # once to the root, once to the analyst's own host.
  expect_length(deliveries$events, 1L)
  event <- deliveries$events[[1L]]
  expect_identical(event$result_type, "audit")
  expect_identical(event$agent_id, auditor$agent_id)
  expect_identical(event$parent_agent_id, analyst$agent_id)
  expect_length(own, 1L)
  expect_identical(own[[1L]]$result_id, event$result_id)
  expect_length(result_trusted_results(result, "audit"), 1L)
  # The auditor's admitted policy is back once the call settles.
  expect_identical(auditor$.__enclos_env__$private$.trusted_results, admitted)
  root$release_agent_graph()
})

test_that("Commons specialists qualify only when constrained", {
  skip_if_not_installed("commons")
  sales <- data.frame(region = c("north", "south"), revenue = c(25, 35))
  commons_chat <- function(server) {
    commons::commons(
      runtime_chat(server),
      data_sources = commons::data_source(sales = sales),
      semantic_layer = commons::semantic_layer(commons::measure(
        "total_revenue",
        "Total revenue across regions.",
        function() sum(sales$revenue),
        arguments = list()
      ))
    )
  }
  permissions <- Permissions(
    mode = "readonly",
    tool_allowlist = c("search_pool", "call_measure")
  )
  adopt <- function(chat, root) {
    adopt_chat(
      chat,
      root,
      permissions = permissions,
      usage_limits = UsageLimits(max_requests = 4),
      history = "fresh",
      callbacks = "replace",
      name = "sales"
    )
  }
  # As Commons ships, its SQL and R fallbacks could compute any number.
  ordinary <- commons_chat(list(url = "http://127.0.0.1:9/v1"))
  expect_true(all(c("run_sql", "run_r") %in% names(ordinary$get_tools())))
  root <- routes_root(
    routes_offline_chat(),
    ordinary$get_tools()$call_measure,
    routes_deliveries()
  )
  expect_error(adopt(ordinary, root), class = "deputy_tool_registration")
  expect_length(root$.__enclos_env__$private$owned_conversations, 0L)

  # Constrained: no fallbacks, closed-world tools, call_measure as producer.
  sales_server <- local_runtime_server(list(
    runtime_reply(
      tool = "call_measure",
      arguments = list(name = "total_revenue", arguments = "{}")
    ),
    runtime_reply("Total revenue is 60.")
  ))
  analyst <- commons_chat(sales_server)
  kept <- lapply(
    analyst$get_tools()[c("search_pool", "call_measure")],
    function(tool) {
      tool@annotations$open_world_hint <- FALSE
      tool
    }
  )
  analyst$set_tools(kept)
  deliveries <- routes_deliveries()
  root_server <- local_runtime_server(list(
    runtime_reply(tool = "ask_sales", arguments = list(task = "Revenue?")),
    runtime_reply("Lead: revenue is ready.")
  ))
  root <- routes_root(
    runtime_chat(root_server),
    analyst$get_tools()$call_measure,
    deliveries
  )
  handle <- adopt(analyst, root)
  routes_route(root, handle)
  result <- root$run_sync("Revenue?")
  expect_length(deliveries$events, 1L)
  event <- deliveries$events[[1L]]
  expect_identical(event$result_type, "measure")
  expect_identical(event$tool_name, "call_measure")
  expect_identical(event$arguments$name, "total_revenue")
  expect_identical(event$value@extra$commons_tag, "A")
  expect_match(paste(format(event$value@value), collapse = ""), "60")
  expect_length(result_trusted_results(result), 1L)
})
