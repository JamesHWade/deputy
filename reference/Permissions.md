# Permissions R6 Class

Controls what an agent is allowed to do. Permissions can be configured
with fine-grained controls for different tool types, or with a custom
callback for complex logic.

Tool gating fields:

- `tool_allowlist`: Optional list of tools that are allowed. When set,
  tools not in the list are denied.

- `tool_denylist`: Optional list of tools that are always denied.

- `permission_prompt_tool_name`: Optional tool name to mention in deny
  messages for gated tools (e.g., "ask_user").

**Security Note:** Permission fields are immutable after construction.
This prevents adversarial code from modifying permissions at runtime.
All fields use active bindings that reject modification attempts.

## Active bindings

- `mode`:

  Permission mode (see
  [PermissionMode](https://jameshwade.github.io/deputy/reference/PermissionMode.md)).
  Read-only after construction.

- `file_read`:

  Allow file reading. Read-only after construction.

- `file_write`:

  Allow file writing. Can be `TRUE`, `FALSE`, or a canonical absolute
  directory path. Read-only after construction.

- `bash`:

  Allow bash command execution. Read-only after construction.

- `r_code`:

  Allow R code execution. Read-only after construction.

- `web`:

  Allow web requests. Read-only after construction.

- `install_packages`:

  Allow package installation. Read-only after construction.

- `can_use_tool`:

  Custom permission callback. Read-only after construction.

- `tool_allowlist`:

  Optional character vector of allowed tool names. Read-only after
  construction.

- `tool_denylist`:

  Optional character vector of denied tool names. Read-only after
  construction.

- `permission_prompt_tool_name`:

  Optional tool name used in gating deny messages. Read-only after
  construction.

## Methods

### Public methods

- [`Permissions$new()`](#method-Permissions-initialize)

- [`Permissions$check()`](#method-Permissions-check)

- [`Permissions$print()`](#method-Permissions-print)

- [`Permissions$clone()`](#method-Permissions-clone)

------------------------------------------------------------------------

### `Permissions$new()`

Create a new Permissions object.

#### Usage

    Permissions$new(
      mode = "standard",
      file_read = TRUE,
      file_write = getwd(),
      bash = FALSE,
      r_code = FALSE,
      web = FALSE,
      install_packages = FALSE,
      can_use_tool = NULL,
      tool_allowlist = NULL,
      tool_denylist = NULL,
      permission_prompt_tool_name = NULL
    )

#### Arguments

- `mode`:

  Permission mode

- `file_read`:

  Allow file reading

- `file_write`:

  Allow file writing (`TRUE`, `FALSE`, or an existing absolute directory
  path). Directory grants are canonicalized once when the policy is
  constructed.

- `bash`:

  Allow bash commands

- `r_code`:

  Allow R code execution. Defaults to `FALSE`; grant it explicitly for
  trusted code or use
  [`permissions_full()`](https://jameshwade.github.io/deputy/reference/permissions_full.md).

- `web`:

  Allow web requests

- `install_packages`:

  Allow package installation

- `can_use_tool`:

  Custom callback function

- `tool_allowlist`:

  Optional character vector of allowed tool names

- `tool_denylist`:

  Optional character vector of denied tool names

- `permission_prompt_tool_name`:

  Optional dedicated approval-tool name to suggest in permission deny
  messages for gated tools. Native capability-bearing tools cannot be
  used as approval prompts.

#### Returns

A new `Permissions` object

------------------------------------------------------------------------

### `Permissions$check()`

Check if a tool is allowed to execute.

#### Usage

    Permissions$check(tool_name, tool_input, context = list())

#### Arguments

- `tool_name`:

  Name of the tool

- `tool_input`:

  Arguments passed to the tool

- `context`:

  Additional context (e.g., working_dir, tool_annotations)

#### Returns

A
[PermissionResultAllow](https://jameshwade.github.io/deputy/reference/PermissionResultAllow.md)
or
[PermissionResultDeny](https://jameshwade.github.io/deputy/reference/PermissionResultDeny.md)

------------------------------------------------------------------------

### `Permissions$print()`

Print the permissions configuration.

#### Usage

    Permissions$print()

------------------------------------------------------------------------

### `Permissions$clone()`

The objects of this class are cloneable with this method.

#### Usage

    Permissions$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.
