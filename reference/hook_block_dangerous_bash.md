# Create a hook that blocks dangerous bash commands

Creates a PreToolUse hook that denies `run_bash` commands matching any
of a set of regular expressions (case-insensitive). The default patterns
cover:

- file system destruction: `rm -rf`, `mkfs`, `dd if=`, writes to
  `/dev/`;

- privilege escalation: `sudo`, `su -`, `chmod 777`, `chown root`,
  `setuid`;

- code execution: `eval`, `exec`, `source $VAR`, backticks, `$(...)`,
  `python -c` and similar one-liners;

- process manipulation: `kill -9`, `killall`, `pkill -9`, fork bombs;

- system files and services: `crontab`, `systemctl`, `/etc/passwd`,
  `/etc/shadow`, `/etc/sudoers`;

- credentials and history: `printenv`, reading `.ssh`, `.aws` or `.env`
  files, clearing shell history;

- network exfiltration: `curl -X POST`, `wget --post`, `nc -e`,
  `netcat`, reverse shells;

- obfuscation: variable expansion, piping `base64` output to a shell,
  hex and octal escapes, quote splitting, backslash escapes.

The patterns are broad, so they also block some harmless commands. A
denylist can't catch every obfuscated command either. To keep shell
commands contained, turn off `bash` in
[Permissions](https://jameshwade.github.io/deputy/reference/Permissions.md)
or run the agent in a container or other OS sandbox.

The hook returns a denial for a matching command and `NULL` otherwise,
so hooks added after it still see the commands it lets through.

## Usage

``` r
hook_block_dangerous_bash(patterns = NULL, additional_patterns = NULL)
```

## Arguments

- patterns:

  Character vector of regular expressions to block. `NULL` (the default)
  uses the built-in patterns.

- additional_patterns:

  Optional character vector of extra patterns to block as well.

## Value

A
[HookMatcher](https://jameshwade.github.io/deputy/reference/HookMatcher.md).

## Examples

``` r
if (FALSE) { # \dontrun{
# Use default patterns
agent$add_hook(hook_block_dangerous_bash())

# Add custom patterns
agent$add_hook(hook_block_dangerous_bash(
  additional_patterns = c("my_custom_pattern", "another_pattern")
))
} # }
```
