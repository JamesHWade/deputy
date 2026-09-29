host_controls_tool <- function(name = "lookup") {
  ellmer::tool(
    function() "ok",
    name = name,
    description = "Look something up.",
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE
    )
  )
}

test_that("set_chat() moves the prompt, history and tools to the new Chat", {
  old <- ellmer::chat_openai(
    model = "gpt-4o-mini",
    credentials = function() "unused"
  )
  old$set_turns(list(
    ellmer::UserTurn(list(ellmer::ContentText("Question"))),
    ellmer::AssistantTurn(
      list(
        ellmer::ContentThinking("provider reasoning"),
        ellmer::ContentText("Answer")
      ),
      tokens = c(10, 5, 0)
    )
  ))
  agent <- Agent$new(
    old,
    tools = list(host_controls_tool()),
    system_prompt = "Be brief."
  )
  new <- ellmer::chat_anthropic(
    model = "claude-sonnet-4-5",
    credentials = function() "unused"
  )

  expect_invisible(agent$set_chat(new))

  expect_identical(new$get_system_prompt(), "Be brief.")
  turns <- agent$get_turns()
  expect_length(turns, 2L)
  expect_length(turns[[2]]@contents, 1L)
  expect_s3_class(turns[[2]]@contents[[1]], "ellmer::ContentText")
  expect_identical(turns[[2]]@contents[[1]]@text, "Answer")
  expect_named(new$get_tools(), "lookup")
  expect_length(old$get_tools(), 0L)
  expect_identical(agent$get_model(), "claude-sonnet-4-5")
  expect_identical(agent$set_chat(new), agent)
})

test_that("runs after set_chat() use the new Chat under the same governance", {
  withr::local_options(ellmer_max_tries = 1)
  first <- local_runtime_server(list(runtime_reply("first answer")))
  second <- local_runtime_server(list(
    runtime_reply(tool = "effect"),
    runtime_reply("second answer")
  ))
  effects <- 0L
  effect <- ellmer::tool(
    function() {
      effects <<- effects + 1L
      "changed"
    },
    name = "effect",
    description = "Change something."
  )
  agent <- Agent$new(
    runtime_chat(first, "first-model"),
    tools = list(effect),
    permissions = permissions_readonly()
  )
  requested <- character()
  agent$on_tool_request(function(request) {
    requested <<- c(requested, request@name)
  })
  expect_identical(trimws(agent$run_sync("one")$response), "first answer")

  agent$set_chat(runtime_chat(second, "second-model"))
  result <- suppressWarnings(agent$run_sync("two"))

  expect_identical(trimws(result$response), "second answer")
  # Read-only permissions still refuse the unannotated tool on the new Chat.
  expect_identical(effects, 0L)
  expect_identical(requested, "effect")
  expect_length(first$requests(), 1L)
  body <- second$requests()[[1]]$body
  expect_identical(body$model, "second-model")
  text <- vapply(
    body$messages,
    function(message) paste(unlist(message$content), collapse = ""),
    character(1)
  )
  # The earlier exchange is sent to the new provider, in order.
  expect_length(text, 3L)
  expect_match(text[[1]], "one", fixed = TRUE)
  expect_match(text[[2]], "first answer", fixed = TRUE)
  expect_match(text[[3]], "two", fixed = TRUE)
})

test_that("set_chat() refuses Chats and states it can't take over", {
  agent <- Agent$new(create_mock_chat())

  busy <- create_mock_chat()
  busy$set_turns(list(create_mock_user_turn("earlier")))
  expect_error(agent$set_chat(busy), "no conversation turns or tools")
  expect_error(agent$set_chat("chat"), class = "deputy_error")
  expect_error(
    agent$set_chat(Agent$new(create_mock_chat())),
    "not an Agent"
  )

  private <- agent$.__enclos_env__$private
  private$run_active <- TRUE
  expect_error(agent$set_chat(create_mock_chat()), "active run")
  private$run_active <- FALSE
  private$.pending_approval_path <- tempfile()
  expect_error(agent$set_chat(create_mock_chat()), "pending approval")
  private$.pending_approval_path <- NULL

  native <- Agent$new(
    create_mock_chat(),
    tools = list(ellmer::openai_tool_web_search()),
    permissions = Permissions(
      mode = "standard",
      web = TRUE,
      tool_allowlist = "web_search"
    )
  )
  expect_error(native$set_chat(create_mock_chat()), "Provider-native tools")
})

test_that("set_chat() rewires tool observers and leaves the old Chat inert", {
  old <- ellmer::chat_openai(
    model = "gpt-4o-mini",
    credentials = function() "unused"
  )
  agent <- Agent$new(old, tools = list(host_controls_tool()))
  agent$on_tool_result(function(result) NULL)
  old_private <- old$.__enclos_env__$private
  expect_gt(old_private$callback_on_tool_result$count(), 0L)

  new <- ellmer::chat_openai(
    model = "gpt-4o",
    credentials = function() "unused"
  )
  agent$set_chat(new)

  new_private <- new$.__enclos_env__$private
  expect_identical(old_private$callback_on_tool_request$count(), 0L)
  expect_identical(old_private$callback_on_tool_result$count(), 0L)
  # Deputy's own result callback plus the observer.
  expect_identical(new_private$callback_on_tool_result$count(), 2L)
  expect_gt(new_private$callback_on_tool_request$count(), 0L)
})

test_that("set_context_policy() replaces the policy but keeps offload_dir", {
  directory <- withr::local_tempdir()
  agent <- Agent$new(
    create_mock_chat(),
    context_policy = ContextPolicy(max_tokens = 1000L, offload_dir = directory)
  )

  expect_invisible(agent$set_context_policy(
    ContextPolicy(max_tokens = 5000L, offload_dir = directory)
  ))
  expect_identical(agent$context_policy$max_tokens, 5000L)

  expect_error(
    agent$set_context_policy(ContextPolicy(max_tokens = 5000L)),
    "same `offload_dir`"
  )
  expect_identical(agent$context_policy$max_tokens, 5000L)
  expect_error(
    agent$context_policy <- ContextPolicy(),
    "set_context_policy"
  )

  private <- agent$.__enclos_env__$private
  private$run_active <- TRUE
  expect_error(
    agent$set_context_policy(ContextPolicy(offload_dir = directory)),
    "active run"
  )
})

test_that("register_sub_agent() replaces a definition only when asked", {
  lead <- LeadAgent$new(
    chat = create_mock_chat(),
    sub_agents = list(agent_definition(
      name = "research",
      description = "Finds sources.",
      prompt = "Find sources."
    ))
  )
  updated <- agent_definition(
    name = "Research",
    description = "Finds and checks sources.",
    prompt = "Find and check sources.",
    tools = list(host_controls_tool())
  )

  expect_error(
    suppressMessages(lead$register_sub_agent(updated)),
    "already registered"
  )
  expect_error(
    lead$register_sub_agent(updated, replace = NA),
    "TRUE or FALSE"
  )

  expect_message(
    lead$register_sub_agent(updated, replace = TRUE),
    "Replaced sub-agent"
  )
  expect_identical(lead$available_sub_agents(), "research")
  expect_identical(
    lead$sub_agent_defs[[1]]$description,
    "Finds and checks sources."
  )
  expect_match(
    lead$get_system_prompt(),
    "Finds and checks sources.",
    fixed = TRUE
  )
  expect_no_match(
    lead$get_system_prompt(),
    "Finds sources.",
    fixed = TRUE
  )
})

test_that("stream methods reset a cancelled controller once the run starts", {
  controller <- ellmer::stream_controller()
  controller$cancel()
  agent <- Agent$new(create_mock_chat(list("streamed")))

  stream <- agent$stream_async("hello", controller = controller)
  expect_false(controller$cancelled)
  expect_identical(
    paste(unlist(collect_async_stream(stream)), collapse = ""),
    "streamed"
  )

  controller$cancel()
  generator <- agent$stream("again", controller = controller)
  expect_false(controller$cancelled)
  expect_identical(
    paste(unlist(coro::collect(generator)), collapse = ""),
    "streamed"
  )
})

test_that("a refused run leaves the controller of the active run alone", {
  controller <- ellmer::stream_controller()
  agent <- Agent$new(create_mock_chat())
  private <- agent$.__enclos_env__$private
  private$run_active <- TRUE
  controller$cancel()

  expect_error(
    agent$stream_async("hello", controller = controller),
    class = "deputy_run_active"
  )
  expect_true(controller$cancelled)
  private$run_active <- FALSE
})
