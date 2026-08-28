# deputy: Governed Agentic Artificial Intelligence Workflows

Run provider-agnostic, agentic artificial intelligence (AI) workflows
with explicit boundaries for tools, permissions, budgets, and filesystem
access. Builds on 'ellmer' to provide multi-step reasoning, lifecycle
hooks, structured events, human input, session persistence, and
delegation. Returns inspectable results and supports synchronous,
asynchronous, terminal, and 'Shiny' hosts. Designed for applications
that need governance and observability around tool-using language models
in 'R'.

A provider-agnostic framework for building agentic AI workflows in R.
Built on ellmer, it enables multi-step reasoning with tool use,
permissions, hooks, human-in-the-loop capabilities, and multi-agent
delegation.

## Main Functions

- [Agent](https://jameshwade.github.io/deputy/reference/Agent.md) - The
  main class for creating agents

- [LeadAgent](https://jameshwade.github.io/deputy/reference/LeadAgent.md) -
  Coordinate specialized delegated agents

- [`tools_preset()`](https://jameshwade.github.io/deputy/reference/tools_preset.md) -
  Curated built-in tool collections

- [`UsageLimits()`](https://jameshwade.github.io/deputy/reference/UsageLimits.md) -
  Run-scoped request, tool, token, and cost limits

- [`permissions_standard()`](https://jameshwade.github.io/deputy/reference/permissions_standard.md) -
  Standard permission policy

- [`permissions_plan()`](https://jameshwade.github.io/deputy/reference/permissions_plan.md) -
  Planning permission policy

- [`permissions_readonly()`](https://jameshwade.github.io/deputy/reference/permissions_readonly.md) -
  Read-only permission policy

## Getting Started

    library(deputy)

    # Create an agent with file tools
    agent <- Agent$new(
      chat = ellmer::chat("openai/gpt-4o"),
      tools = tools_preset("standard")
    )

    # Run a task with streaming output
    events <- agent$run("List files in current directory")
    repeat {
      event <- events()
      if (coro::is_exhausted(event)) break
      if (event$type == "text") cat(event$text)
    }

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
