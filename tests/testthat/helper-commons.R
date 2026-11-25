# Commons 0.2.0 separates the model-free `commons()` object (which works on
# every platform) from `agent()`, which still needs an OS sandbox for `run_r`
# (macOS, or Linux with seccomp and Landlock or user namespaces).
skip_if_no_commons <- function() {
  skip_if_not_installed("commons", "0.2.0")
}

skip_if_commons_refuses <- function() {
  skip_if_not_installed("commons")
  refusal <- commons_refusal()
  if (!is.null(refusal)) {
    skip(paste("commons refuses to build an agent chat here:", refusal))
  }
}

commons_refusal <- local({
  probed <- FALSE
  refusal <- NULL
  function() {
    if (!probed) {
      message <- tryCatch(
        {
          probe_chat <- ellmer::chat_openai_compatible(
            base_url = "http://127.0.0.1:9/v1",
            credentials = function() "probe",
            model = "probe",
            echo = "none"
          )
          source <- commons::data_source(probe = data.frame(x = 1))
          if (utils::packageVersion("commons") >= numeric_version("0.2.0")) {
            commons::agent(
              probe_chat,
              commons = commons::commons(data_sources = source)
            )
          } else {
            commons::commons(probe_chat, data_sources = source)
          }
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
