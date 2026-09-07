# Declarative Skill Configuration

A read-only S7 value bundling a prompt extension, original ellmer tools,
and declared package and provider requirements. Load a Skill into an
[Agent](https://jameshwade.github.io/deputy/reference/Agent.md) with
`agent$load_skill(skill)`.

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

  Non-empty skill name, retained as supplied.

- version:

  Non-empty version string. Defaults to `"0.0.0"`;
  [`skill_create()`](https://jameshwade.github.io/deputy/reference/skill_create.md)
  retains its `"1.0.0"` default.

- description:

  Optional description.

- prompt:

  Optional system prompt extension.

- tools:

  List of tools created with
  [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).

- requires:

  List with optional `packages` and `providers` entries. Each entry
  contains strings, or is NULL or an empty sequence. Other declarative
  metadata is retained but not evaluated.

- path:

  Optional path to the skill directory. Construction does not inspect or
  load this path.

## Value

A read-only `Skill` S7 value.

## Details

Construct skills with `Skill(...)`,
[`skill_create()`](https://jameshwade.github.io/deputy/reference/skill_create.md),
or
[`skill_load()`](https://jameshwade.github.io/deputy/reference/skill_load.md).
Read properties with `$`, `@`, or
[`S7::prop()`](https://rconsortium.github.io/S7/reference/prop.html). To
revise configuration, edit `S7::props(skill)` and pass that list to
`do.call(Skill, fields)`. Individual and bulk property replacement are
rejected, including initially NULL fields. Requirements are declarative
package/provider sequences.

Executable tools are composed without cloning. Their closures, clients,
services, and caller-owned environments retain their original semantics;
read-only Skill configuration does not freeze state inside those tools.
Neither construction nor
[`skill_check_requirements()`](https://jameshwade.github.io/deputy/reference/skill_check_requirements.md)
executes tool code.
[`skill_load()`](https://jameshwade.github.io/deputy/reference/skill_load.md)
remains the explicit boundary that can source declared tools.

RDS can preserve the value and serializable R object graphs after Deputy
loads in the receiving process. It is not a portable transport for live
services or connections. AgentDefinition YAML uses explicit host
registries to attach skills; it does not embed executable Skill objects.

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
