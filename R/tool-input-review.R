#' Tabulate a tool call's arguments for review
#'
#' @description
#' Builds a data frame with one row per argument, pairing the value the model
#' proposed with the tool's declared type and description. Nested objects are
#' flattened to dotted names such as `plan.treatment`. Use it in a
#' `can_use_tool` callback, a `PreToolUse` hook or an approval screen to show a
#' person a table instead of `dput()` output.
#'
#' Permission callbacks and `PreToolUse` hooks get the tool's declared
#' arguments as `context$tool_arguments`. The table is for display only;
#' validate inputs in the tool itself.
#'
#' @param tool_input Named list of proposed arguments, as passed to permission
#'   callbacks and hooks, or the `request$tool_input` of a pending approval
#'   from [approval_read()].
#' @param tool_arguments The tool's declared arguments: an ellmer `TypeObject`
#'   such as `context$tool_arguments` or `tool@arguments`, or `NULL` if you
#'   don't have one.
#' @return A data frame with character columns `argument`, `type`,
#'   `description` and `value`, and logical columns `required` and `declared`.
#'   Input fields the tool doesn't declare are kept with `declared = FALSE`;
#'   declared fields missing from the input have value `NA`. The `"paths"`
#'   attribute holds each row's path as a character vector, which stays exact
#'   when a name itself contains a dot.
#' @examples
#' arguments <- ellmer::type_object(
#'   city = ellmer::type_string("City to forecast"),
#'   days = ellmer::type_integer("Number of days", required = FALSE)
#' )
#' tool_input_review(list(city = "Oslo", days = 3L), arguments)
#' @export
tool_input_review <- function(tool_input, tool_arguments = NULL) {
  if (
    !is.list(tool_input) ||
      (length(tool_input) > 0L && !rlang::is_named(tool_input))
  ) {
    cli_abort("{.arg tool_input} must be a named list.")
  }
  if (
    !is.null(tool_arguments) &&
      !inherits(tool_arguments, "ellmer::TypeObject")
  ) {
    cli_abort("{.arg tool_arguments} must be NULL or an ellmer TypeObject.")
  }
  rows <- review_rows(tool_input, tool_arguments, path = character())
  if (length(rows) == 0L) {
    return(data.frame(
      argument = character(),
      type = character(),
      required = logical(),
      declared = logical(),
      description = character(),
      value = character(),
      stringsAsFactors = FALSE
    ))
  }
  paths <- lapply(rows, `[[`, "path")
  rows <- lapply(rows, function(row) {
    row$path <- NULL
    as.data.frame(row, stringsAsFactors = FALSE)
  })
  table <- do.call(rbind, rows)
  # Display names join path components with dots, which argument names may
  # also contain. Keep the structural path for callers that edit values.
  attr(table, "paths") <- paths
  table
}

review_rows <- function(input, declaration, path) {
  properties <- if (is.null(declaration)) list() else declaration@properties
  fields <- union(names(properties), names(input) %||% character())
  rows <- list()
  for (field in fields) {
    field_path <- c(path, field)
    type <- properties[[field]]
    present <- field %in% names(input)
    value <- if (present) input[[field]] else NULL
    if (
      inherits(type, "ellmer::TypeObject") &&
        (!present || (is.list(value) && rlang::is_named(value)))
    ) {
      rows <- c(rows, review_rows(value %||% list(), type, field_path))
      next
    }
    rows[[length(rows) + 1L]] <- list(
      path = field_path,
      argument = paste(field_path, collapse = "."),
      type = review_type_label(type),
      required = if (is.null(type)) NA else isTRUE(type@required),
      declared = !is.null(type),
      description = if (is.null(type)) {
        NA_character_
      } else {
        type@description %||% NA_character_
      },
      value = if (present) review_value_label(value) else NA_character_
    )
  }
  rows
}

review_type_label <- function(type) {
  if (is.null(type)) {
    return(NA_character_)
  }
  if (inherits(type, "ellmer::TypeEnum")) {
    return(paste0("enum(", paste(type@values, collapse = ", "), ")"))
  }
  if (inherits(type, "ellmer::TypeArray")) {
    return(paste0("array<", review_type_label(type@items), ">"))
  }
  if (inherits(type, "ellmer::TypeObject")) {
    return("object")
  }
  if (inherits(type, "ellmer::TypeBasic")) {
    return(type@type)
  }
  "any"
}

review_value_label <- function(value) {
  if (is.null(value)) {
    return("null")
  }
  if (is.character(value) && length(value) == 1L && !is.na(value)) {
    return(value)
  }
  tryCatch(
    as.character(jsonlite::toJSON(
      value,
      auto_unbox = TRUE,
      null = "null",
      digits = NA
    )),
    error = function(e) paste(format(value), collapse = " ")
  )
}
