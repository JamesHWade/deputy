# Get a tool preset by name

Returns a ready-made set of tools for a common kind of task. The
`"dev"`, `"data"` and `"full"` presets include code execution tools,
which run with your user account's access. The default permissions deny
them; allow them with `r_code = TRUE` (and `bash = TRUE` for `run_bash`)
in
[`Permissions()`](https://jameshwade.github.io/deputy/reference/Permissions.md).

## Usage

``` r
tools_preset(name, env = NULL)
```

## Arguments

- name:

  The preset name. One of:

  - `"minimal"`: read-only tools (`read_file`, `read_markdown`,
    `list_files`).

  - `"standard"`: file tools (`read_file`, `read_markdown`,
    `write_file`, `list_files`).

  - `"dev"`: file tools plus code execution (`read_file`,
    `read_markdown`, `write_file`, `list_files`, `run_r_code`,
    `run_bash`).

  - `"data"`: data analysis (`read_file`, `read_markdown`, `list_files`,
    `read_csv`, `run_r_code`).

  - `"full"`: everything in
    [`tools_all()`](https://jameshwade.github.io/deputy/reference/tools_all.md).

- env:

  The names of other environment variables the code may read, such as
  `c("HTTPS_PROXY", "NO_PROXY")` behind a proxy. Proxy settings match in
  either case, so `"HTTPS_PROXY"` passes `https_proxy` too. `"inherit"`
  passes your whole environment, including every key it holds.

## Value

A list of tools.

## See also

[`tools_file()`](https://jameshwade.github.io/deputy/reference/tools_file.md),
[`tools_code()`](https://jameshwade.github.io/deputy/reference/tools_code.md),
[`tools_data()`](https://jameshwade.github.io/deputy/reference/tools_data.md),
[`tools_all()`](https://jameshwade.github.io/deputy/reference/tools_all.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# Read-only exploration
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-6-luna"),
  tools = tools_preset("minimal"),
  permissions = permissions_readonly()
)

# Reading and writing files
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-6-luna"),
  tools = tools_preset("standard")
)

# Data analysis with R code
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-6-luna"),
  tools = tools_preset("data"),
  permissions = Permissions(r_code = TRUE)
)
} # }
```
