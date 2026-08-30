# Load an R REPL with an enforced OS sandbox

Loads one explicitly configured
[mcp-repl](https://github.com/posit-dev/mcp-repl) server after verifying
that its command requests the exact sandbox policy. Deputy refuses
missing, inherited, external, and unrestricted policies.

This is the supported path for model-generated code that requires an OS
security boundary. Deputy's built-in
[tool_run_r_code](https://jameshwade.github.io/deputy/reference/tool_run_r_code.md)
and
[tool_run_bash](https://jameshwade.github.io/deputy/reference/tool_run_bash.md)
are trusted-code tools; their subprocesses provide fault isolation, not
filesystem or network confinement.

## Usage

``` r
tools_mcp_repl(
  config = NULL,
  server = "r",
  sandbox = c("workspace-write", "read-only")
)
```

## Arguments

- config:

  Path to an mcptools JSON configuration. Defaults to
  `~/.config/mcptools/config.json`.

- server:

  Exact MCP server name. Defaults to `"r"`, the name used by mcp-repl's
  installation examples.

- sandbox:

  Required mcp-repl policy. `"workspace-write"` confines writes to
  configured roots and `"read-only"` denies workspace writes. mcp-repl
  also controls network access according to its server configuration.

## Value

A list of ellmer-compatible tools from the selected mcp-repl server.

## Examples

``` r
if (FALSE) { # \dontrun{
repl_tools <- tools_mcp_repl(
  config = "~/.config/mcptools/config.json",
  server = "r",
  sandbox = "workspace-write"
)
agent <- Agent$new(
  chat = ellmer::chat("openai"),
  tools = repl_tools,
  permissions = Permissions$new(web = FALSE)
)
} # }
```
