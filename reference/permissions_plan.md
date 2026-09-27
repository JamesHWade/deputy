# Create a planning permission policy

Creates a `"plan"` policy, for letting the model look around and propose
a plan before it changes anything. Only tools annotated as read-only are
allowed, plus the approval prompt tool and delegation to the agent's
subagents and retained agents, which are held to plan mode too. Web
access is on, so read-only web tools such as `web_fetch` work. Writes
and code execution are denied.

## Usage

``` r
permissions_plan(permission_prompt_tool_name = "ask_user")
```

## Arguments

- permission_prompt_tool_name:

  Name of the tool the model can call to ask for approval, `"ask_user"`
  by default. `NULL` means none. Built-in file, code, web, install and
  delegation tools can't be used.

## Value

A
[Permissions](https://jameshwade.github.io/deputy/reference/Permissions.md)
object.

## Examples

``` r
perms <- permissions_plan()
```
