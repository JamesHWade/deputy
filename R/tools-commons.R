# Optional adapter for Commons 0.2.0 public calculation methods.

commons_min_version <- "0.2.0"
commons_max_table_rows <- 50L
commons_max_text_chars <- 65536L

commons_package_version <- function() {
  if (!requireNamespace("commons", quietly = TRUE)) {
    return(NULL)
  }
  utils::packageVersion("commons")
}

check_commons_version <- function(call = rlang::caller_env()) {
  version <- commons_package_version()
  if (is.null(version)) {
    cli_abort(
      c(
        "{.fn tools_commons} requires the {.pkg commons} package (>= {commons_min_version}).",
        "i" = "Install it with {.code install.packages(\"commons\")}."
      ),
      call = call
    )
  }
  if (version < numeric_version(commons_min_version)) {
    cli_abort(
      c(
        "{.fn tools_commons} requires {.pkg commons} >= {commons_min_version}, not {as.character(version)}.",
        "i" = "Commons {commons_min_version} separates {.fn commons::commons} from {.fn commons::agent} and exposes public calculation methods.",
        "i" = "Upgrade with {.code install.packages(\"commons\")}."
      ),
      call = call
    )
  }
  invisible(version)
}

check_commons_object <- function(commons, call = rlang::caller_env()) {
  if (inherits(commons, "Chat")) {
    cli_abort(
      c(
        "{.arg commons} must be a model-free {.cls commons} object, not a {.cls Chat}.",
        "i" = "Build it with {.code commons::commons(data_sources = ..., semantic_layer = ...)} without a chat client."
      ),
      call = call
    )
  }
  has_search <- is.function(tryCatch(commons$search, error = function(e) NULL))
  has_measure <- is.function(tryCatch(
    commons$measure,
    error = function(e) NULL
  ))
  if (!inherits(commons, "commons") || !has_search || !has_measure) {
    cli_abort(
      c(
        "{.arg commons} must be a {.cls commons} object created by {.fn commons::commons}.",
        "i" = "Pass the model-free object returned by {.code commons::commons(data_sources = ..., semantic_layer = ...)}."
      ),
      call = call
    )
  }
  invisible(commons)
}

commons_parse_measure_args <- function(arguments) {
  if (
    is.null(arguments) || identical(arguments, "") || identical(arguments, "{}")
  ) {
    return(list())
  }
  if (is.list(arguments) && !is.object(arguments)) {
    if (length(arguments) == 0L) {
      return(list())
    }
    arg_names <- names(arguments)
    if (
      is.null(arg_names) ||
        anyNA(arg_names) ||
        !all(nzchar(arg_names)) ||
        anyDuplicated(arg_names)
    ) {
      ellmer::tool_reject(
        "`arguments` must be a JSON object with unique argument names."
      )
    }
    return(arguments)
  }
  if (!is_nonempty_string(arguments)) {
    ellmer::tool_reject(
      "`arguments` must be a JSON object string, such as \"{}\" or '{\"region\": \"East\"}'."
    )
  }
  trimmed <- trimws(arguments)
  if (!startsWith(trimmed, "{") || !endsWith(trimmed, "}")) {
    ellmer::tool_reject(
      "`arguments` must be a JSON object string, such as \"{}\" or '{\"region\": \"East\"}'."
    )
  }
  parsed <- tryCatch(
    jsonlite::fromJSON(trimmed, simplifyVector = TRUE),
    error = function(e) {
      ellmer::tool_reject(
        paste0("Could not parse `arguments` as JSON: ", conditionMessage(e))
      )
    }
  )
  if (!is.list(parsed) || is.object(parsed)) {
    ellmer::tool_reject("`arguments` must be a JSON object string.")
  }
  if (length(parsed) == 0L) {
    return(list())
  }
  arg_names <- names(parsed)
  if (
    is.null(arg_names) ||
      anyNA(arg_names) ||
      !all(nzchar(arg_names)) ||
      anyDuplicated(arg_names)
  ) {
    ellmer::tool_reject(
      "`arguments` must be a JSON object with unique argument names."
    )
  }
  parsed
}

commons_format_atomic <- function(value) {
  if ((is.double(value) || is.complex(value)) && !is.object(value)) {
    formatted <- as.character(value)
  } else {
    formatted <- trimws(format(value, trim = TRUE))
  }
  formatted[is.na(formatted)] <- "NA"
  formatted
}

commons_format_arg_value <- function(value) {
  if (is.null(value)) {
    return("null")
  }
  if (is.atomic(value) && length(value) <= 20L) {
    return(paste(commons_format_atomic(value), collapse = ", "))
  }
  as.character(jsonlite::toJSON(value, auto_unbox = TRUE, digits = NA))
}

commons_measure_header_html <- function(name, args) {
  name_html <- paste0(
    "<div class=\"deputy-commons-measure-name\"><strong>Measure:</strong> <code>",
    htmltools::htmlEscape(name),
    "</code></div>"
  )
  if (!length(args)) {
    return(name_html)
  }
  items <- vapply(
    names(args),
    function(arg_name) {
      paste0(
        "<li><code>",
        htmltools::htmlEscape(arg_name),
        "</code>: ",
        htmltools::htmlEscape(commons_format_arg_value(args[[arg_name]])),
        "</li>"
      )
    },
    character(1)
  )
  paste0(
    name_html,
    "<ul class=\"deputy-commons-measure-args\">",
    paste(items, collapse = ""),
    "</ul>"
  )
}

commons_bound_text <- function(text, max_chars = commons_max_text_chars) {
  text <- enc2utf8(paste(as.character(text), collapse = "\n"))
  if (nchar(text, type = "chars") <= max_chars) {
    return(text)
  }
  paste0(
    substr(text, 1L, max_chars),
    "\n... [truncated]"
  )
}

commons_format_df_cells <- function(df) {
  cols <- lapply(df, function(col) {
    formatted <- commons_format_atomic(col)
    gsub("[\r\n]+", " ", formatted)
  })
  as.data.frame(cols, stringsAsFactors = FALSE, check.names = FALSE)
}

commons_format_df_markdown <- function(df, max_rows = commons_max_table_rows) {
  total_rows <- nrow(df)
  if (ncol(df) == 0L) {
    return(sprintf("Empty table (%d rows, 0 columns).", total_rows))
  }
  shown <- utils::head(df, max_rows)
  col_names <- names(shown) %||% paste0("V", seq_len(ncol(shown)))
  escape_pipe <- function(x) gsub("|", "\\|", x, fixed = TRUE)
  header <- paste0("| ", paste(escape_pipe(col_names), collapse = " | "), " |")
  separator <- paste0(
    "| ",
    paste(rep("---", length(col_names)), collapse = " | "),
    " |"
  )
  rows <- if (nrow(shown) > 0L) {
    cells <- commons_format_df_cells(shown)
    vapply(
      seq_len(nrow(cells)),
      function(i) {
        vals <- vapply(
          cells[i, , drop = FALSE],
          function(v) escape_pipe(as.character(v)[[1L]]),
          character(1)
        )
        paste0("| ", paste(vals, collapse = " | "), " |")
      },
      character(1)
    )
  } else {
    character()
  }
  lines <- c(header, separator, rows)
  if (total_rows > max_rows) {
    lines <- c(
      lines,
      "",
      sprintf("%d more rows not shown.", total_rows - max_rows)
    )
  }
  commons_bound_text(paste(lines, collapse = "\n"))
}

commons_format_df_html <- function(df, max_rows = commons_max_table_rows) {
  total_rows <- nrow(df)
  if (ncol(df) == 0L) {
    return(sprintf("<p>Empty table (%d rows, 0 columns).</p>", total_rows))
  }
  shown <- utils::head(df, max_rows)
  col_names <- names(shown) %||% paste0("V", seq_len(ncol(shown)))
  thead <- paste0(
    "<thead><tr>",
    paste0("<th>", htmltools::htmlEscape(col_names), "</th>", collapse = ""),
    "</tr></thead>"
  )
  tbody <- if (nrow(shown) > 0L) {
    cells <- commons_format_df_cells(shown)
    row_html <- vapply(
      seq_len(nrow(cells)),
      function(i) {
        vals <- vapply(
          cells[i, , drop = FALSE],
          function(v) htmltools::htmlEscape(as.character(v)[[1L]]),
          character(1)
        )
        paste0("<tr>", paste0("<td>", vals, "</td>", collapse = ""), "</tr>")
      },
      character(1)
    )
    paste0("<tbody>", paste(row_html, collapse = ""), "</tbody>")
  } else {
    "<tbody></tbody>"
  }
  note <- if (total_rows > max_rows) {
    sprintf("<p>%d more rows not shown.</p>", total_rows - max_rows)
  } else {
    ""
  }
  paste0("<table class=\"table table-sm\">", thead, tbody, "</table>", note)
}

commons_format_value_text <- function(value) {
  if (is.null(value)) {
    return("NULL")
  }
  if (is.atomic(value) && length(value) <= 20L) {
    return(commons_bound_text(paste(
      commons_format_atomic(value),
      collapse = ", "
    )))
  }
  old <- options(digits = 15L)
  on.exit(options(old), add = TRUE)
  commons_bound_text(paste(
    utils::capture.output(print(value)),
    collapse = "\n"
  ))
}

commons_value_html <- function(text) {
  escaped <- htmltools::htmlEscape(text)
  if (grepl("\n", text, fixed = TRUE)) {
    paste0("<pre>", escaped, "</pre>")
  } else {
    paste0("<p>", escaped, "</p>")
  }
}

commons_wrap_measure_html <- function(header_html, body_html) {
  htmltools::HTML(paste0(
    "<div class=\"deputy-commons-measure\">",
    header_html,
    "<div class=\"deputy-commons-measure-result\">",
    body_html,
    "</div></div>"
  ))
}

commons_measure_result <- function(name, args, value) {
  header_html <- commons_measure_header_html(name, args)
  if (inherits(value, "ellmer::ContentToolResult")) {
    if (!is.null(value@error)) {
      return(value)
    }
    raw_extra <- value@extra
    raw_display <- if (is.list(raw_extra)) raw_extra[["display"]] else NULL
    display <- if (is.list(raw_display)) unclass(raw_display) else list()
    display$title <- display$title %||% "Ran a trusted calculation"
    if (is.null(display$show_request)) {
      display$show_request <- FALSE
    }
    if (!is.null(display$html)) {
      existing_html <- if (
        is.character(display$html) && length(display$html) == 1L
      ) {
        as.character(display$html)
      } else if (inherits(display$html, c("shiny.tag", "shiny.tag.list"))) {
        as.character(htmltools::renderTags(display$html)$html)
      } else {
        NULL
      }
      if (!is.null(existing_html)) {
        display$html <- commons_wrap_measure_html(header_html, existing_html)
      }
    } else if (is.null(display$markdown) && is.null(display$text)) {
      text <- commons_format_value_text(value@value)
      display$html <- commons_wrap_measure_html(
        header_html,
        commons_value_html(text)
      )
    }
    return(ellmer::ContentToolResult(
      value = value@value,
      extra = list(display = display)
    ))
  }
  if (inherits(value, "tbl_sql")) {
    value <- tryCatch(as.data.frame(value), error = function(e) value)
  }
  if (is.data.frame(value)) {
    return(ellmer::ContentToolResult(
      value = commons_format_df_markdown(value),
      extra = list(
        display = list(
          title = "Ran a trusted calculation",
          html = commons_wrap_measure_html(
            header_html,
            commons_format_df_html(value)
          ),
          show_request = FALSE
        )
      )
    ))
  }
  text <- commons_format_value_text(value)
  ellmer::ContentToolResult(
    value = text,
    extra = list(
      display = list(
        title = "Ran a trusted calculation",
        html = commons_wrap_measure_html(
          header_html,
          commons_value_html(text)
        ),
        show_request = FALSE
      )
    )
  )
}

commons_search_result <- function(commons, query) {
  if (!is_nonempty_string(query)) {
    ellmer::tool_reject("`query` must be a non-empty string.")
  }
  raw <- commons$search(query)
  text <- paste(as.character(raw), collapse = "\n")
  trimmed <- trimws(text)
  no_match <- !nzchar(trimmed) ||
    grepl(
      "^(Nothing in the semantic layer matches|The semantic layer is empty)",
      trimmed
    )
  body <- if (no_match) {
    if (nzchar(trimmed)) {
      paste0(
        text,
        "\n\nNo approved calculation covers this question. ",
        "Report that to the user instead of estimating or computing an unapproved answer."
      )
    } else {
      paste0(
        "No approved calculation covers \"",
        query,
        "\". Report that to the user instead of estimating or computing an unapproved answer."
      )
    }
  } else if (!grepl("\\$measure\\(", text)) {
    paste0(
      text,
      "\n\nNote: Only named measures (`$measure(...)`) can be run through `commons_measure`. ",
      "If no approved measure covers the question, report that to the user instead of computing an unapproved answer."
    )
  } else {
    text
  }
  body <- commons_bound_text(body)
  ellmer::ContentToolResult(
    value = body,
    extra = list(
      display = list(
        title = "Searched for a trusted calculation",
        markdown = body,
        show_request = FALSE
      )
    )
  )
}

#' Get tools for a Commons 0.2.0 object
#'
#' @description
#' Wraps the public `$search()` and `$measure()` methods of a model-free
#' `commons::commons()` object (from **commons** 0.2.0 or later) as Deputy
#' tools: `commons_search` and `commons_measure`. Call `tools_commons()` once
#' and share the returned tools across a lead agent and its specialists so that
#' a single `commons_measure` tool object acts as the producer for
#' [TrustedResults()].
#'
#' Neither SQL nor arbitrary R execution is exposed. When no approved measure
#' matches a search, `commons_search` reports that no approved calculation
#' covers the question.
#'
#' @details
#' You remain responsible for creating and authorizing the `commons` object for
#' the current viewer. Both returned tools are annotated as read-only and
#' closed-world (`read_only_hint = TRUE`, `destructive_hint = FALSE`,
#' `open_world_hint = FALSE`, `idempotent_hint = TRUE`) so they work in
#' read-only policies and alongside [TrustedResults()] without mutating tool
#' metadata. Deputy does not inspect what a measure function does internally, so
#' pass only a `commons` object whose measures are read-only and authorized for
#' the viewer.
#'
#' Public Commons methods return R values rather than the native tool-result
#' evidence that `commons::agent()` attaches to its own tool calls (such as
#' `commons_tag`, compiled SQL, or bound query parameters). `commons_measure`
#' wraps returned values in Deputy's bounded display cards and trusted-result
#' receipts without fabricating query metadata or claiming native Commons card
#' parity. Measures that return an `ellmer::ContentToolResult` keep their own
#' value and display fields.
#'
#' @param commons A `commons` object created by `commons::commons()` (version
#'   0.2.0 or later), without a chat client.
#'
#' @return A named list of two ellmer tools: `commons_search` and
#'   `commons_measure`.
#'
#' @examples
#' \dontrun{
#' cm <- commons::commons(
#'   data_sources = commons::data_source(sales = sales_df),
#'   semantic_layer = commons::semantic_layer(
#'     commons::measure("total_revenue", "Total revenue.", function() sum(sales_df$revenue))
#'   )
#' )
#' tools <- tools_commons(cm)
#' agent <- Agent$new(
#'   chat = ellmer::chat("anthropic/claude-sonnet-5-5"),
#'   tools = tools,
#'   permissions = Permissions(mode = "readonly", tool_allowlist = names(tools)),
#'   trusted_results = TrustedResults(measure = tools$commons_measure)
#' )
#' }
#'
#' @seealso [TrustedResults()], [tools_data()], [tool_metadata()]
#' @export
tools_commons <- function(commons) {
  check_commons_version()
  check_commons_object(commons)

  search_tool <- ellmer::tool(
    fun = function(query) {
      commons_search_result(commons, query)
    },
    name = "commons_search",
    description = paste(
      "Search the Commons semantic layer for approved trusted calculations.",
      "Call this before running a measure and use the exact measure name it",
      "returns with `commons_measure`. Only named measures are available;",
      "if no approved measure covers the question, report that no approved",
      "calculation covers it instead of estimating an answer."
    ),
    arguments = list(
      query = ellmer::type_string(
        "What you want to compute, in plain language."
      )
    ),
    convert = FALSE,
    annotations = ellmer::tool_annotations(
      title = "Searching for a trusted calculation",
      read_only_hint = TRUE,
      destructive_hint = FALSE,
      open_world_hint = FALSE,
      idempotent_hint = TRUE
    )
  )

  measure_tool <- ellmer::tool(
    fun = function(name, arguments = "{}") {
      if (!is_nonempty_string(name)) {
        ellmer::tool_reject("`name` must be a non-empty measure name.")
      }
      args <- commons_parse_measure_args(arguments)
      value <- commons$measure(name, args)
      commons_measure_result(name, args, value)
    },
    name = "commons_measure",
    description = paste(
      "Run a named trusted measure returned by `commons_search`.",
      "`name` must be the exact measure name from search, and `arguments` is",
      "a JSON object of its argument values (or \"{}\" when it takes none).",
      "Do not invent measure names; if no approved measure covers the",
      "question, report that no approved calculation covers it."
    ),
    arguments = list(
      name = ellmer::type_string(
        "The exact measure name, as returned by commons_search."
      ),
      arguments = ellmer::type_string(
        "A JSON object of the measure's arguments, or \"{}\" when it takes none.",
        required = FALSE
      )
    ),
    convert = FALSE,
    annotations = ellmer::tool_annotations(
      title = "Running a trusted calculation",
      read_only_hint = TRUE,
      destructive_hint = FALSE,
      open_world_hint = FALSE,
      idempotent_hint = TRUE
    )
  )

  list(
    commons_search = search_tool,
    commons_measure = measure_tool
  )
}
