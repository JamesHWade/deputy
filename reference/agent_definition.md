# Define a subagent

Describe a subagent that a
[LeadAgent](https://jameshwade.github.io/deputy/reference/LeadAgent.md)
can delegate to: its name, a description the lead's model reads when
choosing, a system prompt, tools and other settings. Each delegation
creates a new subagent from the definition.

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

  Name used to select the subagent. It is trimmed and lowercased, and
  must start with a letter followed by letters, numbers, underscores or
  hyphens.

- description:

  What the subagent does. The lead's model reads it when choosing where
  to delegate.

- prompt:

  System prompt for the subagent.

- tools:

  List of tools for the subagent. It doesn't inherit the lead's tools.

- model:

  Model to use. `"inherit"` (the default) uses a copy of the lead's
  chat. A bare model id such as `"gpt-6-luna"` keeps the lead's provider
  and credentials but switches the model. A `"provider/model"` string
  such as `"anthropic/claude-sonnet-5"` creates a new chat with
  [`ellmer::chat()`](https://ellmer.tidyverse.org/reference/chat-any.html).

- skills:

  List of
  [Skill](https://jameshwade.github.io/deputy/reference/Skill.md)
  objects or skill directory paths to load.

- disallowed_tools:

  Names of tools to remove from the subagent, including tools from
  skills. Case is ignored.

- memory:

  Notes appended to the subagent's system prompt under a "Memory"
  heading.

- mcp_servers:

  Names of MCP servers the subagent needs. Deputy doesn't connect to
  them: such a definition needs a
  [DelegationPolicy](https://jameshwade.github.io/deputy/reference/DelegationPolicy.md)
  with `resource_mode = "owned"`, whose `resources` function creates the
  MCP tools.

- initial_prompt:

  Text sent ahead of every task delegated to this subagent.

- max_requests:

  Maximum model requests per delegation. The remaining budget of the
  lead's run also applies.

- permission_mode:

  Permission mode for the subagent; defaults to the lead's. It can
  otherwise only be `"readonly"`, unless the lead's mode is `"full"`.
  Use `disallowed_tools` and `max_requests` for finer limits.

## Value

An `AgentDefinition` object.

## Details

An `AgentDefinition` is read-only; read its fields with `$`. To change a
field, build a new definition from
[`S7::props()`](https://rconsortium.github.io/S7/reference/props.html),
as in the examples. `agent_definition()` and `AgentDefinition()` are the
same function.

Tools and skills are stored as given, not copied, so a tool that keeps
state in its closure shares that state wherever the definition is used.
To save a definition as YAML, use
[`agent_definition_write()`](https://jameshwade.github.io/deputy/reference/agent_definition_read.md)
and
[`agent_definition_read()`](https://jameshwade.github.io/deputy/reference/agent_definition_read.md).

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
  chat = ellmer::chat("openai/gpt-6-luna"),
  sub_agents = list(code_reviewer)
)
} # }
```
