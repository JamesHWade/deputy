# Permission system for deputy agents

#' Permission modes for agent tool access
#'
#' @description
#' Permission modes control the overall behavior of tool permission checking:
#' * `"standard"` - Check each tool against the configured capabilities
#' * `"plan"` - Allow annotated read-only tools within configured capabilities
#'   plus human approval prompts
#' * `"readonly"` - Deny all write/execute tools
#' * `"full"` - Allow all tools (dangerous, use with caution)
#'
#' @section Tool Annotations:
#'
#' Permissions use tool annotations (from [ellmer::tool_annotations()]) to
#' determine tool behavior. Available annotations:
#'
#' **read_only_hint** (logical, default: FALSE)
#'
#' Indicates the tool only reads data and doesn't modify state. Annotations are
#' descriptive metadata, not an authority grant: `"readonly"` mode allows known
#' Deputy read tools or explicit allowlist entries, subject to destructive and
#' open-world capability checks. Examples: `tool_read_file`, `tool_list_files`,
#' `tool_search`.
#'
#' **destructive_hint** (logical, default: TRUE)
#'
#' Indicates the tool may cause destructive/irreversible changes.
#' Tools with `destructive_hint = TRUE` require explicit permission.
#' Examples: `tool_write_file`, `tool_delete_file`, `tool_run_bash`
#'
#' **open_world_hint** (logical, default: TRUE)
#'
#' Indicates the tool may interact with external systems.
#' Used for network calls, package installation, etc.
#' Examples: `tool_web_search`, `tool_install_package`
#'
#' **idempotent_hint** (logical, default: FALSE)
#'
#' Indicates repeated calls produce the same result.
#' This annotation alone does not authorize automatic retries.
#'
#' Missing annotations remain absent on the tool. For custom tools, permission
#' checks assume modification, possible destruction, external access, and no
#' idempotence unless stated otherwise. If `read_only_hint = TRUE`, an omitted
#' destructive annotation is ignored; an explicit TRUE still denies read-only
#' use. Native tools continue to require their named capabilities. A custom
#' permission callback can explicitly authorize a tool in standard mode;
#' full mode bypasses annotation checks but still honors tool gating.
#'
#' @section Creating Tools with Annotations:
#'
#' ```r
#' # Read-only tool
#' tool_search <- ellmer::tool(
#'   fun = function(pattern) grep(pattern, files),
#'   name = "search",
#'   description = "Search for pattern",
#'   arguments = list(pattern = ellmer::type_string("Search pattern")),
#'   annotations = ellmer::tool_annotations(
#'     read_only_hint = TRUE,
#'     destructive_hint = FALSE,
#'     open_world_hint = FALSE
#'   )
#' )
#'
#' # Destructive tool
#' tool_delete <- ellmer::tool(
#'   fun = function(path) unlink(path),
#'   name = "delete",
#'   description = "Delete a file",
#'   arguments = list(path = ellmer::type_string("File path")),
#'   annotations = ellmer::tool_annotations(
#'     read_only_hint = FALSE,
#'     destructive_hint = TRUE
#'   )
#' )
#' ```
#'
#' @seealso [Permissions], [permissions_standard()], [permissions_plan()],
#'   [permissions_readonly()], and [permissions_full()].
#' @export
PermissionMode <- c(
  "standard",
  "plan",
  "readonly",
  "full"
)

permission_file_read_tool_ids <- c(
  "read_file",
  "read_markdown",
  "read_csv",
  "list_files",
  "glob_files",
  "grep_files"
)

permission_native_capability_tool_ids <- c(
  permission_file_read_tool_ids,
  "write_file",
  "edit_file",
  "multi_edit",
  "run_bash",
  "run_r_code",
  "web_search",
  "web_fetch",
  "install_package",
  "delegate_to_agent"
)

is_permission_file_read_tool <- function(tool_name) {
  normalize_native_tool_id(tool_name) %in% permission_file_read_tool_ids
}

is_permission_native_capability_tool <- function(tool_name) {
  normalize_native_tool_id(tool_name) %in%
    permission_native_capability_tool_ids
}

# Validate a permission mode string.
validate_permission_mode_value <- function(mode, arg = "mode") {
  if (!is.character(mode) || length(mode) != 1 || is.na(mode)) {
    cli_abort("{.arg {arg}} must be a length-1 character string")
  }

  if (!mode %in% PermissionMode) {
    cli_abort(c(
      "Invalid permission mode: {.val {mode}}",
      "i" = "{.arg {arg}} must be one of {.val {PermissionMode}}"
    ))
  }

  mode
}

permission_mode_capabilities <- function(mode, working_dir = getwd()) {
  mode <- validate_permission_mode_value(mode)
  switch(
    mode,
    standard = list(
      file_read = TRUE,
      file_write = working_dir,
      bash = FALSE,
      r_code = FALSE,
      web = FALSE,
      install_packages = FALSE,
      permission_prompt_tool_name = NULL
    ),
    plan = list(
      file_read = TRUE,
      file_write = FALSE,
      bash = FALSE,
      r_code = FALSE,
      web = TRUE,
      install_packages = FALSE,
      permission_prompt_tool_name = "ask_user"
    ),
    readonly = list(
      file_read = TRUE,
      file_write = FALSE,
      bash = FALSE,
      r_code = FALSE,
      web = FALSE,
      install_packages = FALSE,
      permission_prompt_tool_name = NULL
    ),
    full = list(
      file_read = TRUE,
      file_write = TRUE,
      bash = TRUE,
      r_code = TRUE,
      web = TRUE,
      install_packages = TRUE,
      permission_prompt_tool_name = NULL
    )
  )
}

# Return the modes that do not widen or replace an existing mode policy.
permission_mode_targets <- function(mode) {
  mode <- validate_permission_mode_value(mode)
  switch(
    mode,
    full = PermissionMode,
    standard = c("standard", "readonly"),
    plan = c("plan", "readonly"),
    readonly = "readonly"
  )
}

# Extract the capability fields that form an immutable permission ceiling.
permission_capabilities_from <- function(permissions) {
  list(
    file_read = permissions$file_read,
    file_write = permissions$file_write,
    bash = permissions$bash,
    r_code = permissions$r_code,
    web = permissions$web,
    install_packages = permissions$install_packages,
    permission_prompt_tool_name = permissions$permission_prompt_tool_name
  )
}

# Intersect two file-write grants. Directory grants are ordered by containment;
# disjoint or malformed grants fail closed.
intersect_file_write_capability <- function(ceiling, requested) {
  if (isFALSE(ceiling) || isFALSE(requested)) {
    return(FALSE)
  }
  if (isTRUE(ceiling)) {
    if (isTRUE(requested)) {
      return(TRUE)
    }
    requested_root <- canonical_permission_root(requested)
    return(if (is.na(requested_root)) FALSE else requested_root)
  }
  if (isTRUE(requested)) {
    ceiling_root <- canonical_permission_root(ceiling)
    return(if (is.na(ceiling_root)) FALSE else ceiling_root)
  }

  ceiling_root <- canonical_permission_root(ceiling)
  requested_root <- canonical_permission_root(requested)
  if (is.na(ceiling_root) || is.na(requested_root)) {
    return(FALSE)
  }

  if (is_canonical_permission_root_within(ceiling_root, requested_root)) {
    return(ceiling_root)
  }
  if (is_canonical_permission_root_within(requested_root, ceiling_root)) {
    return(requested_root)
  }
  FALSE
}

is_canonical_permission_root_within <- function(path, root) {
  root_with_sep <- if (endsWith(root, "/")) root else paste0(root, "/")
  path_with_sep <- if (endsWith(path, "/")) path else paste0(path, "/")
  startsWith(path_with_sep, root_with_sep) ||
    identical(path, sub("/$", "", root_with_sep))
}

canonical_permission_root <- function(value) {
  if (
    !is.character(value) ||
      length(value) != 1L ||
      is.na(value) ||
      !nzchar(value) ||
      !identical(value, trimws(value)) ||
      !is_absolute_path(value) ||
      !dir.exists(value)
  ) {
    return(NA_character_)
  }

  resolved <- resolve_path_components(value)
  if (is.na(resolved) || !dir.exists(resolved)) {
    return(NA_character_)
  }

  tryCatch(
    normalizePath(resolved, mustWork = TRUE, winslash = "/"),
    error = function(...) NA_character_
  )
}

normalize_file_write_capability <- function(value, arg = "file_write") {
  if (isTRUE(value) || isFALSE(value)) {
    return(value)
  }

  root <- canonical_permission_root(value)
  if (!is.na(root)) {
    return(root)
  }

  cli_abort(c(
    "{.arg {arg}} must be TRUE, FALSE, or an existing absolute directory",
    "i" = "Directory grants are resolved once when the policy is created."
  ))
}

is_path_within_permission_root <- function(path, root) {
  resolved_path <- resolve_path_components(path)
  if (is.na(resolved_path)) {
    return(FALSE)
  }
  is_canonical_permission_root_within(resolved_path, root)
}

# Apply a requested mode preset beneath an existing capability ceiling.
intersect_permission_capabilities <- function(ceiling, requested) {
  out <- list(
    file_read = isTRUE(ceiling$file_read) && isTRUE(requested$file_read),
    file_write = intersect_file_write_capability(
      ceiling$file_write,
      requested$file_write
    ),
    bash = isTRUE(ceiling$bash) && isTRUE(requested$bash),
    r_code = isTRUE(ceiling$r_code) && isTRUE(requested$r_code),
    web = isTRUE(ceiling$web) && isTRUE(requested$web),
    install_packages = isTRUE(ceiling$install_packages) &&
      isTRUE(requested$install_packages),
    permission_prompt_tool_name = requested$permission_prompt_tool_name
  )
  out
}

#' Create an allow permission result
#'
#' @description
#' Returns a permission result that allows the tool to execute.
#'
#' @param message Optional message to display
#' @return A `PermissionResultAllow` object
#'
#' @examples
#' # Allow a tool call
#' PermissionResultAllow()
#'
#' # Allow with a message
#' PermissionResultAllow(message = "Tool approved by custom callback")
#'
#' @export
PermissionResultAllow <- function(message = NULL) {
  structure(
    list(
      decision = "allow",
      message = message
    ),
    class = c("PermissionResultAllow", "PermissionResult", "list")
  )
}

#' Create a deny permission result
#'
#' @description
#' Returns a permission result that denies the tool from executing.
#'
#' @param reason Reason for denial (shown to the LLM)
#' @param interrupt If TRUE, stop the entire conversation (default FALSE)
#' @return A `PermissionResultDeny` object
#'
#' @examples
#' # Deny a tool call
#' PermissionResultDeny(reason = "File write not allowed")
#'
#' # Deny and interrupt the conversation
#' PermissionResultDeny(reason = "Critical security violation", interrupt = TRUE)
#'
#' @export
PermissionResultDeny <- function(reason, interrupt = FALSE) {
  structure(
    list(
      decision = "deny",
      reason = reason,
      interrupt = interrupt
    ),
    class = c("PermissionResultDeny", "PermissionResult", "list")
  )
}
