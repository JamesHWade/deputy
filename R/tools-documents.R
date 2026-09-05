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

  if (anyNA(nums) || any(nums < 1)) {
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

  rlang::check_installed("pdftools", reason = "to read PDF content")
  pdftools::pdf_text(path)
}

# Convert a local file to markdown using Python MarkItDown via reticulate
convert_to_markdown_markitdown <- function(path) {
  rlang::check_installed("reticulate", reason = "for MarkItDown conversion")

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
          conditionMessage(e)
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
