# deputy: Run Tasks with Language Models and R Tools

Run tasks with language models and R tools using 'ellmer'. Control tool
access with permissions, set limits on requests and usage, and inspect
responses, tool calls, and the reason each run stopped. Supports
streaming output, 'Shiny' applications, saved conversations, file
checkpoints, and delegation to other agents.

## Main Functions

- [Agent](https://jameshwade.github.io/deputy/reference/Agent.md) - The
  main class for creating agents

- [LeadAgent](https://jameshwade.github.io/deputy/reference/LeadAgent.md) -
  Coordinate specialized delegated agents

- [`tools_preset()`](https://jameshwade.github.io/deputy/reference/tools_preset.md) -
  Choose a set of built-in tools

- [`UsageLimits()`](https://jameshwade.github.io/deputy/reference/UsageLimits.md) -
  Set request, tool, token, and cost limits

- [`permissions_standard()`](https://jameshwade.github.io/deputy/reference/permissions_standard.md) -
  Standard permission policy

- [`permissions_plan()`](https://jameshwade.github.io/deputy/reference/permissions_plan.md) -
  Planning permission policy

- [`permissions_readonly()`](https://jameshwade.github.io/deputy/reference/permissions_readonly.md) -
  Read-only permission policy

## Getting Started

    library(deputy)

    agent <- Agent$new(
      chat = ellmer::chat("openai/gpt-5.6-luna"),
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
