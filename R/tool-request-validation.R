# Internal validation for provider tool requests.

tool_request_class_label <- function(request) {
  classes <- class(request)
  if (length(classes) == 0L) {
    return("unknown")
  }
  paste(classes, collapse = "/")
}

tool_request_identity_error <- function(request, detail = NULL) {
  message <- paste0(
    "Cannot execute tool request because its name could not be read. ",
    "Request class: <",
    tool_request_class_label(request),
    ">."
  )
  if (!is.null(detail)) {
    message <- paste(message, detail)
  }
  message
}

read_tool_request_name <- function(request) {
  name <- read_optional_value(
    function() request@name,
    validator = is_nonempty_string
  )

  if (identical(name$status, "present")) {
    return(list(value = name$value, error = NULL))
  }

  detail <- switch(
    name$status,
    absent = "The name is absent.",
    invalid = paste0(
      "Expected one non-empty string; got <",
      paste(class(name$value), collapse = "/"),
      ">."
    ),
    unreadable = conditionMessage(name$error)
  )

  list(
    value = "unknown",
    error = tool_request_identity_error(request, detail)
  )
}
