# Approved, bounded display and provenance evidence for tool results.
#
# A tool result's `extra` mixes what a host shows the user (shinychat's
# `display`), what a producer records about where a value came from (Commons'
# `commons_tag`) and provider or application data that must never leave the
# runtime. Inspection keeps only an approved, versioned projection of the first
# two: plain text and flags within fixed sizes, with explicit markers for what
# was left out. Executable objects, HTML dependencies and unknown fields are
# never carried. Replay rebuilds `extra` from a validated projection only.

tool_display_format <- "deputy_tool_display"
tool_display_version <- 1L

# Field limits in bytes. HTML can hold an inline plot, so it gets the most room;
# labels and previews are one-line activity-row text.
tool_display_limits <- c(
  title = 4096,
  icon = 65536,
  html = 2 * 1024^2,
  footer = 65536,
  markdown = 262144,
  text = 262144,
  label = 1024,
  value_preview = 1024
)
tool_display_html_fields <- c("title", "icon", "html", "footer")
tool_display_text_fields <- c("markdown", "text", "label", "value_preview")
tool_display_flag_fields <- c("show_request", "open", "full_screen")
tool_display_fields <- c(
  tool_display_html_fields,
  tool_display_text_fields,
  tool_display_flag_fields,
  "open_style"
)

# Provenance a producer attaches beside its display. Each value is one short
# token: a label, never evidence of trust on its own.
tool_display_provenance_fields <- "commons_tag"
tool_display_provenance_pattern <- "^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$"

tool_display_marker_names <- function(names, limit = 16L) {
  names <- unique(as.character(names))
  names <- names[!is.na(names) & nzchar(names)]
  utils::head(
    vapply(
      names,
      inspection_text,
      character(1),
      bytes = 64L,
      USE.NAMES = FALSE
    ),
    limit
  )
}

# Walk a tag tree without dispatching methods on application objects, checking
# everything rendering reads. Every object must have exactly the class htmltools
# gives it and is read only after `unclass()`, so no `$`, `names()` or
# `length()` method of a subclass runs. Rendering also reads three attributes of
# any node: its attached dependencies (calling any that are functions), its
# singleton flag and a string's `noWS`; each must be plain data. Every value
# rendering writes out counts toward `state$bytes` by a bound found without
# converting it, so a compact sequence such as `1:1e8` is never expanded.
tool_display_plain_tags <- function(x, depth = 0L, state = NULL) {
  state <- state %||% tool_display_walk_state()
  state$nodes <- state$nodes + 1L
  if (state$nodes > 4096L || depth > 64L) {
    return(FALSE)
  }
  if (is.null(x)) {
    return(TRUE)
  }
  class <- oldClass(x)
  if (identical(class, "html_dependency")) {
    return(tool_display_dependency(x, depth, state))
  }
  if (!tool_display_node_attributes(x, depth, state)) {
    return(FALSE)
  }
  if (is.character(x)) {
    if (!is.null(class) && !identical(class, tool_display_html_class)) {
      return(FALSE)
    }
    tool_display_count(state, unclass(x))
    return(TRUE)
  }
  if (identical(class, "shiny.tag")) {
    # An environment or function carrying the class can't be read as a tag.
    if (!is.list(x)) {
      return(FALSE)
    }
    tag <- unclass(x)
    # Render hooks run arbitrary R code when the tag is rendered.
    if (
      !all(names(tag) %in% c("name", "attribs", "children", ".noWS")) ||
        !is.character(tag$name) ||
        is.object(tag$name) ||
        length(tag$name) != 1L ||
        !tool_display_no_ws(tag$.noWS)
    ) {
      return(FALSE)
    }
    # The name is written twice, opening and closing the element.
    tool_display_count(state, c(tag$name, tag$name))
    attribs <- tag$attribs
    if (!is.null(attribs) && (!is.list(attribs) || is.object(attribs))) {
      return(FALSE)
    }
    tool_display_count(state, names(attribs))
    for (value in attribs) {
      html <- is.character(value) &&
        identical(oldClass(value), tool_display_html_class)
      if (!html && !is.null(value) && (!is.atomic(value) || is.object(value))) {
        return(FALSE)
      }
      tool_display_count(state, unclass(value))
    }
    return(tool_display_plain_tags(tag$children, depth + 1L, state))
  }
  if (
    is.list(x) &&
      (is.null(class) || identical(class, c("shiny.tag.list", "list")))
  ) {
    return(all(vapply(
      unclass(x),
      tool_display_plain_tags,
      logical(1),
      depth = depth + 1L,
      state = state
    )))
  }
  FALSE
}

tool_display_html_class <- c("html", "character")

tool_display_walk_state <- function(limit = Inf) {
  state <- new.env(parent = emptyenv())
  state$nodes <- 0L
  state$bytes <- 0
  state$limit <- limit
  state
}

# Rendering converts each element of a value to text and joins them. This adds
# an upper bound on those bytes without converting anything: strings are
# measured only while the walk is within its limit, so measuring costs no more
# than the limit allows, and other types count their widest element.
tool_display_count <- function(state, x) {
  n <- length(x)
  if (n == 0L) {
    return(invisible())
  }
  state$bytes <- state$bytes +
    if (is.character(x) && state$bytes + n <= state$limit) {
      # A missing string renders as "NA", or as an attribute with no value.
      bytes <- nchar(x, type = "bytes")
      bytes[is.na(bytes)] <- 2L
      sum(as.numeric(bytes)) + n
    } else {
      n * tool_display_text_widths[[typeof(x)]]
    }
  invisible()
}

# The most bytes one element takes as text, with its separator.
tool_display_text_widths <- c(
  logical = 6,
  integer = 12,
  double = 25,
  complex = 50,
  raw = 3,
  character = 1
)

# The attributes rendering reads from a node. Attached dependencies are called
# when they are functions, `noWS` is matched with `%in%` (converting a value of
# another type in full) and the singleton flag is tested with `isTRUE()`.
tool_display_node_attributes <- function(x, depth, state) {
  singleton <- attr(x, "htmltools.singleton", exact = TRUE)
  dependencies <- attr(x, "html_dependencies", exact = TRUE)
  (is.null(singleton) || tool_display_flag(singleton)) &&
    tool_display_no_ws(attr(x, "noWS", exact = TRUE)) &&
    (is.null(dependencies) ||
      tool_display_dependency(dependencies, depth, state) ||
      (is.list(dependencies) &&
        is.null(oldClass(dependencies)) &&
        all(vapply(
          dependencies,
          function(dependency) {
            is.null(dependency) ||
              tool_display_dependency(dependency, depth, state)
          },
          logical(1)
        ))))
}

# htmltools only ever sets these.
tool_display_no_ws <- function(x) {
  is.null(x) ||
    (is.character(x) &&
      is.null(attributes(x)) &&
      length(x) <= length(tool_display_no_ws_options) &&
      all(x %in% tool_display_no_ws_options))
}

tool_display_no_ws_options <- c(
  "before",
  "after",
  "after-begin",
  "before-end",
  "outside",
  "inside"
)

# A dependency is recorded by name and version. Rendering also resolves its
# package directory, so those fields must be single strings, and everything in
# it plain data. A function standing in for one is never called.
tool_display_dependency <- function(x, depth, state) {
  if (!identical(oldClass(x), "html_dependency") || !is.list(x)) {
    return(FALSE)
  }
  dependency <- unclass(x)
  src <- if (is.list(dependency)) dependency$src
  is.list(dependency) &&
    tool_display_string(dependency$name) &&
    tool_display_string(dependency$version) &&
    (is.null(dependency$package) || tool_display_string(dependency$package)) &&
    (is.null(src) ||
      (is.list(src) &&
        !is.object(src) &&
        (is.null(src$file) || tool_display_string(src$file)))) &&
    tool_display_plain_data(dependency, depth + 1L, state)
}

# Data with no class anywhere: atomic vectors and plain lists.
tool_display_plain_data <- function(x, depth = 0L, state = NULL) {
  state <- state %||% tool_display_walk_state()
  state$nodes <- state$nodes + 1L
  if (state$nodes > 4096L || depth > 64L) {
    return(FALSE)
  }
  if (is.null(x) || (is.atomic(x) && !is.object(x))) {
    return(TRUE)
  }
  is.list(x) &&
    !is.object(x) &&
    all(vapply(
      x,
      tool_display_plain_data,
      logical(1),
      depth = depth + 1L,
      state = state
    ))
}

# One string, plain or htmltools' `html`. A string or flag with any other class
# is never read, since `length()` and `is.na()` would call its methods.
tool_display_string <- function(value, html = FALSE) {
  if (!is.character(value)) {
    return(FALSE)
  }
  class <- oldClass(value)
  if (!is.null(class) && !(html && identical(class, tool_display_html_class))) {
    return(FALSE)
  }
  value <- unclass(value)
  length(value) == 1L && !is.na(value)
}

tool_display_flag <- function(value) {
  is.logical(value) && !is.object(value) && length(value) == 1L && !is.na(value)
}

# Render one HTML-capable display field to text, recording dependencies by name
# rather than carrying their file paths. A tag tree that would render to more
# than `limit` bytes is not rendered, since rendering copies and escapes it all.
tool_display_html_value <- function(value, limit = Inf) {
  if (tool_display_string(value, html = TRUE)) {
    return(list(value = enc2utf8(as.character(unclass(value)))))
  }
  state <- tool_display_walk_state(limit)
  if (
    inherits(value, c("shiny.tag", "shiny.tag.list")) &&
      tool_display_plain_tags(value, state = state)
  ) {
    if (state$bytes > limit) {
      return(list(reason = "oversized"))
    }
    rendered <- tryCatch(
      tool_display_render_tags(value),
      error = function(error) NULL
    )
    if (is.null(rendered)) {
      return(list(reason = "unrenderable"))
    }
    dependencies <- vapply(
      rendered$dependencies,
      function(dependency) {
        paste(dependency$name %||% "unknown", dependency$version %||% "")
      },
      character(1)
    )
    return(list(
      value = enc2utf8(as.character(rendered$html)),
      dependencies = trimws(dependencies)
    ))
  }
  if (is.character(value)) {
    return(list(reason = "invalid"))
  }
  list(reason = "unsupported_object")
}

tool_display_render_tags <- function(value) {
  htmltools::renderTags(value)
}

tool_display_field <- function(field, value) {
  if (field %in% tool_display_flag_fields) {
    if (tool_display_flag(value)) {
      return(list(value = value))
    }
    return(list(reason = "invalid"))
  }
  if (identical(field, "open_style")) {
    if (
      tool_display_string(value) &&
        value %in% c("minimal", "framed")
    ) {
      return(list(value = as.character(value)))
    }
    return(list(reason = "invalid"))
  }
  out <- if (field %in% tool_display_html_fields) {
    tool_display_html_value(value, tool_display_limits[[field]])
  } else if (tool_display_string(value)) {
    list(value = enc2utf8(as.character(value)))
  } else {
    list(reason = if (is.character(value)) "invalid" else "unsupported_object")
  }
  if (
    !is.null(out$value) &&
      nchar(out$value, type = "bytes") > tool_display_limits[[field]]
  ) {
    out <- list(reason = "oversized", dependencies = out$dependencies)
  }
  out
}

# Project a tool result's display and provenance for portable records. Returns
# NULL when the result has nothing to show or record.
tool_display_projection <- function(content) {
  extra <- tryCatch(content@extra, error = function(error) NULL)
  if (!is.list(extra) || is.object(extra) || !length(extra)) {
    return(NULL)
  }
  extra_names <- names(extra) %||% rep("", length(extra))
  omitted <- list()
  unknown <- setdiff(
    extra_names,
    c("display", tool_display_provenance_fields)
  )
  if (length(unknown)) {
    omitted$extra <- tool_display_marker_names(unknown)
  }

  provenance <- list()
  for (field in intersect(tool_display_provenance_fields, extra_names)) {
    value <- extra[[field]]
    if (is.null(value)) {
      next
    }
    if (
      tool_display_string(value) &&
        grepl(tool_display_provenance_pattern, value)
    ) {
      provenance[[field]] <- as.character(value)
    } else {
      omitted$provenance <- c(omitted$provenance, field)
    }
  }

  display <- list()
  # `[[` matches the name exactly; `$` would take `display_private` for it.
  source <- extra[["display"]]
  if (!is.null(source)) {
    # Only a plain list with exactly shinychat's class is a display; an
    # environment or pointer carrying it can't be unclassed.
    if (
      is.list(source) &&
        identical(oldClass(source), "shinychat_tool_result_display")
    ) {
      source <- unclass(source)
    }
    if (!is.list(source) || is.object(source)) {
      omitted$display <- "invalid"
    } else {
      fields <- names(source) %||% rep("", length(source))
      unknown_fields <- setdiff(fields, tool_display_fields)
      if (length(unknown_fields)) {
        omitted$display_fields <- tool_display_marker_names(unknown_fields)
      }
      reasons <- character()
      dependencies <- character()
      for (field in intersect(tool_display_fields, fields)) {
        if (is.null(source[[field]])) {
          next
        }
        projected <- tool_display_field(field, source[[field]])
        dependencies <- c(dependencies, projected$dependencies)
        if (is.null(projected$reason)) {
          display[[field]] <- projected$value
        } else {
          reasons[[field]] <- projected$reason
        }
      }
      if (length(reasons)) {
        omitted$fields <- reasons
      }
      if (length(dependencies)) {
        omitted$dependencies <- tool_display_marker_names(dependencies)
      }
    }
  }

  if (!length(display) && !length(provenance) && !length(omitted)) {
    return(NULL)
  }
  list(
    format = tool_display_format,
    version = tool_display_version,
    display = display,
    provenance = provenance,
    omitted = omitted
  )
}

tool_display_invalid <- function() {
  cli::cli_abort("Invalid tool display record.")
}

tool_display_check_markers <- function(value, named = FALSE) {
  if (
    !is.character(value) ||
      anyNA(value) ||
      length(value) > 16L ||
      any(nchar(value, type = "bytes") > 64L) ||
      (named && (is.null(names(value)) || !all(nzchar(names(value)))))
  ) {
    tool_display_invalid()
  }
  value
}

# Saved history may come from storage the runtime does not control. Only the
# approved fields, types and sizes pass; anything else is an error. A newer
# format version is ignored (NULL) rather than guessed at.
tool_display_validate <- function(record) {
  if (is.null(record)) {
    return(NULL)
  }
  if (
    !is.list(record) ||
      is.object(record) ||
      !identical(record$format, tool_display_format)
  ) {
    tool_display_invalid()
  }
  version <- record$version
  if (
    !is.numeric(version) ||
      length(version) != 1L ||
      is.na(version) ||
      version != floor(version)
  ) {
    tool_display_invalid()
  }
  if (version > tool_display_version) {
    return(NULL)
  }
  if (version < 1) {
    tool_display_invalid()
  }
  if (
    !setequal(
      names(record),
      c("format", "version", "display", "provenance", "omitted")
    )
  ) {
    tool_display_invalid()
  }
  display <- record$display
  if (!is.list(display) || is.object(display)) {
    tool_display_invalid()
  }
  if (length(display)) {
    fields <- names(display)
    if (
      is.null(fields) ||
        anyDuplicated(fields) ||
        !all(fields %in% tool_display_fields)
    ) {
      tool_display_invalid()
    }
    for (field in fields) {
      value <- display[[field]]
      # Attributes are checked first, so no method of a classed value runs.
      valid <- is.null(attributes(value)) &&
        if (field %in% tool_display_flag_fields) {
          tool_display_flag(value)
        } else if (identical(field, "open_style")) {
          tool_display_string(value) && value %in% c("minimal", "framed")
        } else {
          tool_display_string(value) &&
            nchar(value, type = "bytes") <= tool_display_limits[[field]]
        }
      if (!valid) {
        tool_display_invalid()
      }
    }
  }
  provenance <- record$provenance
  if (!is.list(provenance) || is.object(provenance)) {
    tool_display_invalid()
  }
  if (length(provenance)) {
    fields <- names(provenance)
    if (
      is.null(fields) ||
        anyDuplicated(fields) ||
        !all(fields %in% tool_display_provenance_fields)
    ) {
      tool_display_invalid()
    }
    for (value in provenance) {
      if (
        !is.character(value) ||
          length(value) != 1L ||
          is.na(value) ||
          !grepl(tool_display_provenance_pattern, value)
      ) {
        tool_display_invalid()
      }
    }
  }
  omitted <- record$omitted
  if (!is.list(omitted) || is.object(omitted)) {
    tool_display_invalid()
  }
  allowed_markers <- c(
    "extra",
    "provenance",
    "display",
    "display_fields",
    "fields",
    "dependencies"
  )
  if (
    length(omitted) &&
      (is.null(names(omitted)) || !all(names(omitted) %in% allowed_markers))
  ) {
    tool_display_invalid()
  }
  for (name in names(omitted)) {
    tool_display_check_markers(omitted[[name]], named = name == "fields")
  }
  record
}

# Rebuild a tool result's `extra` from a validated projection.
tool_display_extra <- function(projection) {
  if (is.null(projection)) {
    return(list())
  }
  extra <- list()
  if (length(projection$display)) {
    extra$display <- projection$display
  }
  for (field in names(projection$provenance)) {
    extra[[field]] <- projection$provenance[[field]]
  }
  extra
}
