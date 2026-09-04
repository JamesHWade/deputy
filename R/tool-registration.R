# Tool registration -------------------------------------------------------

tool_annotation_defaults <- list(
  read_only_hint = FALSE,
  destructive_hint = TRUE,
  idempotent_hint = FALSE,
  open_world_hint = TRUE
)

effective_tool_annotations <- function(annotations) {
  effective <- tool_annotation_defaults
  supplied <- annotations[!vapply(annotations, is.null, logical(1))]
  effective[names(supplied)] <- supplied
  # MCP defines destructive/idempotent annotations only for modifying tools.
  # Retain an explicit destructive claim so contradictory metadata cannot
  # weaken a permission check.
  if (
    isTRUE(effective$read_only_hint) && is.null(annotations$destructive_hint)
  ) {
    effective$destructive_hint <- FALSE
  }
  effective
}

tool_registration_error <- function(message, ..., .envir = parent.frame()) {
  abort_deputy(
    message,
    class = c("tool_registration", "tool"),
    ...,
    .envir = .envir
  )
}

validate_tool_annotations <- function(annotations, tool_name) {
  if (is.null(annotations) || identical(annotations, list())) {
    return(invisible(NULL))
  }
  if (
    !is.list(annotations) ||
      is.null(names(annotations)) ||
      anyNA(names(annotations)) ||
      anyDuplicated(names(annotations)) ||
      !all(nzchar(names(annotations)))
  ) {
    tool_registration_error(
      "Annotations for tool {.val {tool_name}} must be a uniquely named list."
    )
  }
  for (field in c(
    "read_only_hint",
    "destructive_hint",
    "idempotent_hint",
    "open_world_hint"
  )) {
    value <- annotations[[field]]
    if (!is.null(value) && !rlang::is_bool(value)) {
      tool_registration_error(
        "Annotation {.val {field}} for tool {.val {tool_name}} must be TRUE or FALSE."
      )
    }
  }
  title <- annotations$title
  if (!is.null(title) && !is_nonempty_string(title)) {
    tool_registration_error(
      "Annotation {.val title} for tool {.val {tool_name}} must be one non-empty string."
    )
  }
  invisible(NULL)
}

validate_tool_batch <- function(
  tools,
  existing = list(),
  replace = FALSE,
  preserve_reader = FALSE
) {
  if (!rlang::is_bool(replace)) {
    tool_registration_error("{.arg replace} must be TRUE or FALSE.")
  }
  if (!is.list(tools)) {
    tool_registration_error(
      "{.arg tools} must be a list of ellmer tool definitions."
    )
  }
  result <- list()
  for (index in seq_along(tools)) {
    tool <- tools[[index]]
    if (!inherits(tool, c("ellmer::ToolDef", "ellmer::ToolBuiltIn"))) {
      tool_registration_error(
        "Tool at position {index} must be an ellmer tool definition."
      )
    }
    # Re-register the executable source, not an old Agent's runtime wrapper.
    tool <- attr(tool, "deputy_runtime_source_tool", exact = TRUE) %||% tool
    name <- tool@name
    if (!is_nonempty_string(name)) {
      tool_registration_error(
        "Tool at position {index} must have a non-empty name."
      )
    }
    if (identical(name, "deputy_read_tool_result")) {
      if (
        isTRUE(preserve_reader) &&
          identical(
            attr(tool, "deputy_internal_tool", exact = TRUE),
            deputy_tool_result_reader_marker
          )
      ) {
        next
      }
      tool_registration_error("Tool name {.val {name}} is reserved by Deputy.")
    }
    if (name %in% names(result)) {
      tool_registration_error(
        "Duplicate tool name {.val {name}} in the registration batch.",
        tool_name = name
      )
    }
    if (!replace && name %in% names(existing)) {
      tool_registration_error(
        c(
          "Tool {.val {name}} is already registered.",
          "i" = "Use {.code replace = TRUE} to replace an existing tool."
        ),
        tool_name = name
      )
    }
    validate_tool_annotations(tool@annotations, name)
    result[[name]] <- tool
  }
  result
}
