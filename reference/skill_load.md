# Load a skill from a directory

Loads a skill from a directory containing `SKILL.yaml` (metadata and
tools), `SKILL.md` (prompt text) or both, or from a single Markdown
file. Loading a skill with tools runs its R files, so only load skills
you trust.

## Usage

``` r
skill_load(path, check_requirements = TRUE)
```

## Arguments

- path:

  Path to the skill directory or Markdown file.

- check_requirements:

  If `TRUE` (the default), warn when required packages are missing.

## Value

A [Skill](https://jameshwade.github.io/deputy/reference/Skill.md).

## Details

`SKILL.yaml` needs a `name`. Each entry under `tools` names an R file in
the skill directory and the object in it created with
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html);
entries that can't be loaded are skipped with a warning.

    name: my_skill
    version: "1.0.0"
    description: What this skill does
    requires:
      packages: [dplyr, ggplot2]
      providers: [openai, anthropic]
    tools:
      - name: my_tool
        file: tools.R
        function: tool_my_tool

The body of `SKILL.md` is added to the agent's system prompt. Its
optional YAML front matter overrides fields from `SKILL.yaml`:

    ---
    name: my_skill
    description: Optional description
    requires:
      packages: [dplyr]
    ---

A skill without a name is named after its directory or file. Reading
YAML needs the yaml package.

## Examples

``` r
if (FALSE) { # \dontrun{
# Load a skill
skill <- skill_load("path/to/my_skill")

# Add to agent
agent$load_skill(skill)
} # }
```
