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

# Register S7 `$` property access inside this helper's frame so `$` is never
# bound in the package namespace.
register_dollar_prop <- function(cls, missing_null = FALSE) {
  if (isTRUE(missing_null)) {
    S7::method(`$`, cls) <- function(x, name) S7::props(x)[[name]]
  } else {
    S7::method(`$`, cls) <- function(x, name) S7::prop(x, name)
  }
  invisible(cls)
}
