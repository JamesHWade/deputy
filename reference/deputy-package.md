# deputy: Run Tasks with Language Models and R Tools

Run tasks with language models and R tools using 'ellmer'. Control tool
access with permissions, set limits on requests and usage, and inspect
responses, tool calls, and the reason each run stopped. Supports
streaming output, 'Shiny' applications, saved conversations, file
checkpoints, and delegation to other agents.

## Main functions

- [Agent](https://jameshwade.github.io/deputy/reference/Agent.md): runs
  a task with an ellmer Chat, tools, permissions and limits.

- [LeadAgent](https://jameshwade.github.io/deputy/reference/LeadAgent.md):
  an agent that delegates tasks to subagents.

- [`tools_preset()`](https://jameshwade.github.io/deputy/reference/tools_preset.md):
  picks a set of built-in tools.

- [`UsageLimits()`](https://jameshwade.github.io/deputy/reference/UsageLimits.md):
  caps requests, tool calls, tokens and cost.

- [`permissions_standard()`](https://jameshwade.github.io/deputy/reference/permissions_standard.md),
  [`permissions_plan()`](https://jameshwade.github.io/deputy/reference/permissions_plan.md)
  and
  [`permissions_readonly()`](https://jameshwade.github.io/deputy/reference/permissions_readonly.md):
  ready-made permission policies.

## Getting started

    library(deputy)

    agent <- Agent$new(
      chat = ellmer::chat("openai/gpt-6-luna"),
      tools = tools_preset("minimal"),
      permissions = permissions_readonly(),
      usage_limits = UsageLimits(max_requests = 6, max_tool_calls = 8),
      working_dir = getwd()
    )

    result <- agent$run_sync("Read DESCRIPTION and explain what this package does.")
    result$response
    result$stop_reason

## See also

Useful links:

- <https://github.com/JamesHWade/deputy>

- <https://jameshwade.github.io/deputy/>

- Report bugs at <https://github.com/JamesHWade/deputy/issues>

## Author

**Maintainer**: James Wade <github@jameshwade.com>
([ORCID](https://orcid.org/0000-0002-9740-1905)) \[copyright holder\]

Authors:

- James Wade <github@jameshwade.com>
  ([ORCID](https://orcid.org/0000-0002-9740-1905)) \[copyright holder\]
