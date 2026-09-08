# Image formatters may open a graphics device. Summaries and text artifacts
# need a deterministic descriptor, never image display or decoded pixel data.
public_content_text <- function(value) {
  if (inherits(value, "ellmer::ContentImage")) {
    props <- S7::props(value)
    if (!is.null(props$url)) {
      return(paste0("[Image URL: ", props$url, "]"))
    }
    return(paste0(
      "[Inline image: ",
      props$mime_type %||% "image",
      "; image bytes retained in the result artifact.]"
    ))
  }
  paste(format(value), collapse = "\n")
}

# Project public content without serializing class environments or display extras.
project_tool_content <- function(
  value,
  for_json = FALSE,
  formatter = public_content_text
) {
  if (inherits(value, "ellmer::Content")) {
    return(formatter(value))
  }
  if (for_json && is.atomic(value) && !is.null(names(value))) {
    value <- as.list(value)
  }
  if (is.list(value)) {
    value[] <- lapply(
      value,
      project_tool_content,
      for_json = for_json,
      formatter = formatter
    )
  }
  value
}

# Native evidence identities contain public properties and type tags, never the
# mutable S7 constructor and validator environments retained by R serialization.
native_content_identity <- function(value) {
  if (inherits(value, "ellmer::Content")) {
    return(list(
      type = "content",
      classes = class(value),
      properties = native_content_identity(S7::props(value))
    ))
  }
  if (is.list(value)) {
    return(list(
      type = "list",
      attributes = attributes(value),
      items = lapply(value, native_content_identity)
    ))
  }
  list(type = "value", value = value)
}

serialize_tool_result_value <- function(value, format = NULL) {
  if (identical(format, "native-content-v1")) {
    value <- native_content_identity(value)
  } else if (!is.null(format)) {
    cli_abort("Offloaded tool result has an unsupported value format")
  }
  serialize(value, NULL, version = 3)
}

# Bound model-facing native content independently of host-facing display data.
# Public property serialization avoids counting S7 class environments as payload.
rich_content_bytes <- function(content) {
  length(serialize(S7::props(content), NULL, version = 3L))
}

bound_rich_tool_result <- function(
  value,
  tool_name,
  policy,
  session_id,
  agent_id
) {
  if (!inherits(value, "ellmer::ContentToolResult")) {
    return(NULL)
  }
  payload <- value@value
  error <- value@error
  if (inherits(payload, "ellmer::ContentImage")) {
    payload <- list(payload)
  }
  native <- is.list(payload) &&
    is.null(names(payload)) &&
    all(vapply(payload, inherits, logical(1), what = "ellmer::Content"))
  keep <- rep(TRUE, length(payload))
  if (!is.null(error)) {
    evidence <- list(
      error = if (inherits(error, "condition")) {
        conditionMessage(error)
      } else {
        error
      }
    )
    record <- offload_tool_result(
      evidence,
      tool_name,
      policy,
      session_id,
      agent_id,
      force = compaction_evidence_exceeds_limit(
        evidence,
        policy$max_tool_result_bytes
      )
    )
  } else if (!native) {
    evidence <- project_tool_content(payload)
    record <- offload_tool_result(
      evidence,
      tool_name,
      policy,
      session_id,
      agent_id,
      force = compaction_evidence_exceeds_limit(
        evidence,
        policy$max_tool_result_bytes
      )
    )
  } else {
    text_bytes <- 0
    image_bytes <- 0
    images <- 0L
    for (index in seq_along(payload)) {
      content <- payload[[index]]
      bytes <- rich_content_bytes(content)
      if (inherits(content, "ellmer::ContentImage")) {
        keep[[index]] <- (is.null(policy$max_tool_result_images) ||
          images < policy$max_tool_result_images) &&
          (is.null(policy$max_tool_result_image_bytes) ||
            image_bytes + bytes <= policy$max_tool_result_image_bytes)
        if (keep[[index]]) {
          images <- images + 1L
          image_bytes <- image_bytes + bytes
        }
      } else {
        keep[[index]] <- is.null(policy$max_tool_result_bytes) ||
          text_bytes + bytes <= policy$max_tool_result_bytes
        if (keep[[index]]) text_bytes <- text_bytes + bytes
      }
    }
    if (all(keep)) {
      return(NULL)
    }
    record <- offload_tool_result(
      list(kind = "deputy_native_content", content = payload),
      tool_name,
      policy,
      session_id,
      agent_id,
      force = TRUE,
      public_content = TRUE
    )
  }
  if (is.null(record)) {
    return(NULL)
  }
  reference <- tool_result_reference_text(record)
  if (!is.null(error)) {
    result <- ellmer::ContentToolResult(
      error = reference,
      extra = value@extra,
      request = value@request
    )
  } else if (native) {
    bounded <- list()
    omitted <- FALSE
    for (index in seq_along(payload)) {
      if (keep[[index]]) {
        bounded[[length(bounded) + 1L]] <- payload[[index]]
        omitted <- FALSE
      } else if (!omitted) {
        bounded[[length(bounded) + 1L]] <- ellmer::ContentText(
          "[Output items were offloaded because they exceeded the model context allowance.]"
        )
        omitted <- TRUE
      }
    }
    bounded[[length(bounded) + 1L]] <- ellmer::ContentText(reference)
    result <- ellmer::ContentToolResult(
      value = bounded,
      extra = value@extra,
      request = value@request
    )
  } else {
    result <- ellmer::ContentToolResult(
      value = reference,
      extra = value@extra,
      request = value@request
    )
  }
  list(result = result, record = record)
}
