# deputy (development version)

* `compact()` now summarizes on a clone of the agent's own chat instead of
  constructing a new provider. Previously any provider other than OpenAI,
  Anthropic, or Google fell through to `ellmer::chat_openai("gpt-4o-mini")`,
  sending conversation history to OpenAI when `OPENAI_API_KEY` happened to be
  set. The clone also preserves the configured model, base URL, and credentials.

# deputy 0.0.0.9000

* Initial development version
* Core `Agent` class with streaming `run()` and blocking `run_sync()` methods
* Built-in tools: `tool_read_file`, `tool_write_file`, `tool_list_files`,
  `tool_run_r_code`, `tool_run_bash`, `tool_read_csv`
* Tool bundles: `tools_file()`, `tools_code()`, `tools_data()`, `tools_all()`
* Permission system with `permissions_readonly()`, `permissions_standard()`,
  `permissions_full()`, and custom `Permissions` class
* Hook system with `HookMatcher`, `HookRegistry`, and events:
  `PreToolUse`, `PostToolUse`, `Stop`, `UserPromptSubmit`, `PreCompact`
* Multi-agent support with `agent_definition()` and `LeadAgent`
* Skills system with `skill_load()`, `skill_create()`, and `Skill` class
* Session persistence via `save_session()` and `load_session()`
* Provider-agnostic design works with any ellmer-supported LLM
