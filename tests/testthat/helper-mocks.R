# Shared test helpers for deputy

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
        # Return a simple iterator
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
        # Return a mock turn with no tool requests
        structure(
          list(text = responses[[min(response_idx, length(responses))]]),
          class = "AssistantTurn"
        )
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
