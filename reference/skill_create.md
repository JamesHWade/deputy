# Create a skill programmatically

Create a skill without loading from disk. Useful for defining skills
inline in R code.

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

  Skill name

- description:

  Brief description

- prompt:

  System prompt extension

- tools:

  List of tools created with
  [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)

- version:

  Version string (default: "1.0.0")

- requires:

  List of requirements (packages, providers)

## Value

A [Skill](https://jameshwade.github.io/deputy/reference/Skill.md) object

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
