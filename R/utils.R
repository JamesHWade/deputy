# Internal utility functions for deputy

# Read an optional value without collapsing absence and read failures.
#
# @param reader Zero-argument function that reads the value.
# @param validator Optional predicate for validating a present value.
# @return A list with `status`, `value`, and `error`. Status is one of
#   `"present"`, `"absent"`, `"invalid"`, or `"unreadable"`.
# @noRd
read_optional_value <- function(reader, validator = NULL) {
  attempt <- tryCatch(
    list(value = reader(), error = NULL),
    error = function(error) list(value = NULL, error = error)
  )

  if (!is.null(attempt$error)) {
    return(list(
      status = "unreadable",
      value = NULL,
      error = attempt$error
    ))
  }

  if (is.null(attempt$value)) {
    return(list(status = "absent", value = NULL, error = NULL))
  }

  if (!is.null(validator) && !isTRUE(validator(attempt$value))) {
    return(list(
      status = "invalid",
      value = attempt$value,
      error = NULL
    ))
  }

  list(status = "present", value = attempt$value, error = NULL)
}

# @noRd
is_nonempty_string <- function(value) {
  is.character(value) &&
    length(value) == 1L &&
    !is.na(value) &&
    nzchar(trimws(value))
}

# Return TRUE when `x` carries unique, non-empty, non-NA names for every element.
has_unique_names <- function(x) {
  nms <- names(x)
  !is.null(nms) &&
    length(nms) == length(x) &&
    !anyNA(nms) &&
    all(nzchar(nms)) &&
    !anyDuplicated(nms)
}

# Unwrap a Deputy runtime-wrapped tool back to its underlying source ToolDef.
runtime_source_tool <- function(tool) {
  attr(tool, "deputy_runtime_source_tool", exact = TRUE) %||% tool
}

# Read an R6 Agent's private environment safely.
agent_private <- function(agent) {
  tryCatch(agent$.__enclos_env__$private, error = function(error) NULL)
}

# Find the largest count in 0..n for which check(k) returns a non-NULL,
# non-FALSE value, assuming monotonicity (if k fits, every j < k fits).
bisect_max_fitting <- function(n, check, empty = NULL) {
  if (n <= 0L) {
    return(list(count = 0L, value = empty))
  }
  best <- check(n)
  if (!is.null(best) && !isFALSE(best)) {
    return(list(count = n, value = best))
  }
  low <- 0L
  high <- n
  best <- empty
  while (high - low > 1L) {
    middle <- (low + high) %/% 2L
    candidate <- check(middle)
    if (!is.null(candidate) && !isFALSE(candidate)) {
      low <- middle
      best <- candidate
    } else {
      high <- middle
    }
  }
  list(count = low, value = best)
}

# Run a tool body and convert unexpected errors into ellmer tool rejections.
tool_reject_on_error <- function(expr, prefix) {
  tryCatch(
    expr,
    error = function(e) {
      if (inherits(e, "ellmer_tool_reject")) {
        rlang::cnd_signal(e)
      }
      ellmer::tool_reject(paste(prefix, conditionMessage(e)))
    }
  )
}

# Validate a positive whole-number integer option (optionally NULL).
validate_positive_int <- function(
  value,
  argument,
  allow_null = TRUE,
  call = rlang::caller_env()
) {
  if (is.null(value) && isTRUE(allow_null)) {
    return(NULL)
  }
  if (
    !is.numeric(value) ||
      length(value) != 1L ||
      is.na(value) ||
      !is.finite(value) ||
      value < 1 ||
      value > .Machine$integer.max ||
      value != floor(value)
  ) {
    if (isTRUE(allow_null)) {
      cli_abort(
        "{.arg {argument}} must be NULL or one positive whole number",
        call = call
      )
    }
    cli_abort(
      "{.arg {argument}} must be one positive whole number",
      call = call
    )
  }
  as.integer(value)
}

# Validate a non-negative whole-number integer option.
validate_nonnegative_int <- function(
  value,
  argument,
  call = rlang::caller_env()
) {
  if (
    !is.numeric(value) ||
      length(value) != 1L ||
      is.na(value) ||
      !is.finite(value) ||
      value < 0 ||
      value > .Machine$integer.max ||
      value != floor(value)
  ) {
    cli_abort(
      "{.arg {argument}} must be one non-negative whole number",
      call = call
    )
  }
  as.integer(value)
}

# Validate a positive, finite numeric timeout value.
validate_positive_timeout <- function(value, argument, class = NULL) {
  if (
    !is.numeric(value) ||
      length(value) != 1L ||
      is.na(value) ||
      !is.finite(value) ||
      value <= 0
  ) {
    abort_deputy(
      "{.arg {argument}} must be positive and finite.",
      class = class
    )
  }
  as.double(value)
}

# Reject process-local runtime state before persisting or crossing a boundary.
assert_portable_data <- function(
  value,
  depth = 0L,
  path = "record",
  allow_classed = FALSE,
  label = "Data",
  abort_fn = abort_deputy
) {
  if (depth > 100L) {
    abort_fn("{label} exceeds the nesting limit.")
  }
  if (is.null(value)) {
    return(invisible(value))
  }
  if (
    inherits(value, c("condition", "connection")) ||
      is.function(value) ||
      is.environment(value) ||
      typeof(value) %in% c("externalptr", "weakref") ||
      S7::S7_inherits(value) ||
      isS4(value)
  ) {
    abort_fn("{label} must not contain runtime objects or conditions.")
  }
  if (is.list(value) && (!is.object(value) || allow_classed)) {
    elements <- if (is.object(value)) unclass(value) else value
    for (i in seq_along(elements)) {
      element_label <- names(elements)[i] %||% as.character(i)
      assert_portable_data(
        elements[[i]],
        depth + 1L,
        paste0(path, "$", element_label),
        allow_classed = allow_classed,
        label = label,
        abort_fn = abort_fn
      )
    }
  } else if (
    !is.atomic(value) ||
      (is.object(value) &&
        !allow_classed &&
        !inherits(value, c("json", "POSIXct")))
  ) {
    abort_fn(
      "{label} at {.val {path}} must contain only portable values; found {.val {class(value)}}."
    )
  }
  # Classed session data retain their RDS representation, including attributes.
  # Inspect attributes too so an otherwise plain value cannot hide a callback
  # or runtime environment in metadata.
  for (attribute in attributes(value)) {
    assert_portable_data(
      attribute,
      depth + 1L,
      paste0(path, " attributes"),
      allow_classed = allow_classed,
      label = label,
      abort_fn = abort_fn
    )
  }
  invisible(value)
}

#' Format cost as dollars
#'
#' @param cost Numeric cost value
#' @return A string such as `"$0.0123"`, or `"unknown"` for `NULL` or `NA`
#' @noRd
format_cost <- function(cost) {
  if (is.null(cost) || is.na(cost)) {
    return("unknown")
  }
  sprintf("$%.4f", cost)
}

#' Truncate a string to a maximum length
#'
#' @param x String to truncate
#' @param max_length Maximum length
#' @param suffix Suffix to add if truncated
#' @return Truncated string
#' @noRd
truncate_string <- function(x, max_length = 100, suffix = "...") {
  if (is.null(x) || nchar(x) <= max_length) {
    return(x)
  }
  paste0(substr(x, 1, max_length - nchar(suffix)), suffix)
}

#' Check that an object is an ellmer Chat
#'
#' Errors with class `deputy_error` if it isn't.
#'
#' @param x Object to validate
#' @param arg_name Name of the argument (for error messages)
#' @noRd
validate_chat <- function(x, arg_name = "chat") {
  if (!inherits(x, "Chat")) {
    abort_deputy(c(
      "Invalid {.arg {arg_name}} argument",
      "x" = "Expected an ellmer Chat object",
      "i" = "Create one with {.fn ellmer::chat} or provider-specific functions like {.fn ellmer::chat_openai}"
    ))
  }
  invisible(x)
}
