# Apply Claude-style settings to an Agent

Applies settings loaded by
[`claude_settings_load()`](https://jameshwade.github.io/deputy/reference/claude_settings_load.md)
to an [Agent](https://jameshwade.github.io/deputy/reference/Agent.md),
including memory injection, skill loading, and slash command
registration.

## Usage

``` r
claude_settings_apply(
  agent,
  settings,
  apply_memory = TRUE,
  load_skills = TRUE,
  load_commands = TRUE
)
```

## Arguments

- agent:

  An [Agent](https://jameshwade.github.io/deputy/reference/Agent.md)
  object.

- settings:

  Settings list returned by
  [`claude_settings_load()`](https://jameshwade.github.io/deputy/reference/claude_settings_load.md).

- apply_memory:

  Logical. If TRUE (default), append memory to system prompt.

- load_skills:

  Logical. If TRUE (default), load skills into the agent.

- load_commands:

  Logical. If TRUE (default), register slash commands.

## Value

Invisibly returns the agent.
