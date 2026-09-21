# Governed tool calls from the persistent R worker --------------------------

# The worker/host bridge deliberately uses a small JSON value protocol.  RDS
# is useful for trusted callr arguments, but an RDS file produced by generated
# code must never be deserialized by the host.  These constants are shared by
# the host mailbox and the worker implementation.
r_session_tool_protocol_version <- 1L
r_session_tool_max_request_bytes <- 256L * 1024L
r_session_tool_max_result_bytes <- 8L * 1024L * 1024L
r_session_tool_max_schema_bytes <- 32L * 1024L

r_session_tool_names <- function(value) {
  if (is.null(value)) {
    return(character())
  }
  if (
    !is.character(value) ||
      anyNA(value) ||
      !all(nzchar(trimws(value))) ||
      any(nchar(value, type = "bytes") > 128L) ||
      !all(grepl("^[A-Za-z][A-Za-z0-9_.-]*$", value))
  ) {
    abort_deputy(
      "{.arg tools} must contain valid tool names.",
      class = "r_session_tool"
    )
  }
  value <- unique(value)
  if (any(value %in% c("run_r_code", "deputy_read_tool_result"))) {
    abort_deputy(
      "R sessions cannot bridge the recursive or internal tool {.val {value[value %in% c('run_r_code', 'deputy_read_tool_result')][[1L]]}}.",
      class = "r_session_tool"
    )
  }
  value
}

r_session_tool_agent_private <- function(agent) {
  tryCatch(agent$.__enclos_env__$private, error = function(error) NULL)
}

r_session_tool_registered <- function(agent, tool_names) {
  tools <- tryCatch(agent$get_tools(), error = function(error) NULL)
  if (!is.list(tools)) {
    abort_deputy(
      "Could not inspect the Agent's registered tools.",
      class = "r_session_tool"
    )
  }
  missing <- setdiff(tool_names, names(tools))
  if (length(missing)) {
    abort_deputy(
      "R session tool {.val {missing[[1L]]}} is not registered on this Agent.",
      class = "r_session_tool"
    )
  }
  selected <- tools[tool_names]
  invalid <- vapply(
    selected,
    function(tool) {
      !inherits(tool, "ellmer::ToolDef") ||
        !identical(tryCatch(tool@convert, error = function(error) NULL), FALSE)
    },
    logical(1)
  )
  if (any(invalid)) {
    name <- names(selected)[which(invalid)[[1L]]]
    abort_deputy(
      "R session tool {.val {name}} must use {.arg convert = FALSE}.",
      class = "r_session_tool"
    )
  }
  selected
}

r_session_tool_specs <- function(agent, tool_names) {
  selected <- r_session_tool_registered(agent, tool_names)
  specs <- lapply(selected, function(tool) {
    description <- tryCatch(tool@description, error = function(error) "")
    arguments <- names(tool@arguments@properties)
    spec <- list(
      name = as.character(tool@name[[1L]]),
      description = as.character(description %||% ""),
      arguments = arguments
    )
    encoded <- tryCatch(
      jsonlite::toJSON(spec, auto_unbox = TRUE, null = "null"),
      error = function(error) NULL
    )
    if (
      is.null(encoded) ||
        nchar(encoded, type = "bytes") > r_session_tool_max_schema_bytes
    ) {
      abort_deputy(
        "The schema for R session tool {.val {spec$name}} is too large or invalid.",
        class = "r_session_tool"
      )
    }
    spec
  })
  names(specs) <- names(selected)
  r_session_tool_json(
    specs,
    r_session_tool_max_schema_bytes,
    "tool descriptions"
  )
  specs
}

r_session_tool_description <- function(specs) {
  if (!length(specs)) {
    return(character())
  }
  pieces <- vapply(
    specs,
    function(spec) {
      argument_text <- paste(spec$arguments, collapse = ", ")
      if (!nzchar(argument_text)) {
        argument_text <- "..."
      }
      paste0("`", spec$name, "(", argument_text, ")`: ", spec$description)
    },
    character(1)
  )
  paste(
    "The persistent R worker can call these explicitly selected governed Agent tools via `tools$<name>(...)`.",
    paste(pieces, collapse = " "),
    "Tool calls remain subject to the active Agent run's permissions, hooks and limits.",
    sep = " "
  )
}

r_session_tool_scalar <- function(value, name) {
  if (
    !is.character(value) ||
      length(value) != 1L ||
      is.na(value) ||
      !nzchar(value)
  ) {
    abort_deputy(
      "R session mailbox field {.arg {name}} must be one non-empty string.",
      class = "r_session_tool_protocol"
    )
  }
  value
}

r_session_tool_integer <- function(value, name, min = 0L) {
  if (
    !is.numeric(value) ||
      length(value) != 1L ||
      is.na(value) ||
      !is.finite(value) ||
      value > .Machine$integer.max ||
      value != as.integer(value) ||
      value < min
  ) {
    abort_deputy(
      "R session mailbox field {.arg {name}} must be a valid whole number.",
      class = "r_session_tool_protocol"
    )
  }
  as.integer(value)
}

r_session_tool_valid_request_id <- function(value) {
  is.character(value) &&
    length(value) == 1L &&
    !is.na(value) &&
    grepl("^[A-Za-z0-9][A-Za-z0-9_.-]{0,191}$", value)
}

r_session_tool_safe_value <- function(value) {
  isTRUE(tryCatch(
    {
      approval_portable(value, allow_classed = TRUE)
      TRUE
    },
    error = function(error) FALSE
  ))
}

r_session_tool_serialize_result <- function(
  value,
  max_bytes = r_session_tool_max_result_bytes
) {
  if (!r_session_tool_safe_value(value)) {
    abort_deputy(
      "R session tool results may contain only bounded plain R data; closures, environments and native pointers are not supported.",
      class = "r_session_tool_value"
    )
  }
  serialized <- tryCatch(
    serialize(value, NULL, version = 3L),
    error = function(error) {
      abort_deputy(
        "Could not serialize the R session tool result: {conditionMessage(error)}",
        class = "r_session_tool_value"
      )
    }
  )
  if (length(serialized) > max_bytes) {
    abort_deputy(
      "R session tool result exceeds its mailbox size limit.",
      class = "r_session_tool_value"
    )
  }
  encoded <- jsonlite::base64_enc(serialized)
  if (nchar(encoded, type = "bytes") > max_bytes * 2L) {
    abort_deputy(
      "R session tool result exceeds its encoded mailbox size limit.",
      class = "r_session_tool_value"
    )
  }
  encoded
}

r_session_tool_json <- function(value, max_bytes, context = "value") {
  encoded <- tryCatch(
    jsonlite::toJSON(value, auto_unbox = TRUE, null = "null", digits = NA),
    error = function(error) {
      abort_deputy(
        "Could not encode R session tool {.val {context}} as bounded JSON: {conditionMessage(error)}",
        class = "r_session_tool_value"
      )
    }
  )
  bytes <- nchar(encoded, type = "bytes")
  if (bytes > max_bytes) {
    abort_deputy(
      "R session tool {.val {context}} exceeds its mailbox size limit.",
      class = "r_session_tool_value"
    )
  }
  encoded
}

r_session_tool_atomic_write <- function(path, text) {
  directory <- dirname(path)
  temporary <- tempfile("mailbox-", tmpdir = directory)
  on.exit(unlink(temporary), add = TRUE)
  connection <- file(temporary, open = "wb")
  on.exit(try(close(connection), silent = TRUE), add = TRUE)
  writeChar(enc2utf8(text), connection, eos = NULL, useBytes = TRUE)
  close(connection)
  on.exit(unlink(temporary), add = FALSE)
  Sys.chmod(temporary, mode = "0600")
  if (!file.rename(temporary, path)) {
    abort_deputy(
      "Could not publish the R session mailbox message.",
      class = "r_session_tool_mailbox"
    )
  }
  invisible(path)
}

r_session_tool_read_json <- function(path, max_bytes, context) {
  info <- file.info(path)
  if (is.na(info$size) || info$size > max_bytes) {
    abort_deputy(
      "R session mailbox {.val {context}} exceeds its size limit.",
      class = "r_session_tool_protocol"
    )
  }
  connection <- file(path, open = "rb")
  on.exit(close(connection), add = TRUE)
  raw <- readBin(connection, what = "raw", n = max_bytes + 1L)
  if (length(raw) > max_bytes) {
    abort_deputy(
      "R session mailbox {.val {context}} exceeds its size limit.",
      class = "r_session_tool_protocol"
    )
  }
  text <- rawToChar(raw)
  tryCatch(
    jsonlite::fromJSON(text, simplifyVector = FALSE),
    error = function(error) {
      abort_deputy(
        "Malformed R session mailbox {.val {context}}: {conditionMessage(error)}",
        class = "r_session_tool_protocol"
      )
    }
  )
}

r_session_tool_plain_json <- function(value, depth = 0L) {
  if (is.null(value)) {
    return(TRUE)
  }
  if (depth > 32L) {
    return(FALSE)
  }
  if (
    is.function(value) ||
      is.environment(value) ||
      typeof(value) == "externalptr"
  ) {
    return(FALSE)
  }
  if (is.language(value) || is.pairlist(value) || is.expression(value)) {
    return(FALSE)
  }
  attributes <- attributes(value)
  if (!is.null(attributes)) {
    attributes$names <- NULL
    if (length(attributes)) return(FALSE)
  }
  if (is.list(value)) {
    return(
      length(value) <= 100000L &&
        all(vapply(
          value,
          r_session_tool_plain_json,
          logical(1),
          depth = depth + 1L
        ))
    )
  }
  if (is.atomic(value)) {
    return(
      length(value) <= 100000L &&
        (!is.numeric(value) || all(is.finite(value) | is.na(value)))
    )
  }
  is.null(value)
}

r_session_tool_validate_request <- function(
  request,
  session_id,
  call_id,
  execution_id,
  generation,
  tool_names,
  request_basename = NULL
) {
  expected <- c(
    "protocol",
    "request_id",
    "session_id",
    "call_id",
    "execution_id",
    "generation",
    "tool_name",
    "arguments"
  )
  if (
    !is.list(request) ||
      !identical(sort(names(request)), sort(expected))
  ) {
    abort_deputy(
      "Malformed R session tool request identity.",
      class = "r_session_tool_protocol"
    )
  }
  protocol <- r_session_tool_integer(request$protocol, "protocol", min = 1L)
  if (!identical(protocol, r_session_tool_protocol_version)) {
    abort_deputy(
      "Unsupported R session tool mailbox protocol.",
      class = "r_session_tool_protocol"
    )
  }
  request_id <- r_session_tool_scalar(request$request_id, "request_id")
  if (!r_session_tool_valid_request_id(request_id)) {
    abort_deputy(
      "Malformed R session tool request ID.",
      class = "r_session_tool_protocol"
    )
  }
  if (
    !is.null(request_basename) &&
      !identical(
        request_basename,
        paste0(request_id, ".request.json")
      )
  ) {
    abort_deputy(
      "R session tool request path does not match its identity.",
      class = "r_session_tool_protocol"
    )
  }
  identity <- list(
    session_id = session_id,
    call_id = call_id,
    execution_id = execution_id,
    generation = generation
  )
  for (name in c("session_id", "call_id", "execution_id")) {
    value <- r_session_tool_scalar(request[[name]], name)
    if (!identical(value, identity[[name]])) {
      abort_deputy(
        "R session tool request identity is stale or belongs to another execution.",
        class = "r_session_tool_protocol"
      )
    }
  }
  if (
    !identical(
      r_session_tool_integer(request$generation, "generation"),
      as.integer(identity$generation)
    )
  ) {
    abort_deputy(
      "R session tool request generation is stale.",
      class = "r_session_tool_protocol"
    )
  }
  tool_name <- r_session_tool_scalar(request$tool_name, "tool_name")
  if (!identical(tool_name, request$tool_name) || !tool_name %in% tool_names) {
    abort_deputy(
      "R session tool request names an unselected tool.",
      class = "r_session_tool_protocol"
    )
  }
  arguments <- request$arguments
  if (!is.list(arguments) || !r_session_tool_plain_json(arguments)) {
    abort_deputy(
      "R session tool arguments must be bounded plain JSON data.",
      class = "r_session_tool_protocol"
    )
  }
  if (
    length(arguments) &&
      (is.null(names(arguments)) ||
        !all(nzchar(names(arguments))) ||
        anyDuplicated(names(arguments)) > 0L)
  ) {
    abort_deputy(
      "R session tool arguments must be named.",
      class = "r_session_tool_protocol"
    )
  }
  list(request_id = request_id, tool_name = tool_name, arguments = arguments)
}

r_session_tool_error_message <- function(error) {
  conditionMessage(error) %||% "R session tool call failed."
}

r_session_tool_response <- function(
  request,
  status,
  value = NULL,
  error = NULL,
  session_id = NULL,
  call_id = NULL,
  generation = NULL
) {
  response <- list(
    protocol = r_session_tool_protocol_version,
    request_id = request$request_id,
    session_id = session_id %||% request$session_id,
    call_id = call_id %||% request$call_id,
    execution_id = request$execution_id,
    generation = generation %||% request$generation,
    tool_name = request$tool_name,
    status = status
  )
  if (identical(status, "ok")) {
    response$value_rds <- r_session_tool_serialize_result(value)
  } else {
    response$error <- as.character(error %||% "R session tool call failed.")
  }
  response
}
