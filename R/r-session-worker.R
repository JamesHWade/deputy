# Evaluated in the callr worker with a base environment. No Deputy namespace or
# host closure is transferred. Persistent objects live only in that worker.
r_session_evaluate <- function(
  code,
  working_dir,
  max_output_bytes,
  plot_width,
  plot_height
) {
  setwd(working_dir)
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
