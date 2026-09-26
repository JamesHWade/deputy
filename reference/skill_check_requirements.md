# Check a skill's requirements

Checks whether the packages a
[Skill](https://jameshwade.github.io/deputy/reference/Skill.md) needs
are installed and, if you give `current_provider`, whether the skill
supports that provider. Nothing is installed, loaded or run.

## Usage

``` r
skill_check_requirements(skill, current_provider = NULL)
```

## Arguments

- skill:

  A [Skill](https://jameshwade.github.io/deputy/reference/Skill.md).

- current_provider:

  Optional provider name, such as `"openai"` or `"anthropic"`. Common
  aliases match their provider (`"claude"` and `"chat_anthropic"` both
  mean `"anthropic"`); other names must match exactly, ignoring case.
  `NULL` skips the provider check.

## Value

A list with `ok` (`TRUE` if nothing is missing or mismatched), `missing`
(such as `"package:readr"`), `provider_mismatch`, `current_provider`,
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
