#' Permissions R6 Class
#'
#' @description
#' Controls what an agent is allowed to do. Permissions can be configured
#' with fine-grained controls for different tool types, or with a custom
#' callback for complex logic.
#'
#' Tool gating fields:
#' - `tool_allowlist`: Optional list of tools that are allowed. When set,
#'   tools not in the list are denied.
#' - `tool_denylist`: Optional list of tools that are always denied.
#' - `permission_prompt_tool_name`: Optional tool name to mention in deny
#'   messages for gated tools (e.g., "ask_user").
#'
#' **Security Note:** Permission fields are immutable after construction.
#' This prevents adversarial code from modifying permissions at runtime.
#' All fields use active bindings that reject modification attempts.
#'
#' @export
Permissions <- R6::R6Class(
  "Permissions",

  public = list(
    #' @description
    #' Create a new Permissions object.
    #'
    #' @param mode Permission mode
    #' @param file_read Allow file reading
    #' @param file_write Allow file writing (`TRUE`, `FALSE`, or an existing
    #'   absolute directory path). Directory grants are canonicalized once when
    #'   the policy is constructed.
    #' @param bash Allow bash commands
    #' @param r_code Allow R code execution. Defaults to `FALSE`; grant it
    #'   explicitly for trusted code or use [permissions_full()].
    #' @param web Allow web requests
    #' @param install_packages Allow package installation
    #' @param can_use_tool Custom callback function
    #' @param tool_allowlist Optional character vector of allowed tool names
    #' @param tool_denylist Optional character vector of denied tool names
    #' @param permission_prompt_tool_name Optional dedicated approval-tool name
    #'   to suggest in permission deny messages for gated tools. Native
    #'   capability-bearing tools cannot be used as approval prompts.
    #' @return A new `Permissions` object
    initialize = function(
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
      mode <- validate_permission_mode_value(mode)
      file_write <- normalize_file_write_capability(file_write)

      if (!is.null(tool_allowlist) && !is.character(tool_allowlist)) {
        cli_abort("{.arg tool_allowlist} must be NULL or a character vector")
      }

      if (!is.null(tool_denylist) && !is.character(tool_denylist)) {
        cli_abort("{.arg tool_denylist} must be NULL or a character vector")
      }

      if (
        !is.null(permission_prompt_tool_name) &&
          (!is.character(permission_prompt_tool_name) ||
            length(permission_prompt_tool_name) != 1)
      ) {
        cli_abort(
          "{.arg permission_prompt_tool_name} must be NULL or a length-1 character string"
        )
      }

      tool_allowlist <- private$normalize_tool_names(tool_allowlist)
      tool_denylist <- private$normalize_tool_names(tool_denylist)
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

      # Store values in private fields (immutable after construction)
      private$.mode <- mode
      private$.file_read <- file_read
      private$.file_write <- file_write
      private$.bash <- bash
      private$.r_code <- r_code
      private$.web <- web
      private$.install_packages <- install_packages
      private$.can_use_tool <- can_use_tool
      private$.tool_allowlist <- tool_allowlist
      private$.tool_denylist <- tool_denylist
      private$.permission_prompt_tool_name <- permission_prompt_tool_name
      private$.frozen <- TRUE
    },

    #' @description
    #' Check if a tool is allowed to execute.
    #'
    #' @param tool_name Name of the tool
    #' @param tool_input Arguments passed to the tool
    #' @param context Additional context (e.g., working_dir, tool_annotations)
    #' @return A [PermissionResultAllow] or [PermissionResultDeny]
    check = function(tool_name, tool_input, context = list()) {
      allowlist_exempt <- private$is_allowlist_exempt(tool_name, context)
      # Explicit tool gating (denylist/allowlist) takes precedence
      gating_result <- private$check_tool_gating(
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
        callback_result <- private$check_permission_callback(
          tool_name,
          tool_input,
          context
        )
        callback_checked <- TRUE
        if (inherits(callback_result, "PermissionResultDeny")) {
          return(callback_result)
        }
      }

      # Allow the configured prompt tool so gated workflows can request
      # explicit human approval, provided it passed explicit tool gating.
      if (
        !is_mcp_tool_context(context) &&
          private$is_permission_prompt_tool(tool_name)
      ) {
        return(PermissionResultAllow())
      }

      # Mode-based shortcuts
      if (self$mode == "full") {
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

      if (self$mode == "readonly") {
        tool_id <- normalize_native_tool_id(tool_name)
        explicitly_allowed <- private$tool_name_in_list(
          tool_name,
          self$tool_allowlist
        ) ||
          isTRUE(allowlist_exempt)

        # Native mutating tools remain denied even if their annotations are
        # incorrect. MCP tools are classified by metadata, not remote names.
        if (!is_mcp_tool_context(context) && private$is_write_tool(tool_name)) {
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
        if (isTRUE(annotations$open_world_hint) && !isTRUE(self$web)) {
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
          if (!isTRUE(self$file_read)) {
            return(PermissionResultDeny(
              reason = "File reading is not allowed"
            ))
          }
          return(private$apply_callback_veto(tool_name, tool_input, context))
        }

        if (
          !is_mcp_tool_context(context) &&
            tool_id %in% c("web_search", "web_fetch")
        ) {
          if (!isTRUE(self$web)) {
            return(PermissionResultDeny(
              reason = "Web access is not allowed in readonly mode"
            ))
          }
          return(private$apply_callback_veto(tool_name, tool_input, context))
        }
        if (isTRUE(explicitly_allowed)) {
          if (isTRUE(callback_checked)) {
            return(PermissionResultAllow())
          }
          return(private$apply_callback_veto(tool_name, tool_input, context))
        }
        return(PermissionResultDeny(
          reason = paste0(
            "Permission denied: readonly mode requires a known read tool ",
            "or an explicit tool allowlist entry"
          )
        ))
      }

      if (self$mode == "plan") {
        plan_result <- private$check_plan_mode(tool_name, tool_input, context)
        if (!is.null(plan_result)) {
          return(plan_result)
        }
      }

      # Custom callback takes precedence in standard mode.
      callback_result <- if (isTRUE(callback_checked)) {
        NULL
      } else {
        private$check_permission_callback(tool_name, tool_input, context)
      }
      if (!is.null(callback_result)) {
        return(callback_result)
      }

      # Tool-specific checks (with annotation awareness)
      private$check_tool_specific(tool_name, tool_input, context)
    },

    #' @description
    #' Print the permissions configuration.
    print = function() {
      cat("<Permissions>\n")
      cat("  mode:", self$mode, "\n")
      cat("  file_read:", self$file_read, "\n")
      cat(
        "  file_write:",
        if (is.null(self$file_write)) "NULL" else self$file_write,
        "\n"
      )
      cat("  bash:", self$bash, "\n")
      cat("  r_code:", self$r_code, "\n")
      cat("  web:", self$web, "\n")
      cat(
        "  tool_allowlist:",
        if (
          is.null(self$tool_allowlist) ||
            length(self$tool_allowlist) == 0
        ) {
          "NULL"
        } else {
          paste(self$tool_allowlist, collapse = ", ")
        },
        "\n"
      )
      cat(
        "  tool_denylist:",
        if (
          is.null(self$tool_denylist) ||
            length(self$tool_denylist) == 0
        ) {
          "NULL"
        } else {
          paste(self$tool_denylist, collapse = ", ")
        },
        "\n"
      )
      cat(
        "  permission_prompt_tool_name:",
        self$permission_prompt_tool_name %||% "NULL",
        "\n"
      )
      invisible(self)
    }
  ),

  active = list(
    #' @field mode Permission mode (see [PermissionMode]). Read-only after construction.
    mode = function(value) {
      if (missing(value)) {
        return(private$.mode)
      }
      if (isTRUE(private$.frozen)) {
        cli_abort(
          "Cannot modify permissions: mode is immutable after construction"
        )
      }
      private$.mode <- value
    },

    #' @field file_read Allow file reading. Read-only after construction.
    file_read = function(value) {
      if (missing(value)) {
        return(private$.file_read)
      }
      if (isTRUE(private$.frozen)) {
        cli_abort(
          "Cannot modify permissions: file_read is immutable after construction"
        )
      }
      private$.file_read <- value
    },

    #' @field file_write Allow file writing. Can be `TRUE`, `FALSE`, or a
    #' canonical absolute directory path. Read-only after construction.
    file_write = function(value) {
      if (missing(value)) {
        return(private$.file_write)
      }
      if (isTRUE(private$.frozen)) {
        cli_abort(
          "Cannot modify permissions: file_write is immutable after construction"
        )
      }
      private$.file_write <- value
    },

    #' @field bash Allow bash command execution. Read-only after construction.
    bash = function(value) {
      if (missing(value)) {
        return(private$.bash)
      }
      if (isTRUE(private$.frozen)) {
        cli_abort(
          "Cannot modify permissions: bash is immutable after construction"
        )
      }
      private$.bash <- value
    },

    #' @field r_code Allow R code execution. Read-only after construction.
    r_code = function(value) {
      if (missing(value)) {
        return(private$.r_code)
      }
      if (isTRUE(private$.frozen)) {
        cli_abort(
          "Cannot modify permissions: r_code is immutable after construction"
        )
      }
      private$.r_code <- value
    },

    #' @field web Allow web requests. Read-only after construction.
    web = function(value) {
      if (missing(value)) {
        return(private$.web)
      }
      if (isTRUE(private$.frozen)) {
        cli_abort(
          "Cannot modify permissions: web is immutable after construction"
        )
      }
      private$.web <- value
    },

    #' @field install_packages Allow package installation. Read-only after construction.
    install_packages = function(value) {
      if (missing(value)) {
        return(private$.install_packages)
      }
      if (isTRUE(private$.frozen)) {
        cli_abort(
          "Cannot modify permissions: install_packages is immutable after construction"
        )
      }
      private$.install_packages <- value
    },

    #' @field can_use_tool Custom permission callback. Read-only after construction.
    can_use_tool = function(value) {
      if (missing(value)) {
        return(private$.can_use_tool)
      }
      if (isTRUE(private$.frozen)) {
        cli_abort(
          "Cannot modify permissions: can_use_tool is immutable after construction"
        )
      }
      private$.can_use_tool <- value
    },

    #' @field tool_allowlist Optional character vector of allowed tool names. Read-only after construction.
    tool_allowlist = function(value) {
      if (missing(value)) {
        return(private$.tool_allowlist)
      }
      if (isTRUE(private$.frozen)) {
        cli_abort(
          "Cannot modify permissions: tool_allowlist is immutable after construction"
        )
      }
      private$.tool_allowlist <- private$normalize_tool_names(value)
    },

    #' @field tool_denylist Optional character vector of denied tool names. Read-only after construction.
    tool_denylist = function(value) {
      if (missing(value)) {
        return(private$.tool_denylist)
      }
      if (isTRUE(private$.frozen)) {
        cli_abort(
          "Cannot modify permissions: tool_denylist is immutable after construction"
        )
      }
      private$.tool_denylist <- private$normalize_tool_names(value)
    },

    #' @field permission_prompt_tool_name Optional tool name used in gating deny messages. Read-only after construction.
    permission_prompt_tool_name = function(value) {
      if (missing(value)) {
        return(private$.permission_prompt_tool_name)
      }
      if (isTRUE(private$.frozen)) {
        cli_abort(
          "Cannot modify permissions: permission_prompt_tool_name is immutable after construction"
        )
      }
      if (!is.null(value) && (!is.character(value) || length(value) != 1)) {
        cli_abort(
          "{.arg permission_prompt_tool_name} must be NULL or a length-1 character string"
        )
      }
      normalized <- trimws(value %||% "")
      private$.permission_prompt_tool_name <- if (nchar(normalized) > 0) {
        normalized
      } else {
        NULL
      }
    }
  ),

  private = list(
    # Private storage for immutable fields
    .mode = NULL,
    .file_read = NULL,
    .file_write = NULL,
    .bash = NULL,
    .r_code = NULL,
    .web = NULL,
    .install_packages = NULL,
    .can_use_tool = NULL,
    .tool_allowlist = NULL,
    .tool_denylist = NULL,
    .permission_prompt_tool_name = NULL,
    .frozen = FALSE,

    normalize_tool_names = function(names_vec) {
      if (is.null(names_vec)) {
        return(NULL)
      }
      out <- trimws(as.character(names_vec))
      out <- out[nchar(out) > 0]
      unique(out)
    },

    tool_name_in_list = function(tool_name, names_vec) {
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
    },

    is_permission_prompt_tool = function(tool_name) {
      if (is.null(private$.permission_prompt_tool_name)) {
        return(FALSE)
      }
      private$tool_name_in_list(
        tool_name,
        private$.permission_prompt_tool_name
      )
    },

    gating_reason = function(tool_name, base_reason) {
      reason <- base_reason
      if (private$permission_prompt_is_available()) {
        reason <- paste0(
          reason,
          " Use ",
          private$.permission_prompt_tool_name,
          " to request approval."
        )
      }
      reason
    },

    permission_prompt_is_available = function() {
      prompt <- private$.permission_prompt_tool_name
      if (is.null(prompt)) {
        return(FALSE)
      }
      if (private$tool_name_in_list(prompt, private$.tool_denylist)) {
        return(FALSE)
      }
      if (
        !is.null(private$.tool_allowlist) &&
          !private$tool_name_in_list(prompt, private$.tool_allowlist)
      ) {
        return(FALSE)
      }
      TRUE
    },

    is_allowlist_exempt = function(tool_name, context) {
      identical(
        context$.deputy_internal_tool,
        deputy_tool_result_reader_marker
      ) &&
        identical(
          normalize_native_tool_id(tool_name),
          "deputy_read_tool_result"
        )
    },

    check_tool_gating = function(tool_name, allowlist_exempt = FALSE) {
      if (private$tool_name_in_list(tool_name, private$.tool_denylist)) {
        return(PermissionResultDeny(
          reason = private$gating_reason(
            tool_name,
            paste0(
              "Tool not allowed by denylist: ",
              tool_name
            )
          )
        ))
      }

      if (!is.null(private$.tool_allowlist) && !isTRUE(allowlist_exempt)) {
        if (!private$tool_name_in_list(tool_name, private$.tool_allowlist)) {
          return(PermissionResultDeny(
            reason = private$gating_reason(
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
    },

    # Check if a tool is a write/execute tool
    is_write_tool = function(tool_name) {
      normalize_native_tool_id(tool_name) %in%
        c(
          "write_file",
          "edit_file",
          "multi_edit",
          "run_bash",
          "run_r_code",
          "install_package"
        )
    },

    check_permission_callback = function(tool_name, tool_input, context) {
      if (is.null(self$can_use_tool)) {
        return(NULL)
      }

      result <- tryCatch(
        self$can_use_tool(tool_name, tool_input, context),
        error = function(e) {
          cli_warn(c(
            "Permission callback failed, denying for safety",
            "x" = e$message
          ))
          PermissionResultDeny(reason = "Permission callback error")
        }
      )
      if (inherits(result, "PermissionResult")) {
        return(result)
      }

      cli_warn("Permission callback returned invalid type, denying for safety")
      PermissionResultDeny(reason = "Invalid callback result")
    },

    apply_callback_veto = function(tool_name, tool_input, context) {
      private$check_permission_callback(tool_name, tool_input, context) %||%
        PermissionResultAllow()
    },

    # Tool-specific permission checks
    check_tool_specific = function(tool_name, tool_input, context) {
      tool_id <- normalize_native_tool_id(tool_name)
      if (is_mcp_tool_context(context)) {
        return(private$check_annotation_capabilities(context))
      }

      # File read tools
      if (is_permission_file_read_tool(tool_name)) {
        if (!self$file_read) {
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
        if (isFALSE(self$file_write)) {
          return(PermissionResultDeny(reason = "File writing is not allowed"))
        }

        # Check directory restriction
        if (is.character(self$file_write)) {
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
                self$file_write
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
              self$file_write
            )
          ) {
            return(PermissionResultDeny(
              reason = paste("File writing only allowed in:", self$file_write)
            ))
          }
        }

        return(PermissionResultAllow())
      }

      # Bash tools
      if (identical(tool_id, "run_bash")) {
        if (!self$bash) {
          return(PermissionResultDeny(
            reason = "Bash command execution is not allowed"
          ))
        }
        return(PermissionResultAllow())
      }

      # R code tools
      if (identical(tool_id, "run_r_code")) {
        if (!self$r_code) {
          return(PermissionResultDeny(
            reason = "R code execution is not allowed"
          ))
        }
        return(PermissionResultAllow())
      }

      # Web tools
      if (tool_id %in% c("web_search", "web_fetch")) {
        if (!self$web) {
          return(PermissionResultDeny(reason = "Web access is not allowed"))
        }
        return(PermissionResultAllow())
      }

      # Package installation
      if (identical(tool_id, "install_package")) {
        if (!self$install_packages) {
          return(PermissionResultDeny(
            reason = "Package installation is not allowed"
          ))
        }
        return(PermissionResultAllow())
      }

      private$check_annotation_capabilities(context)
    },

    check_annotation_capabilities = function(context) {
      # Unknown and MCP tools use conservative defaults for missing annotations.
      annotations <- effective_tool_annotations(context$tool_annotations)
      if (
        isTRUE(annotations$destructive_hint) &&
          isFALSE(self$file_write) &&
          !self$bash
      ) {
        return(PermissionResultDeny(
          reason = "Tool is marked as destructive and write operations are disabled"
        ))
      }
      # External access needs its capability even for read-only tools.
      if (isTRUE(annotations$open_world_hint) && !self$web) {
        return(PermissionResultDeny(
          reason = "Tool can access external resources but web access is disabled"
        ))
      }

      # The tool passed the effective annotation capability checks.
      PermissionResultAllow()
    },

    check_plan_mode = function(tool_name, tool_input, context) {
      annotations <- context$tool_annotations

      if (!is_mcp_tool_context(context) && private$is_write_tool(tool_name)) {
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
          !isTRUE(self$file_read)
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

      if (isTRUE(annotations$open_world_hint) && !isTRUE(self$web)) {
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
  )
)

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
#' perms$check("read_file", list(path = "test.txt"))
#'
#' @export
permissions_readonly <- function() {
  Permissions$new(
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
#' perms$check("write_file", list(path = "output.txt"))
#'
#' @export
permissions_standard <- function(working_dir = getwd()) {
  Permissions$new(
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
  Permissions$new(
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
  Permissions$new(
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
