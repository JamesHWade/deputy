# Built-in tools for deputy agents

#' Read file contents
#'
#' @description
#' A tool that reads the contents of a file and returns it as a string.
#'
#' @format A tool definition created with `ellmer::tool()`.
#'
#' @param path Path to the file to read (tool argument, not R function argument)
#'
#' @examples
#' \dontrun{
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-4o"),
#'   tools = list(tool_read_file)
#' )
#' }
#'
#' @export
tool_read_file <- ellmer::tool(
  fun = function(path) {
    if (!file.exists(path)) {
      ellmer::tool_reject(paste("File not found:", path))
    }

    tryCatch(
      paste(readLines(path, warn = FALSE), collapse = "\n"),
      error = function(e) {
        ellmer::tool_reject(paste("Error reading file:", e$message))
      }
    )
  },
  name = "read_file",
  description = "Read the contents of a file and return as text.",
  arguments = list(
    path = ellmer::type_string("Path to the file to read")
  ),
  annotations = ellmer::tool_annotations(
    read_only_hint = TRUE,
    destructive_hint = FALSE
  )
)

#' Write content to a file
#'
#' @description
#' A tool that writes content to a file, creating it if it doesn't exist.
#'
#' @format A tool definition created with `ellmer::tool()`.
#'
#' @param path Path to the file to write (tool argument)
#' @param content Content to write to the file (tool argument)
#' @param append If TRUE, append to existing file (tool argument)
#'
#' @examples
#' \dontrun{
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-4o"),
#'   tools = list(tool_write_file)
#' )
#' }
#'
#' @export
tool_write_file <- ellmer::tool(
  fun = function(path, content, append = FALSE) {
    tryCatch(
      {
        # Ensure directory exists
        dir <- dirname(path)
        if (!dir.exists(dir) && dir != ".") {
          dir.create(dir, recursive = TRUE)
        }

        if (append) {
          cat(content, file = path, append = TRUE)
        } else {
          writeLines(content, path)
        }

        paste("Successfully wrote", nchar(content), "characters to", path)
      },
      error = function(e) {
        ellmer::tool_reject(paste("Error writing file:", e$message))
      }
    )
  },
  name = "write_file",
  description = "Write content to a file. Creates the file if it doesn't exist, or overwrites if it does. Use append=TRUE to add to existing content.",
  arguments = list(
    path = ellmer::type_string("Path to the file to write"),
    content = ellmer::type_string("Content to write to the file"),
    append = ellmer::type_boolean(
      "If TRUE, append to existing file instead of overwriting. Default is FALSE.",
      required = FALSE
    )
  ),
  annotations = ellmer::tool_annotations(
    read_only_hint = FALSE,
    destructive_hint = TRUE
  )
)

#' List files in a directory
#'
#' @description
#' A tool that lists files and directories within a specified path.
#'
#' @format A tool definition created with `ellmer::tool()`.
#'
#' @param path Directory path to list (tool argument)
#' @param pattern Optional regex pattern to filter files (tool argument)
#' @param recursive If TRUE, list files recursively (tool argument)
#' @param full_names If TRUE, return full paths (tool argument)
#'
#' @examples
#' \dontrun{
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-4o"),
#'   tools = list(tool_list_files)
#' )
#' }
#'
#' @export
tool_list_files <- ellmer::tool(
  fun = function(
    path = ".",
    pattern = NULL,
    recursive = FALSE,
    full_names = FALSE
  ) {
    if (!dir.exists(path)) {
      ellmer::tool_reject(paste("Directory not found:", path))
    }

    tryCatch(
      {
        files <- list.files(
          path = path,
          pattern = pattern,
          recursive = recursive,
          full.names = full_names
        )

        if (length(files) == 0) {
          return("No files found")
        }

        # Get file info for better context
        file_paths <- if (full_names) files else file.path(path, files)
        info <- file.info(file_paths)

        result <- data.frame(
          name = files,
          size = info$size,
          isdir = info$isdir,
          stringsAsFactors = FALSE
        )

        # Format output
        lines <- sprintf(
          "%s %s %s",
          ifelse(result$isdir, "[DIR]", "     "),
          format(result$size, width = 10, justify = "right"),
          result$name
        )

        paste(
          c(
            paste("Directory:", path),
            paste("Files:", length(files)),
            "",
            lines
          ),
          collapse = "\n"
        )
      },
      error = function(e) {
        ellmer::tool_reject(paste("Error listing files:", e$message))
      }
    )
  },
  name = "list_files",
  description = "List files in a directory. Returns file names, sizes, and whether each is a directory.",
  arguments = list(
    path = ellmer::type_string(
      "Directory path to list. Default is current directory.",
      required = FALSE
    ),
    pattern = ellmer::type_string(
      "Optional regex pattern to filter files",
      required = FALSE
    ),
    recursive = ellmer::type_boolean(
      "If TRUE, list files recursively. Default is FALSE.",
      required = FALSE
    ),
    full_names = ellmer::type_boolean(
      "If TRUE, return full paths. Default is FALSE.",
      required = FALSE
    )
  ),
  annotations = ellmer::tool_annotations(
    read_only_hint = TRUE,
    destructive_hint = FALSE
  )
)

#' Execute R code
#'
#' @description
#' A tool that executes R code and returns the result. By default, runs in
#' a separate process for safety (requires the callr package).
#'
#' @details
#' This tool intentionally uses R's code evaluation capabilities to execute
#' arbitrary R code provided by the LLM. This is a core feature for agentic
#' workflows where the agent needs to perform data analysis or other R tasks.
#'
#' For safety:
#' - By default, code runs in a sandboxed subprocess via callr
#' - A timeout prevents runaway execution
#' - The Permissions system can disable this tool entirely
#'
#' @format A tool definition created with `ellmer::tool()`.
#'
#' @param code R code to execute (tool argument)
#'
#' @examples
#' \dontrun{
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-4o"),
#'   tools = list(tool_run_r_code)
#' )
#' }
#'
#' @export
tool_run_r_code <- ellmer::tool(
  fun = function(code) {
    # Internal parameters (not exposed to LLM)
    sandbox <- TRUE
    timeout <- 30

    execute_r_code <- function(code_string) {
      # Parse and evaluate the code, capturing output
      output <- utils::capture.output({
        result <- tryCatch(
          base::eval(base::parse(text = code_string)),
          error = function(e) {
            list(.deputy_error = e$message)
          }
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
    }

    if (sandbox && rlang::is_installed("callr")) {
      tryCatch(
        {
          result <- callr::r(
            function(code_string) {
              output <- utils::capture.output({
                result <- tryCatch(
                  base::eval(base::parse(text = code_string)),
                  error = function(e) list(.deputy_error = e$message)
                )
              })
              list(
                output = paste(output, collapse = "\n"),
                result = if (
                  is.list(result) && ".deputy_error" %in% names(result)
                ) {
                  paste("Error:", result$.deputy_error)
                } else {
                  utils::capture.output(print(result))
                }
              )
            },
            args = list(code_string = code),
            timeout = timeout
          )
        },
        error = function(e) {
          return(paste("Execution error:", e$message))
        }
      )
    } else if (sandbox && !rlang::is_installed("callr")) {
      # Security: Require callr for sandboxed execution - don't fall back to unsafe
      return(ellmer::tool_reject(
        "Cannot execute R code: package 'callr' is required for sandboxed execution. Install with install.packages('callr')"
      ))
    } else {
      # sandbox = FALSE (not exposed to LLM, only for internal use)
      result <- execute_r_code(code)
    }

    # Format output
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
  },
  name = "run_r_code",
  description = "Execute R code and return the output and result. By default runs in a sandboxed process for safety.",
  arguments = list(
    code = ellmer::type_string("R code to execute")
    # Note: sandbox and timeout are internal parameters, not exposed to LLM
  ),
  annotations = ellmer::tool_annotations(
    read_only_hint = FALSE,
    destructive_hint = TRUE,
    open_world_hint = TRUE
  )
)

#' Execute bash commands
#'
#' @description
#' A tool that executes bash/shell commands and returns the output.
#' **Use with caution!** This can execute arbitrary system commands.
#'
#' @format A tool definition created with `ellmer::tool()`.
#'
#' @param command The bash command to execute (tool argument)
#'
#' @examples
#' \dontrun{
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-4o"),
#'   tools = list(tool_run_bash),
#'   permissions = permissions_full()  # Required for bash
#' )
#' }
#'
#' @export
tool_run_bash <- ellmer::tool(
  fun = function(command) {
    # Internal parameter (not exposed to LLM)
    timeout <- 30

    # Use callr for reliable timeout enforcement if available
    if (rlang::is_installed("callr")) {
      tryCatch(
        {
          result <- callr::r(
            function(cmd) {
              system(cmd, intern = TRUE)
            },
            args = list(cmd = command),
            timeout = timeout
          )
          if (length(result) == 0) {
            "Command executed successfully (no output)"
          } else {
            paste(result, collapse = "\n")
          }
        },
        error = function(e) {
          if (grepl("timeout", e$message, ignore.case = TRUE)) {
            ellmer::tool_reject(paste("Command timed out after", timeout, "seconds"))
          } else {
            ellmer::tool_reject(paste("Command failed:", e$message))
          }
        }
      )
    } else {
      # Fallback to system() - timeout may not be reliable
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

#' Read a CSV file
#'
#' @description
#' A tool that reads a CSV file and returns a summary of its structure
#' along with the first few rows.
#'
#' @format A tool definition created with `ellmer::tool()`.
#'
#' @param path Path to the CSV file to read (tool argument)
#' @param n_max Maximum number of rows to read (tool argument)
#' @param show_head Number of rows to show in preview (tool argument)
#'
#' @examples
#' \dontrun{
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-4o"),
#'   tools = list(tool_read_csv)
#' )
#' }
#'
#' @export
tool_read_csv <- ellmer::tool(
  fun = function(path, n_max = 1000, show_head = 10) {
    if (!file.exists(path)) {
      ellmer::tool_reject(paste("File not found:", path))
    }

    tryCatch(
      {
        # Use readr if available, otherwise base R
        if (rlang::is_installed("readr")) {
          df <- readr::read_csv(path, n_max = n_max, show_col_types = FALSE)
        } else {
          df <- utils::read.csv(path, nrows = n_max, stringsAsFactors = FALSE)
        }

        # Build summary
        summary_lines <- c(
          paste("File:", path),
          paste(
            "Rows:",
            nrow(df),
            if (n_max < Inf && nrow(df) == n_max) "(limited)" else ""
          ),
          paste("Columns:", ncol(df)),
          "",
          "Column types:",
          paste(" ", names(df), ":", sapply(df, function(x) class(x)[1])),
          "",
          paste("First", min(show_head, nrow(df)), "rows:"),
          utils::capture.output(print(utils::head(df, show_head)))
        )

        paste(summary_lines, collapse = "\n")
      },
      error = function(e) {
        ellmer::tool_reject(paste("Error reading CSV:", e$message))
      }
    )
  },
  name = "read_csv",
  description = "Read a CSV file and return a summary with column types and first few rows.",
  arguments = list(
    path = ellmer::type_string("Path to the CSV file"),
    n_max = ellmer::type_integer(
      "Maximum rows to read. Default is 1000.",
      required = FALSE
    ),
    show_head = ellmer::type_integer(
      "Number of rows to show in preview. Default is 10.",
      required = FALSE
    )
  ),
  annotations = ellmer::tool_annotations(
    read_only_hint = TRUE,
    destructive_hint = FALSE
  )
)
