# Read and write agent definition files

Save an
[`agent_definition()`](https://jameshwade.github.io/deputy/reference/agent_definition.md)
as a YAML file, read one back, or read every definition in a directory.
Files refer to tools and skills by name; you supply the actual objects
through the `tools` and `skills` arguments. Reading a file never runs R
code, loads packages or connects to MCP servers.

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

  Path to a YAML file. For `agent_definitions()`, a directory, by
  default `.deputy/agents` under the working directory; only the `.yaml`
  and `.yml` files directly inside it are read.

- tools:

  Named list of ellmer tools. Files refer to tools by these names, such
  as `read_file`. Names are case-sensitive.

- skills:

  Named list of
  [Skill](https://jameshwade.github.io/deputy/reference/Skill.md)
  objects or skill directory paths. Files refer to skills by these
  names, never by path.

- definition:

  An
  [AgentDefinition](https://jameshwade.github.io/deputy/reference/agent_definition.md)
  to write. Each of its tools and skills must appear exactly once in
  `tools` or `skills`.

- overwrite:

  Whether to replace an existing file. Defaults to `FALSE`.

## Value

`agent_definition_read()` returns an `AgentDefinition`.
`agent_definition_write()` returns `path`, invisibly.
`agent_definitions()` returns a list of definitions named by definition
name, ready for `LeadAgent$new(sub_agents = ...)`. It returns an empty
list if the directory doesn't exist, and errors if any file is invalid
or two files use the same name.

## Format version 1

A file is a YAML mapping with `version: 1` and the arguments of
[`agent_definition()`](https://jameshwade.github.io/deputy/reference/agent_definition.md)
as fields. `name`, `description` and `prompt` are required; the other
fields default as in
[`agent_definition()`](https://jameshwade.github.io/deputy/reference/agent_definition.md).
`tools` and `skills` are lists of registry names, and
`disallowed_tools`, `memory` and `mcp_servers` are lists of strings; a
single string also works for a one-item list. `model`, `initial_prompt`
and `permission_mode` are strings, and `max_requests` is a non-negative
integer. `null` is allowed only for fields whose default is `NULL`.

Unknown fields or versions, unknown tool or skill names, duplicate keys
and `!expr` tags are errors. YAML guesses types, so quote strings such
as `"yes"` or `"123"`. Files larger than 1 MiB are rejected.

Files are written as UTF-8 with LF line endings. Rewriting a file drops
its comments. Each file is written to a temporary file first and moved
into place when complete. With `overwrite = FALSE`, the file system must
support hard links; that is how an existing file is guaranteed never to
be replaced.

The format has no place for credentials, R code or nested subagents. A
subagent's permission mode and request limit are still capped by its
[LeadAgent](https://jameshwade.github.io/deputy/reference/LeadAgent.md).

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
