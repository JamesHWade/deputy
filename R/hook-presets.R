# Built-in hook presets for logging and policy enforcement.

#' Create a hook that logs tool calls
#'
#' @description
#' Creates a PostToolUse hook that prints a cli line after each tool call,
#' saying whether it succeeded or failed. It returns `NULL`, so hooks added
#' after it still run.
#'
#' @param verbose If `TRUE`, also print the first 100 characters of each
#'   successful result.
#' @return A [HookMatcher].
#'
#' @examples
#' \dontrun{
#' agent$add_hook(hook_log_tools())
#' }
#'
#' @export
hook_log_tools <- function(verbose = FALSE) {
  HookMatcher(
    event = "PostToolUse",
    timeout = 0, # Run in main process for cli output
    callback = function(tool_name, tool_result, tool_error, context) {
      if (!is.null(tool_error)) {
        cli::cli_alert_danger("Tool {tool_name} failed: {tool_error}")
      } else {
        cli::cli_alert_success("Tool {tool_name} completed")
        if (verbose && !is.null(tool_result)) {
          result_preview <- truncate_string(as.character(tool_result), 100)
          cli::cli_alert_info("Result: {result_preview}")
        }
      }
      # Only observes: let later PostToolUse hooks run.
      NULL
    }
  )
}

#' Create a hook that blocks dangerous bash commands
#'
#' @description
#' Creates a PreToolUse hook that denies `run_bash` commands matching any of a
#' set of regular expressions (case-insensitive). The default patterns cover:
#'
#' * file system destruction: `rm -rf`, `mkfs`, `dd if=`, writes to `/dev/`;
#' * privilege escalation: `sudo`, `su -`, `chmod 777`, `chown root`,
#'   `setuid`;
#' * code execution: `eval`, `exec`, `source $VAR`, backticks, `$(...)`,
#'   `python -c` and similar one-liners;
#' * process manipulation: `kill -9`, `killall`, `pkill -9`, fork bombs;
#' * system files and services: `crontab`, `systemctl`, `/etc/passwd`,
#'   `/etc/shadow`, `/etc/sudoers`;
#' * credentials and history: `printenv`, reading `.ssh`, `.aws` or `.env`
#'   files, clearing shell history;
#' * network exfiltration: `curl -X POST`, `wget --post`, `nc -e`, `netcat`,
#'   reverse shells;
#' * obfuscation: variable expansion, piping `base64` output to a shell,
#'   hex and octal escapes, quote splitting, backslash escapes.
#'
#' The patterns are broad, so they also block some harmless commands. A
#' denylist can't catch every obfuscated command either. To keep shell
#' commands contained, turn off `bash` in [Permissions] or run the agent in a
#' container or other OS sandbox.
#'
#' The hook returns a denial for a matching command and `NULL` otherwise, so
#' hooks added after it still see the commands it lets through.
#'
#' @param patterns Character vector of regular expressions to block. `NULL`
#'   (the default) uses the built-in patterns.
#' @param additional_patterns Optional character vector of extra patterns to
#'   block as well.
#' @return A [HookMatcher].
#'
#' @examples
#' \dontrun{
#' # Use default patterns
#' agent$add_hook(hook_block_dangerous_bash())
#'
#' # Add custom patterns
#' agent$add_hook(hook_block_dangerous_bash(
#'   additional_patterns = c("my_custom_pattern", "another_pattern")
#' ))
#' }
#'
#' @export
hook_block_dangerous_bash <- function(
  patterns = NULL,
  additional_patterns = NULL
) {
  # Default dangerous patterns
  default_patterns <- c(
    # File system destruction
    "rm\\s+-rf",
    "rm\\s+-fr",
    "rm\\s+--no-preserve-root",
    "mkfs",
    "dd\\s+if=",
    ">\\s*/dev/",
    "shred\\s",

    # Privilege escalation
    "sudo\\s",
    "su\\s+-",
    "chmod\\s+777",
    "chmod\\s+\\+s",
    "chown\\s+root",
    "setuid",
    "setgid",

    # Code execution patterns
    "\\beval\\s",
    "\\bexec\\s",
    "source\\s+\\$",
    "`.*`",
    "\\$\\(.*\\)",

    # Process manipulation
    "kill\\s+-9",
    "killall\\s",
    "pkill\\s+-9",
    ":\\s*\\(\\s*\\)\\s*\\{",
    "\\|\\s*:\\s*&",

    # System modification
    "crontab\\s+-e",
    "crontab\\s.*<",
    "systemctl\\s+(disable|stop|mask)",
    "/etc/passwd",
    "/etc/shadow",
    "/etc/sudoers",
    "visudo",
    "usermod",
    "useradd.*-o",

    # Network exfiltration/reverse shells
    "curl\\s.*-X\\s*POST",
    "curl\\s.*--data",
    "curl\\s.*-d\\s",
    "wget\\s+--post",
    "nc\\s+-e",
    "nc\\s.*-c",
    "netcat",
    "ncat\\s+-e",
    "/dev/tcp/",
    "/dev/udp/",
    "bash\\s+-i\\s+>&",
    "python.*socket",
    "perl.*socket",

    # Environment/credential access
    "\\benv\\b.*=.*\\bexport\\b",
    "printenv",
    "cat\\s+.*\\.ssh/",
    "cat\\s+.*\\.aws/",
    "cat\\s+.*\\.env",
    "base64\\s+-d",

    # History manipulation
    "history\\s+-c",
    "unset\\s+HISTFILE",
    "export\\s+HISTFILE=/dev/null",

    # === OBFUSCATION DETECTION ===

    # Variable-based command execution (CMD=rm; $CMD -rf)
    "\\$[A-Za-z_][A-Za-z0-9_]*\\s*-", # $VAR followed by flags
    "\\$\\{[^}]+\\}\\s*-", # ${VAR} followed by flags

    # Dangerous variable assignments followed by execution
    "=['\"]?rm['\"]?\\s*[;&|]", # VAR=rm; or VAR='rm' &&
    "=['\"]?sudo['\"]?\\s*[;&|]",
    "=['\"]?dd['\"]?\\s*[;&|]",
    "=['\"]?chmod['\"]?\\s*[;&|]",
    "=['\"]?mkfs['\"]?\\s*[;&|]",

    # Base64/encoding piping to shell
    "base64.*\\|.*\\b(ba)?sh\\b", # base64 -d | bash
    "\\|\\s*(ba)?sh\\s*$", # anything | bash at end
    "\\|\\s*/bin/(ba)?sh", # pipe to /bin/bash
    "xxd.*\\|.*\\b(ba)?sh\\b", # xxd -r | bash (hex decoding)
    "printf.*\\\\x.*\\|", # printf with hex escapes piped

    # Quote splitting obfuscation (r"m" or 'r''m')
    "['\"][a-z]['\"]['\"]?[a-z]", # "r""m" style splitting
    "\\\\[a-z]", # \r\m backslash escaping in commands

    # Hex/octal escape sequences in commands
    "\\$'\\\\x[0-9a-fA-F]", # $'\x72\x6d' style
    "\\$'\\\\[0-7]{3}", # $'\162\155' octal style
    "echo\\s+-e.*\\\\x", # echo -e with hex
    "printf.*%s.*\\\\x", # printf with hex

    # IFS manipulation (space replacement attacks)
    "IFS=", # IFS manipulation
    "\\$\\{IFS\\}", # ${IFS} usage

    # Brace expansion attacks
    "\\{[a-z],[a-z]\\}", # {r,m} style

    # Here-string/here-doc to shell
    "<<<.*\\b(ba)?sh\\b", # <<< to bash
    "<<\\s*['\"]?EOF", # heredoc markers (suspicious in single commands)

    # Aliases and functions for evasion
    "alias\\s+[a-z]+=", # alias definitions
    "function\\s+[a-z]+\\s*\\(", # function definitions

    # Network data exfiltration via DNS/other channels
    "dig\\s+.*\\$", # DNS exfiltration with variables
    "nslookup\\s+.*\\$",
    "host\\s+.*\\$",

    # Additional shell escapes
    "xargs.*\\b(ba)?sh\\b", # xargs feeding to shell
    "find.*-exec.*\\b(ba)?sh\\b", # find -exec bash
    "awk.*system\\s*\\(", # awk system() calls
    "perl\\s+-e", # perl one-liners
    "python\\s+-c", # python one-liners
    "ruby\\s+-e", # ruby one-liners

    # Process substitution attacks
    "<\\(.*\\b(ba)?sh\\b", # <(bash ...) process substitution
    ">\\(.*\\b(ba)?sh\\b" # >(bash ...) process substitution
  )

  # Use provided patterns or defaults
  if (is.null(patterns)) {
    patterns <- default_patterns
  }

  # Add any additional patterns
  if (!is.null(additional_patterns)) {
    patterns <- c(patterns, additional_patterns)
  }

  combined_pattern <- paste(patterns, collapse = "|")

  HookMatcher(
    event = "PreToolUse",
    pattern = "^(run_bash|bash|tool_run_bash)$",
    timeout = 0, # Run in main process
    callback = function(tool_name, tool_input, context) {
      command <- tool_input$command %||% ""

      if (grepl(combined_pattern, command, ignore.case = TRUE)) {
        return(HookResultPreToolUse(
          permission = "deny",
          reason = "Blocked: potentially dangerous command pattern detected"
        ))
      }
      # No objection: let later PreToolUse hooks decide.
      NULL
    }
  )
}

#' Create a hook that limits file writes to a directory
#'
#' @description
#' Creates a PreToolUse hook that denies `write_file`, `edit_file` and
#' `multi_edit` calls outside `allowed_dir`, using the same path checks as
#' `Permissions(file_write = allowed_dir)`. Setting `file_write` in the
#' agent's [Permissions] is the main way to limit writes; this hook adds a
#' second check.
#'
#' The hook returns a denial for a write outside `allowed_dir` and `NULL`
#' otherwise, so hooks added after it still see the writes it lets through.
#'
#' @param allowed_dir An existing directory where writes are allowed. It is
#'   resolved to an absolute path when the hook is created.
#' @return A [HookMatcher].
#'
#' @examples
#' \dontrun{
#' dir.create("output", showWarnings = FALSE)
#' agent$add_hook(hook_limit_file_writes("output"))
#' }
#'
#' @seealso [Permissions]
#' @export
hook_limit_file_writes <- function(allowed_dir) {
  allowed_dir <- normalizePath(allowed_dir, mustWork = TRUE)
  permissions <- Permissions(
    file_write = allowed_dir,
    bash = FALSE,
    r_code = FALSE,
    web = FALSE,
    install_packages = FALSE
  )

  HookMatcher(
    event = "PreToolUse",
    pattern = "^(write_file|edit_file|multi_edit)$",
    timeout = 0, # Run in main process
    callback = function(tool_name, tool_input, context) {
      result <- permissions_check(permissions, tool_name, tool_input, context)
      if (identical(result$decision, "deny")) {
        return(HookResultPreToolUse(
          permission = "deny",
          reason = result$reason
        ))
      }
      # No objection: let later PreToolUse hooks decide.
      NULL
    }
  )
}
