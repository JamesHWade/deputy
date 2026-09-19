retained_artifact_disclosure <- function() {
  DelegationDisclosure(
    authorize = function(requester, scope) identical(requester, "owner")
  )
}

retained_artifact_lead <- function(...) {
  parallel_test_lead(
    new.env(parent = emptyenv()),
    delegation_disclosure = retained_artifact_disclosure(),
    ...
  )
}

test_that("retained child artifacts use child storage without leaking routing", {
  owner_dir <- withr::local_tempdir()
  child_dir <- withr::local_tempdir()
  tool_text <- strrep("child tool evidence ", 600L)
  answer_text <- strrep("child answer ", 1000L)
  server <- local_runtime_server(list(
    runtime_reply(tool = "fetch_fixture"),
    runtime_reply(answer_text),
    runtime_reply(tool = "fetch_fixture"),
    runtime_reply(answer_text)
  ))
  child <- Agent$new(
    runtime_chat(server),
    permissions = permissions_full(),
    tools = list(ellmer::tool(
      function() tool_text,
      name = "fetch_fixture",
      description = "Read fixture evidence.",
      arguments = list()
    )),
    context_policy = ContextPolicy(
      max_tool_result_bytes = 100L,
      offload_dir = child_dir
    )
  )
  owner <- owned_test_owner(
    permissions = permissions_full(),
    context_policy = ContextPolicy(offload_dir = owner_dir)
  )
  live_reads <- list()
  child$on_tool_result(function(result) {
    view <- owner$inspect_subagents("owner")
    active <- Filter(
      function(x) identical(x$outcome$runtime$status, "running"),
      view
    )[[1L]]
    reference <- active$outcome$references[[1L]]
    live_reads[[length(live_reads) + 1L]] <<- list(
      availability = reference$availability,
      chunk = owner$read_subagent_result(
        "owner",
        active$outcome$runtime$delegation_id,
        reference$reference
      )$result
    )
  })
  handle <- owner$retain_agent(child, UsageLimits(max_requests = 4L))
  first <- owner$continue_agent(handle, "first", UsageLimits(max_requests = 2L))
  first_view <- owner$inspect_subagents("owner", first$delegation_id)[[1L]]
  first_refs <- first_view$outcome$references
  expect_gt(length(first_refs), 1L)
  expect_true(all(vapply(
    first_refs,
    function(ref) identical(ref$availability, "available"),
    logical(1)
  )))
  first_tool <- Filter(
    function(ref) identical(ref$source, "tool_result"),
    first_refs
  )[[1L]]
  first_answer <- Filter(
    function(ref) identical(ref$source, "delegation_answer"),
    first_refs
  )[[1L]]
  expect_match(
    owner$read_subagent_result(
      "owner",
      first$delegation_id,
      first_tool$reference
    )$result,
    "child tool evidence",
    fixed = TRUE
  )
  expect_match(
    owner$read_subagent_result(
      "owner",
      first$delegation_id,
      first_answer$reference
    )$result,
    "child answer",
    fixed = TRUE
  )

  expect_false(grepl(child_dir, delegation_json(first_view), fixed = TRUE))
  second <- owner$continue_agent(
    handle,
    "second",
    UsageLimits(max_requests = 2L)
  )
  second_view <- owner$inspect_subagents("owner", second$delegation_id)[[1L]]
  second_refs <- second_view$outcome$references
  expect_true(all(vapply(
    second_refs,
    function(ref) identical(ref$availability, "available"),
    logical(1)
  )))
  for (reference in Filter(
    function(ref) ref$source %in% c("tool_result", "delegation_answer"),
    second_refs
  )) {
    expect_match(
      owner$read_subagent_result(
        "owner",
        second$delegation_id,
        reference$reference
      )$result,
      if (identical(reference$source, "tool_result")) {
        "child tool evidence"
      } else {
        "child answer"
      },
      fixed = TRUE
    )
  }

  expect_length(live_reads, 2L)
  for (live in live_reads) {
    expect_identical(live$availability, "available")
    expect_match(live$chunk, "child tool evidence", fixed = TRUE)
  }
  history <- owner$export_subagents("owner")
  expect_false(grepl(child_dir, delegation_json(history), fixed = TRUE))
  expect_false(grepl(
    child_dir,
    delegation_json(S7::props(delegation_outcome(
      owner$.__enclos_env__$private$subagent_runs[[first$delegation_id]],
      compact = TRUE
    ))),
    fixed = TRUE
  ))

  expect_error(
    owner$inspect_subagents("other", first$delegation_id),
    class = "deputy_delegation_disclosure"
  )
  expect_error(
    owner$read_subagent_result("owner", "wrong-id", first_tool$reference),
    class = "deputy_delegation_disclosure"
  )
  unrelated <- owned_test_owner()
  expect_error(
    unrelated$read_subagent_result(
      "owner",
      first$delegation_id,
      first_tool$reference
    ),
    class = "deputy_delegation_disclosure"
  )
  owner$release_agent(handle)
})

test_that("fresh delegations retain the existing owner-routed behavior", {
  lead <- retained_artifact_lead(
    context_policy = ContextPolicy(offload_dir = withr::local_tempdir())
  )
  resolve_async_value(lead$get_tools()$delegate_to_agent("a", "task"))
  view <- lead$inspect_subagents("owner")[[1L]]
  expect_identical(view$outcome$answer, "a task")
  expect_identical(view$outcome$references, list())
})
