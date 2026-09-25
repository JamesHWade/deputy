# When a provider cannot count tokens, automatic compaction estimates context
# size locally: the last reported usage plus conservative character counts.

not_found_response <- function() {
  list(
    status = 404L,
    headers = list("Content-Type" = "application/json"),
    body = '{ "statusCode": 404, "message": "Resource not found" }'
  )
}

# ellmer's ProviderOpenAI, whose token counting endpoint is absent here.
gateway_chat <- function(server) {
  ellmer::chat_openai(
    base_url = server$url,
    model = "gpt-4o-mini",
    credentials = function() "fixture",
    echo = "none"
  )
}

estimate_context <- function(agent, messages = list(), turns = NULL) {
  agent$.__enclos_env__$private$context_estimate(messages, turns = turns)
}

reported_turn <- function(text = "A", input = NA_real_, output = NA_real_) {
  create_mock_assistant_turn(text, tokens = c(input, output, 0))
}

tool_round <- function(input, output, result) {
  request <- ellmer::ContentToolRequest(
    id = "call_1",
    name = "lookup",
    arguments = list(query = "status")
  )
  list(
    ellmer::AssistantTurn(
      list(request),
      tokens = c(input, output, 0),
      cost = NA_real_
    ),
    ellmer::UserTurn(list(ellmer::ContentToolResult(result, request = request)))
  )
}

compaction_starts <- function(agent) {
  Filter(
    function(event) identical(event$type, "compaction_start"),
    agent$last_run()$events
  )
}

test_that("ContextPolicy selects how context size is estimated", {
  expect_identical(ContextPolicy()$estimator, "auto")
  expect_identical(ContextPolicy(estimator = "provider")$estimator, "provider")
  expect_error(ContextPolicy(estimator = "characters"))
  policy <- ContextPolicy(estimator = "provider")
  expect_identical(
    do.call(ContextPolicy, S7::props(policy))$estimator,
    "provider"
  )
  expect_output(print(policy), "estimator: provider")
})

test_that("a missing token-count endpoint is probed once per base URL", {
  local_ellmer_observations()
  withr::local_options(ellmer_max_tries = 1)
  server <- local_runtime_server(list(not_found_response()))
  chat <- gateway_chat(server)
  chat$set_turns(list(create_mock_user_turn("Q1"), reported_turn("A1", 50, 5)))

  expect_null(chat_token_count(chat, list("hello")))
  expect_length(server$requests(), 1L)
  expect_match(server$requests()[[1]]$path, "responses/input_tokens$")
  expect_true(ellmer_token_count_unsupported(chat))

  agent <- Agent$new(chat = chat)
  estimate <- estimate_context(agent, list("hello"))
  expect_identical(estimate$source, "estimate")
  estimate_context(agent, list("hello"), turns = chat$get_turns())
  expect_length(server$requests(), 1L)

  # The same provider class at another endpoint may count tokens.
  other <- local_runtime_server(list(not_found_response()))
  other_chat <- gateway_chat(other)
  expect_false(ellmer_token_count_unsupported(other_chat))
  expect_null(chat_token_count(other_chat, list("hello")))
  expect_length(other$requests(), 1L)
})

test_that("other token-count HTTP failures are not cached", {
  local_ellmer_observations()
  withr::local_options(ellmer_max_tries = 1)
  server <- local_runtime_server(list(runtime_failure(500L)))
  chat <- gateway_chat(server)
  expect_null(chat_token_count(chat, list("hello")))
  expect_false(ellmer_token_count_unsupported(chat))
  expect_null(chat_token_count(chat, list("hello")))
  expect_length(server$requests(), 2L)
})

test_that("the auto estimate adds later content to the last reported usage", {
  local_ellmer_observations()
  withr::local_options(ellmer_max_tries = 1)
  server <- local_runtime_server(list(not_found_response()))
  chat <- gateway_chat(server)
  result <- strrep("x", 3000)
  chat$set_turns(c(
    list(create_mock_user_turn("Q1")),
    tool_round(input = 5000, output = 200, result = result)
  ))
  agent <- Agent$new(chat = chat)

  estimate <- estimate_context(agent, list("Continue"))
  expect_identical(estimate$source, "estimate")
  # Reported input and output, then at least one token per three characters.
  expect_gte(estimate$tokens, 5200 + 3000 / 3)
  expect_lt(estimate$tokens, 5200 + 3000 / 3 + 100)

  provider_only <- Agent$new(
    chat = chat,
    context_policy = ContextPolicy(estimator = "provider")
  )
  expect_null(estimate_context(provider_only, list("Continue")))
})

test_that("auto compaction triggers from reported usage and pending content", {
  run_with <- function(max_tokens, estimator = "auto") {
    chat <- create_mock_chat(list("done"))
    # About 5,000 tokens of question text, which the usage also reports.
    chat$set_turns(list(
      create_mock_user_turn(strrep("q", 15000)),
      reported_turn("A1", input = 5000, output = 200)
    ))
    agent <- Agent$new(
      chat = chat,
      context_policy = ContextPolicy(
        max_tokens = max_tokens,
        fallback = "text",
        estimator = estimator
      )
    )
    suppressWarnings(agent$run_sync(strrep("y", 1500)))
    agent
  }

  below <- run_with(6000)
  expect_null(below$last_compaction())
  expect_length(compaction_starts(below), 0L)

  # 5,200 reported plus 500 pending exceeds 5,600; characters alone do not.
  above <- run_with(5600)
  compaction <- above$last_compaction()
  expect_s7_class(compaction, DeputyCompaction)
  expect_true(compaction$automatic)
  expect_identical(compaction$method, "text")
  expect_gte(compaction$estimated_tokens, 5200 + 500)
  start <- compaction_starts(above)
  expect_length(start, 1L)
  expect_identical(start[[1]]$estimate_source, "estimate")

  # The provider estimator keeps today's behaviour: no count, no compaction.
  provider_only <- run_with(5600, estimator = "provider")
  expect_null(provider_only$last_compaction())
})

test_that("without reported usage the character estimate drives compaction", {
  chat <- create_mock_chat(list("done"))
  chat$set_system_prompt(strrep("s", 300))
  chat$set_turns(list(
    create_mock_user_turn(strrep("q", 30000)),
    reported_turn("A1")
  ))
  agent <- Agent$new(
    chat = chat,
    context_policy = ContextPolicy(max_tokens = 5000, fallback = "text")
  )
  estimate <- estimate_context(agent, list("Continue"))
  expect_identical(estimate$source, "estimate")
  expect_gte(estimate$tokens, (300 + 30000) / 3)

  suppressWarnings(agent$run_sync("Continue"))
  compaction <- agent$last_compaction()
  expect_s7_class(compaction, DeputyCompaction)
  expect_gte(compaction$estimated_tokens, 10000)
})

test_that("estimates of a kept subset ignore reported usage", {
  chat <- create_mock_chat(list("done"))
  turns <- list(
    create_mock_user_turn(strrep("q", 15000)),
    reported_turn("A1", input = 5000, output = 10),
    create_mock_user_turn("Q2"),
    reported_turn("A2", input = 5020, output = 10)
  )
  chat$set_turns(turns)
  agent <- Agent$new(
    chat = chat,
    context_policy = ContextPolicy(
      max_tokens = 4000,
      compact_to = 0.5,
      fallback = "text"
    )
  )
  subset <- estimate_context(agent, list(), turns = turns[3:4])
  expect_identical(subset$source, "estimate")
  expect_lt(subset$tokens, 100)
  expect_gt(estimate_context(agent, list())$tokens, 5000)

  suppressWarnings(agent$run_sync("Continue"))
  compaction <- agent$last_compaction()
  expect_s7_class(compaction, DeputyCompaction)
  expect_identical(compaction$turns_compacted, 2L)
  expect_identical(compaction$turns_kept, 2L)
})

test_that("usage reported before compaction is not reused afterwards", {
  chat <- create_mock_chat(list("done"))
  chat$set_turns(list(
    create_mock_user_turn(strrep("q", 15000)),
    reported_turn("A1", input = 5000, output = 10),
    create_mock_user_turn("Q2"),
    reported_turn("A2", input = 5020, output = 10)
  ))
  agent <- Agent$new(
    chat = chat,
    context_policy = ContextPolicy(max_tokens = 4000, fallback = "text")
  )
  suppressWarnings(agent$run_sync("Continue"))
  expect_identical(agent$last_compaction()$turns_kept, 2L)
  expect_length(agent$get_context_turns(), 2L)

  # The kept assistant turn still reports its pre-compaction input.
  after <- estimate_context(agent, list("Continue"))
  expect_identical(after$source, "estimate")
  expect_lt(after$tokens, 4000)

  path <- withr::local_tempfile(fileext = ".rds")
  suppressMessages(agent$save_session(path))
  restored <- Agent$new(
    chat = create_mock_chat(list("done")),
    context_policy = ContextPolicy(max_tokens = 4000, fallback = "text")
  )
  suppressMessages(restored$load_session(path))
  expect_lt(estimate_context(restored, list("Continue"))$tokens, 4000)

  # Host-selected history is trusted again.
  restored$set_turns(agent$get_context_turns())
  expect_gt(estimate_context(restored, list("Continue"))$tokens, 5000)
})

test_that("providers that can count tokens keep their own count", {
  chat <- create_mock_chat(list("done"))
  chat$token_count <- function(..., include = c("new", "complete")) 90
  chat$set_turns(list(
    create_mock_user_turn("Q1"),
    reported_turn("A1", input = 5000, output = 200)
  ))
  agent <- Agent$new(
    chat = chat,
    context_policy = ContextPolicy(max_tokens = 1000, fallback = "text")
  )
  estimate <- estimate_context(agent, list("Continue"))
  expect_identical(estimate, list(tokens = 90, source = "provider"))
  suppressWarnings(agent$run_sync("Continue"))
  expect_null(agent$last_compaction())
})

test_that("local estimates count tool arguments, results and images", {
  request <- ellmer::ContentToolRequest(
    id = "call_1",
    name = "lookup",
    arguments = list(query = strrep("a", 300))
  )
  expect_gte(estimate_content_tokens(request), 100)
  structured <- ellmer::ContentToolResult(
    list(rows = strrep("b", 600)),
    request = request
  )
  expect_gte(estimate_content_tokens(structured), 200)
  failed <- ellmer::ContentToolResult(
    error = simpleError(strrep("c", 300)),
    request = request
  )
  expect_gte(estimate_content_tokens(failed), 100)
  image <- ellmer::ContentImageRemote("https://example.invalid/plot.png")
  expect_identical(
    estimate_content_tokens(image),
    context_estimate_image_tokens
  )
  native <- ellmer::ContentToolResult(list(image, image), request = request)
  expect_identical(
    estimate_content_tokens(native),
    2 * context_estimate_image_tokens
  )
  expect_identical(estimate_content_tokens(list("abc", "def")), 2)
})

test_that("text is estimated from UTF-8 bytes, so CJK and emoji are not under-counted", {
  expect_identical(estimate_text_tokens(strrep("x", 900)), 300)
  # One CJK character can be a whole token; three bytes each keeps the
  # estimate at one token per character or more.
  expect_gte(estimate_text_tokens(strrep("漢", 900)), 900)
  expect_gte(estimate_text_tokens(strrep("\U0001F600", 300)), 300)
})

test_that("prompt and tool growth after a reported response is added to its usage", {
  local_ellmer_observations()
  withr::local_options(ellmer_max_tries = 1)
  server <- local_runtime_server(list(
    not_found_response(),
    not_found_response()
  ))
  chat <- gateway_chat(server)
  chat$set_turns(list(
    create_mock_user_turn("Q1"),
    reported_turn("A1", input = 5000, output = 100)
  ))
  agent <- Agent$new(chat = chat)
  # The estimate before the next request records the prompt and tools it
  # will carry.
  before <- estimate_context(agent, list("Q2"))
  expect_identical(before$source, "estimate")
  # That request completes with usage covering the prompt as it was.
  chat$add_turn(
    create_mock_user_turn("Q2"),
    reported_turn("A2", input = 5200, output = 100)
  )
  steady <- estimate_context(agent, list("Q3"))
  expect_lt(steady$tokens, 5300 + 100)

  # The host then enlarges the system prompt and adds a tool.
  chat$set_system_prompt(strrep("Always cite sources. ", 300))
  chat$register_tool(ellmer::tool(
    function(query) query,
    name = "wide_search",
    description = strrep("Search everything. ", 100),
    arguments = list(query = ellmer::type_string("Query"))
  ))
  grown <- estimate_context(agent, list("Q3"))
  growth <- estimate_text_tokens(strrep("Always cite sources. ", 300))
  expect_gte(grown$tokens - steady$tokens, growth)
})

test_that("a replaced conversation forgets earlier frame records", {
  local_ellmer_observations()
  withr::local_options(ellmer_max_tries = 1)
  server <- local_runtime_server(list(not_found_response()))
  chat <- gateway_chat(server)
  chat$set_turns(list(
    create_mock_user_turn("Q1"),
    reported_turn("A1", input = 5000, output = 100)
  ))
  agent <- Agent$new(chat = chat)
  estimate_context(agent, list("Q2"))
  private <- agent$.__enclos_env__$private
  expect_length(private$.frame_snapshots, 1L)
  agent$set_turns(chat$get_turns())
  expect_length(private$.frame_snapshots, 0L)
})
