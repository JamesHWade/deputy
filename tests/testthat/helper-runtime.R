create_content_stream_chat <- function(
  tool_name = "read_file",
  tool_result = "contents",
  final_text = "done",
  execute = NULL
) {
  state <- new.env(parent = emptyenv())
  state$turns <- list()
  state$token_rows <- list()
  state$tools <- list()
  state$system_prompt <- NULL
  state$on_tool_request <- function(request) invisible(NULL)
  state$on_tool_result <- function(result) invisible(NULL)
  state$tool_executed <- FALSE

  tool <- ellmer::tool(
    fun = function(path) tool_result,
    name = tool_name,
    description = "Read a test file.",
    arguments = list(path = ellmer::type_string("File path"))
  )

  add_assistant_turn <- function(contents, input, output, cost) {
    state$turns <- c(
      state$turns,
      list(ellmer::AssistantTurn(
        contents = contents,
        tokens = c(input, output, 0),
        cost = cost
      ))
    )
    state$token_rows <- c(
      state$token_rows,
      list(data.frame(
        input = input,
        output = output,
        cached_input = 0,
        cost = cost
      ))
    )
  }

  provider <- create_mock_provider(model = "content-stream")
  chat <- structure(
    list(
      chat = function(prompt = NULL) final_text,
      stream = function(
        prompt = NULL,
        stream = c("text", "content"),
        controller = NULL
      ) {
        request <- ellmer::ContentToolRequest(
          id = "tool-use-1",
          name = tool_name,
          arguments = list(path = "input.txt"),
          tool = tool
        )
        result <- ellmer::ContentToolResult(
          value = tool_result,
          request = request
        )
        content <- ellmer::ContentText(final_text)
        step <- 0L

        function() {
          step <<- step + 1L
          if (step == 1L) {
            add_assistant_turn(list(request), 10, 1, 0.01)
            return(request)
          }
          if (step == 2L) {
            rejected <- tryCatch(
              {
                state$on_tool_request(request)
                NULL
              },
              ellmer_tool_reject = function(error) {
                ellmer::ContentToolResult(
                  error = conditionMessage(error),
                  request = request
                )
              }
            )
            returned_result <- if (is.null(rejected)) {
              if (!is.null(execute)) {
                execute(request)
              }
              state$tool_executed <- TRUE
              result
            } else {
              state$tool_rejected <- TRUE
              rejected
            }
            state$on_tool_result(returned_result)
            return(returned_result)
          }
          if (step == 3L) {
            if (isTRUE(state$tool_rejected)) {
              return(coro::exhausted())
            }
            add_assistant_turn(list(content), 5, 2, 0.005)
            return(content)
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
        for (registered_tool in tools) {
          state$tools[[registered_tool@name]] <- registered_tool
        }
      },
      get_tokens = function() {
        if (length(state$token_rows) == 0L) {
          return(data.frame(
            input = numeric(),
            output = numeric(),
            cached_input = numeric(),
            cost = numeric()
          ))
        }
        do.call(rbind, state$token_rows)
      },
      get_provider = function() provider,
      get_model = function() mock_provider_model(provider),
      last_turn = function(role = "assistant") {
        if (length(state$turns) == 0L) NULL else tail(state$turns, 1L)[[1]]
      },
      on_tool_request = function(callback) state$on_tool_request <- callback,
      on_tool_result = function(callback) state$on_tool_result <- callback,
      clone = function() {
        create_content_stream_chat(
          tool_name = tool_name,
          tool_result = tool_result,
          final_text = final_text,
          execute = execute
        )$chat
      }
    ),
    class = "Chat"
  )
  chat$stream_async <- function(
    prompt = NULL,
    tool_mode = c("concurrent", "sequential"),
    stream = c("text", "content"),
    controller = NULL
  ) {
    as_mock_async_stream(chat$stream(
      prompt,
      stream = match.arg(stream),
      controller = controller
    ))
  }

  list(chat = chat, tool = tool, state = state)
}

collect_agent_events <- function(generator) {
  events <- list()
  repeat {
    event <- generator()
    if (coro::is_exhausted(event)) {
      break
    }
    events[[length(events) + 1L]] <- event
    if (inherits(event, "AgentEvent") && identical(event$type, "stop")) {
      break
    }
  }
  events
}

collect_async_stream <- function(stream) {
  result <- NULL
  stream_error <- NULL
  done <- FALSE

  coro::async_collect(stream) |>
    promises::then(function(value) {
      result <<- value
      done <<- TRUE
    }) |>
    promises::catch(function(cnd) {
      stream_error <<- cnd
      done <<- TRUE
    })

  for (i in seq_len(100)) {
    if (done) {
      break
    }
    later::run_now(0.01)
  }

  if (!done) {
    stop("Async stream did not settle")
  }
  if (!is.null(stream_error)) {
    stop(stream_error)
  }
  result
}

resolve_async_value <- function(promise) {
  result <- NULL
  stream_error <- NULL
  done <- FALSE

  promise |>
    promises::then(function(value) {
      result <<- value
      done <<- TRUE
    }) |>
    promises::catch(function(cnd) {
      stream_error <<- cnd
      done <<- TRUE
    })

  for (i in seq_len(100)) {
    if (done) {
      break
    }
    later::run_now(0.01)
  }
  if (!done) {
    stop("Async value did not settle")
  }
  if (!is.null(stream_error)) {
    stop(stream_error)
  }
  result
}

create_shiny_tool_chat <- function(tool_name, tool_input, execute = NULL) {
  state <- new.env(parent = emptyenv())
  state$on_tool_request <- function(request) invisible(NULL)
  state$on_tool_result <- function(result) invisible(NULL)
  state$executed <- FALSE
  state$rejected <- FALSE
  state$rejection <- NULL

  chat <- create_mock_chat()
  chat$on_tool_request <- function(callback) state$on_tool_request <- callback
  chat$on_tool_result <- function(callback) state$on_tool_result <- callback
  chat$stream_async <- function(
    prompt,
    stream = "content",
    controller = NULL
  ) {
    coro::async_generator(function() {
      request <- ellmer::ContentToolRequest(
        id = "shiny-tool-1",
        name = tool_name,
        arguments = tool_input
      )
      rejection <- tryCatch(
        {
          state$on_tool_request(request)
          NULL
        },
        ellmer_tool_reject = function(error) error
      )
      state$rejection <- rejection
      if (is.null(rejection)) {
        if (!is.null(execute)) {
          execute(request)
        }
        state$executed <- TRUE
        result <- ellmer::ContentToolResult(value = "ok", request = request)
      } else {
        state$rejected <- TRUE
        result <- ellmer::ContentToolResult(
          error = conditionMessage(rejection),
          request = request
        )
      }
      state$on_tool_result(result)
      coro::yield(if (state$rejected) "rejected" else "done")
    })()
  }

  list(chat = chat, state = state)
}

create_checkpoint_callback_chat <- function() {
  chat <- create_mock_chat("done")
  request_callback <- NULL
  result_callback <- NULL
  original_request_callback <- chat$on_tool_request
  original_result_callback <- chat$on_tool_result

  chat$on_tool_request <- function(callback) {
    request_callback <<- callback
    original_request_callback(callback)
  }
  chat$on_tool_result <- function(callback) {
    result_callback <<- callback
    original_result_callback(callback)
  }

  list(
    chat = chat,
    request_callback = function() request_callback,
    result_callback = function() result_callback
  )
}
