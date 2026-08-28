# Built-in tools for deputy agents

# Parse a page selector string like "1,3-5" into integer page numbers
parse_pdf_page_selector <- function(pages, page_count) {
  if (is.null(pages) || identical(pages, "")) {
    return(seq_len(page_count))
  }

  if (is.numeric(pages)) {
    nums <- as.integer(pages)
  } else if (is.character(pages) && length(pages) == 1) {
    tokens <- trimws(unlist(strsplit(pages, ",", fixed = TRUE)))
    tokens <- tokens[nzchar(tokens)]
    if (length(tokens) == 0) {
      cli_abort("No valid pages specified.")
    }
    nums <- integer()
    for (token in tokens) {
      if (grepl("^[0-9]+$", token)) {
        nums <- c(nums, as.integer(token))
      } else if (grepl("^[0-9]+-[0-9]+$", token)) {
        bounds <- as.integer(strsplit(token, "-", fixed = TRUE)[[1]])
        start <- bounds[1]
        end <- bounds[2]
        if (start > end) {
          cli_abort("Invalid page range: {.val {token}}.")
        }
        nums <- c(nums, seq.int(start, end))
      } else {
        cli_abort("Invalid page selector token: {.val {token}}.")
      }
    }
  } else {
    cli_abort(
      "{.arg pages} must be NULL, numeric, or a selector string like {.val 1,3-5}."
    )
  }

  if (any(is.na(nums)) || any(nums < 1)) {
    cli_abort("Page numbers must be positive integers.")
  }
  if (any(nums > page_count)) {
    cli_abort(
      "Page selection exceeds document length of {page_count} page{?s}."
    )
  }

  sort(unique(nums))
}

# Read PDF text using pdftools if available, otherwise reticulate + pypdf.
read_pdf_text_pages <- function(path) {
  if (rlang::is_installed("pdftools")) {
    return(pdftools::pdf_text(path))
  }

  if (rlang::is_installed("reticulate")) {
    if (!reticulate::py_module_available("pypdf")) {
      cli_abort(c(
        "Python module {.pkg pypdf} is not available.",
        "i" = "Install {.pkg pypdf}, or the R package {.pkg pdftools}."
      ))
    }

    pypdf <- reticulate::import("pypdf", delay_load = FALSE)
    reader <- pypdf$PdfReader(path)
    page_count <- as.integer(reticulate::py_len(reader$pages))

    text <- vapply(
      seq_len(page_count),
      function(i) {
        extracted <- reader$pages[[as.integer(i)]]$extract_text()
        if (is.null(extracted)) "" else as.character(extracted)
      },
      character(1)
    )

    return(text)
  }

  cli_abort(c(
    "Reading PDF content requires {.pkg pdftools}.",
    "i" = "Alternatively, install {.pkg reticulate} with the Python module {.pkg pypdf}."
  ))
}

# Convert a local file to markdown using Python MarkItDown via reticulate
convert_to_markdown_markitdown <- function(path) {
  if (!rlang::is_installed("reticulate")) {
    cli_abort("{.pkg reticulate} is required for MarkItDown conversion.")
  }

  available <- tryCatch(
    reticulate::py_module_available("markitdown"),
    error = function(e) FALSE
  )
  if (!available) {
    cli_abort(c(
      "Python module {.pkg markitdown} is not available.",
      "i" = "Install with {.code pip install 'markitdown[all]'}."
    ))
  }

  markitdown <- reticulate::import("markitdown", delay_load = FALSE)
  converter <- markitdown$MarkItDown()
  result <- converter$convert(path)

  text <- tryCatch(
    reticulate::py_to_r(result$text_content),
    error = function(e) NULL
  )
  if (is.null(text)) {
    text <- tryCatch(
      reticulate::py_to_r(result$markdown),
      error = function(e) NULL
    )
  }

  if (is.null(text)) {
    cli_abort("MarkItDown conversion did not return markdown text.")
  }

  if (length(text) > 1) {
    text <- paste(as.character(text), collapse = "\n")
  }

  text <- as.character(text[[1]])
  if (!nzchar(text)) {
    cli_abort("MarkItDown conversion returned empty markdown.")
  }

  text
}

# Count fixed-string matches in text.
count_fixed_matches <- function(text, pattern) {
  matches <- gregexpr(pattern, text, fixed = TRUE)[[1]]
  if (length(matches) == 1 && identical(matches[[1]], -1L)) {
    return(0L)
  }
  length(matches)
}

# Apply a fixed-string replacement with safety checks for edit tools.
replace_fixed_text <- function(text, old_text, new_text, replace_all = FALSE) {
  if (!nzchar(old_text)) {
    cli_abort("{.arg old_text} must not be empty.")
  }

  occurrences <- count_fixed_matches(text, old_text)
  if (occurrences == 0L) {
    cli_abort("{.arg old_text} was not found in the file.")
  }

  if (!isTRUE(replace_all) && occurrences > 1L) {
    cli_abort(c(
      "{.arg old_text} matched {occurrences} locations.",
      "i" = "Set {.code replace_all = TRUE} to replace all of them."
    ))
  }

  updated <- if (isTRUE(replace_all)) {
    gsub(old_text, new_text, text, fixed = TRUE)
  } else {
    sub(old_text, new_text, text, fixed = TRUE)
  }

  list(
    text = updated,
    replacements = if (isTRUE(replace_all)) occurrences else 1L
  )
}

# Parse multi-edit operations from a list or JSON string.
parse_multi_edits <- function(edits) {
  parsed <- edits

  if (is.character(edits) && length(edits) == 1) {
    if (!rlang::is_installed("jsonlite")) {
      cli_abort("Parsing JSON edits requires {.pkg jsonlite}.")
    }

    parsed <- tryCatch(
      jsonlite::fromJSON(edits, simplifyVector = FALSE),
      error = function(e) {
        cli_abort("Could not parse {.arg edits} as JSON.", parent = e)
      }
    )
  }

  if (!is.list(parsed) || length(parsed) == 0) {
    cli_abort("{.arg edits} must be a non-empty list or JSON array.")
  }

  lapply(seq_along(parsed), function(i) {
    edit <- parsed[[i]]
    if (!is.list(edit)) {
      cli_abort("Edit {i} must be an object.")
    }

    old_text <- edit$old_text %||% edit$old_string
    new_text <- edit$new_text %||% edit$new_string
    replace_all <- isTRUE(edit$replace_all %||% edit$replaceAll)

    if (is.null(old_text) || is.null(new_text)) {
      cli_abort("Edit {i} must include {.arg old_text} and {.arg new_text}.")
    }

    list(
      old_text = as.character(old_text[[1]]),
      new_text = as.character(new_text[[1]]),
      replace_all = replace_all
    )
  })
}

# Convert a glob pattern to a regex with basic ** support.
glob_pattern_to_regex <- function(pattern) {
  placeholder <- "<<DEPUTY_GLOBSTAR>>"
  regex <- pattern
  regex <- gsub("\\*\\*", placeholder, regex)
  regex <- gsub("([][{}()+^$.|\\\\])", "\\\\\\1", regex, perl = TRUE)
  regex <- gsub("\\*", "[^/]*", regex)
  regex <- gsub("\\?", "[^/]", regex)
  regex <- gsub(placeholder, ".*", regex, fixed = TRUE)
  paste0("^", regex, "$")
}

# List files relative to a base directory using a glob-style filter.
glob_relative_paths <- function(path = ".", pattern = "*", recursive = TRUE) {
  if (!dir.exists(path)) {
    cli_abort("Directory not found: {.path {path}}.")
  }

  base <- normalizePath(path, mustWork = TRUE)
  paths <- list.files(
    base,
    recursive = recursive,
    full.names = TRUE,
    include.dirs = TRUE,
    all.files = TRUE,
    no.. = TRUE
  )

  if (length(paths) == 0) {
    return(character())
  }

  rel <- substring(paths, nchar(base) + 2L)
  rel <- rel[nzchar(rel)]

  regex <- glob_pattern_to_regex(pattern)
  matches <- grepl(regex, rel, perl = TRUE)

  # In recursive mode, bare patterns like "*.R" should match nested basenames.
  if (isTRUE(recursive) && !grepl("/", pattern, fixed = TRUE)) {
    matches <- matches | grepl(regex, basename(rel), perl = TRUE)
  }

  sort(rel[matches])
}

#' Read file contents
#'
#' @description
#' A tool that reads the contents of a file and returns it as a string.
#'
#' @format A tool definition created with `ellmer::tool()`.
#' @return When called directly, a character string with the file contents, or
#'   a structured list when selected PDF pages are requested.
#'
#' @param path Path to the file to read (tool argument, not R function argument)
#' @param pages Optional PDF page selection. Accepts comma-separated pages and
#'   ranges (e.g. `"1,3-5"`). Only supported for PDF files.
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
  fun = function(path, pages = NULL) {
    if (!file.exists(path)) {
      ellmer::tool_reject(paste("File not found:", path))
    }

    is_pdf <- tolower(tools::file_ext(path)) == "pdf"

    if (!is_pdf && !is.null(pages) && !identical(pages, "")) {
      ellmer::tool_reject(
        "The pages argument is only supported for PDF files."
      )
    }

    tryCatch(
      {
        if (!is_pdf) {
          return(paste(readLines(path, warn = FALSE), collapse = "\n"))
        }

        page_text <- read_pdf_text_pages(path)
        page_count <- length(page_text)
        selected <- parse_pdf_page_selector(pages, page_count)

        # Preserve historical behavior: plain string for full-file reads.
        if (is.null(pages) || identical(pages, "")) {
          combined <- paste(page_text, collapse = "\n\n--- page break ---\n\n")
          return(combined)
        }

        selected_text <- unname(page_text[selected])
        parts <- lapply(
          seq_along(selected),
          function(i) {
            list(
              page = as.integer(selected[[i]]),
              text = selected_text[[i]]
            )
          }
        )

        list(
          path = normalizePath(path, mustWork = FALSE),
          type = "pdf",
          page_count = as.integer(page_count),
          pages = as.integer(selected),
          parts = parts,
          text = paste(selected_text, collapse = "\n\n--- page break ---\n\n")
        )
      },
      error = function(e) {
        ellmer::tool_reject(paste("Error reading file:", e$message))
      }
    )
  },
  name = "read_file",
  description = "Read a file and return its contents as text. For PDF files, you can optionally select specific pages with the pages argument (e.g., '1,3-5').",
  arguments = list(
    path = ellmer::type_string("Path to the file to read"),
    pages = ellmer::type_string(
      "Optional PDF page selector like '1,3-5'. Only valid for PDF files.",
      required = FALSE
    )
  ),
  annotations = ellmer::tool_annotations(
    read_only_hint = TRUE,
    destructive_hint = FALSE
  )
)

#' Convert a file to markdown using MarkItDown
#'
#' @description
#' Converts a local file to markdown text using Python
#' [MarkItDown](https://github.com/microsoft/markitdown) via `reticulate`.
#' This is useful for rich formats (e.g. DOCX, PPTX, PDF, HTML) when you want
#' a markdown representation instead of raw file text.
#'
#' @format A tool definition created with `ellmer::tool()`.
#' @return When called directly, a character string containing the converted
#'   markdown.
#'
#' @param path Path to the file to convert (tool argument, not R function argument)
#'
#' @details
#' Requires:
#' - R package `reticulate`
#' - Python module `markitdown` (e.g., `pip install 'markitdown[all]'`)
#'
#' @examples
#' \dontrun{
#' tool_read_markdown("report.pdf")
#' }
#'
#' @export
tool_read_markdown <- ellmer::tool(
  fun = function(path) {
    if (!file.exists(path)) {
      ellmer::tool_reject(paste("File not found:", path))
    }

    tryCatch(
      convert_to_markdown_markitdown(path),
      error = function(e) {
        ellmer::tool_reject(paste(
          "Error converting file to markdown:",
          e$message
        ))
      }
    )
  },
  name = "read_markdown",
  description = "Convert a local file to markdown using MarkItDown. Useful for rich document formats.",
  arguments = list(
    path = ellmer::type_string("Path to the file to convert")
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
#' @return When called directly, a character status message describing the
#'   write.
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

#' Edit file contents by replacing text
#'
#' @description
#' Replace a specific text span in an existing file.
#'
#' @format A tool definition created with `ellmer::tool()`.
#' @return When called directly, a character status message describing the
#'   edit and replacement count.
#'
#' @param path Path to the file to edit (tool argument)
#' @param old_text Existing text to replace (tool argument)
#' @param new_text Replacement text (tool argument)
#' @param replace_all If TRUE, replace all matches instead of requiring a
#'   unique match (tool argument)
#'
#' @examples
#' path <- tempfile(fileext = ".txt")
#' writeLines("alpha", path)
#' tool_edit_file(path, "alpha", "beta")
#' unlink(path)
#'
#' @export
tool_edit_file <- ellmer::tool(
  fun = function(path, old_text, new_text, replace_all = FALSE) {
    if (!file.exists(path)) {
      ellmer::tool_reject(paste("File not found:", path))
    }

    tryCatch(
      {
        original <- paste(readLines(path, warn = FALSE), collapse = "\n")
        updated <- replace_fixed_text(
          original,
          old_text = old_text,
          new_text = new_text,
          replace_all = replace_all
        )
        writeLines(updated$text, path)

        paste(
          "Successfully edited",
          path,
          sprintf(
            "(%s replacement%s)",
            updated$replacements,
            if (updated$replacements == 1L) "" else "s"
          )
        )
      },
      error = function(e) {
        ellmer::tool_reject(paste("Error editing file:", e$message))
      }
    )
  },
  name = "edit_file",
  description = "Replace text in an existing file. By default the target text must appear exactly once.",
  arguments = list(
    path = ellmer::type_string("Path to the file to edit"),
    old_text = ellmer::type_string("Existing text to replace"),
    new_text = ellmer::type_string("Replacement text"),
    replace_all = ellmer::type_boolean(
      "If TRUE, replace every occurrence of old_text. Default is FALSE.",
      required = FALSE
    )
  ),
  annotations = ellmer::tool_annotations(
    read_only_hint = FALSE,
    destructive_hint = TRUE
  )
)

#' Apply multiple text edits to a file
#'
#' @description
#' Apply a sequence of exact-match text replacements to a file.
#'
#' @format A tool definition created with `ellmer::tool()`.
#' @return When called directly, a character status message describing the
#'   edits and total replacement count.
#'
#' @param path Path to the file to edit (tool argument)
#' @param edits List or JSON string of edit operations (tool argument)
#'
#' @examples
#' path <- tempfile(fileext = ".txt")
#' writeLines(c("alpha", "beta"), path)
#' tool_multi_edit(
#'   path,
#'   list(list(old_text = "alpha", new_text = "gamma"))
#' )
#' unlink(path)
#'
#' @export
tool_multi_edit <- ellmer::tool(
  fun = function(path, edits) {
    if (!file.exists(path)) {
      ellmer::tool_reject(paste("File not found:", path))
    }

    tryCatch(
      {
        operations <- parse_multi_edits(edits)
        text <- paste(readLines(path, warn = FALSE), collapse = "\n")
        total_replacements <- 0L

        for (edit in operations) {
          result <- replace_fixed_text(
            text,
            old_text = edit$old_text,
            new_text = edit$new_text,
            replace_all = edit$replace_all
          )
          text <- result$text
          total_replacements <- total_replacements + result$replacements
        }

        writeLines(text, path)

        paste(
          "Successfully applied",
          length(operations),
          "edit(s) to",
          path,
          sprintf(
            "(%s total replacement%s)",
            total_replacements,
            if (total_replacements == 1L) "" else "s"
          )
        )
      },
      error = function(e) {
        ellmer::tool_reject(paste("Error applying edits:", e$message))
      }
    )
  },
  name = "multi_edit",
  description = "Apply multiple exact-match text replacements to a file. Edits can be provided as a list or JSON string.",
  arguments = list(
    path = ellmer::type_string("Path to the file to edit"),
    edits = ellmer::type_string(
      "JSON array or structured list of edit operations with old_text/new_text.",
      required = TRUE
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
#' @return When called directly, a character summary of the matching files and
#'   directories.
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

#' Find files using a glob pattern
#'
#' @description
#' Search for files under a directory using shell-style glob matching.
#'
#' @format A tool definition created with `ellmer::tool()`.
#' @return When called directly, a character summary of paths matching the
#'   glob pattern.
#'
#' @param pattern Glob pattern to match (tool argument)
#' @param path Base directory to search (tool argument)
#' @param recursive If TRUE, search subdirectories recursively (tool argument)
#'
#' @examples
#' directory <- tempfile()
#' dir.create(directory)
#' writeLines("example", file.path(directory, "example.txt"))
#' tool_glob_files("*.txt", directory)
#' unlink(directory, recursive = TRUE)
#'
#' @export
tool_glob_files <- ellmer::tool(
  fun = function(pattern = "*", path = ".", recursive = TRUE) {
    tryCatch(
      {
        matches <- glob_relative_paths(
          path = path,
          pattern = pattern,
          recursive = recursive
        )

        if (length(matches) == 0) {
          return(paste("No files matched pattern", shQuote(pattern)))
        }

        paste(
          c(
            paste("Base path:", path),
            paste("Matches:", length(matches)),
            "",
            matches
          ),
          collapse = "\n"
        )
      },
      error = function(e) {
        ellmer::tool_reject(paste("Error globbing files:", e$message))
      }
    )
  },
  name = "glob_files",
  description = "Find files matching a glob pattern under a base directory.",
  arguments = list(
    pattern = ellmer::type_string("Glob pattern to match"),
    path = ellmer::type_string(
      "Base directory to search. Default is current directory.",
      required = FALSE
    ),
    recursive = ellmer::type_boolean(
      "If TRUE, search recursively. Default is TRUE.",
      required = FALSE
    )
  ),
  annotations = ellmer::tool_annotations(
    read_only_hint = TRUE,
    destructive_hint = FALSE
  )
)

#' Search file contents with grep-like matching
#'
#' @description
#' Search text files under a directory and return matching lines.
#'
#' @format A tool definition created with `ellmer::tool()`.
#' @return When called directly, a character summary of matching file lines.
#'
#' @param pattern Regex pattern to search for (tool argument)
#' @param path Base directory to search (tool argument)
#' @param recursive If TRUE, search subdirectories recursively (tool argument)
#' @param ignore_case If TRUE, ignore case when matching (tool argument)
#' @param max_matches Maximum matching lines to return (tool argument)
#'
#' @examples
#' directory <- tempfile()
#' dir.create(directory)
#' writeLines("needle", file.path(directory, "example.txt"))
#' tool_grep_files("needle", directory)
#' unlink(directory, recursive = TRUE)
#'
#' @export
tool_grep_files <- ellmer::tool(
  fun = function(
    pattern,
    path = ".",
    recursive = TRUE,
    ignore_case = FALSE,
    max_matches = 100
  ) {
    tryCatch(
      {
        rel_paths <- glob_relative_paths(
          path = path,
          pattern = if (isTRUE(recursive)) "**" else "*",
          recursive = recursive
        )

        if (length(rel_paths) == 0) {
          return("No files available to search")
        }

        max_matches <- as.integer(max_matches %||% 100L)
        if (is.na(max_matches) || max_matches < 1L) {
          max_matches <- 100L
        }

        hits <- character()
        base <- normalizePath(path, mustWork = TRUE)

        for (rel_path in rel_paths) {
          full_path <- file.path(base, rel_path)
          if (isTRUE(file.info(full_path)$isdir)) {
            next
          }

          lines <- tryCatch(
            readLines(full_path, warn = FALSE),
            error = function(e) NULL
          )
          if (is.null(lines) || length(lines) == 0) {
            next
          }

          matched <- grep(
            pattern,
            lines,
            ignore.case = ignore_case,
            perl = TRUE
          )
          if (length(matched) == 0) {
            next
          }

          entries <- vapply(
            matched,
            function(i) {
              sprintf("%s:%d: %s", rel_path, i, lines[[i]])
            },
            character(1)
          )
          hits <- c(hits, entries)
          if (length(hits) >= max_matches) {
            hits <- hits[seq_len(max_matches)]
            break
          }
        }

        if (length(hits) == 0) {
          return(paste("No matches found for pattern", shQuote(pattern)))
        }

        paste(
          c(
            paste("Pattern:", pattern),
            paste("Matches:", length(hits)),
            "",
            hits
          ),
          collapse = "\n"
        )
      },
      error = function(e) {
        ellmer::tool_reject(paste("Error searching files:", e$message))
      }
    )
  },
  name = "grep_files",
  description = "Search file contents with a regex pattern and return matching lines.",
  arguments = list(
    pattern = ellmer::type_string("Regex pattern to search for"),
    path = ellmer::type_string(
      "Base directory to search. Default is current directory.",
      required = FALSE
    ),
    recursive = ellmer::type_boolean(
      "If TRUE, search recursively. Default is TRUE.",
      required = FALSE
    ),
    ignore_case = ellmer::type_boolean(
      "If TRUE, ignore case while matching. Default is FALSE.",
      required = FALSE
    ),
    max_matches = ellmer::type_integer(
      "Maximum matching lines to return. Default is 100.",
      required = FALSE
    )
  ),
  annotations = ellmer::tool_annotations(
    read_only_hint = TRUE,
    destructive_hint = FALSE
  )
)

run_r_code_impl <- function(code, timeout = 30) {
  if (!rlang::is_installed("callr")) {
    ellmer::tool_reject(
      paste(
        "Cannot execute R code: package 'callr' is required for",
        "subprocess execution. Install with install.packages('callr')"
      )
    )
  }

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
      timeout = timeout
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
#' A tool that executes R code and returns the result. It runs in a separate
#' process for fault isolation and timeout enforcement (requires callr).
#'
#' @details
#' This tool intentionally uses R's code evaluation capabilities to execute
#' arbitrary R code provided by the LLM. This is a core feature for agentic
#' workflows where the agent needs to perform data analysis or other R tasks.
#'
#' The execution boundary is explicit:
#' - Code runs in a separate callr subprocess, not an OS security sandbox
#' - A timeout prevents runaway execution
#' - The Permissions system can disable this tool entirely
#'
#' @format A tool definition created with `ellmer::tool()`.
#' @return When called directly, a character string containing captured output
#'   and the returned value.
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

#' Execute bash commands
#'
#' @description
#' A tool that executes bash/shell commands and returns the output.
#' **Use with caution!** This can execute arbitrary system commands.
#'
#' @format A tool definition created with `ellmer::tool()`.
#' @return When called directly, a character string containing command output
#'   or a success message.
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
            ellmer::tool_reject(paste(
              "Command timed out after",
              timeout,
              "seconds"
            ))
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
#' @return When called directly, a character summary of the CSV structure and
#'   preview rows.
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
