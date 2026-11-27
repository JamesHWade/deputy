# Shiny-independent Markdown sanitization and nested content projection -------

# Keep tool requests and results in the same assistant message so shinychat's
# native tool cards can match them, including results carried by user turns.
subagent_chat_messages <- function(turns) {
  messages <- list()
  for (turn in turns) {
    if (inherits(turn, "ellmer::UserTurn")) {
      is_result <- vapply(
        turn@contents,
        function(x) inherits(x, "ellmer::ContentToolResult"),
        logical(1)
      )
      if (any(is_result)) {
        results <- turn
        results@contents <- lapply(
          turn@contents[is_result],
          subagent_chat_safe_content
        )
        content <- shinychat::contents_shinychat(results)
        last <- length(messages)
        if (last && identical(messages[[last]]$role, "assistant")) {
          messages[[last]]$content <- c(messages[[last]]$content, content)
        } else {
          messages[[last + 1L]] <- list(role = "assistant", content = content)
        }
        turn@contents <- turn@contents[!is_result]
      }
      role <- "user"
    } else {
      role <- "assistant"
    }
    # Native user messages are plain text; only assistant messages use Markdown.
    if (identical(role, "assistant")) {
      turn@contents <- lapply(turn@contents, subagent_chat_safe_content)
    }
    content <- shinychat::contents_shinychat(turn)
    if (!length(content)) {
      next
    }
    last <- length(messages)
    if (last && identical(messages[[last]]$role, role)) {
      messages[[last]]$content <- c(messages[[last]]$content, content)
    } else {
      messages[[last + 1L]] <- list(role = role, content = content)
    }
  }
  messages
}

# Render Markdown once, then rebuild only inert HTML. Sanitizing the rendered
# tree preserves literal characters in inline, fenced and indented code.
subagent_chat_markdown <- function(text) {
  if (!nzchar(text)) {
    return("")
  }
  html <- commonmark::markdown_html(text, extensions = TRUE)
  document <- xml2::read_html(paste0("<html><body>", html, "</body></html>"))
  allowed <- c(
    "p",
    "br",
    "hr",
    "pre",
    "code",
    "em",
    "strong",
    "del",
    "blockquote",
    "ul",
    "ol",
    "li",
    paste0("h", 1:6),
    "a",
    "img",
    "table",
    "thead",
    "tbody",
    "tr",
    "th",
    "td"
  )
  safe_url <- function(value) {
    scheme <- gsub("[[:space:][:cntrl:]]", "", value)
    !grepl(":", sub("[/?#].*$", "", scheme)) ||
      grepl("^(https?|mailto):", scheme, ignore.case = TRUE)
  }
  render <- function(node) {
    if (identical(xml2::xml_type(node), "text")) {
      return(xml2::xml_text(node))
    }
    name <- xml2::xml_name(node)
    if (!name %in% allowed) {
      # Unknown markup is visible as text, never sent as executable HTML.
      return(as.character(node))
    }
    attributes <- as.list(xml2::xml_attrs(node))
    attributes <- attributes[intersect(names(attributes), c("title", "alt"))]
    url_field <- switch(name, a = "href", img = "src", NULL)
    if (!is.null(url_field)) {
      url <- xml2::xml_attr(node, url_field)
      if (!is.na(url) && safe_url(url)) attributes[[url_field]] <- url
    }
    if (identical(name, "code")) {
      language <- xml2::xml_attr(node, "class")
      if (!is.na(language) && grepl("^language-[a-zA-Z0-9_-]+$", language)) {
        attributes$class <- language
      }
    }
    if (identical(name, "ol")) {
      start <- xml2::xml_attr(node, "start")
      if (!is.na(start) && grepl("^[0-9]+$", start)) attributes$start <- start
    }
    children <- lapply(xml2::xml_contents(node), render)
    htmltools::tag(name, c(attributes, children))
  }
  body <- xml2::xml_find_first(document, "//body")
  as.character(htmltools::tagList(lapply(xml2::xml_contents(body), render)))
}

# The released shinychat renderer only recognises Content objects at the
# immediate value-list level. Keep the retained value as-is, but flatten a
# nested presentation copy into labelled Content leaves so that native
# attachments and Markdown still use shinychat's public conversion APIs.
subagent_chat_nested_list_view <- function(value) {
  inspection_safe_list_view(value)
}

subagent_chat_has_nested_content <- function(
  value,
  depth = 0L,
  max_depth = 8L,
  max_nodes = 256L
) {
  state <- new.env(parent = emptyenv())
  state$nodes <- 0L
  state$exhausted <- FALSE
  visit <- function(current, current_depth) {
    state$nodes <- state$nodes + 1L
    if (state$nodes > max_nodes) {
      state$exhausted <- TRUE
      return(FALSE)
    }
    if (current_depth > max_depth) {
      state$exhausted <- TRUE
      return(FALSE)
    }
    if (inherits(current, "ellmer::Content")) {
      return(current_depth >= 2L)
    }
    current_view <- subagent_chat_nested_list_view(current)
    if (is.null(current_view)) {
      return(FALSE)
    }
    for (item in current_view) {
      found <- visit(item, current_depth + 1L)
      if (found) {
        return(TRUE)
      }
      if (isTRUE(state$exhausted)) {
        break
      }
    }
    FALSE
  }
  visit(value, depth)
}

subagent_chat_limit_text <- function(text, max_bytes = 512L) {
  text <- as.character(text %||% "")
  if (!length(text) || is.na(text[[1L]])) {
    text <- ""
  } else {
    text <- enc2utf8(text[[1L]])
  }
  if (nchar(text, type = "bytes") <= max_bytes) {
    return(text)
  }
  suffix <- "..."
  width <- max(1L, max_bytes - nchar(suffix, type = "bytes"))
  text <- substr(text, 1L, width)
  while (nchar(text, type = "bytes") > width && nzchar(text)) {
    text <- substr(text, 1L, nchar(text) - 1L)
  }
  paste0(text, suffix)
}

subagent_chat_nested_path <- function(path, names, index) {
  name <- if (!is.null(names) && length(names) >= index) {
    names[[index]]
  } else {
    NULL
  }
  if (!is.null(name) && !is.na(name) && nzchar(name)) {
    name <- subagent_chat_limit_text(name, 128L)
    if (nzchar(path)) {
      return(subagent_chat_limit_text(paste(path, name, sep = ".")))
    }
    return(name)
  }
  subagent_chat_limit_text(paste0(path, "[", index, "]"))
}

subagent_chat_nested_value_text <- function(value) {
  if (is.null(value)) {
    return("null")
  }
  if (
    subagent_chat_nested_value_supported(value) &&
      (is.data.frame(value) ||
        is.factor(value) ||
        inherits(value, c("Date", "POSIXt", "difftime")))
  ) {
    out <- tryCatch(
      inspection_classed_value_json(value),
      error = function(error) NULL
    )
    if (!is.null(out)) {
      return(subagent_chat_limit_text(out, 4096L))
    }
  }
  # Keep ordinary character scalars literal and other atomic data on a bounded
  # JSON path. Do not invoke format or print methods on arbitrary objects.
  if (is.atomic(value) && !is.object(value)) {
    if (
      is.character(value) &&
        length(value) == 1L &&
        !is.na(value[[1L]])
    ) {
      return(subagent_chat_limit_text(value, 4096L))
    }
    out <- tryCatch(
      jsonlite::toJSON(
        value,
        auto_unbox = TRUE,
        pretty = TRUE,
        force = TRUE,
        na = "null"
      ),
      error = function(error) NULL
    )
    if (!is.null(out)) {
      return(subagent_chat_limit_text(out, 4096L))
    }
  }
  if (is.list(value) && !is.object(value) && !length(value)) {
    return(if (is.null(names(value))) "[]" else "{}")
  }
  classes <- class(value)
  if (length(classes)) {
    return(sprintf(
      "[%s value omitted from nested display]",
      paste(classes, collapse = "/")
    ))
  }
  "[value omitted from nested display]"
}

subagent_chat_nested_value_supported <- function(value) {
  state <- new.env(parent = emptyenv())
  state$nodes <- 0L
  supported <- function(value, depth = 0L) {
    state$nodes <- state$nodes + 1L
    if (state$nodes > 256L || depth > 8L) {
      return(FALSE)
    }
    if (inherits(value, "ellmer::Content")) {
      return(TRUE)
    }
    current_view <- subagent_chat_nested_list_view(value)
    if (!is.null(current_view)) {
      if (length(current_view) > 64L) {
        return(FALSE)
      }
      for (item in current_view) {
        if (!supported(item, depth + 1L)) {
          return(FALSE)
        }
      }
      return(TRUE)
    }
    if (!is.object(value)) {
      return(TRUE)
    }
    classes <- class(value)
    known_classes <- list(
      "data.frame",
      c("tbl_df", "tbl", "data.frame"),
      "factor",
      "Date",
      c("POSIXct", "POSIXt"),
      c("POSIXlt", "POSIXt"),
      "difftime"
    )
    if (!any(vapply(known_classes, identical, logical(1), classes))) {
      return(FALSE)
    }
    TRUE
  }
  supported(value)
}

subagent_chat_nested_content_metadata_bytes <- function(content) {
  props <- S7::props(content)
  metadata <- if (inherits(content, "ellmer::ContentPDF")) {
    list(props$type, props$filename)
  } else {
    list(props$mime_type, props$filename)
  }
  sum(vapply(
    metadata,
    function(value) {
      if (
        is.null(value) ||
          !is.character(value) ||
          !length(value) ||
          is.na(value[[1L]])
      ) {
        return(0)
      }
      if (inherits(content, "ellmer::ContentPDF")) {
        return(nchar(value[[1L]], type = "bytes"))
      }
      nchar(subagent_chat_limit_text(value[[1L]]), type = "bytes")
    },
    numeric(1)
  )) +
    64L
}

subagent_chat_nested_content_fits <- function(content, max_bytes) {
  if (
    inherits(content, "ellmer::ContentPDF") ||
      inherits(content, "ellmer::ContentDocument")
  ) {
    return(
      subagent_chat_nested_content_metadata_bytes(content) <= max_bytes
    )
  }
  observation_payload_fits(content, max_bytes)
}

subagent_chat_nested_content_leaf <- function(content) {
  if (
    inherits(content, "ellmer::ContentText") ||
      inherits(content, "ellmer::ContentJson") ||
      inherits(content, "ellmer::ContentImage") ||
      inherits(content, "ellmer::ContentPDF")
  ) {
    if (inherits(content, "ellmer::ContentImageInline")) {
      type <- S7::props(content)$type
      if (
        !is.character(type) ||
          !length(type) ||
          is.na(type[[1L]]) ||
          !grepl("^image/[[:alnum:].+_-]+$", type[[1L]], ignore.case = TRUE)
      ) {
        return(ellmer::ContentText("[Image omitted: unsupported MIME type.]"))
      }
    }
    if (inherits(content, "ellmer::ContentImageRemote")) {
      url <- S7::props(content)$url
      scheme <- gsub("[[:space:][:cntrl:]]", "", url %||% "")
      is_data_image <- grepl(
        "^data:image/[[:alnum:].+_-]+;base64,[A-Za-z0-9+/]*={0,2}$",
        scheme,
        ignore.case = TRUE
      )
      is_http_image <- grepl("^https?://", scheme, ignore.case = TRUE)
      has_scheme <- grepl("^[A-Za-z][A-Za-z0-9+.-]*:", scheme)
      if (
        (!is_data_image && grepl("^data:", scheme, ignore.case = TRUE)) ||
          (has_scheme && !is_data_image && !is_http_image)
      ) {
        return(ellmer::ContentText("[Image omitted: unsupported URL.]"))
      }
    }
    return(content)
  }
  if (inherits(content, "ellmer::ContentDocument")) {
    props <- S7::props(content)
    filename <- subagent_chat_limit_text(props$filename %||% "document")
    mime_type <- subagent_chat_limit_text(
      props$mime_type %||% "application/octet-stream"
    )
    return(ellmer::ContentText(sprintf(
      "[Document: %s (%s)]",
      filename,
      mime_type
    )))
  }
  if (inherits(content, "ellmer::ContentUploaded")) {
    text <- tryCatch(
      ellmer::contents_markdown(content),
      error = function(error) NULL
    )
    return(ellmer::ContentText(text %||% "[Uploaded content]"))
  }
  # A nested request/result is still data from the retained transcript. Show a
  # stable inert marker rather than handing an unsupported Content object to
  # shinychat's ordinary-value coercion.
  if (inherits(content, "ellmer::ContentToolResult")) {
    return(ellmer::ContentText("[Nested tool result omitted from display.]"))
  }
  text <- tryCatch(ellmer::contents_markdown(content), error = function(error) {
    NULL
  })
  if (is.character(text) && length(text) && nzchar(text[[1L]])) {
    return(ellmer::ContentText(text[[1L]]))
  }
  class_name <- sub("^.*::", "", class(content)[[1L]] %||% "Content")
  ellmer::ContentText(sprintf(
    "[%s content omitted from nested display]",
    class_name
  ))
}

subagent_chat_nested_projection <- function(
  value,
  max_depth = 8L,
  max_items = 64L,
  max_bytes = 8192L
) {
  state <- new.env(parent = emptyenv())
  state$output <- list()
  state$items <- 0L
  state$bytes <- 0L
  state$stopped <- FALSE

  item_bytes <- function(item) {
    remaining <- max_bytes - state$bytes - 256L
    if (
      inherits(item, "ellmer::Content") &&
        !subagent_chat_nested_content_fits(item, max(1L, remaining))
    ) {
      return(max_bytes + 1L)
    }
    if (inherits(item, "ellmer::ContentImageInline")) {
      return(nchar(S7::props(item)$data %||% "", type = "bytes"))
    }
    if (inherits(item, "ellmer::ContentImageRemote")) {
      return(nchar(S7::props(item)$url %||% "", type = "bytes"))
    }
    if (
      inherits(item, "ellmer::ContentPDF") ||
        inherits(item, "ellmer::ContentDocument")
    ) {
      return(subagent_chat_nested_content_metadata_bytes(item))
    }
    if (inherits(item, "ellmer::ContentJson")) {
      return(nchar(ellmer::contents_markdown(item), type = "bytes"))
    }
    if (inherits(item, "ellmer::ContentText")) {
      return(nchar(item@text, type = "bytes"))
    }
    nchar(subagent_chat_nested_value_text(item), type = "bytes")
  }

  stop_with_omission <- function(path, reason) {
    if (isTRUE(state$stopped)) {
      return(invisible(FALSE))
    }
    state$stopped <- TRUE
    label <- if (nzchar(path)) paste0("Path: ", path, "\n") else ""
    state$output[[length(state$output) + 1L]] <- ellmer::ContentText(
      paste0(label, "[Additional nested content omitted: ", reason, ".]")
    )
    invisible(TRUE)
  }

  emit <- function(item, path = "") {
    if (isTRUE(state$stopped)) {
      return(FALSE)
    }
    bytes <- item_bytes(item)
    # Reserve enough room for a deterministic omission marker whenever the
    # presentation reaches a global bound.
    if (
      state$items + 1L >= max_items ||
        state$bytes + bytes + 256L > max_bytes
    ) {
      stop_with_omission(path, "the display size or item limit was reached")
      return(FALSE)
    }
    state$output[[length(state$output) + 1L]] <- item
    state$items <- state$items + 1L
    state$bytes <- state$bytes + bytes
    TRUE
  }

  emit_path <- function(path) {
    emit(
      ellmer::ContentText(
        if (nzchar(path)) paste0("Path: ", path) else "Value"
      ),
      path
    )
  }

  walk <- function(current, path = "", depth = 0L) {
    if (isTRUE(state$stopped)) {
      return(invisible(NULL))
    }
    if (depth > max_depth) {
      emit(
        ellmer::ContentText(paste0(
          if (nzchar(path)) paste0("Path: ", path, "\n") else "",
          "[Nested content omitted: maximum depth ",
          max_depth,
          ".]"
        )),
        path
      )
      return(invisible(NULL))
    }
    if (inherits(current, "ellmer::Content")) {
      remaining <- max_bytes - state$bytes - 256L
      if (!subagent_chat_nested_content_fits(current, max(1L, remaining))) {
        stop_with_omission(path, "the content size limit was reached")
        return(invisible(NULL))
      }
      emit_path(path)
      emit(subagent_chat_nested_content_leaf(current), path)
      return(invisible(NULL))
    }
    current_view <- subagent_chat_nested_list_view(current)
    traverse_view <- !is.null(current_view) &&
      (!is.object(current) ||
        subagent_chat_has_nested_content(current, depth = depth))
    if (traverse_view) {
      if (!length(current_view)) {
        emit(
          ellmer::ContentText(paste0(
            if (nzchar(path)) paste0("Path: ", path, "\n") else "",
            if (is.null(names(current_view))) "[]" else "{}"
          )),
          path
        )
        return(invisible(NULL))
      }
      current_names <- names(current_view)
      indexes <- seq_len(min(length(current_view), max_items))
      for (index in indexes) {
        walk(
          current_view[[index]],
          subagent_chat_nested_path(path, current_names, index),
          depth + 1L
        )
        if (isTRUE(state$stopped)) {
          break
        }
      }
      if (!isTRUE(state$stopped) && length(current_view) > length(indexes)) {
        stop_with_omission(path, "the display size or item limit was reached")
      }
      return(invisible(NULL))
    }
    if (!subagent_chat_nested_value_supported(current)) {
      emit(
        ellmer::ContentText(paste0(
          if (nzchar(path)) paste0("Path: ", path, "\n") else "",
          subagent_chat_nested_value_text(current)
        )),
        path
      )
      return(invisible(NULL))
    }
    remaining <- max_bytes - state$bytes - 256L
    if (!observation_payload_fits(current, max(1L, remaining))) {
      stop_with_omission(path, "the content size limit was reached")
      return(invisible(NULL))
    }
    emit(
      ellmer::ContentText(paste0(
        if (nzchar(path)) paste0("Path: ", path, "\n") else "",
        subagent_chat_nested_value_text(current)
      )),
      path
    )
    invisible(NULL)
  }

  walk(value)
  state$output
}

subagent_chat_safe_content <- function(content) {
  if (inherits(content, "ellmer::ContentJson")) {
    content <- ellmer::ContentText(ellmer::contents_markdown(content))
  }
  if (inherits(content, "ellmer::ContentText")) {
    content@text <- subagent_chat_markdown(content@text)
  } else if (inherits(content, "ellmer::ContentToolResult")) {
    # A retained display renders as the tool's card would, with its raw HTML
    # fields rebuilt inert first.
    if (is.list(content@extra$display)) {
      content@extra$display <- subagent_safe_display(content@extra$display)
    }
    value <- content@value
    if (
      inherits(value, "ellmer::ContentText") ||
        inherits(value, "ellmer::ContentJson")
    ) {
      value <- list(value)
    }
    if (is.list(value) && subagent_chat_has_nested_content(value)) {
      value <- subagent_chat_nested_projection(value)
    }
    # Native tool cards display plain values and errors as code. Only mixed
    # Content lists use Markdown for their text items.
    if (
      is.list(value) &&
        any(vapply(value, inherits, logical(1), "ellmer::Content"))
    ) {
      content@value <- lapply(value, function(item) {
        if (inherits(item, "ellmer::Content")) {
          subagent_chat_safe_content(item)
        } else {
          subagent_chat_markdown(paste(as.character(item), collapse = "\n"))
        }
      })
    }
  }
  content
}
