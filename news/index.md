# Changelog

## deputy 0.0.0.9000

- Initial development version
- Core `Agent` class with streaming `run()` and blocking `run_sync()`
  methods
- Built-in tools: `tool_read_file`, `tool_write_file`,
  `tool_list_files`, `tool_run_r_code`, `tool_run_bash`, `tool_read_csv`
- Tool bundles:
  [`tools_file()`](https://jameshwade.github.io/deputy/reference/tools_file.md),
  [`tools_code()`](https://jameshwade.github.io/deputy/reference/tools_code.md),
  [`tools_data()`](https://jameshwade.github.io/deputy/reference/tools_data.md),
  [`tools_all()`](https://jameshwade.github.io/deputy/reference/tools_all.md)
- Permission system with
  [`permissions_readonly()`](https://jameshwade.github.io/deputy/reference/permissions_readonly.md),
  [`permissions_standard()`](https://jameshwade.github.io/deputy/reference/permissions_standard.md),
  [`permissions_full()`](https://jameshwade.github.io/deputy/reference/permissions_full.md),
  and custom `Permissions` class
- Hook system with `HookMatcher`, `HookRegistry`, and events:
  `PreToolUse`, `PostToolUse`, `Stop`, `UserPromptSubmit`, `PreCompact`
- Multi-agent support with
  [`agent_definition()`](https://jameshwade.github.io/deputy/reference/agent_definition.md)
  and `LeadAgent`
- Skills system with
  [`skill_load()`](https://jameshwade.github.io/deputy/reference/skill_load.md),
  [`skill_create()`](https://jameshwade.github.io/deputy/reference/skill_create.md),
  and `Skill` class
- Session persistence via `save_session()` and `load_session()`
- Provider-agnostic design works with any ellmer-supported LLM
