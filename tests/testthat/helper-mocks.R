# Shared test helpers for deputy

# Helper to create a current ellmer provider.
create_mock_provider <- function(
  name = "mock",
  model = "test-model",
  base_url = "https://example.invalid"
) {
  # ellmer's development version moved `model`, `params`, and `extra_args`
  # off `Provider`. Pass only the arguments the installed ellmer accepts so
  # the mocks build against both the CRAN and development APIs.
  args <- list(
    name = name,
    model = model,
    base_url = base_url,
    params = list(),
    extra_args = list(),
    extra_headers = character(),
    credentials = NULL
  )
  accepted <- names(formals(ellmer::Provider))
  if (utils::packageVersion("ellmer") >= "0.5.0") {
    accepted <- setdiff(accepted, c("model", "params", "extra_args"))
  }
  provider <- do.call(ellmer::Provider, args[names(args) %in% accepted])
  attr(provider, "mock_model") <- model
  provider
}

# The model name behind a mock provider, whichever ellmer API built it.
mock_provider_model <- function(provider) {
  attr(provider, "mock_model") %||%
    tryCatch(provider@model, error = function(e) "test-model")
}

# Helper to create a proper S7 AssistantTurn
# Uses ellmer's current constructors.
create_mock_assistant_turn <- function(
  text = "Hello!",
  contents = NULL,
  tokens = c(100, 50, 0),
  cost = 0.001
) {
  # If no contents provided, create a ContentText

  if (is.null(contents)) {
    contents <- list(ellmer::ContentText(text))
  }

  ellmer::AssistantTurn(
    contents = contents,
    tokens = tokens,
    cost = cost
  )
}

# Helper to create a proper S7 UserTurn
create_mock_user_turn <- function(text = "Hello") {
  ellmer::UserTurn(
    contents = list(ellmer::ContentText(text))
  )
}

# Helper to create a ContentToolRequest
create_mock_tool_request <- function(
  id = "call_123",
  name = "test_tool",
  arguments = list()
) {
  ellmer::ContentToolRequest(
    id = id,
    name = name,
    arguments = arguments
  )
}

# Helper to create an AssistantTurn with a tool request
create_mock_turn_with_tool_request <- function(
  tool_name = "test_tool",
  tool_args = list(),
  text = ""
) {
  tool_request <- create_mock_tool_request(
    id = paste0("call_", sample(1000:9999, 1)),
    name = tool_name,
    arguments = tool_args
  )

  contents <- list(tool_request)
  if (nchar(text) > 0) {
    contents <- c(list(ellmer::ContentText(text)), contents)
  }

  ellmer::AssistantTurn(
    contents = contents,
    tokens = c(100, 50, 0),
    cost = 0.001
  )
}

as_mock_async_stream <- function(stream) {
  coro::async_generator(function() {
    if (!is.function(stream)) {
      coro::yield(stream)
      return()
    }
    repeat {
      chunk <- stream()
      if (coro::is_exhausted(chunk)) {
        break
      }
      coro::yield(chunk)
    }
  })()
}

# Helper to create a mock Chat object for testing
# This avoids the need for real API calls
create_mock_chat <- function(responses = list("Hello!")) {
  response_idx <- 0
  turns <- list()
  tools <- list()
  system_prompt <- NULL
  tool_request_callback <- NULL
  tool_result_callback <- NULL
  provider <- create_mock_provider()

  # Create a simple mock that behaves like ellmer's Chat
  chat <- structure(
    list2env(
      list(
        chat = function(prompt = NULL) {
          response_idx <<- response_idx + 1
          if (response_idx > length(responses)) {
            response_idx <<- length(responses)
          }
          responses[[response_idx]]
        },
        stream = function(prompt = NULL) {
          response_idx <<- response_idx + 1
          if (response_idx > length(responses)) {
            response_idx <<- length(responses)
          }
          # Return an iterator that yields strings (agent expects strings, not ContentText)
          text <- responses[[response_idx]]
          yielded <- FALSE
          function() {
            if (yielded) {
              return(coro::exhausted())
            }
            yielded <<- TRUE
            text
          }
        },
        get_turns = function() turns,
        set_turns = function(new_turns) turns <<- new_turns,
        get_system_prompt = function() system_prompt,
        set_system_prompt = function(prompt) system_prompt <<- prompt,
        get_tools = function() tools,
        set_tools = function(new_tools) tools <<- new_tools,
        register_tool = function(tool) {
          tools[[tool@name]] <<- tool
        },
        register_tools = function(tool_list) {
          for (tool in tool_list) {
            tools[[tool@name]] <<- tool
          }
        },
        get_tokens = function() {
          data.frame(
            input = 100,
            output = 50,
            cached_input = 0,
            cost = 0.001
          )
        },
        get_provider = function() {
          provider
        },
        get_model = function() mock_provider_model(provider),
        last_turn = function(role = "assistant") {
          # Return a proper S7 AssistantTurn
          text <- responses[[min(response_idx, length(responses))]]
          create_mock_assistant_turn(text = text)
        },
        on_tool_request = function(callback) {
          tool_request_callback <<- callback
        },
        on_tool_result = function(callback) {
          tool_result_callback <<- callback
        },
        clone = function(deep = FALSE) {
          cloned <- create_mock_chat(responses = responses)
          cloned$set_turns(turns)
          cloned$set_system_prompt(system_prompt)
          if (length(tools) > 0) {
            cloned$register_tools(unname(tools))
          }
          cloned
        }
      ),
      parent = emptyenv()
    ),
    class = "Chat"
  )
  chat$stream_async <- function(
    prompt = NULL,
    tool_mode = c("concurrent", "sequential"),
    stream = c("text", "content"),
    controller = NULL
  ) {
    stream_args <- list(prompt)
    stream_formals <- names(formals(chat$stream))
    if ("stream" %in% stream_formals) {
      stream_args$stream <- match.arg(stream)
    }
    if ("controller" %in% stream_formals && !is.null(controller)) {
      stream_args$controller <- controller
    }
    as_mock_async_stream(do.call(chat$stream, stream_args))
  }
  chat
}

create_mock_callback_manager <- function(callbacks = list()) {
  state <- new.env(parent = emptyenv())
  state$callbacks <- stats::setNames(
    callbacks,
    as.character(seq_along(callbacks))
  )
  state$next_id <- length(callbacks) + 1L

  structure(
    list(
      add = function(callback) {
        id <- as.character(state$next_id)
        state$next_id <- state$next_id + 1L
        state$callbacks[[id]] <- callback
        invisible(function() {
          state$callbacks[[id]] <- NULL
          invisible(NULL)
        })
      },
      clear = function() {
        state$callbacks <- list()
        invisible(NULL)
      },
      count = function() length(state$callbacks),
      get_callbacks = function() state$callbacks,
      invoke = function(value) {
        for (callback in state$callbacks) {
          callback(value)
        }
        invisible(NULL)
      },
      clone = function() create_mock_callback_manager(state$callbacks)
    ),
    class = "CallbackManager"
  )
}

create_compaction_mock_chat <- function(
  responses = list("Hello!"),
  provider = create_mock_provider(
    name = "gateway",
    model = "test-model",
    base_url = "https://gateway.invalid"
  ),
  request_callbacks = list(),
  result_callbacks = list(),
  simulate_tool_activity = FALSE,
  chat_error = NULL,
  probe = new.env(parent = emptyenv())
) {
  build_chat <- function(
    turns,
    tools,
    system_prompt,
    request_manager,
    result_manager
  ) {
    response_idx <- 0L
    private <- new.env(parent = emptyenv())
    private$callback_on_tool_request <- request_manager
    private$callback_on_tool_result <- result_manager

    chat <- list(
      .__enclos_env__ = list(private = private),
      chat = function(prompt = NULL, echo = NULL) {
        probe$summary_call <- list(
          prompt = prompt,
          echo = echo,
          turns = turns,
          system_prompt = system_prompt,
          tools = tools,
          callback_counts = c(
            request = request_manager$count(),
            result = result_manager$count()
          ),
          provider = provider
        )
        if (!is.null(chat_error)) {
          stop(chat_error)
        }
        if (isTRUE(simulate_tool_activity)) {
          request_manager$invoke(list(
            name = "write_file",
            arguments = list(
              path = "../outside",
              content = "unexpected summary tool content"
            )
          ))
          result_manager$invoke(list(
            name = "write_file",
            value = "unexpected summary tool result"
          ))
        }
        response_idx <<- min(response_idx + 1L, length(responses))
        responses[[response_idx]]
      },
      stream = function(prompt = NULL) {
        response_idx <<- min(response_idx + 1L, length(responses))
        text <- responses[[response_idx]]
        yielded <- FALSE
        function() {
          if (yielded) {
            return(coro::exhausted())
          }
          yielded <<- TRUE
          text
        }
      },
      get_turns = function() turns,
      set_turns = function(new_turns) turns <<- new_turns,
      get_system_prompt = function() system_prompt,
      set_system_prompt = function(prompt) system_prompt <<- prompt,
      get_tools = function() tools,
      set_tools = function(new_tools) tools <<- new_tools,
      register_tool = function(tool) {
        tools[[tool@name]] <<- tool
      },
      register_tools = function(tool_list) {
        for (tool in tool_list) {
          tools[[tool@name]] <<- tool
        }
      },
      get_tokens = function() {
        data.frame(
          input = 100,
          output = 50,
          cached_input = 0,
          cost = 0.001
        )
      },
      get_provider = function() provider,
      get_model = function() mock_provider_model(provider),
      last_turn = function(role = "assistant") {
        text <- responses[[max(1L, response_idx)]]
        create_mock_assistant_turn(text = text)
      },
      on_tool_request = function(callback) {
        request_manager$add(callback)
      },
      on_tool_result = function(callback) {
        result_manager$add(callback)
      },
      callback_counts = function() {
        c(
          request = request_manager$count(),
          result = result_manager$count()
        )
      },
      clone = function(deep = FALSE) {
        probe$clone_calls <- (probe$clone_calls %||% 0L) + 1L
        probe$clone_deep <- deep
        cloned_request_manager <- if (isTRUE(deep)) {
          request_manager$clone()
        } else {
          request_manager
        }
        cloned_result_manager <- if (isTRUE(deep)) {
          result_manager$clone()
        } else {
          result_manager
        }
        build_chat(
          turns = turns,
          tools = tools,
          system_prompt = system_prompt,
          request_manager = cloned_request_manager,
          result_manager = cloned_result_manager
        )
      }
    )

    structure(chat, class = "Chat")
  }

  build_chat(
    turns = list(),
    tools = list(),
    system_prompt = NULL,
    request_manager = create_mock_callback_manager(request_callbacks),
    result_manager = create_mock_callback_manager(result_callbacks)
  )
}
