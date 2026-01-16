# Shared test helpers for deputy

# Helper to create a proper S7 AssistantTurn
# Uses ellmer's actual constructors for compatibility
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

# Helper to create a mock Chat object for testing
# This avoids the need for real API calls
create_mock_chat <- function(responses = list("Hello!")) {
  response_idx <- 0
  turns <- list()
  tools <- list()
  system_prompt <- NULL
  tool_request_callback <- NULL
  tool_result_callback <- NULL

  # Create a simple mock that behaves like ellmer's Chat
  structure(
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
        # Simple mock provider with list access
        list(name = "mock", model = "test-model")
      },
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
      }
    ),
    class = "Chat"
  )
}
