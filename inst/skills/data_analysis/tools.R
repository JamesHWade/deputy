# Data analysis tools for the data_analysis skill

#' EDA Summary Tool
#'
#' Provides an exploratory data analysis summary of a dataset.
tool_eda_summary <- ellmer::tool(
  fun = function(data_var) {
    # Get the data from the global environment
    # Note: This uses get() to access data by variable name, which is
    # necessary for the LLM to reference user's data frames
    data <- tryCatch({
      get(data_var, envir = globalenv())
    }, error = function(e) {
      ellmer::tool_reject(paste("Could not find data frame:", data_var))
    })

    if (!is.data.frame(data)) {
      ellmer::tool_reject("Input must be a data frame")
    }

    # Build summary
    lines <- c(
      paste("Dataset Summary"),
      paste(rep("=", 50), collapse = ""),
      paste("Rows:", nrow(data)),
      paste("Columns:", ncol(data)),
      "",
      "Column Types:",
      paste(rep("-", 30), collapse = "")
    )

    # Summarize each column
    for (col in names(data)) {
      col_data <- data[[col]]
      col_class <- class(col_data)[1]

      if (is.numeric(col_data)) {
        na_count <- sum(is.na(col_data))
        lines <- c(lines, sprintf(
          "  %s (%s): min=%.2f, max=%.2f, mean=%.2f, NA=%d",
          col, col_class,
          min(col_data, na.rm = TRUE),
          max(col_data, na.rm = TRUE),
          mean(col_data, na.rm = TRUE),
          na_count
        ))
      } else if (is.character(col_data) || is.factor(col_data)) {
        n_unique <- length(unique(col_data))
        na_count <- sum(is.na(col_data))
        lines <- c(lines, sprintf(
          "  %s (%s): %d unique values, NA=%d",
          col, col_class, n_unique, na_count
        ))
      } else {
        lines <- c(lines, sprintf("  %s (%s)", col, col_class))
      }
    }

    paste(lines, collapse = "\n")
  },
  name = "eda_summary",
  description = "Provide an exploratory data analysis summary of a dataset. Pass the name of a data frame variable.",
  arguments = list(
    data_var = ellmer::type_string("Name of the data frame variable to analyze")
  ),
  annotations = ellmer::tool_annotations(
    read_only_hint = TRUE,
    destructive_hint = FALSE
  )
)

#' Describe Column Tool
#'
#' Provides detailed statistics for a specific column.
tool_describe_column <- ellmer::tool(
  fun = function(data_var, column) {
    # Get the data from global environment by variable name
    data <- tryCatch({
      get(data_var, envir = globalenv())
    }, error = function(e) {
      ellmer::tool_reject(paste("Could not find data frame:", data_var))
    })

    if (!is.data.frame(data)) {
      ellmer::tool_reject("Input must be a data frame")
    }

    if (!column %in% names(data)) {
      ellmer::tool_reject(paste("Column not found:", column))
    }

    col_data <- data[[column]]
    col_class <- class(col_data)[1]
    n_total <- length(col_data)
    n_na <- sum(is.na(col_data))
    n_valid <- n_total - n_na

    lines <- c(
      paste("Column:", column),
      paste("Type:", col_class),
      paste("Total values:", n_total),
      paste("Missing (NA):", n_na, sprintf("(%.1f%%)", 100 * n_na / n_total)),
      paste("Valid values:", n_valid),
      ""
    )

    if (is.numeric(col_data)) {
      valid_data <- col_data[!is.na(col_data)]
      if (length(valid_data) > 0) {
        lines <- c(lines,
          "Numeric Statistics:",
          paste("  Min:", min(valid_data)),
          paste("  Max:", max(valid_data)),
          paste("  Mean:", round(mean(valid_data), 4)),
          paste("  Median:", round(stats::median(valid_data), 4)),
          paste("  Std Dev:", round(stats::sd(valid_data), 4)),
          "",
          "Quantiles:",
          paste("  25%:", round(stats::quantile(valid_data, 0.25), 4)),
          paste("  50%:", round(stats::quantile(valid_data, 0.50), 4)),
          paste("  75%:", round(stats::quantile(valid_data, 0.75), 4))
        )
      }
    } else if (is.character(col_data) || is.factor(col_data)) {
      valid_data <- col_data[!is.na(col_data)]
      freq <- sort(table(valid_data), decreasing = TRUE)
      n_unique <- length(freq)

      lines <- c(lines,
        paste("Unique values:", n_unique),
        "",
        "Top values (frequency):"
      )

      # Show top 10 values
      top_n <- min(10, length(freq))
      for (i in seq_len(top_n)) {
        val <- names(freq)[i]
        count <- freq[i]
        pct <- round(100 * count / n_valid, 1)
        lines <- c(lines, sprintf("  %s: %d (%.1f%%)", val, count, pct))
      }

      if (n_unique > 10) {
        lines <- c(lines, sprintf("  ... and %d more", n_unique - 10))
      }
    } else if (inherits(col_data, "Date") || inherits(col_data, "POSIXt")) {
      valid_data <- col_data[!is.na(col_data)]
      if (length(valid_data) > 0) {
        lines <- c(lines,
          "Date Range:",
          paste("  Earliest:", min(valid_data)),
          paste("  Latest:", max(valid_data)),
          paste("  Span:", difftime(max(valid_data), min(valid_data), units = "days"), "days")
        )
      }
    }

    paste(lines, collapse = "\n")
  },
  name = "describe_column",
  description = "Get detailed statistics for a specific column in a dataset.",
  arguments = list(
    data_var = ellmer::type_string("Name of the data frame variable"),
    column = ellmer::type_string("Name of the column to describe")
  ),
  annotations = ellmer::tool_annotations(
    read_only_hint = TRUE,
    destructive_hint = FALSE
  )
)
