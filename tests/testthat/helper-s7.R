# S7 1.0 includes the property or constructor call in error headers.
expect_snapshot_s7_error <- function(x, error = TRUE) {
  rlang::inject(
    expect_snapshot(
      !!rlang::enexpr(x),
      error = !!error,
      transform = function(lines) {
        sub("^([[:blank:]]*)Error in `.*`:$", "\\1Error:", lines)
      }
    ),
    env = rlang::caller_env()
  )
}
