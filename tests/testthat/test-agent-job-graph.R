job_graph_test_requirements <- function() {
  skip_if_not_installed("httpuv")
  skip_if_not_installed("jsonlite")
}

job_graph_test_agent <- function(
  server,
  working_dir,
  id,
  permissions = permissions_standard(working_dir),
  turns = NULL,
  tools = list()
) {
  chat <- runtime_chat(server)
  agent <- Agent$new(
    chat = chat,
    tools = tools,
    system_prompt = paste("Durable", id, "worker"),
    permissions = permissions,
    usage_limits = UsageLimits(max_requests = 8L),
    working_dir = working_dir,
    run_context = list(product = "durable-job-test", tenant = "one"),
    agent_id = id,
    session_id = paste0(id, "-session"),
    agent_name = id
  )
  if (!is.null(turns)) {
    agent$set_turns(turns)
  }
  agent
}

job_graph_test_graph <- function(
  server,
  working_dir,
  permissions = permissions_standard(working_dir),
  histories = list()
) {
  root <- job_graph_test_agent(
    server,
    working_dir,
    "job-graph-root",
    permissions = permissions,
    turns = histories$root
  )
  left <- job_graph_test_agent(
    server,
    working_dir,
    "job-graph-left",
    permissions = permissions,
    turns = histories$left
  )
  right <- job_graph_test_agent(
    server,
    working_dir,
    "job-graph-right",
    permissions = permissions,
    turns = histories$right
  )
  root$retain_agent_graph(
    agents = list(left = left, right = right),
    routes = list(
      root = list(
        to_left = list(
          target = "left",
          description = "Ask the left child to complete the task.",
          usage_limits = UsageLimits(max_requests = 4L)
        )
      ),
      left = list(
        to_right = list(
          target = "right",
          description = "Ask the right child to complete the task.",
          usage_limits = UsageLimits(max_requests = 4L)
        )
      )
    ),
    usage_limits = UsageLimits(max_requests = 32L),
    max_depth = 3L,
    max_delegations = 8L,
    max_concurrency = 2L,
    max_runs = 2L
  )
  list(root = root, left = left, right = right)
}

job_graph_test_authorize <- function(job) {
  list(
    job_id = job$id,
    owner_id = job$owner_id,
    definition_revision = job$definition_revision,
    context_revision = job$context_revision
  )
}

job_graph_test_write_tool <- function(path) {
  marker <- path
  ellmer::tool(
    function(value) {
      writeLines(value, marker)
      "wrote"
    },
    name = "write_marker",
    description = "Write a marker file.",
    arguments = list(value = ellmer::type_string("Marker contents")),
    annotations = ellmer::tool_annotations(
      read_only_hint = FALSE,
      destructive_hint = TRUE,
      open_world_hint = FALSE,
      idempotent_hint = FALSE
    )
  )
}

test_that("queued localhost graph jobs preserve lineage and cumulative ledger", {
  job_graph_test_requirements()
  server <- local_runtime_server(list(
    runtime_reply(tool = "to_left", arguments = list(task = "initial left")),
    runtime_reply(tool = "to_right", arguments = list(task = "initial right")),
    runtime_reply("initial right complete"),
    runtime_reply("initial left complete"),
    runtime_reply("initial root complete"),
    runtime_reply(tool = "to_left", arguments = list(task = "queued left")),
    runtime_reply(tool = "to_right", arguments = list(task = "queued right")),
    runtime_failure(400L),
    runtime_reply("queued left recovered"),
    runtime_reply("queued root recovered")
  ))
  directory <- withr::local_tempdir(pattern = "deputy-job-graph-public-")
  source_graph <- job_graph_test_graph(server, directory)
  source <- source_graph$root
  on.exit(try(source$release_agent_graph(), silent = TRUE), add = TRUE)

  expect_no_error(source$run_sync("initial root task"))
  histories <- list(
    root = source$get_turns(),
    left = source_graph$left$get_turns(),
    right = source_graph$right$get_turns()
  )

  path <- deputy::job_create(
    directory = directory,
    agent = source,
    task = "queued root task",
    owner_id = "owner-job-graph",
    definition_revision = "graph-definition-1",
    context_revision = "graph-context-1",
    usage_limits = UsageLimits(max_requests = 32L),
    associations = list(conversation_id = "graph-conversation")
  )
  queued <- deputy::job_read(path)
  expect_identical(queued$status, "queued")
  expect_identical(queued$graph$count, 2L)
  initial_graph <- queued$graph
  expect_true(all(vapply(
    initial_graph$admissions,
    function(admission) {
      isTRUE(admission$settled) &&
        !isTRUE(admission$active)
    },
    logical(1)
  )))
  source$release_agent_graph()

  cleanup_count <- 0L
  bound <- NULL
  cleanup <- NULL
  bind <- function(...) {
    graph <- job_graph_test_graph(
      server,
      directory,
      histories = histories
    )
    bound <<- graph$root
    cleanup <<- function() {
      cleanup_count <<- cleanup_count + 1L
      if (cleanup_count == 1L) graph$root$release_agent_graph()
    }
    list(agent = graph$root, cleanup = cleanup)
  }
  suppressWarnings(deputy::job_run(
    path,
    bind = bind,
    authorize = job_graph_test_authorize
  ))

  completed <- deputy::job_read(path)
  expect_identical(completed$status, "completed")
  expect_identical(cleanup_count, 1L)
  expect_identical(completed$cleanup$attempts, 1L)
  expect_identical(completed$cleanup$status, "completed")
  expect_true(inherits(bound, "Agent"))

  graph <- completed$runtime$graph
  expect_true(is.list(graph))
  expect_identical(graph$count, 4L)
  expect_length(graph$admissions, 4L)
  expect_equal(graph$limits$max_requests, initial_graph$limits$max_requests)
  expect_identical(graph$max_depth, initial_graph$max_depth)
  expect_identical(graph$max_delegations, initial_graph$max_delegations)
  expect_identical(graph$max_concurrency, initial_graph$max_concurrency)
  expect_true(graph$usage$requests >= initial_graph$usage$requests)
  expect_true(all(vapply(
    graph$admissions,
    function(admission) {
      identical(admission$root_agent_id, "job-graph-root") &&
        isTRUE(admission$settled) &&
        !isTRUE(admission$active)
    },
    logical(1)
  )))
  expect_true(graph$usage$requests > initial_graph$usage$requests)
  expect_true(
    graph$members$left$usage$requests >=
      initial_graph$members$left$usage$requests
  )
  expect_true(
    graph$members$right$usage$requests >=
      initial_graph$members$right$usage$requests
  )
  expect_identical(
    graph$members$left$max_runs,
    initial_graph$members$left$max_runs
  )
  expect_identical(
    graph$members$right$max_runs,
    initial_graph$members$right$max_runs
  )
  expect_length(graph$members$left$ids, 2L)
  expect_length(graph$members$right$ids, 2L)

  delegations <- graph$delegations
  agent_ids <- vapply(
    delegations,
    function(record) record$agent_id %||% NA_character_,
    character(1)
  )
  left_records <- delegations[agent_ids == "job-graph-left"]
  right_records <- delegations[agent_ids == "job-graph-right"]
  expect_length(left_records, 2L)
  expect_length(right_records, 2L)
  left_ids <- vapply(
    left_records,
    function(record) record$delegation_id,
    character(1)
  )
  expect_true(any(vapply(
    left_records,
    function(record) {
      identical(record$status, "completed") &&
        identical(record$parent_agent_id, "job-graph-root")
    },
    logical(1)
  )))
  expect_true(any(vapply(
    right_records,
    function(record) {
      identical(record$status, "completed") &&
        identical(record$parent_agent_id, "job-graph-left") &&
        record$parent_delegation_id %in% left_ids
    },
    logical(1)
  )))
  expect_equal(
    unname(sort(vapply(
      right_records,
      function(record) record$status,
      character(1)
    ))),
    c("completed", "failed")
  )
  failed_right <- Filter(
    function(record) identical(record$status, "failed"),
    right_records
  )[[1L]]
  expect_identical(failed_right$parent_agent_id, "job-graph-left")
  expect_true(failed_right$parent_delegation_id %in% left_ids)
  expect_length(server$requests(), 10L)
})

test_that("a wider rebound policy cannot exceed the saved parent ceiling", {
  job_graph_test_requirements()
  server <- local_runtime_server(list(
    runtime_reply(tool = "write_marker", arguments = list(value = "ran")),
    runtime_reply("policy remained bounded")
  ))
  directory <- withr::local_tempdir(pattern = "deputy-job-policy-public-")
  marker <- file.path(directory, "unexpected-write.txt")
  tool <- job_graph_test_write_tool(marker)
  source <- job_graph_test_agent(
    server,
    directory,
    "job-policy-agent",
    permissions = permissions_readonly(),
    tools = list(tool)
  )
  path <- deputy::job_create(
    directory = directory,
    agent = source,
    task = "attempt the protected write",
    owner_id = "owner-job-policy",
    definition_revision = "policy-definition-1",
    context_revision = "policy-context-1",
    usage_limits = UsageLimits(max_requests = 4L)
  )

  borrowed <- NULL
  bind <- function(...) {
    borrowed <<- job_graph_test_agent(
      server,
      directory,
      "job-policy-agent",
      permissions = permissions_full(),
      tools = list(job_graph_test_write_tool(marker))
    )
    borrowed
  }
  policy_result <- suppressWarnings(deputy::job_run(
    path,
    bind = bind,
    authorize = job_graph_test_authorize
  ))

  expect_identical(policy_result$status, "completed")
  expect_false(file.exists(marker))
  expect_true(inherits(borrowed, "Agent"))
  expect_no_error(borrowed$get_turns())
})
