# Permission system for deputy agents

#' Permission modes for agent tool access
#'
#' @description
#' Permission modes control the overall behavior of tool permission checking:
#' * `"default"` - Check each tool against the permission policy
#' * `"acceptEdits"` - Auto-accept file write tools
#' * `"readonly"` - Deny all write/execute tools
#' * `"bypassPermissions"` - Allow all tools (dangerous, use with caution)
#'
#' @section Tool Annotations:
#'
#' Permissions use tool annotations (from [ellmer::tool_annotations()]) to
#' determine tool behavior. Available annotations:
#'
#' **read_only_hint** (logical, default: FALSE)
#'
#' Indicates the tool only reads data and doesn't modify state.
#' Tools with `read_only_hint = TRUE` are allowed in `"readonly"` mode.
#' Examples: `tool_read_file`, `tool_list_files`, `tool_search`
#'
#' **destructive_hint** (logical, default: TRUE)
#'
#' Indicates the tool may cause destructive/irreversible changes.
#' Tools with `destructive_hint = TRUE` require explicit permission.
#' Examples: `tool_write_file`, `tool_delete_file`, `tool_run_bash`
#'
#' **open_world_hint** (logical, default: FALSE)
#'
#' Indicates the tool may interact with external systems.
#' Used for network calls, package installation, etc.
#' Examples: `tool_web_search`, `tool_install_package`
#'
#' **idempotent_hint** (logical, default: FALSE)
#'
#' Indicates repeated calls produce the same result.
#' Safe to retry on failure.
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
#'     destructive_hint = FALSE
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
#' @export
PermissionMode <- c("default", "acceptEdits", "readonly", "bypassPermissions")

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

#' Permissions R6 Class
#'
#' @description
#' Controls what an agent is allowed to do. Permissions can be configured
#' with fine-grained controls for different tool types, or with a custom
#' callback for complex logic.
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
    #' @param file_write Allow file writing (TRUE, FALSE, or directory path)
    #' @param bash Allow bash commands
    #' @param r_code Allow R code execution
    #' @param web Allow web requests
    #' @param install_packages Allow package installation
    #' @param max_turns Maximum turns
    #' @param max_cost_usd Maximum cost
    #' @param can_use_tool Custom callback function
    #' @return A new `Permissions` object
    initialize = function(
      mode = "default",
      file_read = TRUE,
      file_write = NULL,
      bash = FALSE,
      r_code = TRUE,
      web = FALSE,
      install_packages = FALSE,
      max_turns = 25,
      max_cost_usd = NULL,
      can_use_tool = NULL
    ) {
      if (!mode %in% PermissionMode) {
        cli_abort(c(
          "Invalid permission mode: {.val {mode}}",
          "i" = "Valid modes are: {.val {PermissionMode}}"
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
      private$.max_turns <- max_turns
      private$.max_cost_usd <- max_cost_usd
      private$.can_use_tool <- can_use_tool
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
      # Mode-based shortcuts
      if (self$mode == "bypassPermissions") {
        return(PermissionResultAllow())
      }

      # Extract tool annotations from context if available
      annotations <- context$tool_annotations

      if (self$mode == "readonly") {
        # Use annotations if available, otherwise fall back to name-based check
        if (!is.null(annotations)) {
          # read_only_hint = TRUE means the tool is safe for readonly mode
          if (isTRUE(annotations$read_only_hint)) {
            return(PermissionResultAllow())
          }
          # destructive_hint = TRUE means tool modifies state
          if (isTRUE(annotations$destructive_hint)) {
            return(PermissionResultDeny(
              reason = "Permission denied: tool is destructive and readonly mode is active"
            ))
          }
        }
        # Fall back to name-based check
        if (private$is_write_tool(tool_name)) {
          return(PermissionResultDeny(
            reason = "Permission denied: readonly mode active"
          ))
        }
        return(PermissionResultAllow())
      }

      # Custom callback takes precedence
      if (!is.null(self$can_use_tool)) {
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
        } else {
          cli_warn(
            "Permission callback returned invalid type, denying for safety"
          )
          return(PermissionResultDeny(reason = "Invalid callback result"))
        }
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
      cat("  max_turns:", self$max_turns, "\n")
      cat(
        "  max_cost_usd:",
        if (is.null(self$max_cost_usd)) "unlimited" else self$max_cost_usd,
        "\n"
      )
      invisible(self)
    }
  ),

  active = list(
    #' @field mode Permission mode (see [PermissionMode]). Read-only after construction.
    mode = function(value) {
      if (missing(value)) return(private$.mode)
      if (isTRUE(private$.frozen)) {
        cli_abort("Cannot modify permissions: mode is immutable after construction")
      }
      private$.mode <- value
    },

    #' @field file_read Allow file reading. Read-only after construction.
    file_read = function(value) {
      if (missing(value)) return(private$.file_read)
      if (isTRUE(private$.frozen)) {
        cli_abort("Cannot modify permissions: file_read is immutable after construction")
      }
      private$.file_read <- value
    },

    #' @field file_write Allow file writing. Can be TRUE, FALSE, or a directory path. Read-only after construction.
    file_write = function(value) {
      if (missing(value)) return(private$.file_write)
      if (isTRUE(private$.frozen)) {
        cli_abort("Cannot modify permissions: file_write is immutable after construction")
      }
      private$.file_write <- value
    },

    #' @field bash Allow bash command execution. Read-only after construction.
    bash = function(value) {
      if (missing(value)) return(private$.bash)
      if (isTRUE(private$.frozen)) {
        cli_abort("Cannot modify permissions: bash is immutable after construction")
      }
      private$.bash <- value
    },

    #' @field r_code Allow R code execution. Read-only after construction.
    r_code = function(value) {
      if (missing(value)) return(private$.r_code)
      if (isTRUE(private$.frozen)) {
        cli_abort("Cannot modify permissions: r_code is immutable after construction")
      }
      private$.r_code <- value
    },

    #' @field web Allow web requests. Read-only after construction.
    web = function(value) {
      if (missing(value)) return(private$.web)
      if (isTRUE(private$.frozen)) {
        cli_abort("Cannot modify permissions: web is immutable after construction")
      }
      private$.web <- value
    },

    #' @field install_packages Allow package installation. Read-only after construction.
    install_packages = function(value) {
      if (missing(value)) return(private$.install_packages)
      if (isTRUE(private$.frozen)) {
        cli_abort("Cannot modify permissions: install_packages is immutable after construction")
      }
      private$.install_packages <- value
    },

    #' @field max_turns Maximum number of turns before stopping. Read-only after construction.
    max_turns = function(value) {
      if (missing(value)) return(private$.max_turns)
      if (isTRUE(private$.frozen)) {
        cli_abort("Cannot modify permissions: max_turns is immutable after construction")
      }
      private$.max_turns <- value
    },

    #' @field max_cost_usd Maximum cost in USD before stopping. Read-only after construction.
    max_cost_usd = function(value) {
      if (missing(value)) return(private$.max_cost_usd)
      if (isTRUE(private$.frozen)) {
        cli_abort("Cannot modify permissions: max_cost_usd is immutable after construction")
      }
      private$.max_cost_usd <- value
    },

    #' @field can_use_tool Custom permission callback. Read-only after construction.
    can_use_tool = function(value) {
      if (missing(value)) return(private$.can_use_tool)
      if (isTRUE(private$.frozen)) {
        cli_abort("Cannot modify permissions: can_use_tool is immutable after construction")
      }
      private$.can_use_tool <- value
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
    .max_turns = NULL,
    .max_cost_usd = NULL,
    .can_use_tool = NULL,
    .frozen = FALSE,

    # Check if a tool is a write/execute tool
    is_write_tool = function(tool_name) {
      write_tools <- c(
        "write_file",
        "tool_write_file",
        "run_bash",
        "tool_run_bash",
        "bash",
        "run_r_code",
        "tool_run_r_code",
        "install_package",
        "tool_install_package"
      )
      tool_name %in% write_tools
    },

    # Tool-specific permission checks
    check_tool_specific = function(tool_name, tool_input, context) {
      # File read tools
      if (
        tool_name %in%
          c("read_file", "tool_read_file", "list_files", "tool_list_files")
      ) {
        if (!self$file_read) {
          return(PermissionResultDeny(reason = "File reading is not allowed"))
        }
        return(PermissionResultAllow())
      }

      # File write tools
      if (tool_name %in% c("write_file", "tool_write_file")) {
        if (isFALSE(self$file_write)) {
          return(PermissionResultDeny(reason = "File writing is not allowed"))
        }

        # Check directory restriction
        if (is.character(self$file_write)) {
          path <- tool_input$path %||% tool_input$file_path
          if (!is.null(path)) {
            # Check for path traversal attempts first
            if (has_path_traversal(path)) {
              return(PermissionResultDeny(
                reason = "Path traversal patterns not allowed in file paths"
              ))
            }
            # Then check if within allowed directory
            if (!is_path_within(path, self$file_write)) {
              return(PermissionResultDeny(
                reason = paste("File writing only allowed in:", self$file_write)
              ))
            }
          }
        }

        # acceptEdits mode auto-accepts
        if (self$mode == "acceptEdits") {
          return(PermissionResultAllow())
        }

        return(PermissionResultAllow())
      }

      # Bash tools
      if (tool_name %in% c("run_bash", "tool_run_bash", "bash")) {
        if (!self$bash) {
          return(PermissionResultDeny(
            reason = "Bash command execution is not allowed"
          ))
        }
        return(PermissionResultAllow())
      }

      # R code tools
      if (tool_name %in% c("run_r_code", "tool_run_r_code")) {
        if (!self$r_code) {
          return(PermissionResultDeny(
            reason = "R code execution is not allowed"
          ))
        }
        return(PermissionResultAllow())
      }

      # Web tools
      if (
        tool_name %in%
          c("web_search", "tool_web_search", "web_fetch", "tool_web_fetch")
      ) {
        if (!self$web) {
          return(PermissionResultDeny(reason = "Web access is not allowed"))
        }
        return(PermissionResultAllow())
      }

      # Package installation
      if (tool_name %in% c("install_package", "tool_install_package")) {
        if (!self$install_packages) {
          return(PermissionResultDeny(
            reason = "Package installation is not allowed"
          ))
        }
        return(PermissionResultAllow())
      }

      # For unknown tools, use annotations if available
      annotations <- context$tool_annotations
      if (!is.null(annotations)) {
        # Destructive tools need explicit permission
        if (isTRUE(annotations$destructive_hint)) {
          # If file_write is disabled, deny destructive tools
          if (isFALSE(self$file_write) && !self$bash) {
            return(PermissionResultDeny(
              reason = "Tool is marked as destructive and write operations are disabled"
            ))
          }
        }
        # Read-only tools are generally safe
        if (isTRUE(annotations$read_only_hint)) {
          return(PermissionResultAllow())
        }
        # Open-world tools (can access external resources) need explicit permission
        if (isTRUE(annotations$open_world_hint) && !self$web) {
          return(PermissionResultDeny(
            reason = "Tool can access external resources but web access is disabled"
          ))
        }
      }

      # Default: allow unknown tools without destructive annotations
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
#' @param max_turns Maximum number of turns (default 25)
#' @return A [Permissions] object
#'
#' @examples
#' perms <- permissions_readonly()
#' perms$check("read_file", list(path = "test.txt"))
#'
#' @export
permissions_readonly <- function(max_turns = 25) {
  Permissions$new(
    mode = "readonly",
    file_read = TRUE,
    file_write = FALSE,
    bash = FALSE,
    r_code = FALSE,
    web = FALSE,
    install_packages = FALSE,
    max_turns = max_turns
  )
}

#' Create a standard permission policy
#'
#' @description
#' Creates a permission policy suitable for most use cases.
#' Allows file read/write within the working directory and R code execution.
#' Denies bash commands, web access, and package installation.
#'
#' @param working_dir Directory for file operations (default: current directory)
#' @param max_turns Maximum number of turns (default 25)
#' @param max_cost_usd Maximum cost in USD (default NULL = unlimited)
#' @return A [Permissions] object
#'
#' @examples
#' perms <- permissions_standard()
#' perms$check("write_file", list(path = "output.txt"))
#'
#' @export
permissions_standard <- function(
  working_dir = getwd(),
  max_turns = 25,
  max_cost_usd = NULL
) {
  Permissions$new(
    mode = "default",
    file_read = TRUE,
    file_write = working_dir,
    bash = FALSE,
    r_code = TRUE,
    web = FALSE,
    install_packages = FALSE,
    max_turns = max_turns,
    max_cost_usd = max_cost_usd
  )
}

#' Create a full access permission policy
#'
#' @description
#' Creates a permission policy that allows all operations.
#' **Use with caution!** This bypasses all permission checks.
#'
#' @param max_turns Maximum number of turns (default 50)
#' @param max_cost_usd Maximum cost in USD (default NULL = unlimited)
#' @return A [Permissions] object
#'
#' @examples
#' perms <- permissions_full()
#'
#' @export
permissions_full <- function(max_turns = 50, max_cost_usd = NULL) {
  Permissions$new(
    mode = "bypassPermissions",
    file_read = TRUE,
    file_write = TRUE,
    bash = TRUE,
    r_code = TRUE,
    web = TRUE,
    install_packages = TRUE,
    max_turns = max_turns,
    max_cost_usd = max_cost_usd
  )
}
