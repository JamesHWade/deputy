test_that("job admission rejects unjournaled provider-native tools", {
  agent <- Agent$new(
    create_mock_chat(),
    tools = list(ellmer::openai_tool_web_search()),
    permissions = Permissions(
      mode = "standard",
      web = TRUE,
      tool_allowlist = "web_search"
    )
  )
  expect_error(job_agent_manifest(agent), "Provider-native tools")
})

job_runtime_test_tool <- function(name = "read_file") {
  # Stands in for Deputy's own tool of the same name.
  mark_native_tool(ellmer::tool(
    function(path) paste0("read:", path),
    name = name,
    description = "Read a test file.",
    arguments = list(path = ellmer::type_string("File path"))
  ))
}

job_runtime_test_agent <- function(
  agent_id,
  session_id,
  working_dir,
  turns = list(),
  system_prompt = "test worker",
  permissions = permissions_readonly(),
  run_context = list(product = "job-test", tenant = "one")
) {
  chat <- create_mock_chat()
  if (length(turns)) {
    chat$set_turns(turns)
  }
  Agent$new(
    chat = chat,
    tools = list(job_runtime_test_tool()),
    permissions = permissions,
    system_prompt = system_prompt,
    working_dir = working_dir,
    run_context = run_context,
    agent_id = agent_id,
    session_id = session_id,
    agent_name = "test-worker"
  )
}

job_runtime_test_graph_agent <- function(text = "answer", ...) {
  chat <- create_mock_chat()
  chat$stream_async <- function(prompt, ...) {
    coro::async_generator(function() {
      chat$set_turns(c(chat$get_turns(), list(create_mock_user_turn(prompt))))
      coro::yield(ellmer::ContentText(text))
      chat$set_turns(c(
        chat$get_turns(),
        list(create_mock_assistant_turn(text))
      ))
    })()
  }
  Agent$new(chat, ...)
}

job_runtime_test_graph_owner <- function(...) {
  job_runtime_test_graph_agent(
    delegation_disclosure = DelegationDisclosure(
      authorize = function(requester, scope) identical(requester, "owner")
    ),
    ...
  )
}

job_runtime_test_graph_route <- function(target, requests = 2L) {
  list(
    target = target,
    description = paste("Ask", target),
    usage_limits = UsageLimits(max_requests = requests)
  )
}

job_runtime_test_has_executable <- function(value) {
  if (
    is.function(value) ||
      is.environment(value) ||
      isS4(value) ||
      S7::S7_inherits(value) ||
      inherits(value, "connection") ||
      typeof(value) %in% c("externalptr", "weakref")
  ) {
    return(TRUE)
  }
  if (is.list(value) && !is.object(value)) {
    return(any(vapply(value, job_runtime_test_has_executable, logical(1))))
  }
  FALSE
}

job_runtime_test_graph <- function(working_dir, prefix) {
  root <- job_runtime_test_graph_owner(
    agent_id = paste0(prefix, "-root"),
    session_id = paste0(prefix, "-root-session"),
    system_prompt = "root worker",
    permissions = permissions_readonly(),
    working_dir = working_dir
  )
  left <- job_runtime_test_graph_agent(
    agent_id = paste0(prefix, "-left"),
    session_id = paste0(prefix, "-left-session"),
    system_prompt = "left worker",
    permissions = permissions_readonly(),
    working_dir = working_dir
  )
  right <- job_runtime_test_graph_agent(
    agent_id = paste0(prefix, "-right"),
    session_id = paste0(prefix, "-right-session"),
    system_prompt = "right worker",
    permissions = permissions_readonly(),
    working_dir = working_dir
  )
  root$retain_agent_graph(
    agents = list(left = left, right = right),
    routes = list(
      root = list(
        to_left = job_runtime_test_graph_route("left", requests = 2L)
      ),
      left = list(
        to_right = job_runtime_test_graph_route("right", requests = 2L)
      )
    ),
    usage_limits = UsageLimits(max_requests = 8L),
    max_depth = 3L,
    max_delegations = 8L,
    max_concurrency = 2L,
    max_runs = 2L
  )
  root
}

test_that("job manifests are reproducible and portable across independent Agents", {
  working_dir <- withr::local_tempdir(pattern = "deputy-job-manifest-")
  turns <- list(
    create_mock_user_turn("public question"),
    create_mock_assistant_turn("public answer")
  )
  source <- job_runtime_test_agent(
    agent_id = "agent-stable",
    session_id = "session-stable",
    working_dir = working_dir,
    turns = turns
  )
  receiver <- job_runtime_test_agent(
    agent_id = "agent-stable",
    session_id = "session-stable",
    working_dir = working_dir,
    turns = turns
  )

  source_manifest <- job_agent_manifest(source)
  receiver_manifest <- job_agent_manifest(receiver)

  expect_identical(source_manifest, receiver_manifest)
  expect_no_error(approval_portable(source_manifest))
  expect_false(job_runtime_test_has_executable(source_manifest))
  expect_true(all(vapply(
    source_manifest$nodes[["root"]]$tools,
    is.character,
    logical(1)
  )))
})

test_that("job binding rejects public history and configuration drift", {
  working_dir <- withr::local_tempdir(pattern = "deputy-job-drift-")
  turns <- list(
    create_mock_user_turn("public question"),
    create_mock_assistant_turn("public answer")
  )
  source <- job_runtime_test_agent(
    agent_id = "agent-drift",
    session_id = "session-drift",
    working_dir = working_dir,
    turns = turns
  )
  manifest <- job_agent_manifest(source)
  record <- list(status = "queued", manifest = manifest)

  same <- job_runtime_test_agent(
    agent_id = "agent-drift",
    session_id = "session-drift",
    working_dir = working_dir,
    turns = turns
  )
  expect_no_error(job_bind_agent(same, record))

  changed_history <- job_runtime_test_agent(
    agent_id = "agent-drift",
    session_id = "session-drift",
    working_dir = working_dir,
    turns = list(
      create_mock_user_turn("different question"),
      create_mock_assistant_turn("public answer")
    )
  )
  expect_error(
    job_bind_agent(changed_history, record),
    "definition or context changed"
  )

  changed_configuration <- job_runtime_test_agent(
    agent_id = "agent-drift",
    session_id = "session-drift",
    working_dir = working_dir,
    turns = turns,
    system_prompt = "changed worker"
  )
  expect_error(
    job_bind_agent(changed_configuration, record),
    "definition or context changed"
  )
})

test_that("graph binding restores ledger usage, admissions, and max-runs", {
  working_dir <- withr::local_tempdir(pattern = "deputy-job-graph-")
  source <- job_runtime_test_graph(working_dir, "source")
  on.exit(try(source$release_agent_graph(), silent = TRUE), add = TRUE)
  source_private <- source$.__enclos_env__$private
  tree <- source_private$.delegation_tree
  tree_admit(tree, "delegation-saved")
  tree_settle(tree, "delegation-saved")
  tree$usage <- AgentUsage(
    requests = 3L,
    tool_calls = 1L,
    input_tokens = 11L,
    output_tokens = 7L,
    cached_tokens = 0L,
    cost_usd = 0.01
  )
  for (name in names(tree$handles)) {
    entry <- source_private$owned_conversations[[tree$handles[[name]]]]
    entry$usage <- AgentUsage(requests = 1L, input_tokens = 2L)
    entry$ids <- c("continuation-one", "continuation-two")
  }
  source_private$subagent_runs[["delegation-saved"]] <- list(
    delegation_id = "delegation-saved",
    agent_id = "source-left",
    parent_agent_id = "source-root",
    status = "completed",
    usage = AgentUsage(requests = 1L)
  )
  saved_manifest <- job_agent_manifest(source)
  saved_graph <- saved_manifest$graph

  restored <- job_runtime_test_graph(working_dir, "source")
  on.exit(try(restored$release_agent_graph(), silent = TRUE), add = TRUE)
  expect_no_error(job_bind_agent(
    restored,
    list(status = "queued", manifest = saved_manifest)
  ))

  restored_graph <- job_graph_snapshot(restored)
  expect_identical(restored_graph, saved_graph)
  expect_identical(restored_graph$usage$requests, 3L)
  expect_identical(restored_graph$count, 1L)
  expect_identical(
    restored_graph$delegations[["delegation-saved"]]$parent_agent_id,
    "source-root"
  )
  expect_identical(
    restored_graph$admissions[["delegation-saved"]]$settled,
    TRUE
  )
  expect_true(all(vapply(
    restored_graph$members,
    function(member) {
      identical(member$max_runs, 2L) &&
        identical(member$ids, c("continuation-one", "continuation-two"))
    },
    logical(1)
  )))
})

test_that("a rejected graph binding leaves every ledger unchanged", {
  working_dir <- withr::local_tempdir()
  source <- job_runtime_test_graph(working_dir, "atomic")
  restored <- job_runtime_test_graph(working_dir, "atomic")
  on.exit(try(source$release_agent_graph(), silent = TRUE), add = TRUE)
  on.exit(try(restored$release_agent_graph(), silent = TRUE), add = TRUE)
  source_tree <- source$.__enclos_env__$private$.delegation_tree
  tree_admit(source_tree, "prior-admission")
  tree_settle(source_tree, "prior-admission")
  manifest <- job_agent_manifest(source)
  target <- restored$.__enclos_env__$private
  target$owned_conversations[[
    target$.delegation_tree$handles[["right"]]
  ]]$max_runs <- 3L
  before <- job_graph_snapshot(restored)
  expect_error(
    job_bind_agent(restored, list(status = "queued", manifest = manifest)),
    "allocation changed"
  )
  expect_identical(job_graph_snapshot(restored), before)
})

test_that("rebinding cannot erase root-only work after history replacement", {
  working_dir <- withr::local_tempdir()
  root <- job_runtime_test_graph(working_dir, "advanced")
  on.exit(try(root$release_agent_graph(), silent = TRUE), add = TRUE)
  manifest <- job_agent_manifest(root)
  root$run_sync("extra work")
  root$set_turns(list())
  before <- job_graph_snapshot(root)
  expect_identical(before$count, 0L)
  expect_gt(before$usage$requests, 0)
  expect_error(
    job_bind_agent(root, list(status = "queued", manifest = manifest)),
    "advanced beyond"
  )
  expect_identical(job_graph_snapshot(root), before)
})

test_that("a failed admission checkpoint releases its concurrency slot", {
  working_dir <- withr::local_tempdir()
  root <- job_runtime_test_graph(working_dir, "checkpoint")
  on.exit(try(root$release_agent_graph(), silent = TRUE), add = TRUE)
  private <- root$.__enclos_env__$private
  detach <- job_attach_runtime(root, function(node, event) {
    if (identical(event$type, "delegation_admitted")) {
      rlang::abort("storage unavailable")
    }
  })
  on.exit(detach(), add = TRUE)
  expect_error(
    root$continue_agent(
      private$.delegation_tree$handles[["left"]],
      "task",
      UsageLimits(max_requests = 1)
    ),
    "storage unavailable"
  )
  expect_identical(tree_active_count(private$.delegation_tree), 0L)
  expect_length(private$subagent_runs, 0L)
})

test_that("duplicate graph identities cannot alias saved authority", {
  root <- Agent$new(
    create_mock_chat(),
    agent_id = "shared",
    session_id = "root-session"
  )
  child <- Agent$new(
    create_mock_chat(),
    agent_id = "shared",
    session_id = "child-session"
  )
  root$retain_agent_graph(
    agents = list(child = child),
    routes = list(root = list(ask = job_runtime_test_graph_route("child"))),
    usage_limits = UsageLimits(max_requests = 4),
    max_depth = 1,
    max_delegations = 4,
    max_concurrency = 1
  )
  on.exit(try(root$release_agent_graph(), silent = TRUE), add = TRUE)
  expect_error(job_agent_manifest(root), "distinct agent and session")
})

test_that("a failed settlement checkpoint allows child cleanup before reporting", {
  working_dir <- withr::local_tempdir()
  root <- job_runtime_test_graph(working_dir, "settlement")
  on.exit(try(root$release_agent_graph(), silent = TRUE), add = TRUE)
  private <- root$.__enclos_env__$private
  detach <- job_attach_runtime(root, function(node, event) {
    if (identical(event$type, "delegation_settled")) {
      rlang::abort("settlement storage unavailable")
    }
  })
  on.exit(detach(), add = TRUE)
  handle <- private$.delegation_tree$handles[["left"]]
  root$continue_agent(handle, "task", UsageLimits(max_requests = 1))
  expect_false(private$owned_conversations[[handle]]$busy)
  expect_identical(tree_active_count(private$.delegation_tree), 0L)
  expect_length(private$delegation_usage_reservations, 0L)
  expect_match(
    conditionMessage(private$.job_state$checkpoint_error),
    "settlement storage unavailable"
  )
})

test_that("runtime permission checks cannot widen the saved job ceiling", {
  working_dir <- withr::local_tempdir(pattern = "deputy-job-policy-")
  agent <- job_runtime_test_agent(
    agent_id = "agent-policy",
    session_id = "session-policy",
    working_dir = working_dir,
    permissions = permissions_readonly()
  )
  private <- agent$.__enclos_env__$private
  detach <- job_attach_runtime(agent, function(node, event) NULL)
  on.exit(detach(), add = TRUE)

  # A replacement runtime policy is wider, but the job worker retains the
  # static policy captured at binding time as its authority ceiling.
  private$.permissions <- permissions_full()
  expect_error(
    private$.job_checkpoint(
      agent,
      list(
        type = "permission_check",
        tool_name = "write_file",
        tool_input = list(path = "output.txt", content = "blocked"),
        context = list(working_dir = working_dir)
      )
    ),
    "readonly mode active"
  )
})

test_that("runtime callbacks journal effects before calls and after results", {
  working_dir <- withr::local_tempdir(pattern = "deputy-job-effects-")
  agent <- job_runtime_test_agent(
    agent_id = "agent-effects",
    session_id = "session-effects",
    working_dir = working_dir
  )
  private <- agent$.__enclos_env__$private
  private$current_run_id <- "run-effects"
  snapshots <- list()
  detach <- job_attach_runtime(agent, function(node, event) {
    snapshots[[length(snapshots) + 1L]] <<-
      job_runtime_snapshot(node, event)
  })
  on.exit(detach(), add = TRUE)

  private$.job_checkpoint(
    agent,
    list(
      type = "tool_start",
      tool_name = "read_file",
      tool_call_id = "call-effects",
      tool_input = list(path = "input.txt")
    )
  )
  key <- job_effect_key(agent, "call-effects")
  expect_length(snapshots, 1L)
  expect_null(snapshots[[1L]]$effects[[key]])

  private$.job_checkpoint(
    agent,
    list(
      type = "effect_start",
      tool_name = "read_file",
      tool_call_id = "call-effects"
    )
  )
  expect_identical(
    snapshots[[2L]]$effects[[key]]$status,
    "executing"
  )

  tool <- job_runtime_test_tool()
  request <- ellmer::ContentToolRequest(
    id = "call-effects",
    name = "read_file",
    arguments = list(path = "input.txt"),
    tool = tool
  )
  result <- ellmer::ContentToolResult(value = "contents", request = request)
  private$.job_checkpoint(
    agent,
    list(
      type = "effect_result",
      tool_name = "read_file",
      tool_call_id = "call-effects",
      result = result
    )
  )
  completed <- snapshots[[3L]]$effects[[key]]
  expect_identical(completed$status, "completed")
  expect_false(job_runtime_test_has_executable(completed$result))
  expect_true(length(completed$result) > 0L)
})
