# Get all built-in tools

Returns every built-in tool except `ask_user`, which you can add with
[`tools_interactive()`](https://jameshwade.github.io/deputy/reference/tools_interactive.md).
That includes `run_r_code` and `run_bash`, which run with your user
account's access and are not sandboxed. The default permissions deny
them and the web tools;
[`permissions_full()`](https://jameshwade.github.io/deputy/reference/permissions_full.md)
allows everything.

## Usage

``` r
tools_all()
```

## Value

A list of tools.

## Examples

``` r
if (FALSE) { # \dontrun{
# Allow every tool
agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-6-luna"),
  tools = tools_all(),
  permissions = permissions_full()
)
} # }
```
