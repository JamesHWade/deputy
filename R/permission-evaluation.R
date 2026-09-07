# Policy evaluation is separate from the read-only Permissions value.

permission_normalize_tool_names <- function(names_vec) {
  if (is.null(names_vec)) {
    return(NULL)
  }
  out <- trimws(as.character(names_vec))
  out <- out[nchar(out) > 0]
  unique(out)
}

permission_tool_name_in_list <- function(tool_name, names_vec) {
  if (is.null(names_vec) || length(names_vec) == 0) {
    return(FALSE)
  }
  tool_id <- normalize_native_tool_id(tool_name)
  if (is.na(tool_id)) {
    return(FALSE)
  }
  candidate_ids <- unique(vapply(
    names_vec,
    normalize_native_tool_id,
    character(1)
  ))
  tool_id %in% candidate_ids
}

permission_is_prompt_tool <- function(permissions, tool_name) {
  if (is.null(permissions@permission_prompt_tool_name)) {
    return(FALSE)
  }
  permission_tool_name_in_list(
    tool_name,
    permissions@permission_prompt_tool_name
  )
}

permission_gating_reason <- function(permissions, tool_name, base_reason) {
  reason <- base_reason
  if (permission_prompt_is_available(permissions)) {
    reason <- paste0(
      reason,
      " Use ",
      permissions@permission_prompt_tool_name,
      " to request approval."
    )
  }
  reason
}

permission_prompt_is_available <- function(permissions) {
  prompt <- permissions@permission_prompt_tool_name
  if (is.null(prompt)) {
    return(FALSE)
  }
  if (permission_tool_name_in_list(prompt, permissions@tool_denylist)) {
    return(FALSE)
  }
  if (
    !is.null(permissions@tool_allowlist) &&
      !permission_tool_name_in_list(prompt, permissions@tool_allowlist)
  ) {
    return(FALSE)
  }
  TRUE
}

permission_is_allowlist_exempt <- function(tool_name, context) {
  identical(
    context$.deputy_internal_tool,
    deputy_tool_result_reader_marker
  ) &&
    identical(
      normalize_native_tool_id(tool_name),
      "deputy_read_tool_result"
    )
}

permission_check_tool_gating <- function(
  permissions,
  tool_name,
  allowlist_exempt = FALSE
) {
  if (permission_tool_name_in_list(tool_name, permissions@tool_denylist)) {
    return(PermissionResultDeny(
      reason = permission_gating_reason(
        permissions,
        tool_name,
        paste0(
          "Tool not allowed by denylist: ",
          tool_name
        )
      )
    ))
  }

  if (!is.null(permissions@tool_allowlist) && !isTRUE(allowlist_exempt)) {
    if (!permission_tool_name_in_list(tool_name, permissions@tool_allowlist)) {
      return(PermissionResultDeny(
        reason = permission_gating_reason(
          permissions,
          tool_name,
          paste0(
            "Tool not in allowlist: ",
            tool_name
          )
        )
      ))
    }
  }

  NULL
}

permission_is_write_tool <- function(tool_name) {
  normalize_native_tool_id(tool_name) %in%
    c(
      "write_file",
      "edit_file",
      "multi_edit",
      "run_bash",
      "run_r_code",
      "install_package"
    )
}

permission_check_callback <- function(
  permissions,
  tool_name,
  tool_input,
  context
) {
  if (is.null(permissions@can_use_tool)) {
    return(NULL)
  }

  result <- tryCatch(
    permissions@can_use_tool(tool_name, tool_input, context),
    error = function(e) {
      cli_warn(c(
        "Permission callback failed, denying for safety",
        "x" = e$message
      ))
      PermissionResultDeny(reason = "Permission callback error")
    }
  )
  if (S7::S7_inherits(result, PermissionResult)) {
    return(result)
  }

  cli_warn("Permission callback returned invalid type, denying for safety")
  PermissionResultDeny(reason = "Invalid callback result")
}

permission_apply_callback_veto <- function(
  permissions,
  tool_name,
  tool_input,
  context
) {
  permission_check_callback(
    permissions,
    tool_name,
    tool_input,
    context
  ) %||%
    PermissionResultAllow()
}

permission_check_tool_specific <- function(
  permissions,
  tool_name,
  tool_input,
  context
) {
  tool_id <- normalize_native_tool_id(tool_name)
  if (is_mcp_tool_context(context)) {
    return(permission_check_annotation_capabilities(permissions, context))
  }

  # File read tools
  if (is_permission_file_read_tool(tool_name)) {
    if (!permissions@file_read) {
      return(PermissionResultDeny(reason = "File reading is not allowed"))
    }
    return(PermissionResultAllow())
  }

  # File write tools
  if (
    tool_id %in%
      c(
        "write_file",
        "edit_file",
        "multi_edit"
      )
  ) {
    if (isFALSE(permissions@file_write)) {
      return(PermissionResultDeny(reason = "File writing is not allowed"))
    }

    # Check directory restriction
    if (is.character(permissions@file_write)) {
      path <- tool_input$path
      if (
        is.null(path) ||
          !is.character(path) ||
          length(path) != 1 ||
          is.na(path) ||
          !nzchar(trimws(path))
      ) {
        return(PermissionResultDeny(
          reason = paste0(
            "File writing requires a path when restricted to: ",
            permissions@file_write
          )
        ))
      }

      # Check for path traversal attempts first
      if (has_path_traversal(path)) {
        return(PermissionResultDeny(
          reason = "Path traversal patterns not allowed in file paths"
        ))
      }

      # Tool paths are interpreted by the agent relative to its configured
      # working directory, which may differ from the R process directory.
      # Resolve the same way here before checking containment so permission
      # validation and eventual tool execution agree.
      path_for_check <- path
      if (!is_absolute_path(path)) {
        working_dir <- context$working_dir %||% getwd()
        if (
          !is.character(working_dir) ||
            length(working_dir) != 1 ||
            is.na(working_dir) ||
            !nzchar(trimws(working_dir))
        ) {
          return(PermissionResultDeny(
            reason = paste0(
              "Relative file writes require a valid working directory"
            )
          ))
        }

        working_dir <- expand_and_normalize(working_dir)
        if (is.na(working_dir)) {
          return(PermissionResultDeny(
            reason = "Could not resolve the working directory"
          ))
        }
        path_for_check <- file.path(working_dir, path)
      }

      # Then check if within allowed directory
      if (
        !is_path_within_permission_root(
          path_for_check,
          permissions@file_write
        )
      ) {
        return(PermissionResultDeny(
          reason = paste(
            "File writing only allowed in:",
            permissions@file_write
          )
        ))
      }
    }

    return(PermissionResultAllow())
  }

  # Bash tools
  if (identical(tool_id, "run_bash")) {
    if (!permissions@bash) {
      return(PermissionResultDeny(
        reason = "Bash command execution is not allowed"
      ))
    }
    return(PermissionResultAllow())
  }

  # R code tools
  if (identical(tool_id, "run_r_code")) {
    if (!permissions@r_code) {
      return(PermissionResultDeny(
        reason = "R code execution is not allowed"
      ))
    }
    return(PermissionResultAllow())
  }

  # Web tools
  if (tool_id %in% c("web_search", "web_fetch")) {
    if (!permissions@web) {
      return(PermissionResultDeny(reason = "Web access is not allowed"))
    }
    return(PermissionResultAllow())
  }

  # Package installation
  if (identical(tool_id, "install_package")) {
    if (!permissions@install_packages) {
      return(PermissionResultDeny(
        reason = "Package installation is not allowed"
      ))
    }
    return(PermissionResultAllow())
  }

  permission_check_annotation_capabilities(permissions, context)
}

permission_check_annotation_capabilities <- function(permissions, context) {
  # Unknown and MCP tools use conservative defaults for missing annotations.
  annotations <- effective_tool_annotations(context$tool_annotations)
  if (
    isTRUE(annotations$destructive_hint) &&
      isFALSE(permissions@file_write) &&
      !permissions@bash
  ) {
    return(PermissionResultDeny(
      reason = "Tool is marked as destructive and write operations are disabled"
    ))
  }
  # External access needs its capability even for read-only tools.
  if (isTRUE(annotations$open_world_hint) && !permissions@web) {
    return(PermissionResultDeny(
      reason = "Tool can access external resources but web access is disabled"
    ))
  }

  # The tool passed the effective annotation capability checks.
  PermissionResultAllow()
}

permission_check_plan_mode <- function(
  permissions,
  tool_name,
  tool_input,
  context
) {
  annotations <- context$tool_annotations

  if (!is_mcp_tool_context(context) && permission_is_write_tool(tool_name)) {
    return(PermissionResultDeny(
      reason = paste0(
        "Plan mode does not allow write or execute tools: ",
        tool_name
      )
    ))
  }

  if (
    !is_mcp_tool_context(context) &&
      is_permission_file_read_tool(tool_name) &&
      !isTRUE(permissions@file_read)
  ) {
    return(PermissionResultDeny(
      reason = "File reading is not allowed"
    ))
  }

  # Plan mode is intentionally conservative: no annotation means deny.
  if (length(annotations) == 0L) {
    return(PermissionResultDeny(
      reason = paste0(
        "Plan mode only allows annotated read-only tools. ",
        tool_name,
        " has no annotations."
      )
    ))
  }

  if (
    is_mcp_tool_context(context) ||
      !is_permission_native_capability_tool(tool_name)
  ) {
    annotations <- effective_tool_annotations(annotations)
  }

  if (isTRUE(annotations$destructive_hint)) {
    return(PermissionResultDeny(
      reason = paste0(
        "Plan mode does not allow destructive tools: ",
        tool_name
      )
    ))
  }

  if (isTRUE(annotations$open_world_hint) && !isTRUE(permissions@web)) {
    return(PermissionResultDeny(
      reason = paste0(
        "Plan mode cannot use open-world tools when web access is ",
        "disabled: ",
        tool_name
      )
    ))
  }

  if (!isTRUE(annotations$read_only_hint)) {
    return(PermissionResultDeny(
      reason = paste0(
        "Plan mode only allows read-only tools: ",
        tool_name
      )
    ))
  }

  PermissionResultAllow()
}
