# Inert HTML for tool displays shown by the optional Shiny adapter.
#
# shinychat injects a tool display's `title`, `icon`, `footer` and `html` as
# raw HTML. A subagent's display reaches the browser from a retained transcript
# or saved history rather than from the producing tool, so the adapter rebuilds
# it from an allowlist first: structure, classes, inline styles, inline SVG and
# image data stay; scripts, event handlers, embedded documents, forms, external
# style sheets and every URL the browser would fetch do not; only inline data
# images remain. Each display's ids get a prefix of its own, so a display can
# never take over an element id the host page or another card relies on, and a
# `<style>` element is kept only when every rule is scoped to such an id, as gt
# tables are, and holds no nested rules.

subagent_display_elements <- c(
  "a",
  "abbr",
  "article",
  "aside",
  "b",
  "bdi",
  "bdo",
  "blockquote",
  "br",
  "caption",
  "cite",
  "code",
  "col",
  "colgroup",
  "dd",
  "del",
  "details",
  "dfn",
  "div",
  "dl",
  "dt",
  "em",
  "figcaption",
  "figure",
  "footer",
  "h1",
  "h2",
  "h3",
  "h4",
  "h5",
  "h6",
  "header",
  "hr",
  "i",
  "img",
  "ins",
  "kbd",
  "li",
  "main",
  "mark",
  "ol",
  "p",
  "pre",
  "q",
  "s",
  "samp",
  "section",
  "small",
  "span",
  "strong",
  "sub",
  "summary",
  "sup",
  "table",
  "tbody",
  "td",
  "tfoot",
  "th",
  "thead",
  "time",
  "tr",
  "u",
  "ul",
  "var",
  "wbr",
  # Inline SVG, as used for icons and simple charts.
  "svg",
  "g",
  "path",
  "circle",
  "ellipse",
  "line",
  "polyline",
  "polygon",
  "rect",
  "text",
  "tspan",
  "title",
  "desc",
  "defs",
  "lineargradient",
  "radialgradient",
  "stop",
  "clippath"
)

# Removed together with everything inside them.
subagent_display_dropped <- c(
  "script",
  "noscript",
  "template",
  "iframe",
  "frame",
  "frameset",
  "object",
  "embed",
  "applet",
  "form",
  "input",
  "button",
  "select",
  "option",
  "optgroup",
  "textarea",
  "fieldset",
  "legend",
  "label",
  "link",
  "meta",
  "base",
  "head",
  "audio",
  "video",
  "source",
  "track",
  "canvas",
  "math",
  "dialog",
  "slot",
  "foreignobject",
  "animate",
  "animatemotion",
  "animatetransform",
  "set",
  "use",
  "image",
  "feimage",
  "filter",
  "pattern",
  "marker",
  "mask",
  "symbol"
)

subagent_display_attributes <- c(
  "class",
  "title",
  "alt",
  "lang",
  "dir",
  "role",
  "align",
  "valign",
  "width",
  "height",
  "colspan",
  "rowspan",
  "scope",
  "headers",
  "abbr",
  "span",
  "start",
  "reversed",
  "type",
  "open",
  "datetime",
  # SVG presentation and geometry.
  "viewbox",
  "fill",
  "stroke",
  "stroke-width",
  "stroke-linecap",
  "stroke-linejoin",
  "stroke-dasharray",
  "stroke-opacity",
  "fill-opacity",
  "fill-rule",
  "clip-rule",
  "clip-path",
  "d",
  "cx",
  "cy",
  "r",
  "rx",
  "ry",
  "x",
  "y",
  "x1",
  "x2",
  "y1",
  "y2",
  "dx",
  "dy",
  "points",
  "transform",
  "opacity",
  "font-size",
  "font-family",
  "font-weight",
  "font-style",
  "text-anchor",
  "dominant-baseline",
  "preserveaspectratio",
  "focusable",
  "version",
  "offset",
  "stop-color",
  "stop-opacity",
  "gradientunits",
  "gradienttransform"
)

# Each rebuilt display gets its own id prefix, so ids and id-scoped styles
# from one card never reach another.
subagent_display_prefix <- function() {
  paste0(
    "deputy-display-",
    substr(gsub("-", "", new_deputy_id()), 1L, 12L),
    "-"
  )
}

# Rebuilt markup adds no whitespace of its own, so inline content keeps its
# original spacing.
subagent_display_no_whitespace <- c("outside", "inside")

# Attributes whose values a browser can resolve as a reference.
subagent_display_url_attributes <- c("fill", "stroke", "clip-path")

subagent_display_plain <- function(value) {
  gsub("[[:space:][:cntrl:]]", "", tolower(value))
}

# A value is active when it could run script or fetch a resource. Besides
# `url()`, the image functions also fetch a quoted string as a URL.
subagent_display_active <- function(value) {
  plain <- subagent_display_plain(value)
  grepl(
    paste0(
      "javascript:|vbscript:|expression\\(|behavior:|-moz-binding|@import|",
      "image-set\\(|image\\(|cross-fade\\(|element\\(|src\\("
    ),
    plain
  ) |
    grepl("\\\\", value) |
    grepl("url\\((?!['\"]?#)", plain, perl = TRUE)
}

subagent_display_url <- function(value, element) {
  plain <- gsub("[[:space:][:cntrl:]]", "", value)
  if (identical(element, "img")) {
    return(
      grepl(
        "^data:image/(png|jpe?g|gif|webp|bmp|svg\\+xml);base64,[A-Za-z0-9+/=]*$",
        plain,
        ignore.case = TRUE
      )
    )
  }
  grepl("^(https?://|mailto:)", plain, ignore.case = TRUE)
}

subagent_display_id <- function(id, prefix) {
  if (!grepl("^[A-Za-z][A-Za-z0-9_-]{0,63}$", id)) {
    return(NULL)
  }
  paste0(prefix, id)
}

# Keep declarations that only style the element in place. Declarations are
# checked together, so the work stays linear in the length of the style.
subagent_display_css_declarations <- function(
  css,
  ids = character(),
  prefix = subagent_display_prefix()
) {
  if (nchar(css, type = "chars") > subagent_display_style_limit) {
    return("")
  }
  declarations <- strsplit(css, ";", fixed = TRUE)[[1L]]
  colon <- regexpr(":", declarations, fixed = TRUE)
  property <- tolower(trimws(substr(declarations, 1L, colon - 1L)))
  value <- trimws(substring(declarations, colon + 1L))
  keep <- colon > 0L &
    grepl("^-?[a-z][a-z0-9-]*$", property) &
    nzchar(value) &
    # Braces would open nested rules that escape the checks here.
    !grepl("[{}]", value) &
    !subagent_display_active(value) &
    !(property == "position" &
      grepl("fixed|sticky", value, ignore.case = TRUE))
  for (index in which(keep & grepl("url\\(", value, ignore.case = TRUE))) {
    rewritten <- subagent_display_css_refs(value[[index]], ids, prefix)
    if (is.null(rewritten)) {
      keep[[index]] <- FALSE
    } else {
      value[[index]] <- rewritten
    }
  }
  paste(paste0(property[keep], ":", value[keep]), collapse = ";")
}

# `url(#id)` references point at prefixed ids; any other reference is dropped.
# CSS reads `url` in any case, so the match does too.
subagent_display_css_refs <- function(value, ids, prefix) {
  pattern <- "(?i)url\\((\\s*['\"]?)#([A-Za-z][A-Za-z0-9_-]*)"
  refs <- regmatches(value, gregexpr(pattern, value, perl = TRUE))[[1L]]
  referenced <- sub("(?i)^url\\(\\s*['\"]?#", "", refs, perl = TRUE)
  if (!all(referenced %in% ids)) {
    return(NULL)
  }
  gsub(pattern, paste0("url(\\1#", prefix, "\\2"), value, perl = TRUE)
}

# Longer style sheets and inline styles are dropped rather than scanned, as
# are sheets with more rules; gt's are a few KB with about 50 rules.
subagent_display_style_limit <- 256L * 1024L
subagent_display_style_rules <- 1000L

# A rule survives only when each selector starts at an id defined in the same
# display, which is how gt scopes its table styles. `@media` is kept at the top
# level only, so the scan stays linear in the length of the sheet.
subagent_display_style_element <- function(css, ids, prefix) {
  if (
    nchar(css, type = "chars") > subagent_display_style_limit ||
      lengths(gregexpr("{", css, fixed = TRUE)) > subagent_display_style_rules
  ) {
    return("")
  }
  css <- gsub("/\\*.*?\\*/", "", css, perl = TRUE)
  if (
    !length(ids) ||
      grepl("</", css, fixed = TRUE) ||
      grepl("[<\\\\]", css) ||
      grepl("@import|javascript:|expression\\(", tolower(css))
  ) {
    return("")
  }
  rules <- character()
  scan_blocks <- function(text) {
    out <- list()
    position <- 1L
    characters <- strsplit(text, "", fixed = TRUE)[[1L]]
    length_text <- length(characters)
    while (position <= length_text) {
      open <- position
      while (open <= length_text && characters[[open]] != "{") {
        open <- open + 1L
      }
      if (open > length_text) {
        break
      }
      depth <- 1L
      close <- open + 1L
      while (close <= length_text && depth > 0L) {
        if (characters[[close]] == "{") {
          depth <- depth + 1L
        }
        if (characters[[close]] == "}") {
          depth <- depth - 1L
        }
        close <- close + 1L
      }
      if (depth > 0L) {
        break
      }
      prelude <- trimws(paste(characters[position:(open - 1L)], collapse = ""))
      body <- if (close - 2L >= open + 1L) {
        paste(characters[(open + 1L):(close - 2L)], collapse = "")
      } else {
        ""
      }
      out[[length(out) + 1L]] <- list(prelude = prelude, body = body)
      position <- close
    }
    out
  }
  scope <- function(prelude) {
    selectors <- trimws(strsplit(prelude, ",", fixed = TRUE)[[1L]])
    rewritten <- character()
    for (selector in selectors) {
      # Sibling combinators would reach elements outside the display.
      if (grepl("[~+]", selector)) {
        return(NULL)
      }
      id <- regmatches(
        selector,
        regexpr("^#[A-Za-z][A-Za-z0-9_-]*", selector)
      )
      if (!length(id) || !substring(id, 2L) %in% ids) {
        return(NULL)
      }
      rewritten <- c(
        rewritten,
        paste0("#", prefix, substring(selector, 2L))
      )
    }
    paste(rewritten, collapse = ",")
  }
  emit <- function(blocks, nested = FALSE) {
    out <- character(length(blocks))
    for (index in seq_along(blocks)) {
      block <- blocks[[index]]
      if (startsWith(block$prelude, "@media")) {
        if (nested) {
          next
        }
        inner <- emit(scan_blocks(block$body), nested = TRUE)
        if (length(inner)) {
          out[[index]] <- paste0(
            block$prelude,
            "{",
            paste(inner, collapse = ""),
            "}"
          )
        }
        next
      }
      if (startsWith(block$prelude, "@")) {
        next
      }
      selector <- scope(block$prelude)
      # A rule with nested blocks is dropped whole.
      if (is.null(selector) || grepl("[{}]", block$body)) {
        next
      }
      body <- subagent_display_css_declarations(block$body, ids, prefix)
      if (nzchar(body)) {
        out[[index]] <- paste0(selector, "{", body, "}")
      }
    }
    out[nzchar(out)]
  }
  paste(emit(scan_blocks(css)), collapse = "")
}

subagent_display_parse <- function(html) {
  # Well-formed fragments, such as inline SVG icons, keep their structure
  # under the XML parser; anything else goes through the HTML parser.
  root <- tryCatch(
    xml2::xml_root(xml2::read_xml(
      charToRaw(enc2utf8(paste0("<deputy-display>", html, "</deputy-display>")))
    )),
    error = function(error) NULL
  )
  if (!is.null(root)) {
    return(root)
  }
  document <- xml2::read_html(
    charToRaw(enc2utf8(paste0("<html><body>", html, "</body></html>")))
  )
  xml2::xml_find_first(document, "//body")
}

# Rebuild one string of display HTML from the allowlist. Returns "" when
# nothing displayable is left.
subagent_display_html <- function(html) {
  if (!is.character(html) || length(html) != 1L || is.na(html)) {
    return("")
  }
  if (!nzchar(trimws(html))) {
    return("")
  }
  root <- tryCatch(subagent_display_parse(html), error = function(error) NULL)
  if (is.null(root)) {
    return("")
  }
  ids <- unique(xml2::xml_attr(
    xml2::xml_find_all(root, ".//*[@id]"),
    "id"
  ))
  ids <- ids[!is.na(ids) & grepl("^[A-Za-z][A-Za-z0-9_-]{0,63}$", ids)]
  prefix <- subagent_display_prefix()
  state <- new.env(parent = emptyenv())
  state$nodes <- 0L
  render <- function(node, depth) {
    state$nodes <- state$nodes + 1L
    if (state$nodes > 20000L || depth > 64L) {
      return(NULL)
    }
    type <- xml2::xml_type(node)
    if (identical(type, "text") || identical(type, "cdata")) {
      return(xml2::xml_text(node))
    }
    if (!identical(type, "element")) {
      return(NULL)
    }
    name <- tolower(xml2::xml_name(node))
    if (name %in% subagent_display_dropped) {
      return(NULL)
    }
    if (identical(name, "style")) {
      css <- subagent_display_style_element(xml2::xml_text(node), ids, prefix)
      if (!nzchar(css)) {
        return(NULL)
      }
      return(htmltools::tag(
        "style",
        list(htmltools::HTML(css)),
        .noWS = subagent_display_no_whitespace
      ))
    }
    children <- subagent_display_splice(lapply(
      xml2::xml_contents(node),
      render,
      depth = depth + 1L
    ))
    if (!name %in% subagent_display_elements) {
      # Unknown markup keeps its content but not its element.
      return(structure(children, class = "deputy_display_splice"))
    }
    attributes <- xml2::xml_attrs(node)
    kept <- list()
    for (attribute in names(attributes)) {
      value <- attributes[[attribute]]
      key <- tolower(attribute)
      if (grepl(":", key, fixed = TRUE) || startsWith(key, "on")) {
        next
      }
      if (identical(key, "id")) {
        prefixed <- if (value %in% ids) subagent_display_id(value, prefix)
        if (!is.null(prefixed)) {
          kept$id <- prefixed
        }
        next
      }
      if (identical(key, "style")) {
        css <- subagent_display_css_declarations(value, ids, prefix)
        if (nzchar(css)) {
          kept$style <- css
        }
        next
      }
      if (identical(key, "class")) {
        classes <- strsplit(trimws(value), "[[:space:]]+")[[1L]]
        # shinychat sends a `suggestion` element's text as the user's message
        # when it is clicked.
        classes <- classes[nzchar(classes) & tolower(classes) != "suggestion"]
        if (length(classes)) {
          kept$class <- paste(classes, collapse = " ")
        }
        next
      }
      if (identical(key, "href") && identical(name, "a")) {
        if (subagent_display_url(value, name)) {
          kept$href <- value
          kept$target <- "_blank"
          kept$rel <- "noopener noreferrer"
        }
        next
      }
      if (identical(key, "src") && identical(name, "img")) {
        if (subagent_display_url(value, name)) {
          kept$src <- value
        }
        next
      }
      # `data-*` attributes are dropped: Bootstrap, shinychat and other
      # libraries on the host page act on them (`data-bs-toggle`,
      # `data-suggestion`), outside the display.
      allowed <- key %in%
        subagent_display_attributes ||
        grepl("^aria-[a-z0-9_.-]+$", key)
      if (!allowed) {
        next
      }
      if (key %in% subagent_display_url_attributes) {
        # Paint and clipping may reference a gradient or clip path defined in
        # the same display, never anything outside it.
        value <- subagent_display_css_refs(value, ids, prefix)
        if (is.null(value) || subagent_display_active(value)) {
          next
        }
      }
      kept[[key]] <- value
    }
    htmltools::tag(
      name,
      c(kept, children),
      .noWS = subagent_display_no_whitespace
    )
  }
  rendered <- subagent_display_splice(lapply(
    xml2::xml_contents(root),
    render,
    depth = 0L
  ))
  # One render for the whole fragment: per-node renders cost more than the
  # rebuild itself.
  trimws(as.character(htmltools::tagList(rendered)))
}

# Unwrapped elements contribute their children in place, and neighbouring text
# joins up, so rebuilding never adds whitespace between them.
subagent_display_splice <- function(nodes) {
  out <- list()
  for (node in nodes) {
    items <- if (inherits(node, "deputy_display_splice")) {
      unclass(node)
    } else {
      list(node)
    }
    for (item in items) {
      if (is.null(item)) {
        next
      }
      last <- length(out)
      if (
        is.character(item) &&
          !inherits(item, "html") &&
          last &&
          is.character(out[[last]]) &&
          !inherits(out[[last]], "html")
      ) {
        out[[last]] <- paste0(out[[last]], item)
      } else {
        out[[last + 1L]] <- item
      }
    }
  }
  out
}

# Each rebuilt field sits in a box that contains its painting and stacking, so
# positioned, transformed or offset content stays inside its own card.
subagent_display_contain <- function(html, field) {
  if (identical(field, "html")) {
    return(paste0(
      "<div class=\"deputy-display\" style=\"position:relative;overflow:auto;",
      "contain:paint;isolation:isolate\">",
      html,
      "</div>"
    ))
  }
  paste0(
    "<span class=\"deputy-display\" style=\"display:inline-block;",
    "position:relative;max-width:100%;contain:paint;isolation:isolate\">",
    html,
    "</span>"
  )
}

# Tool display fields that shinychat renders as raw HTML go through
# `subagent_display_html()`; plain-text fields and flags pass through.
subagent_safe_display <- function(display) {
  if (!is.list(display) || is.object(display)) {
    return(NULL)
  }
  # shinychat renders Markdown as HTML, remote images included, so a card's
  # Markdown is shown as HTML rebuilt through the same allowlist instead.
  markdown <- display$markdown
  display$markdown <- NULL
  if (
    is.character(markdown) &&
      length(markdown) == 1L &&
      !is.na(markdown) &&
      nzchar(markdown)
  ) {
    if (rlang::is_installed("commonmark")) {
      display$html <- display$html %||%
        commonmark::markdown_html(markdown, extensions = TRUE)
    } else {
      display$text <- display$text %||% markdown
    }
  }
  for (field in intersect(tool_display_html_fields, names(display))) {
    value <- display[[field]]
    safe <- if (is.character(value) && length(value) == 1L) {
      subagent_display_html(value)
    } else {
      ""
    }
    display[[field]] <- if (nzchar(safe)) {
      subagent_display_contain(safe, field)
    }
  }
  display
}
