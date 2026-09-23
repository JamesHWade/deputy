# Per-request usage, token-count and tool-context probes avoid repeated
# failing calls without changing what callers observe.

probe_chat <- function(provider = NULL) {
  if (is.null(provider)) {
    return(ellmer::chat_openai_compatible(
      base_url = "http://127.0.0.1:9",
      credentials = function() "fixture",
      model = "fixture-model",
      echo = "none"
    ))
  }
  ellmer::Chat$new(provider = provider, model = "fixture-model")
}

probe_user <- function(text = "hi") {
  ellmer::UserTurn(list(ellmer::ContentText(text)))
}

probe_assistant <- function(input = 10, output = 5, cost = 0.01) {
  ellmer::AssistantTurn(
    list(ellmer::ContentText("ok")),
    tokens = c(input, output, 0),
    cost = cost
  )
}

probe_tool_result_turn <- function() {
  request <- ellmer::ContentToolRequest(id = "call_1", name = "t")
  ellmer::UserTurn(list(ellmer::ContentToolResult("done", request = request)))
}

local_ellmer_observations <- function(env = parent.frame()) {
  saved <- as.list(ellmer_observations, all.names = TRUE)
  rm(
    list = ls(ellmer_observations, all.names = TRUE),
    envir = ellmer_observations
  )
  withr::defer(
    {
      rm(
        list = ls(ellmer_observations, all.names = TRUE),
        envir = ellmer_observations
      )
      list2env(saved, envir = ellmer_observations)
    },
    envir = env
  )
}

uncached_usage_summary <- function(chat) {
  provider_usage_summary_for(chat, chat$get_turns(), FALSE)
}

test_that("usage summaries are reused only while the turn list is unchanged", {
  chat <- probe_chat()
  chat$set_turns(list(probe_user(), probe_assistant(10, 5, 0.01)))
  computed <- 0L
  real <- provider_usage_summary_for
  local_mocked_bindings(
    provider_usage_summary_for = function(...) {
      computed <<- computed + 1L
      real(...)
    }
  )

  first <- provider_usage_summary(chat)
  second <- provider_usage_summary(chat)
  expect_identical(second, first)
  expect_identical(computed, 1L)
  expect_identical(first$requests, 1L)
  expect_equal(first$input, 10)

  # Appending a turn changes the length.
  chat$set_turns(c(
    chat$get_turns(),
    list(probe_user("again"), probe_assistant(20, 7, 0.02))
  ))
  appended <- provider_usage_summary(chat)
  expect_identical(computed, 2L)
  expect_identical(appended$requests, 2L)
  expect_equal(appended$input, 30)
  expect_equal(appended$total, 0.03)

  # Replacing the last turn keeps the length but changes its identity.
  turns <- chat$get_turns()
  turns[[4L]] <- probe_assistant(40, 7, 0.02)
  chat$set_turns(turns)
  replaced <- provider_usage_summary(chat)
  expect_identical(computed, 3L)
  expect_equal(replaced$input, 50)

  # Replacing an earlier turn is detected as well.
  turns <- chat$get_turns()
  turns[[2L]] <- probe_assistant(1, 5, NA_real_)
  chat$set_turns(turns)
  earlier <- provider_usage_summary(chat)
  expect_identical(computed, 4L)
  expect_equal(earlier$input, 41)
  expect_false(earlier$complete)

  expect_identical(provider_usage_summary(chat), earlier)
  expect_identical(computed, 4L)
  expect_identical(earlier, uncached_usage_summary(chat))
})

test_that("usage summaries are not cached for replaced token methods", {
  chat <- probe_chat()
  chat$set_turns(list(probe_user(), probe_assistant()))
  reported <- 1
  rlang::env_binding_unlock(chat, "get_tokens")
  chat$get_tokens <- function() {
    data.frame(input = reported, output = 0, cached_input = 0, cost = 0)
  }

  expect_equal(provider_usage_summary(chat)$input, 1)
  reported <- 7
  expect_equal(provider_usage_summary(chat)$input, 7)
  expect_null(attr(chat, "deputy_usage_summary", exact = TRUE))
})

test_that("unpaired token tables use the same fallback once observed", {
  local_ellmer_observations()
  shapes <- list(
    list(probe_user(), probe_assistant(10, 5, 0.01), probe_tool_result_turn()),
    list(
      probe_user(),
      probe_assistant(10, 5, 0.01),
      probe_tool_result_turn(),
      probe_assistant(3, 2, NA_real_),
      probe_tool_result_turn()
    )
  )
  expected <- lapply(shapes, function(turns) {
    chat <- probe_chat()
    chat$set_turns(turns)
    expect_error(chat$get_tokens())
    uncached_usage_summary(chat)
  })
  expect_null(ellmer_observations$token_table)

  for (index in seq_along(shapes)) {
    chat <- probe_chat()
    chat$set_turns(shapes[[index]])
    expect_identical(provider_usage_summary(chat), expected[[index]])
  }
  expect_true(ellmer_observations$token_table$unpaired_fails)
  expect_true(ellmer_token_table_fails(shapes[[2L]]))

  # With the observation in place, get_tokens() is no longer called for an
  # unpaired history (so no failure is observed), and the result is unchanged.
  observed <- 0L
  real_observe <- ellmer_token_table_observe
  local_mocked_bindings(
    ellmer_token_table_observe = function(...) {
      observed <<- observed + 1L
      real_observe(...)
    }
  )
  chat <- probe_chat()
  chat$set_turns(shapes[[2L]])
  expect_identical(provider_usage_summary(chat), expected[[2L]])
  expect_identical(observed, 0L)

  # Paired histories are still read from ellmer's own table.
  paired <- probe_chat()
  paired$set_turns(list(probe_user(), probe_assistant(10, 5, 0.01)))
  expect_false(ellmer_token_table_fails(paired$get_turns()))
  expect_identical(
    provider_usage_summary(paired),
    uncached_usage_summary(paired)
  )
})

test_that("an observation is ignored for a different get_tokens method", {
  local_ellmer_observations()
  turns <- list(probe_user(), probe_assistant(), probe_tool_result_turn())
  ellmer_observations$token_table <- list(
    unpaired_fails = TRUE,
    body = quote(stop("another ellmer"))
  )
  expect_false(ellmer_token_table_fails(turns))
})

test_that("providers that cannot count tokens are probed once", {
  local_ellmer_observations()
  provider <- create_mock_provider()
  chat <- probe_chat(provider)
  chat$set_turns(list(probe_user(), probe_assistant()))
  agent <- Agent$new(chat = chat)
  count <- function() {
    agent$.__enclos_env__$private$context_token_count(list("hello"))
  }
  failures <- 0L
  real_observe <- ellmer_token_count_observe
  local_mocked_bindings(
    ellmer_token_count_observe = function(...) {
      failures <<- failures + 1L
      real_observe(...)
    }
  )

  expect_null(count())
  expect_identical(failures, 1L)
  expect_true(
    ellmer_token_count_unsupported(agent$.__enclos_env__$private$.chat)
  )
  expect_null(count())
  expect_null(count())
  expect_identical(failures, 1L)

  # Other provider classes are still asked.
  counting <- ellmer::chat_openai(
    base_url = "http://127.0.0.1:9",
    credentials = function() "fixture",
    model = "fixture-model",
    echo = "none"
  )
  expect_false(ellmer_token_count_unsupported(counting))

  # Replacement token counters are always called, whatever their provider.
  replaced <- probe_chat(provider)
  rlang::env_binding_unlock(replaced, "token_count")
  replaced$token_count <- function(...) 42
  expect_false(ellmer_token_count_unsupported(replaced))
  expect_identical(chat_token_count(replaced, list("hello")), 42)
})

test_that("token-count observations expire when namespaces change", {
  local_ellmer_observations()
  chat <- probe_chat(create_mock_provider())
  expect_null(chat_token_count(chat, list("hello")))
  expect_true(ellmer_token_count_unsupported(chat))

  observed <- ellmer_observations$token_count
  observed$namespaces <- c(observed$namespaces, "deputy.not.loaded")
  ellmer_observations$token_count <- observed
  expect_false(ellmer_token_count_unsupported(chat))
})

test_that("other token-count failures are not recorded as unsupported", {
  local_ellmer_observations()
  chat <- probe_chat()
  chat$set_turns(list(
    probe_user(),
    probe_assistant(),
    probe_tool_result_turn()
  ))
  expect_null(chat_token_count(chat, list("hello")))
  expect_null(ellmer_observations$token_count)
  expect_true(ellmer_observations$token_table$unpaired_fails)
  expect_false(ellmer_token_count_unsupported(chat))
})

test_that("nested R session context is read only inside Deputy's extent", {
  expect_null(r_session_tool_context())

  request <- ellmer::ContentToolRequest(id = "inner", name = "t")
  context <- structure(
    list(
      request = request,
      turns = list(),
      deputy_r_session_nested = TRUE,
      parent_tool_call_id = "parent",
      r_session_execution_id = "execution",
      r_session_generation = "generation"
    ),
    class = "ellmer_tool_context"
  )
  nested <- with_r_session_tool_context(context, r_session_tool_context())
  expect_identical(
    nested,
    list(
      parent_tool_call_id = "parent",
      execution_id = "execution",
      generation = "generation"
    )
  )
  expect_identical(r_session_nested_contexts$depth, 0L)

  # An ordinary tool context inside the extent is not a nested request.
  inner <- with_r_session_tool_context(
    context,
    ellmer::with_tool_context(
      list(request = request, turns = list()),
      r_session_tool_context()
    )
  )
  expect_null(inner)

  expect_error(
    with_r_session_tool_context(context, stop("boom")),
    "boom"
  )
  expect_identical(r_session_nested_contexts$depth, 0L)
  expect_null(r_session_tool_context())
})
