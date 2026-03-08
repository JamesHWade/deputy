# Create Claude Agent SDK compatibility options

Create Claude Agent SDK compatibility options

## Usage

``` r
claude_sdk_options(
  chat = NULL,
  model = NULL,
  system_prompt = NULL,
  hooks = list(),
  custom_tools = list(),
  agents = list(),
  setting_sources = NULL,
  settings = NULL,
  allowed_tools = NULL,
  disallowed_tools = NULL,
  permission_prompt_tool_name = "AskUserQuestion",
  permission_mode = "default",
  cwd = getwd(),
  persist_session = TRUE,
  session_store_dir = session_store_default_dir(),
  resume_session_id = NULL,
  resume_session_at = NULL,
  fork_session = FALSE,
  max_turns = 25,
  max_cost_usd = NULL
)
```

## Arguments

- chat:

  Optional ellmer chat object to use directly

- model:

  Model string used when `chat` is not supplied

- system_prompt:

  Optional system prompt

- hooks:

  Optional HookMatcher or list of HookMatcher objects

- custom_tools:

  Optional list of additional ellmer tools

- agents:

  Optional list of
  [`agent_definition()`](https://jameshwade.github.io/deputy/reference/agent_definition.md)
  objects

- setting_sources:

  Optional Claude-style setting sources

- settings:

  Optional pre-loaded settings list from
  [`claude_settings_load()`](https://jameshwade.github.io/deputy/reference/claude_settings_load.md)

- allowed_tools:

  Optional explicit tool allowlist

- disallowed_tools:

  Optional explicit tool denylist

- permission_prompt_tool_name:

  Tool name to suggest when approval is required

- permission_mode:

  Compatibility permission mode

- cwd:

  Working directory for the agent

- persist_session:

  Whether to persist compat snapshots to disk

- session_store_dir:

  Directory where compat session snapshots are stored

- resume_session_id:

  Optional session id to resume later

- resume_session_at:

  Optional timestamp to resume at or before

- fork_session:

  Whether to fork the resumed session into a new session id

- max_turns:

  Maximum turns per query

- max_cost_usd:

  Maximum cost per query

## Value

A `ClaudeSDKOptions` object
