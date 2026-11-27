#' @include value-properties.R
NULL

#' Create a permission policy
#'
#' @description
#' A `Permissions` object decides which tool calls an agent may make. Pass it
#' to `Agent$new()`, or test a call with [permissions_check()].
#' [PermissionMode] describes how each mode uses these settings.
#'
#' The object is read-only; read its fields with `$`. To restrict an agent
#' further while it runs, call `agent$set_permission_mode()`. Permissions can
#' be narrowed but not widened.
#'
#' A policy is not an OS sandbox: code run through `run_r_code` or `run_bash`
#' can do anything your R session can.
#'
#' @param mode One of `"standard"`, `"plan"`, `"readonly"`, or `"full"`.
#' @param file_read Allow file reading. `TRUE` or `FALSE`. Reads aren't
#'   limited to a directory: with `TRUE`, the file tools can read any file the
#'   R process can, including credential files such as `~/.Renviron`. Use
#'   `can_use_tool` to refuse particular paths.
#' @param file_write `TRUE`, `FALSE`, or an existing absolute directory. A
#'   directory allows writes only inside it and is resolved when the policy is
#'   created. The path is checked when the model asks to write and again just
#'   before writing, so a symbolic link swapped in between is refused. The
#'   second check narrows the window for such a swap but can't remove it.
#'   Defaults to the current working directory.
#' @param bash Allow shell commands. `TRUE` or `FALSE`.
#' @param r_code Allow R code execution. `TRUE` or `FALSE`.
#' @param web Allow web access, including other tools that reach external
#'   systems. `TRUE` or `FALSE`.
#' @param install_packages Allow package installation. `TRUE` or `FALSE`.
#' @param can_use_tool Optional function `(tool_name, tool_input, context)`
#'   that returns [PermissionResultAllow()], [PermissionResultDeny()] or
#'   [PermissionResultPending()]. It is called, in every mode, for each call
#'   the rest of the policy allows, so it can deny a call or pause it for
#'   approval but can't allow a call the policy denies. Any other return
#'   value, including `NULL`, denies the call with a warning, and so does an
#'   error.
#' @param tool_allowlist Character vector of allowed tool names, or `NULL`
#'   (the default) to allow any name. An empty vector denies all tools.
#' @param tool_denylist Character vector of denied tool names, or `NULL`.
#' @param permission_prompt_tool_name Optional name of a tool the model can
#'   call to ask for approval, such as `"ask_user"`. It is allowed in every
#'   mode unless `tool_allowlist` or `tool_denylist` excludes it, and denials
#'   from those lists point the model to it. Built-in file, code, web, install
#'   and delegation tools can't be used.
#' @return A `Permissions` object.
#' @seealso `vignette("permissions")`
#' @examples
#' policy <- Permissions(file_write = FALSE)
#' permissions_check(policy, "write_file", list(path = "output.txt"))
#' policy$file_write
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

register_dollar_prop(Permissions)

#' Check a tool call against a permission policy
#'
#' Returns the policy's decision for one tool call. It calls the policy's
#' `can_use_tool` callback if the rest of the policy allows the call, but runs
#' no hooks. Use it to test a policy.
#'
#' @param permissions A [Permissions] object.
#' @param tool_name Name of the tool.
#' @param tool_input Named list of arguments for the tool.
#' @param context Optional named list of details the agent normally supplies,
#'   such as `working_dir` (used to resolve relative paths) and
#'   `tool_annotations`.
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

  # Allow the configured prompt tool so gated workflows can request
  # explicit human approval, provided it passed explicit tool gating. A
  # native prompt name such as ask_user must belong to Deputy's own tool; a
  # host-chosen prompt name is the host's explicit trust.
  if (
    !is_mcp_tool_context(context) &&
      permission_is_prompt_tool(permissions, tool_name) &&
      (permission_trusts_native_name(context) ||
        !normalize_native_tool_id(tool_name) %in% permission_native_tool_ids)
  ) {
    return(PermissionResultAllow())
  }

  mode_result <- permission_check_mode(
    permissions,
    tool_name,
    tool_input,
    context,
    allowlist_exempt = allowlist_exempt
  )
  if (!S7::S7_inherits(mode_result, PermissionResultAllow)) {
    return(mode_result)
  }

  # The callback refines what the mode and capabilities allow: it can deny
  # a call or pause it for approval, but never allow a call they deny.
  permission_apply_callback_veto(permissions, tool_name, tool_input, context)
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

permissions_from_mode <- function(mode, working_dir = getwd(), ...) {
  caps <- permission_mode_capabilities(mode, working_dir = working_dir)
  overrides <- list(...)
  for (name in names(overrides)) {
    caps[name] <- list(overrides[[name]])
  }
  do.call(Permissions, c(list(mode = mode), caps))
}

#' Create a read-only permission policy
#'
#' @description
#' Creates a `"readonly"` policy. The agent can use the built-in file-reading
#' tools such as `read_file`, `list_files` and `grep_files`, and can delegate
#' to its subagents and retained agents, which are held to read-only mode too.
#' Writes, code execution, web access and custom tools are denied.
#'
#' @return A [Permissions] object.
#'
#' @examples
#' perms <- permissions_readonly()
#' permissions_check(perms, "read_file", list(path = "test.txt"))
#'
#' @export
permissions_readonly <- function() {
  permissions_from_mode("readonly")
}

#' Create a standard permission policy
#'
#' @description
#' Creates a `"standard"` policy for everyday use. The agent can read any file
#' your R session can read, and write files inside `working_dir`. R code, shell
#' commands, web access and package installation are denied. Turn on code
#' execution only when you trust the model and the task: the code runs with
#' your user's access, not in an OS sandbox.
#'
#' @param working_dir An existing absolute path to the directory the agent may
#'   write to. Defaults to the current directory. Reads are not limited to it.
#' @return A [Permissions] object.
#'
#' @examples
#' perms <- permissions_standard()
#' permissions_check(perms, "write_file", list(path = "output.txt"))
#'
#' @export
permissions_standard <- function(working_dir = getwd()) {
  permissions_from_mode("standard", working_dir = working_dir)
}

#' Create a planning permission policy
#'
#' @description
#' Creates a `"plan"` policy, for letting the model look around and propose a
#' plan before it changes anything. Only tools annotated as read-only are
#' allowed, plus the approval prompt tool and delegation to the agent's
#' subagents and retained agents, which are held to plan mode too. Web access
#' is on, so read-only web tools such as `web_fetch` work. Writes and code
#' execution are denied.
#'
#' @param permission_prompt_tool_name Name of the tool the model can call to
#'   ask for approval, `"ask_user"` by default. `NULL` means none. Built-in
#'   file, code, web, install and delegation tools can't be used.
#' @return A [Permissions] object.
#'
#' @examples
#' perms <- permissions_plan()
#'
#' @export
permissions_plan <- function(
  permission_prompt_tool_name = "ask_user"
) {
  permissions_from_mode(
    "plan",
    permission_prompt_tool_name = permission_prompt_tool_name
  )
}

#' Create a full access permission policy
#'
#' @description
#' Creates a `"full"` policy, which allows every tool call: writes anywhere
#' your R session can write, R and shell code, web access and package
#' installation. Capability flags and tool annotations are not checked,
#' though PreToolUse hooks still run and can deny a call. Use it only
#' with a model and task you trust, ideally inside a container or other OS
#' sandbox.
#'
#' @return A [Permissions] object.
#'
#' @examples
#' perms <- permissions_full()
#'
#' @export
permissions_full <- function() {
  permissions_from_mode("full")
}
