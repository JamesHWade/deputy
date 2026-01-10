# LeadAgent R6 Class

A LeadAgent is an agent that can delegate tasks to specialized
sub-agents. It automatically has a `delegate_to_agent` tool that allows
it to spawn sub-agents based on registered AgentDefinitions.

## Super class

[`deputy::Agent`](https://jameshwade.github.io/deputy/reference/Agent.md)
-\> `LeadAgent`

## Public fields

- `sub_agent_defs`:

  List of AgentDefinition objects

## Methods

### Public methods

- [`LeadAgent$new()`](#method-LeadAgent-new)

- [`LeadAgent$register_sub_agent()`](#method-LeadAgent-register_sub_agent)

- [`LeadAgent$available_sub_agents()`](#method-LeadAgent-available_sub_agents)

- [`LeadAgent$print()`](#method-LeadAgent-print)

- [`LeadAgent$clone()`](#method-LeadAgent-clone)

Inherited methods

- [`deputy::Agent$add_hook()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-add_hook)
- [`deputy::Agent$compact()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-compact)
- [`deputy::Agent$cost()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-cost)
- [`deputy::Agent$last_turn()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-last_turn)
- [`deputy::Agent$load_mcp()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-load_mcp)
- [`deputy::Agent$load_session()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-load_session)
- [`deputy::Agent$load_skill()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-load_skill)
- [`deputy::Agent$mcp_tools()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-mcp_tools)
- [`deputy::Agent$provider()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-provider)
- [`deputy::Agent$register_tool()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-register_tool)
- [`deputy::Agent$register_tools()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-register_tools)
- [`deputy::Agent$run()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-run)
- [`deputy::Agent$run_sync()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-run_sync)
- [`deputy::Agent$save_session()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-save_session)
- [`deputy::Agent$skills()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-skills)
- [`deputy::Agent$turns()`](https://jameshwade.github.io/deputy/reference/Agent.html#method-turns)

------------------------------------------------------------------------

### Method `new()`

Create a new LeadAgent.

#### Usage

    LeadAgent$new(
      chat,
      sub_agents = list(),
      tools = list(),
      system_prompt = NULL,
      permissions = NULL,
      working_dir = getwd()
    )

#### Arguments

- `chat`:

  An ellmer Chat object

- `sub_agents`:

  List of
  [`agent_definition()`](https://jameshwade.github.io/deputy/reference/agent_definition.md)
  objects

- `tools`:

  Additional tools for the lead agent

- `system_prompt`:

  System prompt for the lead agent

- `permissions`:

  Permissions for the lead agent (also applied to sub-agents)

- `working_dir`:

  Working directory

#### Returns

A new `LeadAgent` object

------------------------------------------------------------------------

### Method `register_sub_agent()`

Register a new sub-agent definition.

#### Usage

    LeadAgent$register_sub_agent(definition)

#### Arguments

- `definition`:

  An
  [`agent_definition()`](https://jameshwade.github.io/deputy/reference/agent_definition.md)
  object

#### Returns

Invisible self

------------------------------------------------------------------------

### Method `available_sub_agents()`

Get available sub-agent names.

#### Usage

    LeadAgent$available_sub_agents()

#### Returns

Character vector of sub-agent names

------------------------------------------------------------------------

### Method [`print()`](https://rdrr.io/r/base/print.html)

Print the lead agent.

#### Usage

    LeadAgent$print()

------------------------------------------------------------------------

### Method `clone()`

The objects of this class are cloneable with this method.

#### Usage

    LeadAgent$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.
