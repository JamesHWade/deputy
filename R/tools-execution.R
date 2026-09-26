# Trusted one-shot R and shell tools.

run_r_code_impl <- function(code, timeout = 30, working_dir = getwd()) {
  rlang::check_installed("callr", reason = "to execute R code in a subprocess")

  result <- tryCatch(
    callr::r(
      function(code_string) {
        output <- utils::capture.output({
          result <- tryCatch(
            base::eval(base::parse(text = code_string)),
            error = function(e) list(.deputy_error = e$message)
          )
        })
        list(
          output = paste(output, collapse = "\n"),
          result = if (is.list(result) && ".deputy_error" %in% names(result)) {
            paste("Error:", result$.deputy_error)
          } else {
            utils::capture.output(print(result))
          }
        )
      },
      args = list(code_string = code),
      timeout = timeout,
      wd = working_dir
    ),
    error = function(e) {
      if (inherits(e, "callr_timeout_error")) {
        ellmer::tool_reject(sprintf(
          "R code execution timed out after %s seconds",
          format(timeout, trim = TRUE)
        ))
      }
      ellmer::tool_reject(paste(
        "R code execution failed:",
        conditionMessage(e)
      ))
    }
  )

  parts <- character()
  if (nchar(result$output) > 0) {
    parts <- c(parts, "Output:", result$output)
  }
  if (length(result$result) > 0 && any(nchar(result$result) > 0)) {
    parts <- c(parts, "Result:", paste(result$result, collapse = "\n"))
  }

  if (length(parts) == 0) {
    return("Code executed successfully (no output)")
  }

  paste(parts, collapse = "\n")
}

#' Execute R code
#'
#' @description
#' A tool that runs model-written R code and returns its printed output and
#' value. Each call starts a fresh R process, so nothing carries over between
#' calls; for a persistent session, use [RSession]. Calls time out after 30
#' seconds.
#'
#' The code runs with your user account's access to files and the network. The
#' separate process protects your R session from crashes; it is not a sandbox.
#' The default permissions deny this tool; allow it with `r_code = TRUE` in
#' [Permissions()]. For an OS sandbox, use [tools_mcp_repl()].
#'
#' @format A tool definition created with `ellmer::tool()`.
#' @return The captured output and the printed value as one string.
#'
#' @param code R code to run.
#'
#' @examples
#' \dontrun{
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-6-luna"),
#'   tools = list(tool_run_r_code),
#'   permissions = Permissions(r_code = TRUE)
#' )
#' }
#'
#' @export
tool_run_r_code <- ellmer::tool(
  fun = function(code) {
    run_r_code_impl(code)
  },
  name = "run_r_code",
  description = paste(
    "Execute R code in a separate process and return the output and result.",
    "Process isolation is not an OS security sandbox."
  ),
  arguments = list(
    code = ellmer::type_string("R code to execute")
    # Note: process isolation and timeout are internal, not exposed to the LLM
  ),
  annotations = ellmer::tool_annotations(
    read_only_hint = FALSE,
    destructive_hint = TRUE,
    open_world_hint = TRUE
  )
)
attr(tool_run_r_code, "deputy_workspace_runner") <-
  function(arguments, working_dir) {
    run_r_code_impl(arguments$code, working_dir = working_dir)
  }

# A non-zero exit is a failed step: the model sees the status and both streams.
bash_result <- function(output, errors, status) {
  text <- paste(
    c(output, if (length(errors)) c("[stderr]", errors)),
    collapse = "\n"
  )
  if (!identical(status, 0L)) {
    ellmer::tool_reject(paste0(
      "Command exited with status ",
      status,
      if (nzchar(text)) paste0(":\n", text) else " (no output)"
    ))
  }
  if (!nzchar(text)) "Command executed successfully (no output)" else text
}

run_bash_impl <- function(command, timeout = 30, working_dir = getwd()) {
  # Use callr for reliable timeout enforcement if available
  if (rlang::is_installed("callr")) {
    # The shell inherits the child's stderr, so this file captures its errors.
    stderr_file <- tempfile("deputy-bash-", fileext = ".txt")
    on.exit(unlink(stderr_file), add = TRUE)
    result <- tryCatch(
      callr::r(
        function(cmd) {
          # system(intern = TRUE) errors on status 127 (command not found);
          # the shell has already written its message to stderr.
          output <- tryCatch(
            suppressWarnings(system(cmd, intern = TRUE)),
            error = function(e) structure(character(), status = 127L)
          )
          status <- attr(output, "status")
          list(
            output = as.character(output),
            status = if (is.null(status)) 0L else as.integer(status)
          )
        },
        args = list(cmd = command),
        timeout = timeout,
        wd = working_dir,
        stderr = stderr_file
      ),
      error = function(e) {
        if (inherits(e, "callr_timeout_error")) {
          ellmer::tool_reject(sprintf(
            "Command timed out after %s seconds",
            format(timeout, trim = TRUE)
          ))
        }
        ellmer::tool_reject(paste(
          "Command failed:",
          conditionMessage(e)
        ))
      }
    )
    errors <- if (file.exists(stderr_file)) {
      readLines(stderr_file, warn = FALSE)
    } else {
      character()
    }
    bash_result(result$output, errors, result$status)
  } else {
    # Keep the host process directory unchanged in the fallback path.
    command <- paste("cd", shQuote(working_dir), "&&", command)
    tryCatch(
      {
        result <- system(command, intern = TRUE, timeout = timeout)
        if (length(result) == 0) {
          "Command executed successfully (no output)"
        } else {
          paste(result, collapse = "\n")
        }
      },
      error = function(e) {
        ellmer::tool_reject(paste("Command failed:", e$message))
      },
      warning = function(w) {
        paste("Warning:", w$message)
      }
    )
  }
}

#' Execute bash commands
#'
#' @description
#' A tool that runs a shell command and returns its output. The model can run
#' any command your user account can, and nothing is sandboxed. Commands time
#' out after 30 seconds. The default permissions deny this tool; allow it with
#' `bash = TRUE` in [Permissions()].
#'
#' @format A tool definition created with `ellmer::tool()`.
#' @return The command's output as one string, with standard error after a
#'   `[stderr]` line. A command that exits with a non-zero status is reported
#'   to the model as a failed tool call, with its status and output.
#'
#' @param command The shell command to run.
#'
#' @examples
#' \dontrun{
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-6-luna"),
#'   tools = list(tool_run_bash),
#'   permissions = Permissions(bash = TRUE)
#' )
#' }
#'
#' @export
tool_run_bash <- ellmer::tool(
  fun = function(command) {
    run_bash_impl(command)
  },
  name = "run_bash",
  description = "Execute a bash/shell command and return the output. Use with caution - this can execute arbitrary system commands.",
  arguments = list(
    command = ellmer::type_string("The bash command to execute")
    # Note: timeout is an internal parameter, not exposed to LLM
  ),
  annotations = ellmer::tool_annotations(
    read_only_hint = FALSE,
    destructive_hint = TRUE,
    open_world_hint = TRUE
  )
)
attr(tool_run_bash, "deputy_workspace_runner") <-
  function(arguments, working_dir) {
    run_bash_impl(arguments$command, working_dir = working_dir)
  }
