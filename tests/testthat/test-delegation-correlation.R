create_delegation_child_chat <- function() {
  state <- new.env(parent = emptyenv())
  state$turns <- list()
  state$tools <- list()
  state$system_prompt <- NULL
  state$on_tool_request <- function(request) invisible(NULL)
  state$on_tool_result <- function(result) invisible(NULL)
  state$executions <- 0L

  add_turn <- function(contents, tokens = c(4, 2, 0), cost = 0) {
    state$turns <- c(
      state$turns,
      list(ellmer::AssistantTurn(
        contents = contents,
        tokens = tokens,
        cost = cost
      ))
    )
  }

  chat <- structure(
    list(
      chat = function(prompt = NULL) "child complete",
      stream = function(
        prompt = NULL,
        stream = c("text", "content"),
        controller = NULL
      ) {
        tool <- state$tools[["inspect_evidence"]]
        request <- ellmer::ContentToolRequest(
          id = "child-tool-call-1",
          name = "inspect_evidence",
          arguments = list(claim = "claim-1"),
          tool = tool
        )
        step <- 0L

        function() {
          step <<- step + 1L
          if (step == 1L) {
            add_turn(list(request))
            return(request)
          }
          if (step == 2L) {
            state$on_tool_request(request)
            state$executions <- state$executions + 1L
            value <- tool(claim = request@arguments$claim)
            result <- ellmer::ContentToolResult(
              value = value,
              request = request
            )
            state$on_tool_result(result)
            return(result)
          }
          if (step == 3L) {
            text <- ellmer::ContentText("child complete")
            add_turn(list(text))
            return(text)
          }
          coro::exhausted()
        }
      },
      get_turns = function() state$turns,
      set_turns = function(turns) state$turns <- turns,
      get_system_prompt = function() state$system_prompt,
      set_system_prompt = function(prompt) state$system_prompt <- prompt,
      get_tools = function() state$tools,
      register_tool = function(tool) state$tools[[tool@name]] <- tool,
      register_tools = function(tools) {
        for (tool in tools) {
          state$tools[[tool@name]] <- tool
        }
      },
      get_tokens = function() {
        data.frame(input = 4, output = 2, cached_input = 0, cost = 0)
      },
      get_provider = function() {
        list(name = "mock", model = "delegation-child")
      },
      last_turn = function(role = "assistant") {
        if (length(state$turns) == 0L) {
          return(NULL)
        }
        tail(state$turns, 1L)[[1L]]
      },
      on_tool_request = function(callback) state$on_tool_request <- callback,
      on_tool_result = function(callback) state$on_tool_result <- callback,
      clone = function() chat
    ),
    class = "Chat"
  )

  list(chat = chat, state = state)
}

create_delegation_parent_chat <- function(child_chat) {
  state <- new.env(parent = emptyenv())
  state$turns <- list()
  state$tools <- list()
  state$system_prompt <- NULL
  state$on_tool_request <- function(request) invisible(NULL)
  state$on_tool_result <- function(result) invisible(NULL)
  state$request_number <- 0L

  add_turn <- function(contents, tokens = c(6, 3, 0), cost = 0) {
    state$turns <- c(
      state$turns,
      list(ellmer::AssistantTurn(
        contents = contents,
        tokens = tokens,
        cost = cost
      ))
    )
  }

  chat <- structure(
    list(
      chat = function(prompt = NULL) "lead complete",
      stream = function(
        prompt = NULL,
        stream = c("text", "content"),
        controller = NULL
      ) {
        state$request_number <- state$request_number + 1L
        if (state$request_number > 1L) {
          step <- 0L
          return(function() {
            step <<- step + 1L
            if (step == 1L) {
              text <- ellmer::ContentText("lead complete")
              add_turn(list(text))
              return(text)
            }
            coro::exhausted()
          })
        }

        tool <- state$tools[["delegate_to_agent"]]
        request <- ellmer::ContentToolRequest(
          id = "parent-delegate-call-1",
          name = "delegate_to_agent",
          arguments = list(
            agent_name = "evidence_reviewer",
            task = "Review claim-1"
          ),
          tool = tool
        )
        step <- 0L

        function() {
          step <<- step + 1L
          if (step == 1L) {
            add_turn(list(request))
            return(request)
          }
          if (step == 2L) {
            result <- tryCatch(
              {
                state$on_tool_request(request)
                value <- tool(
                  agent_name = request@arguments$agent_name,
                  task = request@arguments$task
                )
                ellmer::ContentToolResult(value = value, request = request)
              },
              error = function(error) {
                ellmer::ContentToolResult(
                  error = conditionMessage(error),
                  request = request
                )
              }
            )
            state$on_tool_result(result)
            return(result)
          }
          coro::exhausted()
        }
      },
      get_turns = function() state$turns,
      set_turns = function(turns) state$turns <- turns,
      get_system_prompt = function() state$system_prompt,
      set_system_prompt = function(prompt) state$system_prompt <- prompt,
      get_tools = function() state$tools,
      register_tool = function(tool) state$tools[[tool@name]] <- tool,
      register_tools = function(tools) {
        for (tool in tools) {
          state$tools[[tool@name]] <- tool
        }
      },
      get_tokens = function() {
        data.frame(input = 10, output = 5, cached_input = 0, cost = 0)
      },
      get_provider = function() {
        list(name = "mock", model = "delegation-parent")
      },
      last_turn = function(role = "assistant") {
        if (length(state$turns) == 0L) {
          return(NULL)
        }
        tail(state$turns, 1L)[[1L]]
      },
      on_tool_request = function(callback) state$on_tool_request <- callback,
      on_tool_result = function(callback) state$on_tool_result <- callback,
      clone = function() child_chat
    ),
    class = "Chat"
  )

  list(chat = chat, state = state)
}

test_that("delegated runs retain end-to-end correlation", {
  child <- create_delegation_child_chat()
  parent <- create_delegation_parent_chat(child$chat)
  inspect_evidence <- ellmer::tool(
    fun = function(claim) paste("reviewed", claim),
    name = "inspect_evidence",
    description = "Inspect one deterministic evidence fixture.",
    arguments = list(claim = ellmer::type_string("Claim identifier")),
    annotations = ellmer::tool_annotations(read_only_hint = TRUE)
  )
  definition <- agent_definition(
    name = "evidence_reviewer",
    description = "Reviews evidence",
    prompt = "Review the supplied claim.",
    tools = list(inspect_evidence)
  )
  run_context <- list(
    product = "tempest",
    research_run_id = "research-123",
    knowledge_snapshot_id = "snapshot-456",
    dsprrr_program_id = "sha256:program-789"
  )
  root <- withr::local_tempdir(pattern = "deputy-delegation-")
  lead <- LeadAgent$new(
    chat = parent$chat,
    sub_agents = list(definition),
    permissions = permissions_standard(root),
    working_dir = root,
    run_context = run_context,
    agent_id = "agent-lead-1",
    agent_name = "moderator"
  )

  parent_result <- lead$run_sync("Delegate evidence review")
  parent_start <- parent_result$tool_calls()[[1L]]
  parent_end <- parent_result$tool_results()[[1L]]

  expect_identical(parent_result$response, "lead complete")
  expect_identical(parent_start$tool_name, "delegate_to_agent")
  expect_identical(parent_end$tool_name, "delegate_to_agent")
  expect_identical(parent_start$tool_call_id, "parent-delegate-call-1")
  expect_identical(parent_end$tool_call_id, parent_start$tool_call_id)
  expect_identical(parent_end$delegation_id, parent_start$delegation_id)

  runs <- lead$list_subagents()
  expect_equal(nrow(runs), 1L)
  expect_identical(runs$parent_agent_id, parent_result$agent_id)
  expect_identical(runs$parent_run_id, parent_result$run_id)
  expect_identical(runs$tool_call_id, parent_start$tool_call_id)
  expect_identical(runs$delegation_id, parent_start$delegation_id)
  expect_identical(runs$agent_name, "evidence_reviewer")
  expect_match(runs$agent_id, "^agent_")
  expect_match(runs$run_id, "^run_")

  child_results <- lead$get_subagent_results(
    delegation_id = runs$delegation_id
  )
  expect_length(child_results, 1L)
  child_result <- child_results[[1L]]
  expect_s3_class(child_result, "AgentResult")
  expect_identical(runs$agent_id, child_result$agent_id)
  expect_identical(runs$run_id, child_result$run_id)
  expect_identical(child_result$agent_name, "evidence_reviewer")
  expect_identical(child_result$parent_agent_id, parent_result$agent_id)
  expect_identical(child_result$parent_run_id, parent_result$run_id)
  expect_identical(child_result$delegation_id, parent_start$delegation_id)

  expected_context <- c(run_context, list(role = "evidence_reviewer"))
  for (field in names(expected_context)) {
    expect_identical(
      child_result$run_context[[field]],
      expected_context[[field]],
      info = field
    )
  }

  expect_identical(child$state$executions, 1L)
  child_start <- child_result$tool_calls()[[1L]]
  child_end <- child_result$tool_results()[[1L]]
  expect_identical(child_start$tool_name, "inspect_evidence")
  expect_identical(child_start$tool_call_id, "child-tool-call-1")
  expect_identical(child_end$tool_call_id, child_start$tool_call_id)
  expect_identical(child_start$agent_id, child_result$agent_id)
  expect_identical(child_end$agent_id, child_result$agent_id)
  expect_identical(child_start$agent_name, "evidence_reviewer")
  expect_identical(child_end$agent_name, "evidence_reviewer")
  expect_identical(child_start$run_id, child_result$run_id)
  expect_identical(child_end$run_id, child_result$run_id)
  expect_identical(child_start$parent_agent_id, parent_result$agent_id)
  expect_identical(child_end$parent_agent_id, parent_result$agent_id)
  expect_identical(child_start$parent_run_id, parent_result$run_id)
  expect_identical(child_end$parent_run_id, parent_result$run_id)
  expect_identical(child_start$delegation_id, parent_start$delegation_id)
  expect_identical(child_end$delegation_id, parent_start$delegation_id)
  expect_identical(child_start$run_context, child_result$run_context)
  expect_identical(child_end$run_context, child_result$run_context)
})

test_that("failed delegated runs retain parent tool correlation", {
  failing_child <- create_mock_chat()
  failing_child$stream <- function(...) stop("deterministic child failure")
  failing_child$chat <- function(...) stop("deterministic child failure")
  parent <- create_delegation_parent_chat(failing_child)
  definition <- agent_definition(
    name = "evidence_reviewer",
    description = "Fails deterministically",
    prompt = "Fail this delegated task."
  )
  root <- withr::local_tempdir(pattern = "deputy-delegation-failure-")
  lead <- LeadAgent$new(
    chat = parent$chat,
    sub_agents = list(definition),
    permissions = permissions_standard(root),
    working_dir = root,
    run_context = list(product = "tempest"),
    agent_id = "agent-lead-failure"
  )

  result <- suppressWarnings(lead$run_sync("Delegate failing review"))
  tool_start <- result$tool_calls()[[1L]]
  tool_end <- result$tool_results()[[1L]]
  runs <- lead$list_subagents()

  expect_equal(nrow(runs), 1L)
  expect_identical(runs$status, "failed")
  expect_match(runs$error, "deterministic child failure")
  expect_identical(runs$parent_agent_id, result$agent_id)
  expect_identical(runs$parent_run_id, result$run_id)
  expect_identical(runs$tool_call_id, tool_start$tool_call_id)
  expect_identical(runs$delegation_id, tool_start$delegation_id)
  expect_identical(tool_end$tool_call_id, tool_start$tool_call_id)
  expect_identical(tool_end$delegation_id, tool_start$delegation_id)
  expect_match(tool_end$tool_error, "deterministic child failure")
  expect_identical(
    lead$get_subagent_results(delegation_id = runs$delegation_id),
    list(NULL)
  )
})

test_that("denied delegation requests do not leave stale correlation", {
  root <- withr::local_tempdir(pattern = "deputy-delegation-denied-")
  lead <- LeadAgent$new(
    chat = create_mock_chat(),
    sub_agents = list(agent_definition(
      name = "reviewer",
      description = "Reviews evidence",
      prompt = "Review evidence."
    )),
    permissions = permissions_standard(root),
    working_dir = root
  )
  lead$add_hook(HookMatcher$new(
    event = "PreToolUse",
    timeout = 0,
    callback = function(tool_name, tool_input, context) {
      HookResultPreToolUse(permission = "deny", reason = "not this turn")
    }
  ))
  tool <- lead$chat$get_tools()[["delegate_to_agent"]]
  request <- ellmer::ContentToolRequest(
    id = "denied-delegation",
    name = "delegate_to_agent",
    arguments = list(agent_name = "reviewer", task = "Review claim-1"),
    tool = tool
  )

  rejection <- tryCatch(
    lead$.__enclos_env__$private$on_tool_request(request),
    ellmer_tool_reject = identity
  )

  expect_s3_class(rejection, "ellmer_tool_reject")
  expect_length(
    lead$.__enclos_env__$private$pending_delegations,
    0L
  )
})
