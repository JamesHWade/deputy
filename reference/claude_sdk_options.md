# Create Agent SDK compatibility options

`agent_sdk_options()` is an additive alias for teams that prefer the
newer Agent SDK naming while keeping the same deputy runtime and
behavior.

## Usage

``` r
claude_sdk_options(
  chat = NULL,
  model = NULL,
  system_prompt = NULL,
  hooks = list(),
  tools = NULL,
  custom_tools = list(),
  agents = list(),
  setting_sources = NULL,
  settings = NULL,
  managed_settings = NULL,
  allowed_tools = NULL,
  disallowed_tools = NULL,
  permission_prompt_tool_name = "AskUserQuestion",
  permission_mode = "default",
  can_use_tool = NULL,
  cwd = getwd(),
  persist_session = TRUE,
  session_store_dir = session_store_default_dir(),
  session_store = NULL,
  resume_session_id = NULL,
  resume_session_at = NULL,
  fork_session = FALSE,
  max_turns = 25,
  max_cost_usd = NULL,
  include_partial_messages = TRUE,
  output_format = NULL,
  skills = NULL,
  sandbox = NULL,
  plugins = NULL,
  thinking = NULL,
  effort = NULL,
  title = NULL,
  user = NULL,
  fallback_model = NULL,
  betas = NULL,
  cli_path = NULL,
  add_dirs = NULL,
  env = NULL,
  extra_args = NULL,
  max_buffer_size = NULL,
  stderr = NULL,
  enable_file_checkpointing = FALSE,
  file_checkpoint_max_file_bytes = 50 * 1024^2,
  file_checkpoint_max_journal_bytes = 250 * 1024^2,
  load_timeout_ms = NULL,
  task_budget = NULL
)

agent_sdk_options(...)
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

- tools:

  Optional SDK-style built-in tool names or ellmer tools to register

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

- managed_settings:

  Optional settings values that override loaded settings

- allowed_tools:

  Optional explicit tool allowlist

- disallowed_tools:

  Optional explicit tool denylist

- permission_prompt_tool_name:

  Tool name to suggest when approval is required

- permission_mode:

  Compatibility permission mode

- can_use_tool:

  Optional permission callback

- cwd:

  Working directory for the agent

- persist_session:

  Whether to persist compat snapshots to disk

- session_store_dir:

  Directory where compat session snapshots are stored

- session_store:

  Optional external session store adapter

- resume_session_id:

  Optional session id to resume later

- resume_session_at:

  Optional timestamp to resume at or before

- fork_session:

  Whether to fork the resumed session into a new session id

- max_turns:

  Maximum model requests per query

- max_cost_usd:

  Maximum cost per query

- include_partial_messages:

  Whether query results keep partial text events

- output_format:

  Optional default structured output format

- skills:

  Optional SDK-style skill selection (`"all"`, names, paths, or skills)

- sandbox, plugins, thinking, effort, title, user, fallback_model,
  betas, cli_path, add_dirs, env, extra_args, max_buffer_size, stderr,
  load_timeout_ms, task_budget:

  Additional SDK-shaped options that are preserved for compatibility.
  deputy applies the subset that maps to its R-native runtime.

- enable_file_checkpointing:

  Whether to capture reversible file preimages for mutating Deputy and
  SDK-compatible file tools.

- file_checkpoint_max_file_bytes:

  Maximum bytes captured for one file preimage. Defaults to 50 MiB.

- file_checkpoint_max_journal_bytes:

  Maximum aggregate serialized bytes for checkpoint records, markers,
  metadata, and pending captures. Defaults to 250 MiB.

- ...:

  Passed through to `claude_sdk_options()`

## Value

A `ClaudeSDKOptions` object
