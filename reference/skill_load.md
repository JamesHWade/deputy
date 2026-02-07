# Load a skill from a directory

Loads a skill from a directory containing `SKILL.yaml` (metadata) and/or
`SKILL.md` (system prompt extension). You can also pass a direct path to
a `SKILL.md` file.

## Usage

``` r
skill_load(path, check_requirements = TRUE)
```

## Arguments

- path:

  Path to the skill directory

- check_requirements:

  If TRUE (default), verify requirements are met

## Value

A [Skill](https://jameshwade.github.io/deputy/reference/Skill.md) object

## Details

The skill directory should contain one of:

**SKILL.yaml** (required):

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

**SKILL.md** (optional, or standalone file): Markdown content that will
be appended to the agent's system prompt when this skill is loaded.
Frontmatter is supported:

    ---
    name: my_skill
    description: Optional description
    requires:
      packages: [dplyr]
    ---

**tools.R** (optional): R file containing tool definitions referenced in
SKILL.yaml.

## Examples

``` r
if (FALSE) { # \dontrun{
# Load a skill
skill <- skill_load("path/to/my_skill")

# Add to agent
agent$load_skill(skill)
} # }
```
