r_session_await <- function(value, timeout = 70) {
  done <- FALSE
  result <- NULL
  promises::then(
    value,
    function(x) {
      result <<- x
      done <<- TRUE
    },
    function(e) {
      result <<- e
      done <<- TRUE
    }
  )
  deadline <- Sys.time() + timeout
  while (!done && Sys.time() < deadline) {
    later::run_now(0.01)
  }
  if (!done) {
    cli::cli_abort("R session promise did not settle.")
  }
  if (inherits(result, "condition")) {
    rlang::cnd_signal(result)
  }
  result
}

r_session_text <- function(result) {
  paste(
    vapply(
      Filter(function(x) inherits(x, "ellmer::ContentText"), result@value),
      function(x) x@text,
      character(1)
    ),
    collapse = "\n"
  )
}
