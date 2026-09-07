# Check Skill Requirements

Report missing packages and provider compatibility for a
[Skill](https://jameshwade.github.io/deputy/reference/Skill.md). This
function does not install packages, load the skill, or execute its
tools.

## Usage

``` r
skill_check_requirements(skill, current_provider = NULL)
```

## Arguments

- skill:

  A [Skill](https://jameshwade.github.io/deputy/reference/Skill.md)
  value.

- current_provider:

  Optional current provider name. Known aliases are normalized; other
  provider names use case-insensitive exact matching. NULL skips the
  provider check.

## Value

A list with `ok`, `missing`, `provider_mismatch`, `current_provider`,
and `required_providers`.

## Examples

``` r
skill <- Skill("calculator", requires = list(packages = "stats"))
skill_check_requirements(skill)
#> $ok
#> [1] TRUE
#> 
#> $missing
#> character(0)
#> 
#> $provider_mismatch
#> [1] FALSE
#> 
#> $current_provider
#> NULL
#> 
#> $required_providers
#> NULL
#> 
```
