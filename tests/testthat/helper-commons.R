# commons builds a chat only where it can sandbox its `run_r` tool (macOS, or
# Linux with seccomp and Landlock or user namespaces). Elsewhere, Windows
# included, it refuses before a chat's tools can be chosen.
skip_if_commons_refuses <- function() {
  skip_if_not_installed("commons")
  refusal <- commons_refusal()
  if (!is.null(refusal)) {
    skip(paste("commons refuses to build a chat here:", refusal))
  }
}

commons_refusal <- local({
  probed <- FALSE
  refusal <- NULL
  function() {
    if (!probed) {
      message <- tryCatch(
        {
          commons::commons(
            ellmer::chat_openai_compatible(
              base_url = "http://127.0.0.1:9/v1",
              credentials = function() "probe",
              model = "probe",
              echo = "none"
            ),
            data_sources = commons::data_source(probe = data.frame(x = 1))
          )
          NULL
        },
        error = conditionMessage
      )
      # Any other error is left for the test itself to report.
      if (!is.null(message) && grepl("cannot sandbox", message, fixed = TRUE)) {
        refusal <<- strsplit(message, "\n", fixed = TRUE)[[1L]][[1L]]
      }
      probed <<- TRUE
    }
    refusal
  }
})
