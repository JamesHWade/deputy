# Skill R6 Class

Represents a skill that can be loaded into an agent. Skills bundle
together a system prompt extension, tools, and metadata about
requirements.

## Public fields

- `name`:

  Skill name

- `version`:

  Skill version

- `description`:

  Brief description of the skill

- `prompt`:

  System prompt extension (from SKILL.md)

- `tools`:

  List of tools provided by this skill

- `requires`:

  Requirements (packages, providers)

- `path`:

  Path to the skill directory

## Methods

### Public methods

- [`Skill$new()`](#method-Skill-new)

- [`Skill$check_requirements()`](#method-Skill-check_requirements)

- [`Skill$print()`](#method-Skill-print)

- [`Skill$clone()`](#method-Skill-clone)

------------------------------------------------------------------------

### Method `new()`

Create a new Skill object.

#### Usage

    Skill$new(
      name,
      version = "0.0.0",
      description = NULL,
      prompt = NULL,
      tools = list(),
      requires = list(),
      path = NULL
    )

#### Arguments

- `name`:

  Skill name

- `version`:

  Skill version (default: "0.0.0")

- `description`:

  Brief description

- `prompt`:

  System prompt extension

- `tools`:

  List of tools

- `requires`:

  List of requirements

- `path`:

  Path to skill directory

#### Returns

A new `Skill` object

------------------------------------------------------------------------

### Method `check_requirements()`

Check if skill requirements are met.

#### Usage

    Skill$check_requirements(current_provider = NULL)

#### Arguments

- `current_provider`:

  Optional current provider name for validation

#### Returns

List with `ok` (logical), `missing` (character vector), and
`provider_mismatch` (logical)

------------------------------------------------------------------------

### Method [`print()`](https://rdrr.io/r/base/print.html)

Print the skill.

#### Usage

    Skill$print()

------------------------------------------------------------------------

### Method `clone()`

The objects of this class are cloneable with this method.

#### Usage

    Skill$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.
