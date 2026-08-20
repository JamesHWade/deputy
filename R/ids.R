# Internal identifiers for Deputy runtime correlation.

# Process-local counter keeps generated identifiers unique without consuming
# the caller's random-number stream.
deputy_id_state <- new.env(parent = emptyenv())
deputy_id_state$counter <- 0L

new_deputy_id <- function(prefix = NULL) {
  deputy_id_state$counter <- deputy_id_state$counter + 1L
  entropy <- paste(
    Sys.getpid(),
    format(Sys.time(), "%Y%m%d%H%M%OS9", tz = "UTC"),
    deputy_id_state$counter,
    sep = ":"
  )
  hex <- substr(
    digest::digest(entropy, algo = "sha256", serialize = FALSE),
    1L,
    32L
  )
  id <- paste(
    substr(hex, 1L, 8L),
    substr(hex, 9L, 12L),
    substr(hex, 13L, 16L),
    substr(hex, 17L, 20L),
    substr(hex, 21L, 32L),
    sep = "-"
  )

  if (is.null(prefix)) id else paste0(prefix, id)
}

validate_deputy_id <- function(id, argument = "id") {
  if (
    !is.character(id) ||
      length(id) != 1L ||
      is.na(id) ||
      !nzchar(id) ||
      !grepl("^[A-Za-z0-9][A-Za-z0-9._-]*$", id)
  ) {
    cli::cli_abort(
      paste0(
        "{.arg ",
        argument,
        "} must be one non-empty identifier containing only letters, ",
        "numbers, dots, underscores, or hyphens"
      ),
      class = c("deputy_id_error", "deputy_error")
    )
  }
  id
}
