context_fork_test_agents <- function(
  responses = list("fork response"),
  parent_turns = list()
) {
  parent <- Agent$new(
    chat = create_mock_chat(),
    usage_limits = UsageLimits(max_requests = 4L)
  )
  if (length(parent_turns)) {
    parent$set_turns(parent_turns)
  }
  child <- Agent$new(
    chat = create_mock_chat(responses = responses),
    usage_limits = UsageLimits(max_requests = 4L)
  )
  list(parent = parent, child = child)
}

context_fork_test_value <- function(
  turns,
  view = "transcript",
  branch = "branch-a",
  revision = "revision-1",
  max_bytes = 65536L,
  max_turns = 16L
) {
  ContextFork(
    owner_id = "owner-a",
    conversation_id = "conversation-a",
    branch_id = branch,
    revision = revision,
    fork_point = 1L,
    view = view,
    turns = turns,
    max_bytes = max_bytes,
    max_turns = max_turns
  )
}

context_fork_test_authorize <- function(meta) {
  list(
    owner_id = meta$owner_id,
    conversation_id = meta$conversation_id,
    branch_id = meta$branch_id,
    revision = meta$revision
  )
}

# This method must never be reached by bounded fork preflight. The unique
# class keeps the regression local to this test process.
length.context_fork_hostile <- function(x) {
  stop("hostile length method should not run")
}

test_that("ContextFork stores independent bounded public records", {
  source <- list(
    create_mock_user_turn("source question"),
    create_mock_assistant_turn("source answer")
  )
  fork <- context_fork_test_value(source)

  source[[1]]@contents[[1]]@text <- "changed after snapshot"
  expect_identical(
    fork$turns[[1]]$props$contents[[1]]$props$text,
    "source question"
  )
  expect_identical(fork$view, "transcript")
  expect_identical(fork$size$turns, 2L)
  expect_identical(
    fork$projection$execution,
    "inert"
  )
  expect_identical(
    is.null(attr(S7::props(fork), "deputy_conversation_owner")),
    TRUE
  )
  expect_no_error(serialize(S7::props(fork), NULL, version = 3))
})

test_that("context and transcript are explicit selected views", {
  transcript <- list(
    create_mock_user_turn("old"),
    create_mock_assistant_turn("old answer"),
    create_mock_user_turn("current")
  )
  context <- list(transcript[[3]])
  transcript_fork <- context_fork_test_value(transcript, view = "transcript")
  context_fork <- context_fork_test_value(context, view = "context")

  expect_identical(transcript_fork$view, "transcript")
  expect_identical(context_fork$view, "context")
  expect_identical(transcript_fork$size$turns, 3L)
  expect_identical(context_fork$size$turns, 1L)
  expect_identical(
    context_fork$turns[[1]]$props$contents[[1]]$props$text,
    "current"
  )
})

test_that("context view follows the source Agent's compacted context", {
  fixture <- context_fork_test_agents(
    parent_turns = list(
      create_mock_user_turn("old source"),
      create_mock_assistant_turn("old answer"),
      create_mock_user_turn("current source")
    )
  )
  fixture$parent$compact(keep_last = 1L, summary = "selected summary")
  transcript <- context_fork_test_value(
    fixture$parent$get_turns(),
    view = "transcript"
  )
  context <- context_fork_test_value(
    fixture$parent$get_context_turns(),
    view = "context"
  )

  expect_identical(transcript$size$turns, 3L)
  expect_identical(context$size$turns, 1L)
  expect_identical(
    context$turns[[1L]]$props$contents[[1L]]$props$text,
    "current source"
  )
  expect_identical(
    any(vapply(
      context$turns[[1L]]$props$contents,
      function(content) {
        identical(content$props$text, "old source")
      },
      logical(1)
    )),
    FALSE
  )
})

test_that("fork selection rejects provider system and partial turns", {
  expect_error(
    context_fork_test_value(list(ellmer::SystemTurn(list(
      ellmer::ContentText("system")
    )))),
    class = "deputy_context_fork_error"
  )
  expect_error(
    context_fork_test_value(list(ellmer::AssistantPartialTurn(list(
      ellmer::ContentText("partial")
    )))),
    class = "deputy_context_fork_error"
  )
})

test_that("public image and document content round trips without execution", {
  contents <- list(
    ellmer::ContentImageInline(type = "image/png", data = "AQI="),
    ellmer::ContentImageRemote(url = "https://example.test/a.png"),
    ellmer::ContentPDF(
      type = "application/pdf",
      data = "JVBERi0=",
      filename = "a.pdf"
    ),
    ellmer::ContentDocument(
      mime_type = "text/plain",
      data = "aGVsbG8=",
      filename = "a.txt"
    )
  )
  fork <- context_fork_test_value(list(ellmer::UserTurn(contents)))
  replayed <- context_fork_replay(fork)[[1L]]@contents

  expect_identical(
    vapply(fork$turns[[1L]]$props$contents, `[[`, character(1), "class"),
    c(
      "ellmer::ContentImageInline",
      "ellmer::ContentImageRemote",
      "ellmer::ContentPDF",
      "ellmer::ContentDocument"
    )
  )
  expect_identical(
    vapply(replayed, function(content) class(content)[[1L]], character(1)),
    c(
      "ellmer::ContentImageInline",
      "ellmer::ContentImageRemote",
      "ellmer::ContentPDF",
      "ellmer::ContentDocument"
    )
  )
})

test_that("provider upload handles become inert fork evidence", {
  upload <- ellmer::ContentUploaded(
    uri = "file-provider-secret",
    mime_type = "application/pdf",
    provider = "openai",
    extra = list()
  )
  turn <- ellmer::UserTurn(list(upload))
  for (selected in list(turn, ellmer::contents_record(turn))) {
    fork <- context_fork_test_value(list(selected))
    content <- context_fork_replay(fork)[[1L]]@contents[[1L]]
    expect_s7_class(content, ellmer::ContentText)
    expect_match(content@text, "Provider upload omitted", fixed = TRUE)
    expect_true("provider_upload" %in% fork$omissions)
    expect_false(grepl(
      "file-provider-secret",
      jsonlite::toJSON(fork$turns, auto_unbox = TRUE),
      fixed = TRUE
    ))
  }

  request <- ellmer::ContentToolRequest(
    id = "uploaded-tool",
    name = "read_file",
    arguments = list()
  )
  result <- ellmer::ContentToolResult(
    request = request,
    value = list(report = list(upload = upload))
  )
  fork <- context_fork_test_value(list(
    ellmer::AssistantTurn(list(request)),
    ellmer::UserTurn(list(result))
  ))
  content <- context_fork_replay(fork)[[2L]]@contents[[1L]]@value$report$upload
  expect_s7_class(content, ellmer::ContentText)
  expect_match(content@text, "Provider upload omitted", fixed = TRUE)
  expect_true("provider_upload" %in% fork$omissions)
  expect_false(grepl(
    "file-provider-secret",
    jsonlite::toJSON(fork$turns, auto_unbox = TRUE),
    fixed = TRUE
  ))
})

test_that("partial tool evidence is narrowed to inert text", {
  tool <- ellmer::tool(
    function() "side effect",
    name = "write_file",
    description = "writes",
    arguments = list()
  )
  request <- ellmer::ContentToolRequest(
    id = "call-1",
    name = "write_file",
    arguments = list(path = "outside"),
    tool = tool
  )
  fork <- context_fork_test_value(
    list(ellmer::AssistantTurn(list(request)))
  )

  expect_identical(
    fork$turns[[1]]$props$contents[[1]]$class,
    "ellmer::ContentText"
  )
  expect_match(
    fork$turns[[1]]$props$contents[[1]]$props$text,
    "^\\[Inert incomplete tool evidence: write_file; arguments="
  )
  replayed <- context_fork_replay(fork)
  expect_match(replayed[[1]]@contents[[1]]@text, "arguments=")
  expect_identical(
    "partial_tool_evidence" %in% fork$omissions,
    TRUE
  )
})

test_that("inert partial evidence cannot leak hidden or private content", {
  tool <- ellmer::tool(
    function() "side effect",
    name = "secret_tool",
    description = "private",
    arguments = list()
  )
  request <- ellmer::ContentToolRequest(
    id = "orphan",
    name = "secret_tool",
    arguments = list(path = "safe"),
    tool = tool
  )
  result <- ellmer::ContentToolResult(
    value = ellmer::ContentThinking("HIDDEN_PROVIDER_REASONING"),
    error = "CLEAR TOOL FAILURE",
    extra = list(private_display_metadata = "HOST_ONLY_SECRET"),
    request = request
  )
  fork <- context_fork_test_value(list(ellmer::UserTurn(list(result))))
  text <- fork$turns[[1L]]$props$contents[[1L]]$props$text

  expect_match(text, "CLEAR TOOL FAILURE", fixed = TRUE)
  expect_identical(
    grepl("HIDDEN_PROVIDER_REASONING", text, fixed = TRUE),
    FALSE
  )
  expect_identical(
    grepl("HOST_ONLY_SECRET", text, fixed = TRUE),
    FALSE
  )
})

test_that("nonportable tool arguments fail without revealing private content", {
  for (arguments in list(
    list(hidden = ellmer::ContentThinking("NESTED_PROVIDER_REASONING")),
    list(
      path = "safe",
      hidden = ellmer::ContentThinking("NESTED_PROVIDER_REASONING")
    )
  )) {
    request <- ellmer::ContentToolRequest(
      id = "orphan-nested",
      name = "inspect",
      arguments = arguments
    )
    result <- ellmer::ContentToolResult(
      value = "public result",
      request = request
    )
    for (turn in list(
      ellmer::AssistantTurn(list(request)),
      ellmer::UserTurn(list(result)),
      ellmer::UserTurn(list(ellmer::ContentToolResult(value = list(result))))
    )) {
      error <- expect_error(
        context_fork_test_value(list(turn)),
        "unsupported public fork evidence",
        class = "deputy_context_fork_error"
      )
      expect_false(grepl("NESTED_PROVIDER_REASONING", conditionMessage(error)))
    }
  }
})

test_that("portable ellmer records scrub provider fields before replay", {
  executed <- FALSE
  tool <- ellmer::tool(
    function() {
      executed <<- TRUE
      "executed"
    },
    name = "provider_tool",
    description = "provider tool",
    arguments = list()
  )
  request <- ellmer::ContentToolRequest(
    id = "record-tool",
    name = "provider_tool",
    arguments = list(path = "safe"),
    tool = tool,
    extra = list(display_secret = "DISPLAY_SECRET")
  )
  record <- ellmer::contents_record(
    ellmer::AssistantTurn(list(request))
  )
  record$props$json <- list(
    hidden_reasoning = "HIDDEN_PROVIDER_REASONING"
  )
  record$props$contents[[1L]]$props$tool <- list(name = "provider_tool")
  record$props$contents[[1L]]$props$extra <- list(
    display_secret = "DISPLAY_SECRET"
  )

  fork <- context_fork_test_value(list(record))
  serialized <- jsonlite::toJSON(fork$turns, auto_unbox = TRUE)
  expect_identical(
    grepl("HIDDEN_PROVIDER_REASONING", serialized, fixed = TRUE),
    FALSE
  )
  expect_identical(
    grepl("DISPLAY_SECRET", serialized, fixed = TRUE),
    FALSE
  )
  expect_false(executed)
  replayed <- context_fork_replay(fork)[[1L]]@contents[[1L]]
  expect_identical(class(replayed)[[1L]], "ellmer::ContentText")
})

test_that("portable thinking is omitted only at typed content positions", {
  record <- ellmer::contents_record(ellmer::AssistantTurn(list(
    ellmer::ContentThinking("PRIVATE_THINKING"),
    ellmer::ContentText("public answer")
  )))
  fork <- context_fork_test_value(list(record))
  contents <- context_fork_replay(fork)[[1L]]@contents
  expect_length(contents, 1L)
  expect_identical(contents[[1L]]@text, "public answer")

  ambiguous <- ellmer::contents_record(ellmer::UserTurn(list(
    ellmer::ContentToolResult(
      value = ellmer::ContentThinking("PRIVATE_THINKING")
    )
  )))
  expect_error(
    context_fork_test_value(list(ambiguous)),
    class = "deputy_context_fork_error"
  )
  ambiguous$props$contents[[1L]]$deputy_value_kind <- "marked"
  ambiguous$props$contents[[1L]]$deputy_content_paths <- list()
  expect_error(
    context_fork_test_value(list(ambiguous)),
    class = "deputy_context_fork_error"
  )
})

test_that("record-shaped tool values remain ordinary data", {
  request <- ellmer::ContentToolRequest(
    id = "ordinary-record",
    name = "inspect",
    arguments = list()
  )
  ordinary <- list(
    version = 1L,
    class = "ellmer::ContentText",
    props = list(text = "ordinary value")
  )
  request_record <- ellmer::contents_record(
    ellmer::AssistantTurn(list(request))
  )
  result_record <- ellmer::contents_record(
    ellmer::UserTurn(list(
      ellmer::ContentToolResult(value = ordinary, request = request)
    ))
  )

  fork <- context_fork_test_value(list(request_record, result_record))
  value <- context_fork_replay(fork)[[2L]]@contents[[1L]]@value
  expect_true(is.list(value))
  expect_identical(value$class, "ellmer::ContentText")
  expect_identical(value$props$text, "ordinary value")
})

test_that("fork preflight does not dispatch hostile provider length methods", {
  hostile <- structure("provider-private", class = "context_fork_hostile")
  result <- ellmer::ContentToolResult(
    value = hostile,
    request = ellmer::ContentToolRequest(
      id = "orphan-hostile",
      name = "inspect",
      arguments = list()
    )
  )

  expect_no_error({
    fork <- context_fork_test_value(list(ellmer::UserTurn(list(result))))
  })
  text <- fork$turns[[1L]]$props$contents[[1L]]$props$text
  expect_match(text, "Unsupported tool payload omitted", fixed = TRUE)
})

test_that("settled tool request and result retain native public types", {
  request <- ellmer::ContentToolRequest(
    id = "call-1",
    name = "read_file",
    arguments = list(path = "inside")
  )
  result <- ellmer::ContentToolResult(
    value = "safe evidence",
    request = request
  )
  fork <- context_fork_test_value(list(
    ellmer::AssistantTurn(list(request)),
    ellmer::UserTurn(list(result))
  ))

  expect_identical(
    fork$turns[[1]]$props$contents[[1]]$class,
    "ellmer::ContentToolRequest"
  )
  expect_identical(
    fork$turns[[2]]$props$contents[[1]]$class,
    "ellmer::ContentToolResult"
  )
  replayed <- context_fork_replay(fork)
  expect_null(replayed[[1]]@contents[[1]]@tool)
  expect_identical(
    replayed[[2]]@contents[[1]]@request@id,
    "call-1"
  )
})

test_that("settled multi-call tool rounds retain all native request and result types", {
  request_a <- ellmer::ContentToolRequest(
    id = "call-a",
    name = "read_a",
    arguments = list(path = "a")
  )
  request_b <- ellmer::ContentToolRequest(
    id = "call-b",
    name = "read_b",
    arguments = list(path = "b")
  )
  result_a <- ellmer::ContentToolResult(value = "a", request = request_a)
  result_b <- ellmer::ContentToolResult(value = "b", request = request_b)
  fork <- context_fork_test_value(list(
    ellmer::AssistantTurn(list(request_a, request_b)),
    ellmer::UserTurn(list(result_a, result_b))
  ))

  expect_true(all(vapply(
    fork$turns[[1L]]$props$contents,
    function(content) identical(content$class, "ellmer::ContentToolRequest"),
    logical(1)
  )))
  expect_true(all(vapply(
    fork$turns[[2L]]$props$contents,
    function(content) identical(content$class, "ellmer::ContentToolResult"),
    logical(1)
  )))
})

test_that("reversed result order in an adjacent tool round remains native", {
  request_a <- ellmer::ContentToolRequest(
    id = "call-a",
    name = "read_a",
    arguments = list(path = "a")
  )
  request_b <- ellmer::ContentToolRequest(
    id = "call-b",
    name = "read_b",
    arguments = list(path = "b")
  )
  result_a <- ellmer::ContentToolResult(value = "a", request = request_a)
  result_b <- ellmer::ContentToolResult(value = "b", request = request_b)
  fork <- context_fork_test_value(list(
    ellmer::AssistantTurn(list(request_a, request_b)),
    ellmer::UserTurn(list(result_b, result_a))
  ))

  expect_identical(
    all(vapply(
      c(fork$turns[[1L]]$props$contents, fork$turns[[2L]]$props$contents),
      function(content) !identical(content$class, "ellmer::ContentText"),
      logical(1)
    )),
    TRUE
  )
  expect_identical("partial_tool_evidence" %in% fork$omissions, FALSE)
})

test_that("non-adjacent tool rounds become inert evidence", {
  request <- ellmer::ContentToolRequest(
    id = "call-a",
    name = "read_a",
    arguments = list(path = "a")
  )
  result <- ellmer::ContentToolResult(value = "a", request = request)
  fork <- context_fork_test_value(list(
    ellmer::AssistantTurn(list(request)),
    ellmer::AssistantTurn(list(ellmer::ContentText("intervening"))),
    ellmer::UserTurn(list(result))
  ))

  expect_identical(
    all(vapply(
      c(
        fork$turns[[1L]]$props$contents,
        fork$turns[[3L]]$props$contents
      ),
      function(content) identical(content$class, "ellmer::ContentText"),
      logical(1)
    )),
    TRUE
  )
  expect_identical("partial_tool_evidence" %in% fork$omissions, TRUE)
})

test_that("fork_agent selects the host branch and keeps source divergence isolated", {
  source <- list(
    create_mock_user_turn("source question"),
    create_mock_assistant_turn("source answer")
  )
  fixture <- context_fork_test_agents(parent_turns = source)
  fork <- context_fork_test_value(
    fixture$parent$get_turns(),
    branch = "branch-b",
    revision = "revision-b"
  )
  seen <- NULL
  authorize <- function(meta) {
    seen <<- meta
    # Receipt field order is transport-specific; the names and values are
    # exact, but Deputy canonicalizes the order before comparison.
    list(
      revision = meta$revision,
      branch_id = meta$branch_id,
      owner_id = meta$owner_id,
      conversation_id = meta$conversation_id
    )
  }

  handle <- fork_agent(
    fixture$parent,
    fixture$child,
    fork,
    authorize,
    UsageLimits(max_requests = 2L)
  )
  fixture$parent$set_turns(list(create_mock_user_turn("parent changed")))

  expect_identical(seen$branch_id, "branch-b")
  expect_identical(seen$revision, "revision-b")
  expect_identical(
    fixture$child$get_turns()[[1]]@contents[[1]]@text,
    "source question"
  )
  expect_identical(
    fixture$parent$.__enclos_env__$private$owned_conversations[[
      handle
    ]]$fork$branch_id,
    "branch-b"
  )
})

test_that("stale or denied authorization leaves the child and owner unchanged", {
  fixture <- context_fork_test_agents()
  fork <- context_fork_test_value(list(create_mock_user_turn("source")))
  before <- fixture$child$get_turns()

  expect_error(
    fork_agent(
      fixture$parent,
      fixture$child,
      fork,
      function(meta) {
        list(
          owner_id = meta$owner_id,
          conversation_id = meta$conversation_id,
          branch_id = meta$branch_id,
          revision = "old-revision"
        )
      },
      UsageLimits(max_requests = 1L)
    ),
    class = "deputy_context_fork_error"
  )
  expect_identical(fixture$child$get_turns(), before)
  expect_length(fixture$parent$.__enclos_env__$private$owned_conversations, 0L)

  expect_error(
    fork_agent(
      fixture$parent,
      fixture$child,
      fork,
      function(meta) FALSE,
      UsageLimits(max_requests = 1L)
    ),
    class = "deputy_context_fork_error"
  )
  expect_identical(fixture$child$get_turns(), before)
  expect_length(fixture$parent$.__enclos_env__$private$owned_conversations, 0L)
})

test_that("parent ownership denial wins before source authorization", {
  fixture <- context_fork_test_agents()
  middle <- Agent$new(chat = create_mock_chat())
  retained <- fixture$parent$retain_agent(
    middle,
    UsageLimits(max_requests = 1L)
  )
  calls <- 0L
  fork <- context_fork_test_value(list(create_mock_user_turn("source")))

  expect_error(
    fork_agent(
      middle,
      fixture$child,
      fork,
      function(meta) {
        calls <<- calls + 1L
        context_fork_test_authorize(meta)
      },
      UsageLimits(max_requests = 1L)
    ),
    class = "deputy_conversation"
  )
  expect_identical(calls, 0L)
  fixture$parent$release_agent(retained)
})

test_that("fork manifest and retained follow-ups keep authorization and context", {
  fixture <- context_fork_test_agents(
    responses = list("first response", "second response"),
    parent_turns = list(create_mock_user_turn("source"))
  )
  fork <- context_fork_test_value(fixture$parent$get_turns())
  calls <- 0L
  authorize <- function(meta) {
    calls <<- calls + 1L
    context_fork_test_authorize(meta)
  }
  handle <- fork_agent(
    fixture$parent,
    fixture$child,
    fork,
    authorize,
    UsageLimits(max_requests = 3L),
    max_runs = 2L
  )

  fixture$parent$continue_agent(
    handle,
    "first follow-up",
    UsageLimits(max_requests = 1L)
  )
  fixture$parent$continue_agent(
    handle,
    "second follow-up",
    UsageLimits(max_requests = 1L)
  )
  manifest <- fixture$parent$get_subagent_contexts(view = "initial")[[1L]]
  entry <- fixture$parent$.__enclos_env__$private$owned_conversations[[handle]]

  expect_identical(calls, 3L)
  expect_identical(manifest$policies$fork$branch_id, "branch-a")
  expect_identical(manifest$policies$fork$revision, "revision-1")
  expect_identical(manifest$policies$fork$view, "transcript")
  expect_length(entry$ids, 2L)
  expect_identical(entry$busy, FALSE)
})

test_that("a retained fork uses an independent real ellmer Chat history", {
  server <- local_runtime_server(list(runtime_reply("child reply")))
  parent <- Agent$new(runtime_chat(server))
  child <- Agent$new(runtime_chat(server))
  parent$set_turns(list(create_mock_user_turn("source question")))
  fork <- context_fork_test_value(parent$get_turns(), branch = "branch-real")

  handle <- fork_agent(
    parent,
    child,
    fork,
    context_fork_test_authorize,
    UsageLimits(max_requests = 1L)
  )
  parent$set_turns(list(create_mock_user_turn("parent divergence")))
  result <- parent$continue_agent(
    handle,
    "child follow-up",
    UsageLimits(max_requests = 1L)
  )

  expect_match(result$response, "child reply")
  expect_length(server$requests(), 1L)
  body <- server$requests()[[1L]]$body
  messages <- jsonlite::toJSON(body$messages, auto_unbox = TRUE)
  expect_match(messages, "source question")
  expect_match(messages, "child follow-up")
  expect_identical(grepl("parent divergence", messages, fixed = TRUE), FALSE)
  expect_match(child$turns()[[1L]]@contents[[1L]]@text, "source question")
  expect_match(
    parent$get_turns()[[1L]]@contents[[1L]]@text,
    "parent divergence"
  )
})

test_that("authorization is rechecked before admitting a follow-up", {
  fixture <- context_fork_test_agents()
  fork <- context_fork_test_value(list(create_mock_user_turn("source")))
  allowed <- TRUE
  authorize <- function(meta) {
    if (!allowed) {
      return(FALSE)
    }
    context_fork_test_authorize(meta)
  }
  handle <- fork_agent(
    fixture$parent,
    fixture$child,
    fork,
    authorize,
    UsageLimits(max_requests = 2L)
  )
  allowed <- FALSE

  expect_error(
    fixture$parent$continue_agent(
      handle,
      "denied follow-up",
      UsageLimits(max_requests = 1L)
    ),
    class = "deputy_context_fork_error"
  )
  entry <- fixture$parent$.__enclos_env__$private$owned_conversations[[handle]]
  expect_identical(entry$busy, FALSE)
  expect_length(entry$ids, 0L)
})
