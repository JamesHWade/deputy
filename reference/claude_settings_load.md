# Load Claude-style settings from settingSources

Loads Claude-style settings from a list of `setting_sources`, mirroring
the Agent SDK behavior. Supports user, project, and local sources, and
returns memory, skills, slash commands, and custom agents discovered in
`.claude` directories.

Supported sources:

- `"user"`: loads `~/.claude` settings, skills, commands, agents, and
  memory

- `"project"`: loads project `.claude` settings, skills, commands,
  agents, and memory

- `"local"`: loads project `.claude/settings.local.json` only

- explicit file paths to `.json` settings files

## Usage

``` r
claude_settings_load(setting_sources, working_dir = getwd())
```

## Arguments

- setting_sources:

  Character vector of sources, e.g. `c("project", "user")`.

- working_dir:

  Working directory used for project sources.

## Value

A list with `settings`, `memory`, `skills`, `commands`, `agents`, and
metadata.
