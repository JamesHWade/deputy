# Create a hook that blocks dangerous bash commands

Convenience function to create a PreToolUse hook that blocks potentially
dangerous bash commands. Default patterns include:

**File system destruction:** `rm -rf`, `mkfs`, `dd if=`, writes to
`/dev/`

**Privilege escalation:** `sudo`, `su -`, `chmod 777`, `chown`, `setuid`

**Code execution:** `eval`, `exec`, `source` (with variables), backticks

**Process manipulation:** `kill -9`, `killall`, `pkill`, fork bombs

**System modification:** `crontab`, `systemctl`, `/etc/passwd`,
`/etc/shadow`

**Network exfiltration:** `curl -X POST`, `wget --post`, `nc -e`,
`netcat`, reverse shells

**Obfuscation detection:** Variable expansion in commands, base64
piping, hex/octal escapes, quote splitting, backslash escapes

**Security Note:** This is defense-in-depth and cannot catch all
possible obfuscation techniques. For high-security environments,
consider:

1.  Using sandboxed execution (Docker, firejail)

2.  Disabling bash entirely via
    [Permissions](https://jameshwade.github.io/deputy/reference/Permissions.md)

3.  Using a command whitelist instead of blacklist

## Usage

``` r
hook_block_dangerous_bash(patterns = NULL, additional_patterns = NULL)
```

## Arguments

- patterns:

  Character vector of regex patterns to block. Default includes
  comprehensive dangerous patterns.

- additional_patterns:

  Optional character vector of additional patterns to block alongside
  defaults.

## Value

A
[HookMatcher](https://jameshwade.github.io/deputy/reference/HookMatcher.md)
object

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
