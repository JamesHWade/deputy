# Reusable instructions and tools

A skill bundles extra system prompt text, tools, and the packages and
providers it needs, so you can add them to an
[Agent](https://jameshwade.github.io/deputy/reference/Agent.md) in one
step with `agent$load_skill(skill)`.

## Usage

``` r
Skill(
  name,
  version = "0.0.0",
  description = NULL,
  prompt = NULL,
  tools = list(),
  requires = list(),
  path = NULL
)
```

## Arguments

- name:

  Skill name.

- version:

  Version string. Defaults to `"0.0.0"`
  ([`skill_create()`](https://jameshwade.github.io/deputy/reference/skill_create.md)
  defaults to `"1.0.0"`).

- description:

  Optional description.

- prompt:

  Optional text to add to the system prompt.

- tools:

  List of tools created with
  [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).

- requires:

  List with optional `packages` and `providers` entries, each a
  character vector. Other entries are kept but not checked. It must hold
  only plain data, not functions or environments.

- path:

  Optional path to the skill directory. It is recorded, not read.

## Value

A read-only `Skill` S7 object.

## Details

Create skills with `Skill()`,
[`skill_create()`](https://jameshwade.github.io/deputy/reference/skill_create.md),
or
[`skill_load()`](https://jameshwade.github.io/deputy/reference/skill_load.md).
Skills are read-only: read fields with `$`, and to change one, edit
`S7::props(skill)` and pass the list back to `Skill()` with
[`do.call()`](https://rdrr.io/r/base/do.call.html), as in the example.

Tools are stored as given, not copied, so any state they hold is shared
with the originals. Creating a skill or checking its requirements never
runs tool code;
[`skill_load()`](https://jameshwade.github.io/deputy/reference/skill_load.md)
runs the R files a skill's tools come from.

## Examples

``` r
concise <- Skill("concise", prompt = "Answer in one short paragraph.")
fields <- S7::props(concise)
fields$prompt <- "Answer in one sentence."
shorter <- do.call(Skill, fields)
shorter$prompt
#> [1] "Answer in one sentence."
concise$prompt
#> [1] "Answer in one short paragraph."
skill_check_requirements(concise)$ok
#> [1] TRUE
```
