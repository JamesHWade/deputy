# Deputy error classes

Errors signalled by deputy have class `deputy_error` plus more specific
classes, so you can catch them by class with
[`tryCatch()`](https://rdrr.io/r/base/conditions.html). Many carry extra
fields, such as `tool_name` or `limit`. Errors from ellmer or the
provider, such as HTTP errors, are passed through unchanged.

## Error classes

- `deputy_error`: every deputy error.

  - `deputy_permission_denied` (also `deputy_permission`): an action
    wasn't allowed.

  - `deputy_tool_execution` (also `deputy_tool`): a tool failed.

  - `deputy_budget`: a usage limit was reached. Only signalled when
    [`UsageLimits()`](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
    has `on_exceed = "error"`.

    - `deputy_request_limit`: `max_requests` was reached.

    - `deputy_cost_unavailable`: `max_cost_usd` is set but a response's
      cost is unknown.

    - `deputy_budget_exceeded`: a tool-call, token or cost limit was
      reached. The error's `budget_type`, `actual` and `limit` fields
      say which.

  - `deputy_session_load`, `deputy_session_save` (also
    `deputy_session`): loading or saving a session file failed.

  - `deputy_human_input_unavailable`: an `ask_user` request couldn't
    reach a person, for example in a non-interactive session with no
    handler.

Other deputy errors, such as `deputy_run_active` (the agent is already
running), also inherit from `deputy_error`.

## Usage

    tryCatch(
      agent$run_sync("task"),
      deputy_budget = function(e) {
        message("Usage limit reached: ", conditionMessage(e))
      },
      deputy_error = function(e) {
        message("Deputy error: ", conditionMessage(e))
      }
    )
