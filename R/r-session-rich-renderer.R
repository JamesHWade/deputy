# Sent to callr with a base environment. The worker exports producer HTML and
# a bounded preview, then gives their bytes to the host for publication.
r_session_render_rich <- function(
  value,
  max_bytes,
  width,
  height,
  preview_document = identity
) {
  widget <- inherits(value, "htmlwidget")
  producer <- if (widget) {
    class(value)[[1L]]
  } else if (inherits(value, "gt_tbl")) {
    "gt"
  } else if (inherits(value, "flextable")) {
    "flextable"
  } else {
    stop("This R value requires a live renderer.", call. = FALSE)
  }
  if (max_bytes < 256L) {
    stop("Too little output budget remains for an interactive result.", call. = FALSE)
  }

  # Leave headroom for the status, dependency labels, and UTF-8 expansion.
  brief <- function(text, chars = 80L) {
    paste(substr(as.character(text), 1L, chars), collapse = ", ")
  }
  result <- list(
    html = raw(),
    text = paste("Interactive R output from", brief(producer)),
    png = NULL,
    renderer = "",
    dependencies = character(),
    fallback = ""
  )

  directory <- tempfile("deputy-rich-")
  if (!dir.create(directory, mode = "0700")) {
    stop("Could not create an R rendering directory.", call. = FALSE)
  }
  on.exit(unlink(directory, recursive = TRUE), add = TRUE)
  html_file <- file.path(directory, "result.html")
  dependencies <- list()
  render <- tryCatch(
    {
      if (widget) {
        # Plotly's public build step supplies the traces used by its exporter.
        if (identical(producer, "plotly")) value <- plotly::plotly_build(value)
        dependencies <- htmltools::resolveDependencies(c(
          value$dependencies,
          htmltools::htmlDependencies(value)
        ))
        htmlwidgets::saveWidget(
          value,
          html_file,
          selfcontained = TRUE,
          libdir = file.path(directory, "dependencies")
        )
      } else if (identical(producer, "gt")) {
        gt::gtsave(value, basename(html_file), path = directory, inline_css = TRUE)
      } else {
        flextable::save_as_html(value, path = html_file)
      }
      NULL
    },
    error = identity
  )
  if (inherits(render, "error")) {
    result$fallback <- paste("HTML export failed.", brief(conditionMessage(render), 240L))
    return(result)
  }

  producer_package <- if (widget) attr(value, "package", exact = TRUE) else producer
  if (!length(producer_package)) producer_package <- producer
  packages <- unique(c(producer_package, if (widget) "htmlwidgets", "htmltools"))
  versions <- vapply(packages, function(package) {
    if (requireNamespace(package, quietly = TRUE)) {
      paste(package, utils::packageVersion(package))
    } else {
      package
    }
  }, character(1))
  exporter <- if (widget) "htmlwidgets::saveWidget()" else switch(
    producer,
    gt = "gt::gtsave()",
    flextable = "flextable::save_as_html()"
  )
  result$renderer <- paste(versions[[1L]], "via", exporter)
  labels <- vapply(utils::head(dependencies, 24L), function(dep) {
    brief(c(dep$name, dep$version))
  }, character(1))
  result$dependencies <- unique(unname(c(versions, labels)))

  read_bytes <- function(path, limit) {
    size <- file.info(path)$size
    if (is.na(size) || size <= 0 || size > limit) return(raw())
    bytes <- readBin(path, "raw", n = as.integer(limit + 1))
    if (length(bytes) != size) return(raw())
    bytes
  }
  html <- read_bytes(html_file, max_bytes)
  if (!length(html)) {
    result$fallback <- "HTML export was empty or exceeded the remaining output budget."
    return(result)
  }
  document <- xml2::read_html(html, options = c("NONET", "NOERROR", "NOWARNING"))
  refs <- xml2::xml_text(xml2::xml_find_all(
    document,
    "//script/@src | //link/@href | //img/@src | //source/@src"
  ))
  refs <- trimws(refs)
  # Styles and widget JavaScript may also attempt dynamic resource loads. The
  # viewer and preview enforce the same subresource policy for those loads.
  if (any(nzchar(refs) & !grepl("^(data:|blob:|#)", refs, ignore.case = TRUE))) {
    result$fallback <- "HTML export contains a script, stylesheet or image that was not bundled."
    return(result)
  }

  if (identical(producer, "plotly")) {
    traces <- utils::head(value$x$data, 6L)
    summary <- vapply(traces, function(trace) {
      paste0(
        brief(if (is.null(trace$type)) "trace" else trace$type), " ", brief(trace$name),
        " (", max(length(trace$x), length(trace$y)), " points)",
        " x: ", brief(utils::head(trace$x, 3L)),
        "; y: ", brief(utils::head(trace$y, 3L))
      )
    }, character(1))
    result$text <- paste(c(result$text, summary), collapse = "\n")
  } else if (identical(producer, "leaflet")) {
    calls <- value$x$calls
    layers <- unique(vapply(utils::head(calls, 32L), function(call) {
      brief(call$method)
    }, character(1)))
    result$text <- paste0(
      "Leaflet map with ", length(calls), " configured map calls. ",
      paste(layers, collapse = ", "),
      ". Remote tile sources are unavailable in the offline viewer."
    )
  } else if (identical(producer, "datatables")) {
    columns <- utils::head(value$x$data, 6L)
    entries <- vapply(columns, function(column) {
      brief(utils::head(column, 4L))
    }, character(1))
    result$text <- paste(c("Interactive table samples by column.", entries), collapse = "\n")
  } else if (!widget) {
    rows <- utils::head(xml2::xml_find_all(document, "//table//tr"), 6L)
    entries <- vapply(rows, function(row) {
      cells <- utils::head(xml2::xml_children(row), 8L)
      brief(xml2::xml_text(cells, trim = TRUE))
    }, character(1))
    result$text <- paste(c(result$text, entries), collapse = "\n")
  }

  result$text <- substr(enc2utf8(result$text), 1L, 1024L)
  result$html <- html
  metadata_bytes <- sum(nchar(enc2utf8(c(
    result$text, result$renderer, result$dependencies
  )), "bytes"))
  remaining <- max_bytes - length(html) - metadata_bytes
  if (remaining < 512L) {
    if (remaining < 96L) {
      result$html <- raw()
      result$fallback <- "HTML and its provenance exceeded the remaining output budget."
    } else {
      result$fallback <- "Static preview omitted because the output budget was reached."
    }
    return(result)
  }

  selector <- switch(
    producer,
    plotly = ".main-svg",
    leaflet = ".leaflet-container",
    gt = "table",
    flextable = "table",
    datatables = "table",
    NULL
  )
  if (is.null(selector)) {
    result$fallback <- "Static preview unavailable for this widget."
    return(result)
  }
  native_image <- identical(producer, "flextable")
  if (!native_image && !requireNamespace("webshot2", quietly = TRUE)) {
    result$fallback <- "Install webshot2 and Chrome to capture a static preview."
    return(result)
  }
  png_file <- file.path(directory, "preview.png")
  preview <- tryCatch(
    {
      if (native_image) {
        flextable::save_as_image(value, path = png_file, res = 96L)
      } else {
        preview_file <- file.path(directory, "preview.html")
        writeLines(preview_document(rawToChar(html)), preview_file, useBytes = TRUE)
        webshot2::webshot(
          preview_file, file = png_file, selector = selector,
          vwidth = width, vheight = height, quiet = TRUE
        )
      }
      read_bytes(png_file, remaining - 256L)
    },
    error = identity
  )
  if (inherits(preview, "error")) {
    result$fallback <- paste("Static preview failed.", brief(conditionMessage(preview), 160L))
    return(result)
  }
  signature <- as.raw(c(137, 80, 78, 71, 13, 10, 26, 10))
  if (length(preview) < 24L || !identical(preview[seq_along(signature)], signature)) {
    result$fallback <- "Static preview was missing, too large or not a PNG."
    return(result)
  }
  dimensions <- vapply(c(17L, 21L), function(start) {
    sum(as.integer(preview[start + 0:3]) * c(256^3, 256^2, 256, 1))
  }, numeric(1))
  if (any(dimensions < 1L | dimensions > 4096L)) {
    result$fallback <- "Static preview exceeded the PNG dimension bounds."
    return(result)
  }
  result$png <- preview
  result$fallback <- if (native_image) {
    "Static PNG captured with flextable::save_as_image()."
  } else {
    "Static PNG captured with webshot2."
  }
  result
}
