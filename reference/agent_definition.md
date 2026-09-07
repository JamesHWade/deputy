# Create an Agent Definition

AgentDefinition describes a specialized agent that can be used by a lead
agent to delegate tasks. It bundles together a system prompt, tools, and
metadata about what the agent can do.

## Usage

``` r
AgentDefinition(
  name,
  description,
  prompt,
  tools = list(),
  model = "inherit",
  skills = list(),
  disallowed_tools = NULL,
  memory = NULL,
  mcp_servers = NULL,
  initial_prompt = NULL,
  max_requests = NULL,
  permission_mode = NULL
)

agent_definition(
  name,
  description,
  prompt,
  tools = list(),
  model = "inherit",
  skills = list(),
  disallowed_tools = NULL,
  memory = NULL,
  mcp_servers = NULL,
  initial_prompt = NULL,
  max_requests = NULL,
  permission_mode = NULL
)
```

## Arguments

- name:

  Unique routing key for this Agent type. Names are trimmed, converted
  to lowercase, and must start with a letter followed only by letters,
  numbers, underscores, or hyphens.

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

- disallowed_tools:

  Optional tool denylist for this sub-agent

- memory:

  Optional memory text appended to this sub-agent's prompt

- mcp_servers:

  Optional MCP server names to load for this sub-agent

- initial_prompt:

  Optional text prepended to delegated tasks

- max_requests:

  Optional non-negative whole-number sub-agent request limit

- permission_mode:

  Optional permission mode. A child may keep the lead mode or narrow it
  to `"readonly"`; a `"full"` lead may select any mode. Use
  `disallowed_tools` and `max_requests` for additional limits.

## Value

A read-only `AgentDefinition` S7 object

## Details

This is a read-only S7 value. `agent_definition()` is an alias of
`AgentDefinition()`; both construct the same class. Read fields with
`$`,
[`S7::prop()`](https://rconsortium.github.io/S7/reference/prop.html), or
`@`.
[`S7::props()`](https://rconsortium.github.io/S7/reference/props.html)
returns a plain property list for constructing a revised value.
Canonical names, limits, and other fields cannot be changed after
construction, including through LeadAgent snapshots.

Tools and read-only Skill values are composed directly. Executable tools
nested in either value retain their closures, services, and caller-owned
state without cloning. Read-only configuration does not freeze tool
state. Use
[`agent_definition_write()`](https://jameshwade.github.io/deputy/reference/agent_definition_read.md)
and
[`agent_definition_read()`](https://jameshwade.github.io/deputy/reference/agent_definition_read.md)
with explicit host registries for portable YAML;
[`S7::props()`](https://rconsortium.github.io/S7/reference/props.html)
alone is not a portable serializer for executable objects.

## Examples

``` r
# Define a code review agent
code_reviewer <- agent_definition(
  name = "code_reviewer",
  description = "Reviews code for bugs, style issues, and best practices",
  prompt = "You are an expert code reviewer...",
  tools = list(tool_read_file, tool_list_files)
)

code_reviewer$name
#> [1] "code_reviewer"
fields <- S7::props(code_reviewer)
fields$max_requests <- 3L
do.call(agent_definition, fields)
#> <AgentDefinition: code_reviewer >
#>   description: Reviews code for bugs, style issues, and best practices
#>   tools: 2
#>   skills: 0
#>   model: inherit

if (FALSE) { # \dontrun{
# Use with a lead agent
lead <- LeadAgent$new(
  chat = ellmer::chat("openai/gpt-5.6-luna"),
  sub_agents = list(code_reviewer)
)
} # }
```
