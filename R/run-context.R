# Internal validation and merging for immutable run context.

run_context_abort <- function(
  message,
  class = character(),
  path = NULL,
  key = NULL
) {
  classes <- unique(c(
    class,
    "deputy_run_context_error",
    "deputy_error",
    "error",
    "condition"
  ))
  condition <- structure(
    list(
      message = message,
      call = NULL,
      path = path,
      key = key
    ),
    class = classes
  )
  stop(condition)
}

run_context_max_depth <- 32L

normalize_run_context <- function(x, argument = "run_context") {
  if (!identical(typeof(x), "list")) {
    run_context_abort(
      sprintf("`%s` must be a named list.", argument),
      path = argument
    )
  }

  normalize_run_context_value(
    x,
    depth = 0L,
    path = argument,
    top_level = TRUE
  )
}

clone_run_context <- function(x) {
  normalize_run_context(x)
}

normalize_run_context_value <- function(
  x,
  depth,
  path,
  top_level = FALSE
) {
  if (depth > run_context_max_depth) {
    run_context_abort(
      "Run context exceeds the maximum nesting depth.",
      path = path
    )
  }

  if (is.null(x)) {
    return(NULL)
  }

  if (identical(typeof(x), "list")) {
    return(normalize_run_context_list(
      x,
      depth = depth,
      path = path,
      top_level = top_level
    ))
  }

  if (length(attributes(x)) > 0L) {
    run_context_abort(
      paste0(
        "Run context primitive vectors must be unnamed, unclassed, ",
        "and free of other attributes."
      ),
      path = path
    )
  }

  type <- typeof(x)
  if (identical(type, "logical")) {
    if (anyNA(x)) {
      run_context_abort(
        "Run context values must not contain missing values.",
        path = path
      )
    }
    return(as.logical(x))
  }

  if (type %in% c("integer", "double")) {
    if (anyNA(x) || any(!is.finite(x))) {
      run_context_abort(
        paste0(
          "Run context numeric values must be finite and must not be ",
          "missing."
        ),
        path = path
      )
    }
    if (identical(type, "integer")) {
      return(as.integer(x))
    }
    return(as.double(x))
  }

  if (identical(type, "character")) {
    if (anyNA(x)) {
      run_context_abort(
        "Run context values must not contain missing values.",
        path = path
      )
    }
    return(run_context_utf8(x, path))
  }

  run_context_abort(
    paste0(
      "Run context values must be canonical JSON-compatible primitives, ",
      "arrays, or objects."
    ),
    path = path
  )
}

normalize_run_context_list <- function(x, depth, path, top_level) {
  attribute_names <- names(attributes(x))
  if (length(setdiff(attribute_names, "names")) > 0L) {
    run_context_abort(
      paste0(
        "Run context arrays and objects must be unclassed and free of ",
        "non-name attributes."
      ),
      path = path
    )
  }

  keys <- names(x)
  if (is.null(keys)) {
    if (top_level && length(x) > 0L) {
      run_context_abort(
        sprintf("`%s` must be a named list.", path),
        path = path
      )
    }

    output <- vector("list", length(x))
    for (index in seq_along(x)) {
      child_path <- paste0(path, "[", index, "]")
      output[index] <- list(normalize_run_context_value(
        x[[index]],
        depth = depth + 1L,
        path = child_path
      ))
    }
    return(output)
  }

  if (anyNA(keys) || any(!nzchar(keys))) {
    run_context_abort(
      "Run context objects must have complete, non-empty keys.",
      path = path
    )
  }

  keys <- run_context_utf8(keys, path)
  if (anyDuplicated(keys)) {
    run_context_abort(
      "Run context object keys must be unique.",
      path = path
    )
  }

  credential_index <- which(vapply(
    keys,
    run_context_is_credential_key,
    logical(1)
  ))
  if (length(credential_index) > 0L) {
    key <- keys[[credential_index[[1L]]]]
    run_context_abort(
      "Run context contains a credential-like key, which is not allowed.",
      path = paste0(path, ".", key),
      key = key
    )
  }

  order <- run_context_key_order(keys)
  output <- vector("list", length(x))
  names(output) <- keys[order]
  for (output_index in seq_along(order)) {
    input_index <- order[[output_index]]
    key <- keys[[input_index]]
    child_path <- paste0(path, ".", key)
    output[output_index] <- list(normalize_run_context_value(
      x[[input_index]],
      depth = depth + 1L,
      path = child_path
    ))
  }
  output
}

run_context_utf8 <- function(x, path) {
  converted <- tryCatch(
    enc2utf8(x),
    error = function(e) NULL
  )
  if (is.null(converted)) {
    run_context_abort(
      "Run context text and object keys must be valid UTF-8.",
      path = path
    )
  }

  validated <- tryCatch(
    iconv(
      converted,
      from = "UTF-8",
      to = "UTF-8",
      sub = NA_character_
    ),
    error = function(e) NULL
  )
  if (is.null(validated) || anyNA(validated)) {
    run_context_abort(
      "Run context text and object keys must be valid UTF-8.",
      path = path
    )
  }

  converted
}

run_context_key_order <- function(keys) {
  if (length(keys) < 2L) {
    return(seq_along(keys))
  }

  byte_keys <- vapply(
    keys,
    function(key) {
      paste(sprintf("%03d", as.integer(charToRaw(key))), collapse = "")
    },
    character(1)
  )
  order(byte_keys, method = "radix")
}

run_context_is_credential_key <- function(key) {
  compact <- chartr(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
    "abcdefghijklmnopqrstuvwxyz",
    key
  )
  compact <- gsub("[^a-z0-9]", "", compact)

  credential_fragments <- c(
    "password",
    "passwd",
    "passphrase",
    "credential",
    "apikey",
    "accesskey",
    "privatekey",
    "clientkey",
    "clientsecret",
    "appsecret",
    "secretkey",
    "secretvalue",
    "signingkey",
    "encryptionkey",
    "authorization",
    "bearertoken",
    "accesstoken",
    "refreshtoken",
    "authtoken",
    "oauthtoken",
    "sessiontoken",
    "idtoken",
    "tokenvalue",
    "tokensecret",
    "tokenkey"
  )
  if (
    any(vapply(
      credential_fragments,
      function(fragment) grepl(fragment, compact, fixed = TRUE),
      logical(1)
    ))
  ) {
    return(TRUE)
  }

  if (compact %in% c("auth", "authentication", "cookie", "setcookie")) {
    return(TRUE)
  }

  separated <- gsub(
    "([A-Z]+)([A-Z][a-z])",
    "\\1_\\2",
    key,
    perl = TRUE
  )
  separated <- gsub(
    "([a-z0-9])([A-Z])",
    "\\1_\\2",
    separated,
    perl = TRUE
  )
  separated <- tolower(separated)
  separated <- gsub("[^a-z0-9]+", "_", separated)
  if (grepl("(^|_)secrets?($|_)", separated)) {
    return(TRUE)
  }

  token_metric <- grepl(
    paste0(
      "^(n|num|number|input|output|cached|cache|total|prompt|completion|",
      "reasoning|billable|used|remaining|max|maximum|min|minimum|consumed|",
      "estimated|actual)+tokens?(count|counts|used|usage|budget|limit)?$"
    ),
    compact
  ) ||
    grepl(
      "^tokens?(count|counts|used|usage|budget|limit)$",
      compact
    )
  if (token_metric) {
    return(FALSE)
  }

  grepl("tokens?$", compact) || grepl("^tokens?(value|secret|key)", compact)
}

run_context_is_object <- function(x) {
  identical(typeof(x), "list") &&
    (length(x) == 0L || !is.null(names(x)))
}

run_context_is_protected_key <- function(key) {
  lowered <- chartr(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
    "abcdefghijklmnopqrstuvwxyz",
    key
  )
  identical(lowered, "product") ||
    grepl("(^|[_.-])id$", lowered) ||
    grepl("[a-z0-9](Id|ID)$", key)
}

merge_run_context <- function(defaults, override) {
  defaults <- normalize_run_context(defaults, argument = "defaults")
  override <- normalize_run_context(override, argument = "override")
  protected <- run_context_collect_protected(defaults)

  merged <- run_context_merge_objects(defaults, override)

  for (entry in protected) {
    current <- run_context_lookup(merged, entry$segments)
    if (!current$found || !identical(current$value, entry$value)) {
      run_context_abort(
        paste0(
          "A protected run-context identity field cannot be changed or ",
          "removed."
        ),
        class = "deputy_run_context_conflict",
        path = run_context_format_path(entry$segments),
        key = entry$key
      )
    }
  }

  clone_run_context(merged)
}

run_context_merge_objects <- function(defaults, override) {
  keys <- unique(c(names(defaults), names(override)))
  if (length(keys) == 0L) {
    return(list())
  }
  keys <- keys[run_context_key_order(keys)]

  output <- vector("list", length(keys))
  names(output) <- keys
  for (index in seq_along(keys)) {
    key <- keys[[index]]
    in_defaults <- key %in% names(defaults)
    in_override <- key %in% names(override)

    if (!in_override) {
      value <- defaults[[key]]
    } else if (!in_defaults) {
      value <- override[[key]]
    } else if (
      run_context_is_object(defaults[[key]]) &&
        run_context_is_object(override[[key]])
    ) {
      value <- run_context_merge_objects(defaults[[key]], override[[key]])
    } else {
      value <- override[[key]]
    }

    output[index] <- list(value)
  }
  output
}

run_context_collect_protected <- function(
  x,
  segments = list(),
  output = list()
) {
  if (!identical(typeof(x), "list")) {
    return(output)
  }

  if (run_context_is_object(x)) {
    for (key in names(x)) {
      child_segments <- c(
        segments,
        list(list(kind = "key", value = key))
      )
      if (run_context_is_protected_key(key)) {
        output[[length(output) + 1L]] <- list(
          segments = child_segments,
          key = key,
          value = x[[key]]
        )
      }
      output <- run_context_collect_protected(
        x[[key]],
        segments = child_segments,
        output = output
      )
    }
    return(output)
  }

  for (index in seq_along(x)) {
    child_segments <- c(
      segments,
      list(list(kind = "index", value = index))
    )
    output <- run_context_collect_protected(
      x[[index]],
      segments = child_segments,
      output = output
    )
  }
  output
}

run_context_lookup <- function(x, segments) {
  current <- x
  for (segment in segments) {
    if (identical(segment$kind, "key")) {
      if (
        !run_context_is_object(current) ||
          !segment$value %in% names(current)
      ) {
        return(list(found = FALSE, value = NULL))
      }
      current <- current[[segment$value]]
    } else {
      if (
        !identical(typeof(current), "list") ||
          run_context_is_object(current) ||
          length(current) < segment$value
      ) {
        return(list(found = FALSE, value = NULL))
      }
      current <- current[[segment$value]]
    }
  }
  list(found = TRUE, value = current)
}

run_context_format_path <- function(segments) {
  path <- "run_context"
  for (segment in segments) {
    if (identical(segment$kind, "key")) {
      path <- paste0(path, ".", segment$value)
    } else {
      path <- paste0(path, "[", segment$value, "]")
    }
  }
  path
}
