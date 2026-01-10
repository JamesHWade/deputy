# Deputy Error Classes

Structured error types for programmatic error handling in deputy. All
deputy errors inherit from `deputy_error` and include contextual
information for debugging. Errors use cli formatting for readable
output.

## Error Hierarchy

- **deputy_error** - Base class for all deputy errors

  - **deputy_permission** - Permission-related failures

    - `deputy_permission_denied` - Tool/action not allowed by
      permissions

  - **deputy_tool** - Tool execution failures

    - `deputy_tool_execution` - Tool failed during execution

  - **deputy_budget** - Resource limit violations

    - `deputy_budget_exceeded` - Cost limit exceeded

    - `deputy_turn_limit` - Max turns exceeded

  - **deputy_provider** - LLM provider failures

  - **deputy_session** - Session management failures

    - `deputy_session_load` - Failed to load session

    - `deputy_session_save` - Failed to save session

  - **deputy_hook** - Hook execution failures

## Usage

Errors can be caught using
[`tryCatch()`](https://rdrr.io/r/base/conditions.html) with class-based
matching:

    tryCatch(
      agent$run_sync("task"),
      deputy_budget_exceeded = function(e) {
        message("Budget exceeded: ", conditionMessage(e))
        message("Current cost: $", e$current_cost)
      },
      deputy_error = function(e) {
        message("Deputy error: ", conditionMessage(e))
      }
    )
