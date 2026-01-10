# Get a tool preset by name

Returns a pre-configured collection of tools for common use cases.
Presets simplify agent setup by providing curated toolsets.

## Usage

``` r
tools_preset(name)
```

## Arguments

- name:

  The preset name. One of:

  - `"minimal"` - Read-only tools for safe exploration (`read_file`,
    `list_files`)

  - `"standard"` - Balanced toolset for R development (`read_file`,
    `write_file`, `list_files`, `run_r_code`)

  - `"dev"` - Full development with shell access (`read_file`,
    `write_file`, `list_files`, `run_r_code`, `run_bash`)

  - `"data"` - Data analysis focused tools (`read_file`, `list_files`,
    `read_csv`, `run_r_code`)

  - `"full"` - All available tools (requires appropriate permissions)

## Value

A list of tool definitions

## See also

[`tools_file()`](https://jameshwade.github.io/deputy/reference/tools_file.md),
[`tools_code()`](https://jameshwade.github.io/deputy/reference/tools_code.md),
[`tools_data()`](https://jameshwade.github.io/deputy/reference/tools_data.md),
[`tools_all()`](https://jameshwade.github.io/deputy/reference/tools_all.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# Minimal preset for read-only operations
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-4o"),
  tools = tools_preset("minimal"),
  permissions = permissions_readonly()
)

# Standard preset for typical development
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-4o"),
  tools = tools_preset("standard")
)

# Data analysis preset
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-4o"),
  tools = tools_preset("data")
)
} # }
```
