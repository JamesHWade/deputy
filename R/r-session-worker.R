# Evaluated in the callr worker with a base environment. No Deputy namespace or
# host closure is transferred. Persistent objects live only in that worker.
r_session_evaluate <- function(
  code,
  working_dir,
  max_output_bytes,
  plot_width,
  plot_height,
  mailbox_dir = NULL,
  session_id = NULL,
  call_id = NULL,
  execution_id = NULL,
  generation = NULL,
  tool_specs = list(),
  tool_timeout = 30,
  max_tool_request_bytes = 256L * 1024L,
  max_tool_result_bytes = 8L * 1024L * 1024L
) {
  setwd(working_dir)

  # This function is deliberately sent to callr with baseenv() as its
  # enclosing environment.  The bridge helpers below are worker-only copies:
  # they contain no Agent, ToolDef, host closure or credential-bearing state.
  # The only host-owned value crossing the boundary is bounded JSON metadata
  # and the mailbox identity for this execution.
  worker_abort <- function(message) {
    condition <- structure(
      list(message = as.character(message)),
      class = c("r_session_worker_tool_error", "error", "condition")
    )
    stop(condition)
  }
  worker_json_safe <- function(value, depth = 0L) {
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
    value_attributes <- attributes(value)
    if (!is.null(value_attributes)) {
      value_attributes$names <- NULL
      if (length(value_attributes)) return(FALSE)
    }
    if (is.list(value)) {
      return(
        length(value) <= 100000L &&
          all(vapply(
            value,
            worker_json_safe,
            logical(1),
            depth = depth + 1L
          ))
      )
    }
    if (is.atomic(value)) {
      # jsonlite would encode NA as the string "NA"; reject it explicitly.
      return(
        length(value) <= 100000L &&
          !anyNA(value) &&
          (!is.numeric(value) || all(is.finite(value)))
      )
    }
    is.null(value)
  }
  worker_json <- function(value, limit) {
    text <- tryCatch(
      jsonlite::toJSON(value, auto_unbox = TRUE, null = "null", digits = NA),
      error = function(error) worker_abort(conditionMessage(error))
    )
    if (nchar(text, type = "bytes") > limit) {
      worker_abort("R session tool mailbox message exceeds its size limit.")
    }
    text
  }
  worker_write <- function(path, text) {
    temporary <- tempfile("mailbox-", tmpdir = dirname(path))
    on.exit(unlink(temporary), add = TRUE)
    connection <- file(temporary, open = "wb")
    on.exit(try(close(connection), silent = TRUE), add = TRUE)
    writeChar(enc2utf8(text), connection, eos = NULL, useBytes = TRUE)
    close(connection)
    on.exit(unlink(temporary), add = FALSE)
    Sys.chmod(temporary, mode = "0600")
    if (!file.rename(temporary, path)) {
      worker_abort("Could not publish an R session tool request.")
    }
    invisible(path)
  }
  worker_read <- function(path, limit) {
    info <- file.info(path)
    if (is.na(info$size) || info$size > limit) {
      worker_abort("R session tool response exceeds its size limit.")
    }
    text <- paste(
      readLines(path, warn = FALSE, encoding = "UTF-8"),
      collapse = "\n"
    )
    tryCatch(
      jsonlite::fromJSON(text, simplifyVector = FALSE),
      error = function(error) worker_abort(conditionMessage(error))
    )
  }
  # The request counter lives in this execution's own environment, not in
  # globalenv(), so evaluated code cannot reset it and reuse a request ID.
  tool_counter <- new.env(parent = emptyenv())
  tool_counter$value <- 0L
  worker_request_id <- function() {
    tool_counter$value <- tool_counter$value + 1L
    paste0(call_id, "-", generation, "-", tool_counter$value)
  }
  worker_call_tool <- function(name, arguments) {
    if (
      !is.character(name) ||
        length(name) != 1L ||
        is.na(name) ||
        !name %in% names(tool_specs)
    ) {
      worker_abort("The R session tool is not selected for this execution.")
    }
    if (
      !is.list(arguments) ||
        (length(arguments) > 0L &&
          (is.null(names(arguments)) ||
            !all(nzchar(names(arguments))) ||
            anyDuplicated(names(arguments)) > 0L)) ||
        !worker_json_safe(arguments)
    ) {
      worker_abort(
        "R session tool arguments must be a named list of JSON-compatible values without NA."
      )
    }
    if (!dir.exists(mailbox_dir)) {
      worker_abort("R session tool execution is no longer active.")
    }
    request_id <- worker_request_id()
    request <- list(
      protocol = 1L,
      request_id = request_id,
      session_id = session_id,
      call_id = call_id,
      execution_id = execution_id,
      generation = as.integer(generation),
      tool_name = name,
      arguments = arguments
    )
    request_path <- file.path(mailbox_dir, paste0(request_id, ".request.json"))
    response_path <- file.path(
      mailbox_dir,
      paste0(request_id, ".response.json")
    )
    worker_write(request_path, worker_json(request, max_tool_request_bytes))
    deadline <- unname(proc.time()[["elapsed"]]) +
      max(0.1, as.numeric(tool_timeout))
    repeat {
      if (file.exists(response_path)) {
        break
      }
      if (unname(proc.time()[["elapsed"]]) >= deadline) {
        unlink(request_path)
        worker_abort("R session tool call timed out.")
      }
      Sys.sleep(0.01)
    }
    response <- worker_read(response_path, max_tool_result_bytes * 2L)
    unlink(c(request_path, response_path))
    required <- c(
      "protocol",
      "request_id",
      "session_id",
      "call_id",
      "execution_id",
      "generation",
      "tool_name",
      "status"
    )
    if (
      !is.list(response) ||
        !identical(sort(names(response)), sort(c(required, "value_rds"))) &&
          !identical(sort(names(response)), sort(c(required, "error")))
    ) {
      worker_abort("Malformed R session tool response identity.")
    }
    if (
      !identical(as.integer(response$protocol), 1L) ||
        !identical(response$request_id, request_id) ||
        !identical(response$session_id, session_id) ||
        !identical(response$call_id, call_id) ||
        !identical(response$execution_id, execution_id) ||
        !identical(as.integer(response$generation), as.integer(generation)) ||
        !identical(response$tool_name, name)
    ) {
      worker_abort("R session tool response did not match its request.")
    }
    if (identical(response$status, "error")) {
      worker_abort(
        if (is.null(response$error)) {
          "R session tool call failed."
        } else {
          response$error
        }
      )
    }
    if (!identical(response$status, "ok")) {
      worker_abort("R session tool response has an invalid status.")
    }
    if (!is.character(response$value_rds) || length(response$value_rds) != 1L) {
      worker_abort("Malformed R session tool result payload.")
    }
    result <- tryCatch(
      unserialize(jsonlite::base64_dec(response$value_rds)),
      error = function(error) worker_abort(conditionMessage(error))
    )
    result
  }
  if (length(tool_specs) && !is.null(mailbox_dir)) {
    # The persistent worker keeps user variables in its global environment;
    # the `tools` binding lives beside them by design.
    worker_globals <- globalenv()
    if (
      !exists("tools", envir = worker_globals, inherits = FALSE) ||
        !is.environment(get("tools", envir = worker_globals, inherits = FALSE))
    ) {
      assign("tools", new.env(parent = baseenv()), envir = worker_globals)
    }
    worker_tools <- get("tools", envir = worker_globals, inherits = FALSE)
    for (name in names(tool_specs)) {
      local_name <- name
      assign(
        local_name,
        local({
          name <- local_name
          function(...) worker_call_tool(name, list(...))
        }),
        envir = worker_tools
      )
    }
  }

  segments <- list()
  retained <- 0L
  truncated <- FALSE
  failed <- FALSE
  unsupported <- FALSE
  last_plot <- NULL
  add <- function(type, text = NULL, data = NULL) {
    if (truncated) {
      return(invisible(NULL))
    }
    bytes <- if (is.null(data)) nchar(enc2utf8(text), "bytes") else length(data)
    available <- max(0, max_output_bytes - retained)
    if (bytes > available) {
      truncated <<- TRUE
      if (is.null(data) && available > 0) {
        low <- 0L
        high <- min(nchar(text), available)
        while (low < high) {
          mid <- ceiling((low + high) / 2)
          if (nchar(enc2utf8(substr(text, 1L, mid)), "bytes") <= available) {
            low <- mid
          } else {
            high <- mid - 1L
          }
        }
        if (low > 0) {
          segments[[length(segments) + 1L]] <<- list(
            type = type,
            text = substr(text, 1L, low)
          )
        }
      }
      segments[[length(segments) + 1L]] <<- list(
        type = "message",
        text = "Captured output limit reached; further output and plots were omitted."
      )
      return(invisible(NULL))
    }
    retained <<- retained + bytes
    segments[[length(segments) + 1L]] <<- if (is.null(data)) {
      list(type = type, text = text)
    } else {
      list(type = type, data = data)
    }
    invisible(NULL)
  }
  flush_plot <- function() {
    if (is.null(last_plot)) {
      return(invisible(NULL))
    }
    plot <- last_plot
    last_plot <<- NULL
    if (truncated) {
      return(invisible(NULL))
    }
    path <- tempfile("deputy-plot-", fileext = ".png")
    on.exit(unlink(path), add = TRUE)
    grDevices::png(path, width = plot_width, height = plot_height, res = 120)
    tryCatch(grDevices::replayPlot(plot), finally = grDevices::dev.off())
    size <- file.info(path)$size
    if (size > max_output_bytes - retained) {
      truncated <<- TRUE
      segments[[length(segments) + 1L]] <<- list(
        type = "message",
        text = "Captured output limit reached; this plot and further output were omitted."
      )
    } else {
      add("plot", data = readBin(path, "raw", size))
    }
    invisible(NULL)
  }
  # evaluate emits updates to the same display list. Keep the final drawing
  # until a new plot or intervening console/condition output fixes its position.
  # Prior art: posit-dev/commons worker_run_code(), originally from btw.
  render_value <- evaluate::new_output_handler()$value
  handler <- evaluate::new_output_handler(
    value = function(value, visible, envir) {
      if (
        visible &&
          any(vapply(
            c(
              "htmlwidget",
              "shiny.tag",
              "shiny.tag.list",
              "gt_tbl",
              "flextable"
            ),
            function(class) inherits(value, class),
            logical(1)
          ))
      ) {
        flush_plot()
        unsupported <<- TRUE
        add(
          "warning",
          text = paste0(
            "Unsupported rich output (",
            paste(class(value), collapse = ", "),
            "): this R session captures static graphics and printed text. ",
            "No interactive widget or rich table was saved. ",
            "Create a static plot or print the underlying data for review."
          )
        )
        return(invisible(NULL))
      }
      render_value(value, visible, envir)
    },
    source = function(source, expr) NULL,
    text = function(text) {
      flush_plot()
      add("text", text = text)
      invisible(NULL)
    },
    graphics = function(plot) {
      if (!is.null(last_plot)) {
        x <- last_plot[[1L]]
        y <- plot[[1L]]
        if (!(length(x) <= length(y) && identical(x[], y[seq_along(x)]))) {
          flush_plot()
        }
      }
      last_plot <<- plot
      invisible(NULL)
    },
    message = function(message) {
      flush_plot()
      add("message", text = conditionMessage(message))
      invisible(NULL)
    },
    warning = function(warning) {
      flush_plot()
      add("warning", text = conditionMessage(warning))
      invisible(NULL)
    },
    error = function(error) {
      flush_plot()
      failed <<- TRUE
      add("error", text = conditionMessage(error))
      invisible(NULL)
    }
  )
  tryCatch(
    {
      evaluate::evaluate(
        code,
        envir = globalenv(),
        stop_on_error = 1L,
        new_device = TRUE,
        output_handler = handler
      )
      flush_plot()
    },
    error = function(error) {
      failed <<- TRUE
      add("error", text = conditionMessage(error))
    }
  )
  list(
    segments = segments,
    outcome = if (failed) {
      "error"
    } else if (unsupported) {
      "unsupported_output"
    } else if (truncated) {
      "output_truncated"
    } else {
      "complete"
    }
  )
}
