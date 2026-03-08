# deputy: Agentic AI Workflows for R

A provider-agnostic framework for building agentic AI workflows in R.
Built on ellmer, it enables multi-step reasoning with tool use,
permissions, hooks, and human-in-the-loop capabilities. Works with any
LLM provider that ellmer supports including OpenAI, Anthropic, Google,
and local models via Ollama.

A provider-agnostic framework for building agentic AI workflows in R.
Built on ellmer, it enables multi-step reasoning with tool use,
permissions, hooks, and human-in-the-loop capabilities. deputy also
ships an opt-in Anthropic-compatible Claude Agent SDK facade for teams
that want Claude-style entrypoints and session semantics on top of the
same runtime.

## Main Functions

- [Agent](https://jameshwade.github.io/deputy/reference/Agent.md) - The
  main class for creating agents

- [ClaudeSDKClient](https://jameshwade.github.io/deputy/reference/ClaudeSDKClient.md) -
  Anthropic-compatible client facade

- [`claude_sdk_query()`](https://jameshwade.github.io/deputy/reference/claude_sdk_query.md) -
  One-shot Claude-compatible query helper

- [`tools_file()`](https://jameshwade.github.io/deputy/reference/tools_file.md) -
  File operation tools

- [`tools_code()`](https://jameshwade.github.io/deputy/reference/tools_code.md) -
  Code execution tools

- [`permissions_standard()`](https://jameshwade.github.io/deputy/reference/permissions_standard.md) -
  Standard permission policy

- [`permissions_plan()`](https://jameshwade.github.io/deputy/reference/permissions_plan.md) -
  Claude-style planning permission policy

- [`permissions_readonly()`](https://jameshwade.github.io/deputy/reference/permissions_readonly.md) -
  Read-only permission policy

## Getting Started

    library(deputy)

    # Create an agent with file tools
    agent <- Agent$new(
      chat = ellmer::chat("openai/gpt-4o"),
      tools = tools_file()
    )

    # Run a task with streaming output
    for (event in agent$run("List files in current directory")) {
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
