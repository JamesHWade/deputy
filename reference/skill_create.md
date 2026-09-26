# Create a skill in code

Creates a
[Skill](https://jameshwade.github.io/deputy/reference/Skill.md) in R
instead of loading one from disk. It is the same as
[`Skill()`](https://jameshwade.github.io/deputy/reference/Skill.md),
except that `version` defaults to `"1.0.0"`.

## Usage

``` r
skill_create(
  name,
  description = NULL,
  prompt = NULL,
  tools = list(),
  version = "1.0.0",
  requires = list()
)
```

## Arguments

- name:

  Skill name.

- description:

  Short description.

- prompt:

  Text to add to the system prompt.

- tools:

  List of tools created with
  [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).

- version:

  Version string. Defaults to `"1.0.0"`.

- requires:

  List with optional `packages` and `providers` character vectors.

## Value

A [Skill](https://jameshwade.github.io/deputy/reference/Skill.md).

## Examples

``` r
if (FALSE) { # \dontrun{
# Create a simple skill
my_skill <- skill_create(
  name = "calculator",
  description = "Basic math operations",
  prompt = "You are a helpful calculator assistant.",
  tools = list(tool_add, tool_multiply)
)

agent$load_skill(my_skill)
} # }
```
