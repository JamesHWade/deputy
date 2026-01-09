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
#' @export
Permissions <- R6::R6Class(
  "Permissions",

  public = list(
    #' @field mode Permission mode (see [PermissionMode])
    mode = "default",

    #' @field file_read Allow file reading
    file_read = TRUE,

    #' @field file_write Allow file writing. Can be TRUE, FALSE, or a directory path.
    file_write = NULL,

    #' @field bash Allow bash command execution
    bash = FALSE,

    #' @field r_code Allow R code execution
    r_code = TRUE,

    #' @field web Allow web requests
    web = FALSE,

    #' @field install_packages Allow package installation
    install_packages = FALSE,

    #' @field max_turns Maximum number of turns before stopping
    max_turns = 25,

    #' @field max_cost_usd Maximum cost in USD before stopping
    max_cost_usd = NULL,

    #' @field can_use_tool Custom permission callback
    can_use_tool = NULL,

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

      self$mode <- mode
      self$file_read <- file_read
      self$file_write <- file_write
      self$bash <- bash
      self$r_code <- r_code
      self$web <- web
      self$install_packages <- install_packages
      self$max_turns <- max_turns
      self$max_cost_usd <- max_cost_usd
      self$can_use_tool <- can_use_tool
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
        result <- self$can_use_tool(tool_name, tool_input, context)
        if (inherits(result, "PermissionResult")) {
          return(result)
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
      cat("  file_write:", if (is.null(self$file_write)) "NULL" else self$file_write, "\n")
      cat("  bash:", self$bash, "\n")
      cat("  r_code:", self$r_code, "\n")
      cat("  web:", self$web, "\n")
      cat("  max_turns:", self$max_turns, "\n")
      cat("  max_cost_usd:", if (is.null(self$max_cost_usd)) "unlimited" else self$max_cost_usd, "\n")
      invisible(self)
    }
  ),

  private = list(
    # Check if a tool is a write/execute tool
    is_write_tool = function(tool_name) {
      write_tools <- c(
        "write_file", "tool_write_file",
        "run_bash", "tool_run_bash", "bash",
        "run_r_code", "tool_run_r_code",
        "install_package", "tool_install_package"
      )
      tool_name %in% write_tools
    },

    # Tool-specific permission checks
    check_tool_specific = function(tool_name, tool_input, context) {
      # File read tools
      if (tool_name %in% c("read_file", "tool_read_file", "list_files", "tool_list_files")) {
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
          return(PermissionResultDeny(reason = "Bash command execution is not allowed"))
        }
        return(PermissionResultAllow())
      }

      # R code tools
      if (tool_name %in% c("run_r_code", "tool_run_r_code")) {
        if (!self$r_code) {
          return(PermissionResultDeny(reason = "R code execution is not allowed"))
        }
        return(PermissionResultAllow())
      }

      # Web tools
      if (tool_name %in% c("web_search", "tool_web_search", "web_fetch", "tool_web_fetch")) {
        if (!self$web) {
          return(PermissionResultDeny(reason = "Web access is not allowed"))
        }
        return(PermissionResultAllow())
      }

      # Package installation
      if (tool_name %in% c("install_package", "tool_install_package")) {
        if (!self$install_packages) {
          return(PermissionResultDeny(reason = "Package installation is not allowed"))
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
permissions_standard <- function(working_dir = getwd(), max_turns = 25, max_cost_usd = NULL) {
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
