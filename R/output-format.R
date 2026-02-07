# Structured output helpers

# Normalize output format spec
normalize_output_format <- function(output_format) {
  if (is.null(output_format) || !is.list(output_format)) {
    cli::cli_abort("{.arg output_format} must be a list")
  }

  if (is.null(output_format$type) && !is.null(output_format$schema)) {
    output_format$type <- "json_schema"
  }

  output_format
}

# Inject output format instructions into a task prompt
apply_output_format_instructions <- function(task, output_format) {
  if (is.null(output_format)) {
    return(task)
  }

  output_format <- normalize_output_format(output_format)

  if (identical(output_format$type, "json_schema")) {
    schema <- output_format$schema
    schema_json <- format_schema_json(schema)
    instruction <- paste(
      "Return a JSON object that matches this schema.",
      "Output only JSON.",
      "Schema:",
      schema_json,
      sep = "\n"
    )
    return(paste(instruction, "", "Task:", task, sep = "\n"))
  }

  if (identical(output_format$type, "json_object")) {
    instruction <- "Return a JSON object. Output only JSON."
    return(paste(instruction, "", "Task:", task, sep = "\n"))
  }

  task
}

# Parse and validate structured output
parse_structured_output <- function(text, output_format) {
  if (is.null(output_format)) {
    return(NULL)
  }

  output_format <- normalize_output_format(output_format)
  parsed <- extract_json_from_text(text)

  if (is.null(parsed$parsed)) {
    return(list(
      format = output_format,
      raw = text,
      parsed = NULL,
      valid = FALSE,
      errors = parsed$error %||% "Failed to parse JSON output",
      schema_validation_skipped = FALSE
    ))
  }

  validation <- validate_output_schema(parsed$parsed, output_format)

  list(
    format = output_format,
    raw = text,
    parsed = parsed$parsed,
    valid = validation$valid,
    errors = validation$errors,
    schema_validation_skipped = validation$skipped %||% FALSE
  )
}

format_schema_json <- function(schema) {
  if (rlang::is_installed("jsonlite")) {
    return(jsonlite::toJSON(schema, auto_unbox = TRUE, pretty = TRUE))
  }
  # Fallback string for display when jsonlite is missing
  paste(utils::capture.output(utils::str(schema)), collapse = "\n")
}

# Extract JSON from a response string
extract_json_from_text <- function(text) {
  if (is.null(text) || !is.character(text) || length(text) != 1) {
    return(list(parsed = NULL, error = "Invalid response text"))
  }

  if (!rlang::is_installed("jsonlite")) {
    return(list(parsed = NULL, error = "jsonlite package is required"))
  }

  parsed <- tryCatch(
    jsonlite::fromJSON(text, simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (!is.null(parsed)) {
    return(list(parsed = parsed))
  }

  # Try to extract a JSON object/array substring
  start_obj <- regexpr("\\{", text)
  end_obj <- regexpr("\\}[^\\}]*$", text)
  start_arr <- regexpr("\\[", text)
  end_arr <- regexpr("\\][^\\]]*$", text)

  candidates <- character()
  if (start_obj > 0 && end_obj > 0 && end_obj > start_obj) {
    candidates <- c(candidates, substr(text, start_obj, end_obj))
  }
  if (start_arr > 0 && end_arr > 0 && end_arr > start_arr) {
    candidates <- c(candidates, substr(text, start_arr, end_arr))
  }

  for (candidate in candidates) {
    parsed <- tryCatch(
      jsonlite::fromJSON(candidate, simplifyVector = FALSE),
      error = function(e) NULL
    )
    if (!is.null(parsed)) {
      return(list(parsed = parsed))
    }
  }

  list(parsed = NULL, error = "No valid JSON found in response")
}

# Validate against a JSON schema when available
validate_output_schema <- function(parsed, output_format) {
  if (!identical(output_format$type, "json_schema")) {
    return(list(valid = TRUE, errors = NULL, skipped = FALSE))
  }

  if (!rlang::is_installed("jsonvalidate")) {
    return(list(
      valid = NA,
      errors = "jsonvalidate not installed; schema validation skipped",
      skipped = TRUE
    ))
  }

  schema_json <- format_schema_json(output_format$schema)
  payload_json <- jsonlite::toJSON(parsed, auto_unbox = TRUE, null = "null")

  result <- tryCatch(
    jsonvalidate::json_validate(
      payload_json,
      schema_json,
      engine = "jsonschema",
      error = TRUE
    ),
    error = function(e) e$message
  )

  if (isTRUE(result)) {
    return(list(valid = TRUE, errors = NULL, skipped = FALSE))
  }

  if (is.character(result)) {
    # Treat validator/engine availability as unknown
    if (
      grepl(
        "engine|validator|jsonschema|ajv|python|module|package",
        result,
        ignore.case = TRUE
      )
    ) {
      return(list(valid = NA, errors = result, skipped = TRUE))
    }
    return(list(valid = FALSE, errors = result, skipped = FALSE))
  }

  list(valid = FALSE, errors = "Schema validation failed", skipped = FALSE)
}
