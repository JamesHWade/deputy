#' @include delegation-inspection.R
NULL

#' Set limits for the subagent event buffer
#'
#' Each agent keeps recent subagent events in an in-memory buffer that
#' `$observe_subagents()` readers poll. When it is full, the oldest events are
#' dropped: a slow reader never holds up a run, but sees a gap. Subagent
#' transcripts are kept separately and don't count toward these limits.
#' @param max_events Maximum number of events kept. Defaults to 256.
#' @param max_bytes Maximum total size of the kept events, in bytes. Defaults
#'   to 1 MiB.
#' @param max_event_bytes Maximum size of one event, in bytes: between 2048 and
#'   `max_bytes`, 64 KiB by default. Larger content is replaced by a marker;
#'   get it from a [DelegationSubscription] snapshot instead.
#' @return A `DelegationObservation` object for the `delegation_observation`
#'   argument of [Agent] or [LeadAgent].
#' @export
DelegationObservation <- S7::new_class(
  "DelegationObservation",
  package = "deputy",
  properties = list(
    max_events = readonly_property("max_events", S7::class_integer),
    max_bytes = readonly_property("max_bytes", S7::class_double),
    max_event_bytes = readonly_property("max_event_bytes", S7::class_double)
  ),
  constructor = function(
    max_events = 256L,
    max_bytes = 1024^2,
    max_event_bytes = 65536
  ) {
    max_events <- context_policy_whole_number(max_events, "max_events")
    max_bytes <- context_policy_whole_number(max_bytes, "max_bytes")
    max_event_bytes <- context_policy_whole_number(
      max_event_bytes,
      "max_event_bytes"
    )
    if (
      is.null(max_events) ||
        is.null(max_bytes) ||
        is.null(max_event_bytes) ||
        max_event_bytes < 2048 ||
        max_event_bytes > max_bytes
    ) {
      cli::cli_abort(
        "Observation limits must be finite, with 2048 <= max_event_bytes <= max_bytes."
      )
    }
    value <- S7::new_object(
      S7::S7_object(),
      max_events = as.integer(max_events),
      max_bytes = as.double(max_bytes),
      max_event_bytes = as.double(max_event_bytes)
    )
    freeze_value(value)
  }
)
local({
  S7::method(`$`, DelegationObservation) <- function(x, name) S7::prop(x, name)
})

new_delegation_buffer <- function(policy) {
  buffer <- new.env(parent = emptyenv())
  buffer$stream_id <- new_deputy_id("observation_")
  buffer$sequence <- 0
  buffer$events <- list()
  buffer$sizes <- numeric()
  buffer$policy <- policy
  buffer
}

# Runtime work only appends bounded data. No host subscriber callback is invoked.
lead_observe_event <- function(lead, id, event) {
  private <- lead$.__enclos_env__$private
  buffer <- private$.delegation_buffer
  record <- private$subagent_runs[[id]]
  if (is.null(buffer) || is.null(record)) {
    return(invisible(NULL))
  }
  if (
    event$type == "content" &&
      inherits(event$content, "ellmer::ContentThinking")
  ) {
    return(invisible(NULL))
  }
  buffer$sequence <- buffer$sequence + 1
  envelope <- list(
    sequence = buffer$sequence,
    stream_id = buffer$stream_id,
    delegation_id = id,
    conversation_id = record$session_id,
    agent_id = record$agent_id,
    agent_name = record$agent_name,
    run_id = event$run_id %||% record$run_id,
    parent_agent_id = record$parent_agent_id,
    parent_run_id = record$parent_run_id,
    parent_delegation_id = record$parent_delegation_id,
    depth = record$depth,
    root_agent_id = record$root_agent_id,
    parent_tool_call_id = record$tool_call_id,
    tool_call_id = event$tool_call_id,
    type = event$type,
    timestamp = as.numeric(event$timestamp),
    data = NULL
  )
  # Bound fixed-schema metadata first, then charge its actual serialized size
  # against the same allowance used for payload projection and serialization.
  metadata <- unname(envelope[names(envelope) != "data"])
  if (!observation_payload_fits(metadata, buffer$policy$max_event_bytes)) {
    return(invisible(NULL))
  }
  metadata_bytes <- length(serialize(envelope, NULL, version = 3))
  payload_budget <- buffer$policy$max_event_bytes - metadata_bytes
  if (payload_budget <= 0) {
    return(invisible(NULL))
  }
  payload <- tryCatch(
    observation_payload(event, payload_budget),
    error = function(e) {
      list(content_omitted = "nonportable", recover = "snapshot")
    }
  )
  if (is.null(payload)) {
    return(invisible(NULL))
  }
  # The portable record can add structure to native Content. Check that final
  # projection against the remaining allowance before serializing the envelope.
  if (!observation_payload_fits(payload, payload_budget)) {
    payload <- list(content_omitted = "oversized", recover = "snapshot")
  }
  if (!observation_payload_fits(payload, payload_budget)) {
    return(invisible(NULL))
  }
  envelope$data <- payload
  bytes <- length(serialize(envelope, NULL, version = 3))
  if (bytes > buffer$policy$max_event_bytes) {
    envelope$data <- list(content_omitted = "oversized", recover = "snapshot")
    bytes <- length(serialize(envelope, NULL, version = 3))
  }
  # An extreme host-supplied identity can itself exceed the event allowance.
  # Retain a gap rather than violating the configured memory bound.
  if (bytes > buffer$policy$max_event_bytes) {
    return(invisible(NULL))
  }
  buffer$events[[length(buffer$events) + 1L]] <- envelope
  buffer$sizes <- c(buffer$sizes, bytes)
  while (
    length(buffer$events) > buffer$policy$max_events ||
      sum(buffer$sizes) > buffer$policy$max_bytes
  ) {
    buffer$events <- buffer$events[-1L]
    buffer$sizes <- buffer$sizes[-1L]
  }
  invisible(NULL)
}

observation_payload <- function(event, max_bytes = 65536) {
  if (
    event$type == "content" &&
      inherits(event$content, "ellmer::ContentThinking")
  ) {
    return(NULL)
  }
  data <- event$data
  if (
    event$type %in%
      c("request_error", "run_error", "fallback") &&
      inherits(data$condition, "condition")
  ) {
    data$message <- inspection_text(conditionMessage(data$condition), 1024L)
  }
  # Request/transport objects and conditions may contain credentials. Only public
  # error text is observed, never arbitrary provider objects or call stacks.
  if (
    event$type %in%
      c(
        "request_error",
        "run_error",
        "request_start",
        "request_end",
        "fallback"
      )
  ) {
    data <- data[intersect(
      names(data),
      c(
        "message",
        "phase",
        "request_number",
        "model",
        "provider",
        "fallback_index",
        "usage"
      )
    )]
  }
  if (!observation_payload_fits(data, max_bytes)) {
    return(list(content_omitted = "oversized", recover = "snapshot"))
  }
  public <- function(value) {
    if (inherits(value, "condition")) {
      return(inspection_text(conditionMessage(value), 1024L))
    }
    if (S7::S7_inherits(value, AgentUsage)) {
      return(S7::props(value))
    }
    if (S7::S7_inherits(value, UsageLimits)) {
      return(S7::props(value))
    }
    if (inherits(value, "ellmer::Turn")) {
      return(inspection_record_turn(value))
    }
    if (inherits(value, "ellmer::ContentThinking")) {
      return(NULL)
    }
    if (inherits(value, "ellmer::Content")) {
      turn <- ellmer::AssistantTurn(list(value))
      return(inspection_record_turn(turn)$props$contents[[1L]])
    }
    if (
      is.data.frame(value) ||
        is.factor(value) ||
        inherits(value, c("Date", "POSIXt", "difftime"))
    ) {
      if (inherits(value, "difftime") || is.data.frame(value)) {
        return(inspection_duration_json(value))
      }
      return(as.character(jsonlite::toJSON(
        value,
        dataframe = "rows",
        auto_unbox = TRUE,
        null = "null",
        na = "null"
      )))
    }
    if (inherits(value, "ellmer_dollars")) {
      return(as.numeric(value))
    }
    if (is.list(value) && (!is.object(value) || inherits(value, "AsIs"))) {
      raw_value <- if (inherits(value, "AsIs")) unclass(value) else value
      return(lapply(raw_value, public))
    }
    value
  }
  data <- lapply(data, public)
  inspection_portable(data)
  data
}

lead_observation_error <- function(lead, id, error) {
  private <- lead$.__enclos_env__$private
  record <- private$subagent_runs[[id]]
  record$observation_error <- inspection_text(conditionMessage(error), 1024L)
  private$subagent_runs[[id]] <- record
  invisible(NULL)
}

lead_observe_status <- function(lead, id, type) {
  private <- lead$.__enclos_env__$private
  record <- private$subagent_runs[[id]]
  if (is.function(private$.job_checkpoint)) {
    private$.job_checkpoint(
      lead,
      list(
        type = "delegation_status",
        phase = type,
        delegation_id = id,
        status = record$status,
        stop_reason = record$stop_reason,
        run_id = record$run_id
      )
    )
  }
  tryCatch(
    lead_observe_event(
      lead,
      id,
      AgentEvent(
        type,
        status = record$status,
        stop_reason = record$stop_reason,
        run_id = record$run_id
      )
    ),
    error = function(error) lead_observation_error(lead, id, error)
  )
}

observation_cursor <- function(buffer) {
  list(stream_id = buffer$stream_id, sequence = buffer$sequence)
}

validate_observation_cursor <- function(cursor, buffer) {
  if (
    !is.list(cursor) ||
      !identical(cursor$stream_id, buffer$stream_id) ||
      !is.numeric(cursor$sequence) ||
      length(cursor$sequence) != 1L ||
      is.na(cursor$sequence) ||
      !is.finite(cursor$sequence) ||
      cursor$sequence < 0 ||
      cursor$sequence != floor(cursor$sequence) ||
      cursor$sequence > buffer$sequence
  ) {
    cli::cli_abort("Invalid or foreign child observation cursor.")
  }
  cursor
}

#' Subscription to subagent events
#'
#' Reads an agent's subagent events; create one with
#' `Agent$observe_subagents()`. `$snapshot()` returns the current state and
#' `$poll()` the events since the last read. Reading never affects the
#' subagents, and every read checks access again with the agent's
#' [DelegationDisclosure]. Event sequence numbers count across all of the
#' agent's subagents. A cursor marks a position; it doesn't grant access.
#' @export
DelegationSubscription <- R6::R6Class(
  "DelegationSubscription",
  cloneable = FALSE,
  public = list(
    #' @description Create a subscription, usually through
    #' `Agent$observe_subagents()`.
    #' @param lead The `Agent` or [LeadAgent] to follow.
    #' @param requester Who is reading, passed to the disclosure functions.
    #'   Authenticate it first.
    #' @param delegation_id Optional delegation ID, to follow one subagent.
    #' @param after A cursor from this agent to resume from, or `NULL` to start
    #'   now. A cursor from another agent is an error.
    initialize = function(lead, requester, delegation_id = NULL, after = NULL) {
      if (!inherits(lead, "Agent")) {
        cli::cli_abort("lead must be an Agent.")
      }
      private$lead <- lead
      private$requester <- requester
      private$authorize()
      if (!is.null(delegation_id)) {
        delegation_text(delegation_id, "delegation_id")
      }
      private$delegation_id <- delegation_id
      buffer <- lead$.__enclos_env__$private$.delegation_buffer
      private$position <- validate_observation_cursor(
        after %||% observation_cursor(buffer),
        buffer
      )
      invisible(self)
    },
    #' @description Get the subagents' current state and move the cursor to
    #' now, so the next `$poll()` returns only later events.
    #' @param transcript Whether to include transcripts. Defaults to `FALSE`.
    #' @return A list with `children`, one redacted view per subagent, and
    #'   `cursor`.
    snapshot = function(transcript = FALSE) {
      private$authorize()
      if (
        !is.logical(transcript) || length(transcript) != 1L || is.na(transcript)
      ) {
        cli::cli_abort("transcript must be TRUE or FALSE.")
      }
      lead <- private$lead
      cursor <- observation_cursor(
        lead$.__enclos_env__$private$.delegation_buffer
      )
      children <- lead_inspection_records(
        lead,
        private$delegation_id,
        transcript
      )
      disclosure <- lead$.__enclos_env__$private$.delegation_disclosure
      children <- lapply(children, function(view) {
        result <- disclosure$redact(view, private$requester)
        inspection_portable(result)
        if (!is.list(result)) {
          cli::cli_abort("Disclosure redaction must return a list.")
        }
        result
      })
      out <- inspection_bound(
        list(children = children, cursor = cursor),
        disclosure
      )
      private$position <- cursor
      out
    },
    #' @description Get the events since the last read and advance the cursor.
    #' Ranges of events dropped before you read them are listed in `gaps`;
    #' call `$snapshot()` to catch up. When following one subagent, a gap may
    #' only cover other subagents' events.
    #' @return A list with `events`, `gaps` and `cursor`. Each event goes
    #' through the disclosure `redact` function as
    #' `list(kind = "event", event = event)`; remove `event` to hide it. If
    #' `redact` errors, the cursor doesn't move.
    poll = function() {
      private$authorize()
      lead <- private$lead
      buffer <- lead$.__enclos_env__$private$.delegation_buffer
      cursor <- observation_cursor(buffer)
      retained <- buffer$events
      selected <- Filter(
        function(event) event$sequence > private$position$sequence,
        retained
      )
      observed <- vapply(selected, function(event) event$sequence, numeric(1))
      boundaries <- c(private$position$sequence, observed, cursor$sequence + 1)
      gaps <- lapply(which(diff(boundaries) > 1), function(i) {
        list(from = boundaries[[i]] + 1, to = boundaries[[i + 1L]] - 1)
      })
      disclosure <- lead$.__enclos_env__$private$.delegation_disclosure
      if (!is.null(private$delegation_id)) {
        selected <- Filter(
          function(event) {
            identical(event$delegation_id, private$delegation_id)
          },
          selected
        )
      }
      events <- lapply(selected, function(event) {
        view <- disclosure$redact(
          list(kind = "event", event = event),
          private$requester
        )
        inspection_portable(view)
        if (!is.list(view)) {
          cli::cli_abort("Disclosure redaction must return a list.")
        }
        view$event
      })
      events <- Filter(Negate(is.null), events)
      out <- inspection_bound(
        list(events = events, gaps = gaps, cursor = cursor),
        disclosure
      )
      private$position <- cursor
      out
    },
    #' @description Stop reading; the subagents keep running.
    #' @return `NULL`, invisibly. Later reads error.
    close = function() {
      private$lead <- NULL
      private$requester <- NULL
      invisible(NULL)
    }
  ),
  private = list(
    lead = NULL,
    requester = NULL,
    delegation_id = NULL,
    position = NULL,
    authorize = function() {
      if (is.null(private$lead)) {
        cli::cli_abort("This child observation subscription is closed.")
      }
      inspection_authorize(
        private$lead$.__enclos_env__$private$.delegation_disclosure,
        private$requester,
        inspection_scope(private$lead)
      )
    }
  )
)

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
