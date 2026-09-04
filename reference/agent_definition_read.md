# Read, write, and discover AgentDefinition files

Deputy's versioned YAML format represents every field in
[`agent_definition()`](https://jameshwade.github.io/deputy/reference/agent_definition.md).
Tools and skills are symbolic references resolved only through explicit
host-supplied registries. Reading a file does not load packages, source
R code, connect MCP servers, or instantiate an Agent.

## Usage

``` r
agent_definition_read(path, tools = list(), skills = list())

agent_definition_write(
  definition,
  path,
  tools = list(),
  skills = list(),
  overwrite = FALSE
)

agent_definitions(
  path = file.path(".deputy", "agents"),
  tools = list(),
  skills = list()
)
```

## Arguments

- path:

  A YAML file for reading/writing, or a directory for discovery.
  Discovery defaults to `.deputy/agents` in the current project and
  reads `.yaml` and `.yml` files in that directory, without recursion.

- tools:

  Named list of ellmer tool objects available to the definition.
  Registry keys are case-sensitive symbols, such as `read_file`.

- skills:

  Named list of
  [Skill](https://jameshwade.github.io/deputy/reference/Skill.md)
  objects or skill paths approved by the host. Files reference these
  keys, never literal paths.

- definition:

  An
  [AgentDefinition](https://jameshwade.github.io/deputy/reference/agent_definition.md)
  to write. Each tool and skill must match exactly one entry in its
  supplied registry.

- overwrite:

  Whether to replace an existing file. Defaults to `FALSE`.

## Value

`agent_definition_read()` returns an `AgentDefinition`.
`agent_definition_write()` invisibly returns `path`.
`agent_definitions()` returns a named list of definitions keyed by their
canonical routing names, ready for `LeadAgent$new(sub_agents = ...)`. A
missing discovery directory returns an empty list. Invalid files or
duplicate names abort the entire discovery operation.

## Format version 1

A file is one YAML mapping with `version: 1` and the fields of
[`agent_definition()`](https://jameshwade.github.io/deputy/reference/agent_definition.md).
`name`, `description`, and `prompt` are required. Optional fields use
the constructor defaults. `tools` and `skills` are sequences of registry
keys; `disallowed_tools`, `memory`, and `mcp_servers` are sequences of
strings. `model`, `initial_prompt`, and `permission_mode` are strings,
and `max_requests` is a non-negative integer. Explicit `null` is
accepted only for constructor fields that allow `NULL`.

Unknown fields, versions, references, duplicate keys, and YAML
evaluation tags are rejected. YAML type inference applies: quote strings
such as `"yes"` or `"123"`. Empty sequences are written as `[]` and
optional NULL values as `null`. Writing canonicalizes formatting; it
does not preserve comments or names attached to R lists or character
sequences. Object order and registry identity are preserved. A single
string is accepted as shorthand for a one-element sequence. Only regular
files of at most 1 MiB are read. Files are written as UTF-8 with LF line
endings on every platform. Writes use a temporary file in the
destination directory and replace the destination only after writing
succeeds. With `overwrite = FALSE`, installing the file requires
hard-link support from the filesystem so a concurrently created
destination is never replaced.

A definition describes a subagent. Permission modes and request limits
remain bounded by its LeadAgent. Nested `sub_agents`, host credentials,
runtime objects, and executable code are not part of this format.

## Examples

``` r
if (requireNamespace("yaml", quietly = TRUE)) {
  registry <- list(read_file = tool_read_file)
  definition <- agent_definition(
    "reviewer", "Reviews local text", "Read the supplied text carefully.",
    tools = unname(registry), permission_mode = "readonly", max_requests = 3
  )
  path <- tempfile(fileext = ".yaml")
  agent_definition_write(definition, path, tools = registry)
  restored <- agent_definition_read(path, tools = registry)
  restored$name
  unlink(path)
}
```
