# Permission system for deputy agents

#' Permission modes
#'
#' @description
#' `PermissionMode` lists the modes a [Permissions] policy can use. In every
#' mode, `tool_denylist` and `tool_allowlist` are checked first, and the
#' approval prompt tool (`permission_prompt_tool_name`) is then allowed
#' without further checks.
#'
#' * `"standard"`: checks built-in tools against the capability flags
#'   (`file_read`, `file_write`, `bash`, `r_code`, `web`, `install_packages`)
#'   and custom tools against their annotations.
#' * `"readonly"`: allows the built-in file-reading tools, the web tools when
#'   `web = TRUE`, the agent's own delegation tools and tools on
#'   `tool_allowlist`. It denies writes, code execution, destructive tools
#'   and, unless `web = TRUE`, open-world tools.
#' * `"plan"`: allows only tools annotated as read-only, plus the approval
#'   prompt tool and the agent's own delegation tools. Open-world tools also
#'   need `web = TRUE`.
#' * `"full"`: allows every call. Capability flags and annotations are not
#'   checked.
#'
#' An agent's own delegation tools are a [LeadAgent]'s `delegate_to_agent`
#' tool and the tools that call its retained agents, from [delegation_tool()]
#' and `$retain_agent_graph()`. Another tool doesn't qualify by using the same
#' name. Each tool call a subagent or retained agent makes is also checked
#' against the policy of the agent that delegated to it, so in read-only or
#' plan mode that agent's delegates are held to the same mode. A [LeadAgent]'s
#' subagents also can't use a less strict mode than their lead.
#'
#' If the policy has a `can_use_tool` callback, it is called in every mode for
#' each call the rest of the policy allows. It can deny the call or pause it
#' for approval, but it can't allow a call the policy denies.
#'
#' A denied call can still be allowed by a PermissionRequest hook (see
#' [HookEvent]).
#'
#' @section Tool annotations:
#'
#' Custom tools are checked through their annotations, set with
#' [ellmer::tool_annotations()]. A missing annotation takes a cautious
#' default:
#'
#' * `read_only_hint` (default `FALSE`): the tool only reads data. Plan mode
#'   allows only these tools.
#' * `destructive_hint` (default `TRUE`, or `FALSE` when `read_only_hint =
#'   TRUE`): the tool may make irreversible changes. Destructive tools are
#'   denied in plan and readonly modes, and in standard mode when both
#'   `file_write` and `bash` are off.
#' * `open_world_hint` (default `TRUE`): the tool may reach external systems.
#'   Open-world tools are denied unless `web = TRUE`, except in full mode.
#' * `idempotent_hint` (default `FALSE`): repeated calls have the same effect.
#'   Permission checks don't use it.
#'
#' So in standard mode an unannotated custom tool needs `web = TRUE`, and plan
#' and readonly modes deny it. Built-in tools such as `write_file` and
#' `run_bash` are checked against their capability flag instead.
#'
#' @section Annotating tools:
#'
#' Set annotations when you create a tool:
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
#'     destructive_hint = TRUE,
#'     open_world_hint = FALSE
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

# Normalize Deputy's canonical snake-case tool identifiers.
normalize_native_tool_id <- function(name) {
  if (is.null(name) || length(name) == 0L) {
    return(NA_character_)
  }
  normalized <- tolower(trimws(as.character(name[[1L]])))
  normalized <- gsub("[^a-z0-9]+", "_", normalized)
  gsub("^_+|_+$", "", normalized)
}

is_permission_file_read_tool <- function(tool_name) {
  normalize_native_tool_id(tool_name) %in% permission_file_read_tool_ids
}

is_permission_native_capability_tool <- function(tool_name) {
  normalize_native_tool_id(tool_name) %in%
    permission_native_capability_tool_ids
}

# Names that carry native permission treatment, including the default prompt
# tool. Grants based on them need a trusted native origin (#216).
permission_native_tool_ids <- c(
  permission_native_capability_tool_ids,
  "ask_user"
)

permission_is_native_capability <- function(tool_name, context) {
  permission_trusts_native_name(context) &&
    is_permission_native_capability_tool(tool_name)
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
  path_prefix_within(path, root, ignore_case = FALSE)
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

agent_set_permission_mode <- function(
  self,
  private,
  mode,
  call = rlang::caller_env()
) {
  check_conversation_access(self, NULL)
  mode <- validate_permission_mode_value(mode)
  existing <- self$permissions
  old_mode <- existing$mode

  if (identical(mode, old_mode)) {
    return(invisible(self))
  }

  if (!mode %in% permission_mode_targets(old_mode)) {
    cli_abort(
      c(
        "Permission mode cannot widen or replace the current policy",
        "x" = paste0(
          "Mode ",
          old_mode,
          " cannot change to ",
          mode,
          "."
        ),
        "i" = paste0(
          "Create a new Agent with explicitly broader Permissions to ",
          "make this change."
        )
      ),
      class = c("deputy_permission_mode_widening", "deputy_error"),
      call = call
    )
  }

  capabilities <- intersect_permission_capabilities(
    permission_capabilities_from(existing),
    permission_mode_capabilities(mode, self$working_dir)
  )

  narrowed_permissions <- Permissions(
    mode = mode,
    file_read = capabilities$file_read,
    file_write = capabilities$file_write,
    bash = capabilities$bash,
    r_code = capabilities$r_code,
    web = capabilities$web,
    install_packages = capabilities$install_packages,
    can_use_tool = existing$can_use_tool,
    tool_allowlist = existing$tool_allowlist,
    tool_denylist = existing$tool_denylist,
    permission_prompt_tool_name = capabilities$permission_prompt_tool_name
  )

  registered_tools <- private$.chat$get_tools()
  provider_native <- vapply(
    registered_tools,
    inherits,
    logical(1),
    what = "ellmer::ToolBuiltIn"
  )
  removed_provider_tools <- character()
  if (!isTRUE(narrowed_permissions$web) && any(provider_native)) {
    removed_provider_tools <- vapply(
      registered_tools[provider_native],
      \(tool) tool@name,
      character(1)
    )
    private$.chat$set_tools(registered_tools[!provider_native])
  }

  private$.permissions <- narrowed_permissions

  hook_unawaited(private$fire_hook(
    "ConfigChange",
    key = "permission_mode",
    old_value = old_mode,
    new_value = mode,
    context = private$hook_context()
  ))

  private$notify(
    paste0("Permission mode changed from ", old_mode, " to ", mode, "."),
    level = "info",
    code = "permission_mode_changed",
    previous_mode = old_mode,
    permission_mode = mode,
    removed_provider_tools = removed_provider_tools
  )

  invisible(self)
}
