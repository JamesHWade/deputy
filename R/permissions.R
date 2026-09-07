#' @include value-properties.R
NULL

#' Create a permission policy
#'
#' @description
#' A read-only S7 value controlling tool access. Use [permissions_check()] to
#' evaluate a call. Read properties with `S7::prop(policy, "mode")` or `$`.
#' To narrow an active Agent, use its `set_permission_mode()` method; replacing
#' its policy or changing its properties is not supported.
#'
#' Directory grants are canonicalized at construction. The callback retains
#' its caller-owned executable state. Read-only properties protect the public
#' configuration; they are not an execution sandbox. Serialized policies are
#' configuration records, not portable authority grants or a way to widen an
#' existing Agent's authority.
#'
#' @param mode One of `"standard"`, `"plan"`, `"readonly"`, or `"full"`.
#' @param file_read Allow file reading. One non-missing logical value.
#' @param file_write `TRUE`, `FALSE`, or an existing absolute directory path.
#' @param bash Allow shell commands. One non-missing logical value.
#' @param r_code Allow R code execution. One non-missing logical value;
#'   defaults to `FALSE`.
#' @param web Allow web requests. One non-missing logical value.
#' @param install_packages Allow package installation. One non-missing logical
#'   value.
#' @param can_use_tool A function accepting tool name, input, and context,
#'   returning a [PermissionResultAllow], [PermissionResultDeny],
#'   [PermissionResultPending], or `NULL`.
#' @param tool_allowlist Character vector of allowed tool names, or `NULL`.
#'   An empty vector denies all tools; `NULL` disables this gate.
#' @param tool_denylist Character vector of denied tool names, or `NULL`.
#' @param permission_prompt_tool_name Optional dedicated approval-tool name to
#'   suggest in deny messages. Native capability-bearing tools cannot be used.
#' @return A read-only `Permissions` S7 object.
#' @examples
#' policy <- Permissions(file_write = FALSE)
#' permissions_check(policy, "write_file", list(path = "output.txt"))
#' S7::prop(policy, "file_write")
#' @export
Permissions <- S7::new_class(
  "Permissions",
  package = "deputy",
  properties = list(
    mode = readonly_property("mode", S7::class_character),
    file_read = readonly_property("file_read", S7::class_logical),
    file_write = readonly_property(
      "file_write",
      S7::new_union(S7::class_logical, S7::class_character)
    ),
    bash = readonly_property("bash", S7::class_logical),
    r_code = readonly_property("r_code", S7::class_logical),
    web = readonly_property("web", S7::class_logical),
    install_packages = readonly_property("install_packages", S7::class_logical),
    can_use_tool = readonly_property(
      "can_use_tool",
      S7::new_union(NULL, S7::class_function)
    ),
    tool_allowlist = readonly_property(
      "tool_allowlist",
      S7::new_union(NULL, S7::class_character)
    ),
    tool_denylist = readonly_property(
      "tool_denylist",
      S7::new_union(NULL, S7::class_character)
    ),
    permission_prompt_tool_name = readonly_property(
      "permission_prompt_tool_name",
      S7::new_union(NULL, S7::class_character)
    )
  ),
  constructor = function(
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
  ) {
    flags <- list(
      file_read = file_read,
      bash = bash,
      r_code = r_code,
      web = web,
      install_packages = install_packages
    )
    for (name in names(flags)) {
      value <- flags[[name]]
      if (!is.logical(value) || length(value) != 1L || is.na(value)) {
        cli_abort("{.arg {name}} must be TRUE or FALSE")
      }
    }
    if (!is.null(can_use_tool) && !is.function(can_use_tool)) {
      cli_abort("{.arg can_use_tool} must be NULL or a function")
    }
    mode <- validate_permission_mode_value(mode)
    file_write <- normalize_file_write_capability(file_write)

    if (
      !is.null(tool_allowlist) &&
        (!is.character(tool_allowlist) || anyNA(tool_allowlist))
    ) {
      cli_abort("{.arg tool_allowlist} must be NULL or a character vector")
    }

    if (
      !is.null(tool_denylist) &&
        (!is.character(tool_denylist) || anyNA(tool_denylist))
    ) {
      cli_abort("{.arg tool_denylist} must be NULL or a character vector")
    }

    if (
      !is.null(permission_prompt_tool_name) &&
        (!is.character(permission_prompt_tool_name) ||
          length(permission_prompt_tool_name) != 1 ||
          anyNA(permission_prompt_tool_name))
    ) {
      cli_abort(
        "{.arg permission_prompt_tool_name} must be NULL or a length-1 character string"
      )
    }

    tool_allowlist <- permission_normalize_tool_names(tool_allowlist)
    tool_denylist <- permission_normalize_tool_names(tool_denylist)
    permission_prompt_tool_name <- trimws(permission_prompt_tool_name %||% "")
    if (nchar(permission_prompt_tool_name) == 0) {
      permission_prompt_tool_name <- NULL
    }
    if (
      !is.null(permission_prompt_tool_name) &&
        is_permission_native_capability_tool(permission_prompt_tool_name)
    ) {
      cli_abort(c(
        "{.arg permission_prompt_tool_name} must name a dedicated approval tool",
        "x" = "Native read, write, execute, web, install, and delegation tools cannot bypass their capabilities."
      ))
    }

    value <- S7::new_object(
      S7::S7_object(),
      mode = mode,
      file_read = file_read,
      file_write = file_write,
      bash = bash,
      r_code = r_code,
      web = web,
      install_packages = install_packages,
      can_use_tool = can_use_tool,
      tool_allowlist = tool_allowlist,
      tool_denylist = tool_denylist,
      permission_prompt_tool_name = permission_prompt_tool_name
    )
    freeze_value(value)
  }
)

local({
  S7::method(`$`, Permissions) <- function(x, name) S7::prop(x, name)
})

#' Evaluate a tool call against a permission policy
#'
#' @param permissions A [Permissions] S7 value.
#' @param tool_name Name of the tool.
#' @param tool_input Arguments passed to the tool.
#' @param context Additional context such as working directory, tool origin,
#'   and annotations.
#' @return A [PermissionResultAllow], [PermissionResultDeny], or
#'   [PermissionResultPending].
#' @examples
#' permissions_check(permissions_readonly(), "read_file", list(path = "x.txt"))
#' @export
permissions_check <- S7::new_generic(
  "permissions_check",
  "permissions",
  function(permissions, tool_name, tool_input, context = list()) {
    S7::S7_dispatch()
  }
)

S7::method(permissions_check, Permissions) <- function(
  permissions,
  tool_name,
  tool_input,
  context = list()
) {
  allowlist_exempt <- permission_is_allowlist_exempt(tool_name, context)
  # Explicit tool gating (denylist/allowlist) takes precedence
  gating_result <- permission_check_tool_gating(
    permissions,
    tool_name,
    allowlist_exempt = allowlist_exempt
  )
  if (!is.null(gating_result)) {
    return(gating_result)
  }

  # The internal result reader must remain vetoable even in modes that
  # otherwise short-circuit custom callbacks. An allow result does not
  # override the remaining mode and capability checks.
  callback_checked <- FALSE
  if (isTRUE(allowlist_exempt)) {
    callback_result <- permission_check_callback(
      permissions,
      tool_name,
      tool_input,
      context
    )
    callback_checked <- TRUE
    if (
      !is.null(callback_result) &&
        !S7::S7_inherits(callback_result, PermissionResultAllow)
    ) {
      return(callback_result)
    }
  }

  # Allow the configured prompt tool so gated workflows can request
  # explicit human approval, provided it passed explicit tool gating.
  if (
    !is_mcp_tool_context(context) &&
      permission_is_prompt_tool(permissions, tool_name)
  ) {
    return(PermissionResultAllow())
  }

  # Mode-based shortcuts
  if (permissions@mode == "full") {
    return(PermissionResultAllow())
  }

  # Extract tool annotations from context if available
  annotations <- context$tool_annotations
  if (
    (is_mcp_tool_context(context) ||
      !normalize_native_tool_id(tool_name) %in%
        permission_native_capability_tool_ids) &&
      !isTRUE(allowlist_exempt)
  ) {
    annotations <- effective_tool_annotations(annotations)
  }

  if (permissions@mode == "readonly") {
    tool_id <- normalize_native_tool_id(tool_name)
    explicitly_allowed <- permission_tool_name_in_list(
      tool_name,
      permissions@tool_allowlist
    ) ||
      isTRUE(allowlist_exempt)

    # Native mutating tools remain denied even if their annotations are
    # incorrect. MCP tools are classified by metadata, not remote names.
    if (!is_mcp_tool_context(context) && permission_is_write_tool(tool_name)) {
      return(PermissionResultDeny(
        reason = "Permission denied: readonly mode active"
      ))
    }
    if (isTRUE(annotations$destructive_hint)) {
      return(PermissionResultDeny(
        reason = paste0(
          "Permission denied: tool is destructive and readonly mode ",
          "is active"
        )
      ))
    }
    if (isTRUE(annotations$open_world_hint) && !isTRUE(permissions@web)) {
      return(PermissionResultDeny(
        reason = paste0(
          "Permission denied: tool can access external resources and ",
          "web access is disabled"
        )
      ))
    }

    if (
      !is_mcp_tool_context(context) &&
        is_permission_file_read_tool(tool_name)
    ) {
      if (!isTRUE(permissions@file_read)) {
        return(PermissionResultDeny(
          reason = "File reading is not allowed"
        ))
      }
      return(permission_apply_callback_veto(
        permissions,
        tool_name,
        tool_input,
        context
      ))
    }

    if (
      !is_mcp_tool_context(context) &&
        tool_id %in% c("web_search", "web_fetch")
    ) {
      if (!isTRUE(permissions@web)) {
        return(PermissionResultDeny(
          reason = "Web access is not allowed in readonly mode"
        ))
      }
      return(permission_apply_callback_veto(
        permissions,
        tool_name,
        tool_input,
        context
      ))
    }
    if (isTRUE(explicitly_allowed)) {
      if (isTRUE(callback_checked)) {
        return(PermissionResultAllow())
      }
      return(permission_apply_callback_veto(
        permissions,
        tool_name,
        tool_input,
        context
      ))
    }
    return(PermissionResultDeny(
      reason = paste0(
        "Permission denied: readonly mode requires a known read tool ",
        "or an explicit tool allowlist entry"
      )
    ))
  }

  if (permissions@mode == "plan") {
    plan_result <- permission_check_plan_mode(
      permissions,
      tool_name,
      tool_input,
      context
    )
    if (!is.null(plan_result)) {
      return(plan_result)
    }
  }

  # Custom callback takes precedence in standard mode.
  callback_result <- if (isTRUE(callback_checked)) {
    NULL
  } else {
    permission_check_callback(
      permissions,
      tool_name,
      tool_input,
      context
    )
  }
  if (!is.null(callback_result)) {
    return(callback_result)
  }

  # Tool-specific checks (with annotation awareness)
  permission_check_tool_specific(permissions, tool_name, tool_input, context)
}

S7::method(print, Permissions) <- function(x, ...) {
  cli::cat_line(cli::cli_format_method({
    cli::cli_text("<Permissions>")
    cli::cli_div(theme = list(div = list("margin-left" = 2)))
    cli::cli_text("mode: {x@mode}")
    cli::cli_text("file_read: {x@file_read}")
    cli::cli_text(
      "file_write: {if (is.null(x@file_write)) \"NULL\" else x@file_write}"
    )
    cli::cli_text("bash: {x@bash}")
    cli::cli_text("r_code: {x@r_code}")
    cli::cli_text("web: {x@web}")
    tool_allowlist <- if (is.null(x@tool_allowlist)) {
      "NULL"
    } else if (length(x@tool_allowlist) == 0L) {
      "character(0)"
    } else {
      paste(x@tool_allowlist, collapse = ", ")
    }
    cli::cli_text("tool_allowlist: {tool_allowlist}")
    tool_denylist <- if (is.null(x@tool_denylist)) {
      "NULL"
    } else if (length(x@tool_denylist) == 0L) {
      "character(0)"
    } else {
      paste(x@tool_denylist, collapse = ", ")
    }
    cli::cli_text("tool_denylist: {tool_denylist}")
    cli::cli_text(
      "permission_prompt_tool_name: {x@permission_prompt_tool_name %||% \"NULL\"}"
    )
  }))
  invisible(x)
}

#' Create a read-only permission policy
#'
#' @description
#' Creates a permission policy that only allows reading files.
#' All write operations, code execution, and web access are denied.
#'
#' @return A [Permissions] object
#'
#' @examples
#' perms <- permissions_readonly()
#' permissions_check(perms, "read_file", list(path = "test.txt"))
#'
#' @export
permissions_readonly <- function() {
  Permissions(
    mode = "readonly",
    file_read = TRUE,
    file_write = FALSE,
    bash = FALSE,
    r_code = FALSE,
    web = FALSE,
    install_packages = FALSE
  )
}

#' Create a standard permission policy
#'
#' @description
#' Creates a permission policy suitable for most use cases.
#' Allows reads of files accessible to the R process, confines file writes to
#' the working directory. Denies arbitrary R code, bash commands, web access,
#' and package installation. Grant code execution explicitly only when the
#' model and task are trusted; process separation is not an OS sandbox.
#'
#' @param working_dir Existing absolute root directory for file writes (default:
#'   current directory). This does not restrict otherwise accessible file
#'   reads.
#' @return A [Permissions] object
#'
#' @examples
#' perms <- permissions_standard()
#' permissions_check(perms, "write_file", list(path = "output.txt"))
#'
#' @export
permissions_standard <- function(working_dir = getwd()) {
  Permissions(
    mode = "standard",
    file_read = TRUE,
    file_write = working_dir,
    bash = FALSE,
    r_code = FALSE,
    web = FALSE,
    install_packages = FALSE
  )
}

#' Create a planning permission policy
#'
#' @description
#' Creates a permission policy for planning-oriented sessions.
#' Only tools annotated as read-only are allowed, plus the permission prompt
#' tool when configured.
#'
#' @param permission_prompt_tool_name Optional dedicated approval-tool name that
#'   the model can use to request explicit approval. Native capability-bearing
#'   tools are rejected. Defaults to `"ask_user"`.
#' @return A [Permissions] object
#'
#' @examples
#' perms <- permissions_plan()
#'
#' @export
permissions_plan <- function(
  permission_prompt_tool_name = "ask_user"
) {
  Permissions(
    mode = "plan",
    file_read = TRUE,
    file_write = FALSE,
    bash = FALSE,
    r_code = FALSE,
    web = TRUE,
    install_packages = FALSE,
    permission_prompt_tool_name = permission_prompt_tool_name
  )
}

#' Create a full access permission policy
#'
#' @description
#' Creates a permission policy that allows all operations.
#' **Use with caution!** This bypasses all permission checks.
#'
#' @return A [Permissions] object
#'
#' @examples
#' perms <- permissions_full()
#'
#' @export
permissions_full <- function() {
  Permissions(
    mode = "full",
    file_read = TRUE,
    file_write = TRUE,
    bash = TRUE,
    r_code = TRUE,
    web = TRUE,
    install_packages = TRUE
  )
}
# Normalize Deputy's canonical snake-case tool identifiers.
normalize_native_tool_id <- function(name) {
  if (is.null(name) || length(name) == 0L) {
    return(NA_character_)
  }
  normalized <- tolower(trimws(as.character(name[[1L]])))
  normalized <- gsub("[^a-z0-9]+", "_", normalized)
  gsub("^_+|_+$", "", normalized)
}
