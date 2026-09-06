# Read-only stored properties retain S7's type validation. A separate marker
# distinguishes construction from an initialized property whose value is NULL.
readonly_property <- function(name, class) {
  S7::new_property(
    class,
    setter = function(self, value) {
      if (isTRUE(attr(self, ".deputy_frozen", exact = TRUE))) {
        cli_abort(
          "Cannot modify {.arg {name}}: property is read-only after construction"
        )
      }
      attr(self, name) <- value
      self
    }
  )
}

freeze_value <- function(x) {
  attr(x, ".deputy_frozen") <- TRUE
  x
}
