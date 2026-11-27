# Portable content record/replay, duration projection, and payload sizing ----

inspection_portable <- function(x, depth = 0L) {
  if (
    depth > 64L ||
      is.object(x) ||
      !(is.null(x) || is.atomic(x) || is.list(x)) ||
      !all(names(attributes(x)) %in% c("names", "dim", "dimnames"))
  ) {
    cli::cli_abort("Inspection history must contain portable data only.")
  }
  if (is.list(x)) {
    lapply(x, inspection_portable, depth = depth + 1L)
  }
  invisible(NULL)
}

inspection_text <- function(text, bytes = 8192L) {
  text <- enc2utf8(text %||% "")
  # Starting with at most `bytes` characters bounds the UTF-8 trim work.
  text <- substr(text, 1L, bytes)
  while (nchar(text, type = "bytes") > bytes) {
    text <- substr(text, 1L, nchar(text) - 1L)
  }
  text
}

inspection_duration_omission <-
  "[Unsupported duration payload omitted from retained history.]"

inspection_duration_projection_budget <- 16 * 1024^2

inspection_data_frame_rows <- function(value) {
  row_names <- unclass(attr(unclass(value), "row.names", exact = TRUE))
  if (
    length(row_names) == 2L &&
      is.na(row_names[[1L]]) &&
      is.numeric(row_names[[2L]]) &&
      row_names[[2L]] < 0L
  ) {
    return(-row_names[[2L]])
  }
  length(row_names)
}

inspection_safe_list_view <- function(value) {
  if (!is.object(value)) {
    return(if (is.list(value)) value else NULL)
  }
  classes <- class(value)
  if (
    !identical(classes, "data.frame") &&
      !identical(classes, c("tbl_df", "tbl", "data.frame")) &&
      !identical(classes, "AsIs")
  ) {
    return(NULL)
  }
  value <- unclass(value)
  if (!is.list(value)) {
    return(NULL)
  }
  attributes(value) <- list(names = names(value))
  value
}

inspection_content_scan <- function(
  value,
  max_depth = 64L,
  max_nodes = floor(inspection_duration_projection_budget / 64)
) {
  state <- new.env(parent = emptyenv())
  state$nodes <- 0L
  state$exhausted <- FALSE
  visit <- function(current, depth) {
    state$nodes <- state$nodes + 1L
    if (state$nodes > max_nodes || depth > max_depth) {
      state$exhausted <- TRUE
      return(FALSE)
    }
    if (inherits(current, "ellmer::Content")) {
      return(TRUE)
    }
    current_view <- inspection_safe_list_view(current)
    if (is.null(current_view)) {
      return(FALSE)
    }
    for (item in current_view) {
      found <- visit(item, depth + 1L)
      if (found || isTRUE(state$exhausted)) {
        return(found)
      }
    }
    FALSE
  }
  list(
    found = visit(value, 0L),
    exhausted = state$exhausted
  )
}

inspection_duration_shape_supported <- function(value) {
  if (!inherits(value, "difftime") || length(class(value)) != 1L) {
    return(FALSE)
  }
  units <- attr(value, "units", exact = TRUE)
  if (
    !is.character(units) ||
      is.object(units) ||
      length(units) != 1L ||
      is.na(units)
  ) {
    return(FALSE)
  }
  if (!units %in% c("secs", "mins", "hours", "days", "weeks")) {
    return(FALSE)
  }
  attributes <- attributes(value)
  if (!all(names(attributes) %in% c("class", "units"))) {
    return(FALSE)
  }
  values <- unclass(value)
  is.numeric(values) && !is.object(values)
}

inspection_duration_supported <- function(value) {
  if (!inspection_duration_shape_supported(value)) {
    return(FALSE)
  }
  values <- unclass(value)
  !any(is.nan(values) | is.infinite(values))
}

inspection_duration_projection <- function(value) {
  if (inherits(value, "difftime")) {
    if (!inspection_duration_supported(value)) {
      return(inspection_duration_omission)
    }
    return(list(
      value = as.double(unclass(value)),
      units = attr(value, "units", exact = TRUE)
    ))
  }
  if (is.data.frame(value)) {
    columns <- unclass(value)
    column_names <- unclass(attr(columns, "names", exact = TRUE))
    row_names <- unclass(attr(columns, "row.names", exact = TRUE))
    rows <- inspection_data_frame_rows(value)
    # Compact row names can claim an arbitrary number of rows without
    # allocating the row names vector. Apply the disclosure-sized observation
    # preflight before any row-wise repetition or lapply().
    if (
      !isTRUE(tryCatch(
        observation_payload_fits(
          value,
          inspection_duration_projection_budget,
          duration_projection = TRUE
        ),
        error = function(error) FALSE
      ))
    ) {
      return(inspection_duration_omission)
    }
    columns <- lapply(columns, function(column) {
      if (inherits(column, "difftime")) {
        projected <- inspection_duration_projection(column)
        if (identical(projected, inspection_duration_omission)) {
          return(rep(inspection_duration_omission, rows))
        }
        values <- projected$value
        units <- projected$units
        if (length(values) != rows) {
          return(rep(inspection_duration_omission, rows))
        }
        return(lapply(seq_len(rows), function(index) {
          list(
            value = if (is.na(values[[index]])) NA_real_ else values[[index]],
            units = units
          )
        }))
      }
      if (is.data.frame(column)) {
        if (inspection_data_frame_rows(column) != rows) {
          return(rep(inspection_duration_omission, rows))
        }
        return(inspection_duration_projection(column))
      }
      as_is <- inherits(column, "AsIs")
      if (
        is.list(column) &&
          (!is.object(column) || as_is) &&
          !inherits(column, "POSIXlt")
      ) {
        raw_column <- if (as_is) unclass(column) else column
        if (length(raw_column) != rows) {
          return(rep(inspection_duration_omission, rows))
        }
        return(lapply(
          seq_len(rows),
          function(index) inspection_duration_projection(raw_column[[index]])
        ))
      }
      column
    })
    return(structure(
      columns,
      names = column_names,
      row.names = row_names,
      class = "data.frame"
    ))
  }
  as_is <- inherits(value, "AsIs")
  if (
    is.list(value) &&
      (!is.object(value) || as_is) &&
      !inherits(value, "POSIXlt")
  ) {
    raw_value <- if (as_is) unclass(value) else value
    return(lapply(raw_value, inspection_duration_projection))
  }
  value
}

inspection_duration_json <- function(value) {
  projected <- inspection_duration_projection(value)
  if (identical(projected, inspection_duration_omission)) {
    return(inspection_duration_omission)
  }
  as.character(jsonlite::toJSON(
    projected,
    dataframe = "rows",
    auto_unbox = TRUE,
    null = "null",
    na = "null"
  ))
}

inspection_classed_value_json <- function(value) {
  if (inherits(value, "difftime") || is.data.frame(value)) {
    return(inspection_duration_json(value))
  }
  as.character(jsonlite::toJSON(
    value,
    dataframe = "rows",
    auto_unbox = TRUE,
    null = "null",
    na = "null"
  ))
}

# Preserve released ellmer Content records; omit provider-private payloads,
# hidden thinking and executable tool definitions. A tool result's `extra`
# keeps only its approved display and provenance projection.
inspection_record_turn <- function(turn) {
  turn <- portable_session_turns(list(turn))[[1L]]
  if ("json" %in% S7::prop_names(turn)) {
    turn@json <- list()
  }
  clean <- function(content) {
    if (inherits(content, "ellmer::ContentThinking")) {
      return(NULL)
    }
    if (inherits(content, "ellmer::Content")) {
      if ("extra" %in% S7::prop_names(content)) {
        display <- if (inherits(content, "ellmer::ContentToolResult")) {
          tool_display_projection(content)
        }
        content@extra <- if (is.null(display)) {
          list()
        } else {
          list(deputy_display = display)
        }
      }
      if (inherits(content, "ellmer::ContentToolRequest")) {
        content@tool <- NULL
      }
      if (inherits(content, "ellmer::ContentToolResult")) {
        if (inherits(content@error, "condition")) {
          content@error <- conditionMessage(content@error)
        }
        if (!is.null(content@request)) {
          content@request <- clean(content@request)
        }
        content@value <- clean(content@value)
      }
    } else {
      safe_view <- inspection_safe_list_view(content)
      if (!is.null(safe_view) && is.object(content)) {
        scan <- inspection_content_scan(content)
        if (isTRUE(scan$found)) {
          return(lapply(safe_view, clean))
        }
        if (isTRUE(scan$exhausted)) {
          return(
            "[Unsupported tool payload omitted from retained history.]"
          )
        }
      }
      if (
        is.data.frame(content) ||
          is.factor(content) ||
          inherits(content, c("Date", "POSIXt", "difftime"))
      ) {
        content <- inspection_classed_value_json(content)
      } else if (is.object(content)) {
        # Unknown application classes have no portable public record contract.
        # Do not execute their format/record methods or lose sibling histories.
        content <- "[Unsupported tool payload omitted from retained history.]"
      } else if (is.list(content) && !is.object(content)) {
        content <- lapply(
          Filter(function(x) !inherits(x, "ellmer::ContentThinking"), content),
          clean
        )
      }
    }
    content
  }
  turn@contents <- Filter(Negate(is.null), lapply(turn@contents, clean))
  if ("cost" %in% S7::prop_names(turn)) {
    turn@cost <- as.numeric(turn@cost)
  }
  record <- inspection_record_content(turn)
  inspection_portable(record)
  record
}

# Mark genuinely typed tool values before serializing; application objects can
# legitimately have the same field names as an ellmer record.
inspection_record_content <- function(content) {
  # Tool arguments are JSON data, never nested native content. Validate them
  # before recording can turn an S7 object into an ordinary data record.
  if (inherits(content, "ellmer::ContentToolRequest")) {
    approval_portable(content@arguments)
    approval_json_inputs(content@arguments)
  }
  record <- ellmer::contents_record(content)
  if (inherits(content, "ellmer::ContentToolResult")) {
    # The approved projection travels beside the ellmer props, so `extra`
    # itself stays empty and nothing else in it can be recorded.
    display <- tool_display_validate(record$props$extra$deputy_display)
    record$props$extra <- list()
    if (!is.null(display)) {
      record$deputy_display <- display
    }
  }
  for (field in names(record$props)) {
    value <- S7::prop(content, field)
    if (inherits(value, "S7_object")) {
      record$props[[field]] <- inspection_record_content(value)
    } else if (
      is.list(value) &&
        length(value) &&
        all(vapply(value, inherits, logical(1), "S7_object"))
    ) {
      record$props[[field]] <- lapply(value, inspection_record_content)
    }
  }
  if (inherits(content, "ellmer::ContentToolResult")) {
    paths <- list()
    record_value <- function(value, path = integer()) {
      if (inherits(value, "ellmer::Content")) {
        paths[[length(paths) + 1L]] <<- path
        return(inspection_record_content(value))
      }
      current_view <- inspection_safe_list_view(value)
      if (!is.null(current_view)) {
        value <- current_view
      }
      if (is.list(value) && !is.object(value)) {
        for (i in seq_along(value)) {
          value[i] <- list(record_value(value[[i]], c(path, i)))
        }
      }
      value
    }
    record$props$value <- record_value(content@value)
    record$deputy_value_kind <- "marked"
    record$deputy_content_paths <- paths
  }
  record
}

inspection_replay <- function(record, sanitize = FALSE) {
  allowed <- paste0(
    "ellmer::",
    c(
      "UserTurn",
      "AssistantTurn",
      "AssistantPartialTurn",
      "SystemTurn",
      "ContentText",
      "ContentJson",
      "ContentUploaded",
      "ContentImageInline",
      "ContentImageRemote",
      "ContentPDF",
      "ContentDocument",
      "ContentToolRequest",
      "ContentToolResult",
      "ContentCitation",
      "ContentToolRequestSearch",
      "ContentToolResponseSearch",
      "ContentToolRequestFetch",
      "ContentToolResponseFetch",
      "Source",
      "WebSource"
    )
  )
  inspection_portable(record)
  reject_hidden_record <- function(value) {
    if (!is.list(value)) {
      return(invisible(NULL))
    }
    if (
      identical(value$class, "ellmer::ContentThinking") &&
        all(c("version", "class", "props") %in% names(value))
    ) {
      cli::cli_abort(
        "Untyped tool data cannot contain private thinking records."
      )
    }
    lapply(value, reject_hidden_record)
    invisible(NULL)
  }
  replay <- function(x) {
    if (!is.list(x) || !all(c("version", "class", "props") %in% names(x))) {
      cli::cli_abort("Invalid inspection content record.")
    }
    if (!identical(x$version, 1) && !identical(x$version, 1L)) {
      cli::cli_abort("Unsupported ellmer content record version.")
    }
    if (isTRUE(sanitize) && identical(x$class, "ellmer::ContentThinking")) {
      return(NULL)
    }
    if (
      !is.character(x$class) || length(x$class) != 1L || !x$class %in% allowed
    ) {
      cli::cli_abort("Unsupported inspection content class.")
    }
    props <- x$props
    if (isTRUE(sanitize)) {
      # Only typed content positions reach replay(). Opaque tool data keeps its
      # meaning, while executable/private properties are never reconstructed.
      props$tool <- NULL
      if ("extra" %in% names(props)) {
        props$extra <- list()
      }
      if ("json" %in% names(props)) {
        props$json <- list()
      }
      if (identical(x$class, "ellmer::ContentToolRequest")) {
        reject_hidden_record(props$arguments)
      }
    }
    if (
      !is.null(props$tool) ||
        length(props$extra) > 0L ||
        length(props$json) > 0L
    ) {
      cli::cli_abort(
        "Inspection history cannot restore executable or private content."
      )
    }
    if (
      x$class %in%
        paste0(
          "ellmer::",
          c("UserTurn", "AssistantTurn", "AssistantPartialTurn", "SystemTurn")
        )
    ) {
      props$contents <- Filter(Negate(is.null), lapply(props$contents, replay))
    }
    if (identical(x$class, "ellmer::ContentToolResult")) {
      if (!is.null(props$request)) {
        props$request <- replay(props$request)
      }
      kind <- x$deputy_value_kind %||% "data"
      if (!kind %in% c("content", "contents", "data", "marked")) {
        cli::cli_abort("Invalid tool payload kind.")
      }
      props$value <- switch(
        kind,
        content = replay(props$value),
        contents = lapply(props$value, replay),
        data = props$value,
        marked = {
          restore_path <- function(value, path) {
            if (!length(path)) {
              return(replay(value))
            }
            index <- path[[1L]]
            if (
              !is.list(value) ||
                !is.numeric(index) ||
                length(index) != 1L ||
                is.na(index) ||
                index < 1L ||
                index > length(value) ||
                index != as.integer(index)
            ) {
              cli::cli_abort("Invalid tool content position.")
            }
            value[index] <- list(restore_path(value[[index]], path[-1L]))
            value
          }
          value <- props$value
          for (path in x$deputy_content_paths) {
            value <- restore_path(value, path)
          }
          value
        }
      )
      if (isTRUE(sanitize)) {
        # Resolve typed positions first, then reject private record shapes left
        # in opaque data. Caller-supplied markers cannot exempt unmarked data.
        reject_hidden_record(props$value)
      }
    }
    if (
      identical(x$class, "ellmer::ContentCitation") && !is.null(props$source)
    ) {
      props$source <- replay(props$source)
    }
    if (identical(x$class, "ellmer::ContentToolResponseSearch")) {
      props$sources <- lapply(props$sources, replay)
    }
    # The native constructor must never interpret opaque application objects as
    # record envelopes. Restore list-valued properties only after construction.
    safe <- x
    safe$version <- 1
    safe$props <- props
    for (field in names(props)) {
      if (is.list(props[[field]]) || inherits(props[[field]], "S7_object")) {
        safe$props[field] <- list(
          if (field %in% c("request", "source")) NULL else list()
        )
      }
    }
    out <- ellmer::contents_replay(safe, tools = list())
    for (field in names(props)) {
      S7::prop(out, field) <- props[[field]]
    }
    if (identical(x$class, "ellmer::ContentToolResult")) {
      display <- tool_display_validate(x$deputy_display)
      if (!is.null(display)) {
        S7::prop(out, "extra") <- tool_display_extra(display)
      }
    }
    out
  }
  replay(record)
}

# Budget traversal itself as well as the data. Inspect shared values without
# materializing public records or serializing large payloads on the runtime path.
observation_payload_fits <- function(
  value,
  max_bytes,
  duration_projection = FALSE
) {
  remaining <- max_bytes
  visit <- function(value, depth = 0L, json = FALSE) {
    # Classed values become JSON text before the final envelope is serialized.
    # Every input byte may require a six-byte Unicode escape in that projection.
    json <- json || is.data.frame(value) || is.factor(value)
    remaining <<- remaining - 64
    if (remaining < 0 || depth > 64L) {
      return(FALSE)
    }
    if (duration_projection && is.object(value)) {
      # Projection calls JSON only for known data shapes. Reject application
      # classes before any generic length/format method can be dispatched.
      classes <- class(value)
      known <- list(
        "factor",
        c("ordered", "factor"),
        "Date",
        c("POSIXct", "POSIXt"),
        c("POSIXlt", "POSIXt"),
        c("AsIs", "POSIXct", "POSIXt"),
        c("AsIs", "POSIXlt", "POSIXt")
      )
      container <- !inherits(value, c("Date", "POSIXt")) &&
        (is.data.frame(value) ||
          (inherits(value, "AsIs") && is.list(unclass(value))))
      if (
        !container &&
          !inherits(value, "difftime") &&
          !any(vapply(known, identical, logical(1), classes))
      ) {
        return(FALSE)
      }
    }
    if (is.null(value) || inherits(value, "ellmer::ContentThinking")) {
      return(TRUE)
    }
    if (inherits(value, "condition")) {
      return(visit(inspection_text(conditionMessage(value), 1024L), depth + 1L))
    }
    if (inherits(value, "difftime")) {
      values <- unclass(value)
      value_count <- length(values)
      repeats <- if (json) max(1L, value_count) else 1L
      if (!inspection_duration_shape_supported(value)) {
        remaining <<- remaining -
          nchar(inspection_duration_omission, type = "bytes") *
            6 *
            repeats
        return(remaining >= 0)
      }
      units <- attr(value, "units", exact = TRUE)
      # Duration values are projected as one numeric vector plus one units
      # field. Data-frame rows repeat the units field, so charge the escaped
      # units text once per value while still avoiding its materialization.
      unit_bytes <- nchar(units, type = "bytes") * 6 + 16
      value_bytes <- max(1L, value_count) * 32
      if (json) {
        unit_bytes <- unit_bytes * max(1L, value_count)
      }
      if (remaining - 128 - unit_bytes - value_bytes < 0) {
        return(FALSE)
      }
      if (!inspection_duration_supported(value)) {
        remaining <<- remaining -
          nchar(inspection_duration_omission, type = "bytes") *
            6 *
            repeats
        return(remaining >= 0)
      }
      remaining <<- remaining - 128 - unit_bytes - value_bytes
      return(remaining >= 0)
    }
    if (inherits(value, "S7_object")) {
      fields <- setdiff(S7::prop_names(value), c("tool", "extra", "json"))
      if (inherits(value, "ellmer::Turn")) {
        fields <- setdiff(fields, c("text", "role"))
      }
      for (field in fields) {
        if (!visit(S7::prop(value, field), depth + 1L, json = json)) {
          return(FALSE)
        }
      }
      return(TRUE)
    }
    for (field in c("names", "dim", "dimnames", "levels")) {
      metadata <- attr(value, field, exact = TRUE)
      if (!is.null(metadata) && !visit(metadata, depth + 1L, json = json)) {
        return(FALSE)
      }
    }
    if (inherits(value, c("Date", "POSIXt"))) {
      # Timestamp JSON needs quotes, separators, date/time, fractional seconds
      # and zone text. Charge a conservative rendered allowance before format().
      raw <- unclass(value)
      count <- length(raw)
      if (inherits(value, "POSIXlt")) {
        # POSIXlt is a list of component vectors, not a vector of timestamps.
        if (count * 64 > remaining) {
          return(FALSE)
        }
        count <- 0L
        for (component in raw) {
          count <- max(count, length(unclass(component)))
        }
      }
      remaining <<- remaining - 64 * count
      return(remaining >= 0)
    }
    if (is.data.frame(value)) {
      columns <- unclass(value)
      row_bytes <- sum(6 * nchar(names(columns), type = "bytes") + 8)
      if (duration_projection) {
        # A malformed short column can repeat an omission for every declared
        # row. Charge that expansion in this shared recursive budget before
        # allocating it; nested frames and sibling columns share the allowance.
        expands <- vapply(
          columns,
          function(column) {
            inherits(column, "difftime") ||
              is.data.frame(column) ||
              (is.list(column) &&
                (!is.object(column) || inherits(column, "AsIs")) &&
                !inherits(column, "POSIXlt"))
          },
          logical(1)
        )
        row_bytes <- row_bytes + 128 * sum(expands)
      }
      remaining <<- remaining - inspection_data_frame_rows(value) * row_bytes
      if (remaining < 0) return(FALSE)
    }
    list_container <- is.data.frame(value) || inherits(value, "AsIs")
    list_value <- if (list_container) unclass(value) else value
    if (is.list(list_value) && (!is.object(list_value) || list_container)) {
      if (length(list_value) * 64 > remaining) {
        return(FALSE)
      }
      for (item in list_value) {
        if (!visit(item, depth + 1L, json = json)) return(FALSE)
      }
      return(TRUE)
    }
    if (is.character(value)) {
      if (length(unclass(value)) * 16 > remaining) {
        return(FALSE)
      }
      for (item in value) {
        remaining <<- remaining -
          16 -
          if (is.na(item)) {
            0
          } else {
            nchar(item, type = "bytes") * if (json) 6 else 1
          }
        if (remaining < 0) return(FALSE)
      }
      return(TRUE)
    }
    if (is.factor(value)) {
      if (length(unclass(value)) * 16 > remaining) {
        return(FALSE)
      }
      labels <- attr(value, "levels", exact = TRUE)
      for (code in unclass(value)) {
        label <- if (is.na(code)) NA_character_ else labels[[code]]
        if (!visit(label, depth + 1L, json = TRUE)) return(FALSE)
      }
      return(TRUE)
    }
    if (is.atomic(value)) {
      remaining <<- remaining -
        length(unclass(value)) * if (is.raw(value)) 1 else 16
      return(remaining >= 0)
    }
    FALSE
  }
  visit(value)
}
