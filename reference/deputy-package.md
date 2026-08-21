# deputy: Agentic AI Workflows for R

A provider-agnostic framework for building agentic AI workflows in R.
Built on ellmer, it enables multi-step reasoning with tool use,
permissions, hooks, and human-in-the-loop capabilities. Works with any
LLM provider that ellmer supports including OpenAI, Anthropic, Google,
and local models via Ollama.

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
([ORCID](https://orcid.org/0000-0002-9740-1905))

Authors:

- James Wade <github@jameshwade.com>
  ([ORCID](https://orcid.org/0000-0002-9740-1905))
