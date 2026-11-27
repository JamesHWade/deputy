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

r_session_tool_is_disallowed <- function(name, tool, source) {
  identical(name, "run_r_code") ||
    identical(name, "run_bash") ||
    identical(name, "deputy_read_tool_result") ||
    !is.null(composition_tool_owner(tool)) ||
    !is.null(composition_tool_owner(source)) ||
    !is.null(attr(source, "deputy_r_session_owner", exact = TRUE))
}

r_session_tool_admit <- function(
  registered,
  tool_names,
  abort_fn,
  missing_message,
  convert_message,
  disallowed_message,
  require_exact_name = FALSE
) {
  selected <- lapply(tool_names, function(name) {
    tool <- registered[[name]]
    if (is.null(tool) || !inherits(tool, "ellmer::ToolDef")) {
      abort_fn(missing_message, name = name)
    }
    source <- runtime_source_tool(tool)
    if (require_exact_name && !identical(source@name, name)) {
      abort_fn(
        "Nested R session tool {.val {name}} does not have an exact registered executable.",
        name = name
      )
    }
    if (!identical(tryCatch(source@convert, error = function(e) NULL), FALSE)) {
      abort_fn(convert_message, name = name)
    }
    if (r_session_tool_is_disallowed(name, tool, source)) {
      abort_fn(disallowed_message, name = name)
    }
    list(tool = tool, source = source)
  })
  names(selected) <- tool_names
  selected
}

r_session_tool_registered <- function(agent, tool_names) {
  call <- environment()
  abort_tool <- function(message, ...) {
    env <- list2env(list(...), parent = parent.frame())
    abort_deputy(message, class = "r_session_tool", call = call, .envir = env)
  }
  tools <- tryCatch(agent$get_tools(), error = function(error) NULL)
  if (!is.list(tools)) {
    abort_tool("Could not inspect the Agent's registered tools.")
  }
  admitted <- r_session_tool_admit(
    registered = tools,
    tool_names = tool_names,
    abort_fn = abort_tool,
    missing_message = "R session tool {.val {name}} is not registered on this Agent.",
    convert_message = "R session tool {.val {name}} must use {.arg convert = FALSE}.",
    disallowed_message = "R sessions cannot bridge recursive execution or composition tool {.val {name}}."
  )
  lapply(admitted, `[[`, "tool")
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

r_session_tool_check_size <- function(
  value,
  max_bytes,
  oversize_message,
  abort_fn,
  serialize_error_message = NULL
) {
  serialized <- tryCatch(
    serialize(value, NULL, version = 3L),
    error = function(error) {
      if (!is.null(serialize_error_message)) {
        abort_fn(serialize_error_message, error = error)
      }
      NULL
    }
  )
  bytes <- if (is.null(serialized)) NA_real_ else length(serialized)
  if (is.na(bytes) || !is.finite(bytes) || bytes > max_bytes) {
    abort_fn(oversize_message)
  }
  serialized
}

r_session_tool_serialize_result <- function(
  value,
  max_bytes = r_session_tool_max_result_bytes
) {
  call <- environment()
  abort_value <- function(message, ...) {
    env <- list2env(list(...), parent = parent.frame())
    abort_deputy(
      message,
      class = "r_session_tool_value",
      call = call,
      .envir = env
    )
  }
  if (!r_session_tool_safe_value(value)) {
    abort_value(
      "R session tool results may contain only bounded plain R data; closures, environments and native pointers are not supported."
    )
  }
  serialized <- r_session_tool_check_size(
    value,
    max_bytes = max_bytes,
    oversize_message = "R session tool result exceeds its mailbox size limit.",
    abort_fn = abort_value,
    serialize_error_message = "Could not serialize the R session tool result: {conditionMessage(error)}"
  )
  encoded <- jsonlite::base64_enc(serialized)
  if (nchar(encoded, type = "bytes") > max_bytes * 2L) {
    abort_value(
      "R session tool result exceeds its encoded mailbox size limit."
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
  write_file_atomic(
    path,
    write_fn = function(temporary) {
      connection <- file(temporary, open = "wb")
      tryCatch(
        writeChar(enc2utf8(text), connection, eos = NULL, useBytes = TRUE),
        finally = close(connection)
      )
    },
    prefix = "mailbox-",
    on_commit_error = function() {
      abort_deputy(
        "Could not publish the R session mailbox message.",
        class = "r_session_tool_mailbox"
      )
    }
  )
}

r_session_tool_read_io <- function(fun, context) {
  warnings <- character()
  io_error <- function(causes) {
    abort_deputy(
      "Could not read R session mailbox {.val {context}}: {paste(causes, collapse = '; ')}",
      class = "r_session_tool_io"
    )
  }
  value <- tryCatch(
    withCallingHandlers(
      fun(),
      warning = function(warning) {
        warnings <<- c(warnings, conditionMessage(warning))
        invokeRestart("muffleWarning")
      }
    ),
    error = function(error) {
      io_error(c(warnings, conditionMessage(error)))
    }
  )
  if (length(warnings)) {
    io_error(warnings)
  }
  value
}

r_session_tool_file_info <- function(path) {
  file.info(path)
}

r_session_tool_read_bytes <- function(path, max_bytes) {
  connection <- file(path, open = "rb")
  on.exit(close(connection), add = TRUE)
  readBin(connection, what = "raw", n = max_bytes + 1L)
}

r_session_tool_read_json <- function(path, max_bytes, context) {
  info <- r_session_tool_read_io(
    function() r_session_tool_file_info(path),
    context
  )
  if (is.na(info$size)) {
    abort_deputy(
      "Could not determine the size of R session mailbox {.val {context}}.",
      class = "r_session_tool_io"
    )
  }
  if (info$size > max_bytes) {
    abort_deputy(
      "R session mailbox {.val {context}} exceeds its size limit.",
      class = "r_session_tool_protocol"
    )
  }
  raw <- r_session_tool_read_io(
    function() r_session_tool_read_bytes(path, max_bytes),
    context
  )
  if (length(raw) > max_bytes) {
    abort_deputy(
      "R session mailbox {.val {context}} exceeds its size limit.",
      class = "r_session_tool_protocol"
    )
  }
  text <- rawToChar(raw)
  tryCatch(
    jsonlite::parse_json(text, simplifyVector = FALSE),
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
  if (!tool_name %in% tool_names) {
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
  if (length(arguments) && !has_unique_names(arguments)) {
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

# Host mailbox bridge for RSession ------------------------------------------

r_session_bridge_directory <- function(private, job) {
  if (is.null(private$bridge_root)) {
    private$bridge_root <- tempfile("deputy-r-tools-")
    if (!dir.create(private$bridge_root, recursive = TRUE, mode = "0700")) {
      abort_deputy(
        "Could not create the R session tool mailbox.",
        class = "r_session_tool_mailbox"
      )
    }
  }
  directory <- file.path(
    private$bridge_root,
    paste0("generation-", private$generation),
    paste0("call-", job$id)
  )
  if (!dir.create(directory, recursive = TRUE, mode = "0700")) {
    abort_deputy(
      "Could not create the R session execution mailbox.",
      class = "r_session_tool_mailbox"
    )
  }
  directory
}

r_session_cleanup_bridge <- function(private) {
  if (!is.null(private$bridge_root)) {
    unlink(private$bridge_root, recursive = TRUE, force = TRUE)
    private$bridge_root <- NULL
  }
  invisible(NULL)
}

r_session_write_tool_response <- function(
  private,
  job,
  request,
  status,
  value = NULL,
  error = NULL
) {
  if (!private$active_job(job)) {
    return(invisible(NULL))
  }
  request_id <- request$request_id
  if (
    exists(request_id, envir = job$tool_requests, inherits = FALSE) &&
      identical(get(request_id, envir = job$tool_requests), "settled")
  ) {
    return(invisible(NULL))
  }
  response <- tryCatch(
    r_session_tool_response(
      request,
      status = status,
      value = value,
      error = error,
      session_id = private$id,
      call_id = job$id,
      generation = job$generation
    ),
    error = function(condition) {
      list(
        protocol = r_session_tool_protocol_version,
        request_id = request_id,
        session_id = private$id,
        call_id = job$id,
        execution_id = job$governed_execution_id,
        generation = job$generation,
        tool_name = request$tool_name %||% "unknown",
        status = "error",
        error = r_session_tool_error_message(condition)
      )
    }
  )
  path <- file.path(job$mailbox_dir, paste0(request_id, ".response.json"))
  tryCatch(
    r_session_tool_atomic_write(
      path,
      r_session_tool_json(
        response,
        r_session_tool_max_result_bytes * 2L,
        context = "response"
      )
    ),
    error = function(condition) {
      # The worker may have timed out or the owner may be resetting. In
      # either case there is no later execution to which this response may
      # be delivered.
      invisible(NULL)
    }
  )
  assign(request_id, "settled", envir = job$tool_requests)
  invisible(NULL)
}

r_session_poll_tool_mailbox <- function(private, job) {
  if (
    !length(private$tool_names) ||
      is.null(job$mailbox_dir) ||
      !dir.exists(job$mailbox_dir)
  ) {
    return(invisible(NULL))
  }
  paths <- list.files(
    job$mailbox_dir,
    pattern = "\\.request\\.json$",
    full.names = TRUE,
    no.. = TRUE
  )
  for (path in paths) {
    request_id <- sub("\\.request\\.json$", "", basename(path))
    if (exists(request_id, envir = job$tool_requests, inherits = FALSE)) {
      next
    }
    assign(request_id, "processing", envir = job$tool_requests)
    request <- tryCatch(
      r_session_tool_read_json(
        path,
        r_session_tool_max_request_bytes,
        context = "request"
      ),
      error = function(condition) condition
    )
    if (inherits(request, "deputy_r_session_tool_io")) {
      # The request has not been parsed or dispatched. Leave it eligible
      # for the next poll; the execution's existing deadline bounds retries.
      job$tool_read_state$last_error <- conditionMessage(request)
      rm(list = request_id, envir = job$tool_requests)
      next
    }
    job$tool_read_state$last_error <- NULL
    if (inherits(request, "condition")) {
      # A malformed request cannot be safely associated with an execution;
      # mark it consumed and leave the worker to report its bounded timeout.
      assign(request_id, "settled", envir = job$tool_requests)
      next
    }
    validated <- tryCatch(
      r_session_tool_validate_request(
        request,
        session_id = private$id,
        call_id = job$id,
        execution_id = job$governed_execution_id,
        generation = job$generation,
        tool_names = private$tool_names,
        request_basename = basename(path)
      ),
      error = function(condition) condition
    )
    if (inherits(validated, "condition")) {
      if (
        is.list(request) &&
          is_nonempty_string(request$request_id) &&
          r_session_tool_valid_request_id(request$request_id) &&
          identical(request$request_id, request_id)
      ) {
        private$write_tool_response(
          job,
          request,
          status = "error",
          error = r_session_tool_error_message(validated)
        )
      } else {
        assign(request_id, "settled", envir = job$tool_requests)
      }
      next
    }
    value <- tryCatch(
      job$dispatch(
        validated$tool_name,
        validated$arguments,
        execution_id = job$id,
        generation = as.character(job$generation)
      ),
      error = function(condition) condition
    )
    if (inherits(value, "condition")) {
      private$write_tool_response(
        job,
        request,
        status = "error",
        error = r_session_tool_error_message(value)
      )
      next
    }
    if (promises::is.promising(value)) {
      local({
        pending_request <- request
        promises::then(
          value,
          function(result) {
            private$write_tool_response(
              job,
              pending_request,
              "ok",
              value = result
            )
            invisible(NULL)
          },
          function(condition) {
            private$write_tool_response(
              job,
              pending_request,
              "error",
              error = r_session_tool_error_message(condition)
            )
            invisible(NULL)
          }
        )
      })
      assign(request_id, "pending", envir = job$tool_requests)
    } else {
      private$write_tool_response(job, request, "ok", value = value)
    }
  }
  invisible(NULL)
}
