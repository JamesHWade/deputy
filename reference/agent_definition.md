# Create an Agent Definition

AgentDefinition describes a specialized agent that can be used by a lead
agent to delegate tasks. It bundles together a system prompt, tools, and
metadata about what the agent can do.

## Usage

``` r
agent_definition(
  name,
  description,
  prompt,
  tools = list(),
  model = "inherit",
  skills = list()
)
```

## Arguments

- name:

  Unique name for this agent type

- description:

  Brief description of what this agent does (shown to lead agent)

- prompt:

  System prompt for this agent

- tools:

  Optional list of tools for this agent

- model:

  Model to use (default: "inherit" uses parent's model)

- skills:

  Optional list of skills to load

## Value

An `AgentDefinition` object

## Examples

``` r
if (FALSE) { # \dontrun{
# Define a code review agent
code_reviewer <- agent_definition(
  name = "code_reviewer",
  description = "Reviews code for bugs, style issues, and best practices",
  prompt = "You are an expert code reviewer...",
  tools = list(tool_read_file, tool_list_files)
)

# Use with a lead agent
lead <- LeadAgent$new(
  chat = ellmer::chat("openai/gpt-4o"),
  sub_agents = list(code_reviewer)
)
} # }
```
