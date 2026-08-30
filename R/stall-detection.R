# Deterministic detection of repeated tool requests.

canonicalize_tool_input <- function(value) {
  if (!is.list(value) || is.data.frame(value)) {
    return(value)
  }

  result <- lapply(value, canonicalize_tool_input)
  value_names <- names(result)
  if (
    !is.null(value_names) &&
      length(value_names) > 0L &&
      all(nzchar(value_names))
  ) {
    result <- result[order(value_names)]
  }
  result
}

tool_request_signature <- function(tool_name, tool_input) {
  digest::digest(
    list(
      tool_name = tool_name,
      tool_input = canonicalize_tool_input(tool_input)
    ),
    algo = "sha256",
    serialize = TRUE
  )
}

advance_tool_loop <- function(
  signature,
  last_signature,
  consecutive_calls,
  threshold = 3L
) {
  count <- if (identical(signature, last_signature)) {
    consecutive_calls + 1L
  } else {
    1L
  }

  list(
    signature = signature,
    consecutive_calls = count,
    stalled = count >= threshold
  )
}
