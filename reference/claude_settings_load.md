# Load Claude-style settings from settingSources

Loads Claude-style settings from a list of `setting_sources`, mirroring
the Claude Agent SDK behavior. Supports project and user sources, and
returns memory, skills, slash commands, and custom agents discovered in
`.claude` directories.

Supported sources:

- `"project"`: loads project `.claude` settings, skills, commands,
  agents, and memory

- `"user"`: loads `~/.claude` settings, skills, commands, agents, and
  memory

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
