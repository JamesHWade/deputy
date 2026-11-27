# Typed JSON codec for portable subagent history records ---------------------

history_codec_abort <- function() {
  cli::cli_abort("Saved subagent records are not in a readable form.")
}

history_encode_double <- function(value) {
  if (is.nan(value)) {
    return("NaN")
  }
  if (is.na(value)) {
    return(NULL)
  }
  if (is.infinite(value)) {
    return(if (value > 0) "Inf" else "-Inf")
  }
  # A finite value is saved as its IEEE 754 bits. Decimal text reads back
  # exactly only where R parses it with extended precision, which arm64 lacks,
  # and the C library writes it with the decimal point of LC_NUMERIC.
  bytes <- writeBin(value, raw(), size = 8L, endian = "big")
  paste0("0x", paste(as.character(bytes), collapse = ""))
}

# JSON holds only UTF-8 text. A string that isn't valid UTF-8 once converted
# (marked "bytes", or invalid bytes under another mark) keeps its bytes and its
# mark instead, as base64.
history_encode_text <- function(value) {
  if (is.na(value)) {
    return(NULL)
  }
  mark <- Encoding(value)
  if (!identical(mark, "bytes")) {
    text <- enc2utf8(value)
    if (validUTF8(text)) {
      return(text)
    }
  }
  list(
    b = gsub("\n", "", jsonlite::base64_enc(charToRaw(value))),
    e = mark
  )
}

history_encode <- function(x, depth = 0L) {
  if (depth > 64L) {
    history_codec_abort()
  }
  if (is.null(x)) {
    return(list(t = "null"))
  }
  if (
    is.object(x) ||
      !all(names(attributes(x)) %in% c("names", "dim", "dimnames"))
  ) {
    history_codec_abort()
  }
  values <- unname(x)
  attributes(values) <- NULL
  node <- if (is.pairlist(x)) {
    # is.list() is also true of a pairlist; it keeps its own type.
    list(
      t = "pairlist",
      v = lapply(values, history_encode, depth = depth + 1L)
    )
  } else if (is.list(x)) {
    list(t = "list", v = lapply(values, history_encode, depth = depth + 1L))
  } else if (is.logical(x)) {
    list(
      t = "lgl",
      v = lapply(values, function(value) {
        if (is.na(value)) NULL else value
      })
    )
  } else if (is.integer(x)) {
    list(
      t = "int",
      v = lapply(values, function(value) {
        if (is.na(value)) NULL else format(value, scientific = FALSE)
      })
    )
  } else if (is.double(x)) {
    list(t = "dbl", v = lapply(values, history_encode_double))
  } else if (is.character(x)) {
    list(t = "chr", v = lapply(values, history_encode_text))
  } else if (is.raw(x)) {
    list(t = "raw", v = list(gsub("\n", "", jsonlite::base64_enc(values))))
  } else if (is.complex(x)) {
    list(
      t = "cplx",
      v = lapply(values, function(value) {
        list(history_encode_double(Re(value)), history_encode_double(Im(value)))
      })
    )
  } else {
    history_codec_abort()
  }
  # A names attribute is kept beside dimensions too. A one-dimensional
  # array's `names()` are its dimnames, which are saved as such.
  if ("names" %in% names(attributes(x))) {
    node$n <- lapply(attr(x, "names", exact = TRUE), history_encode_text)
  }
  if (!is.null(dim(x))) {
    node$d <- lapply(dim(x), format, scientific = FALSE)
    if (!is.null(dimnames(x))) {
      node$dn <- history_encode(dimnames(x), depth + 1L)
    }
  }
  node
}

history_json <- function(x) {
  as.character(jsonlite::toJSON(
    history_encode(x),
    auto_unbox = TRUE,
    null = "null",
    na = "null"
  ))
}

history_decode_number <- function(value, integer) {
  if (is.null(value)) {
    return(if (integer) NA_integer_ else NA_real_)
  }
  if (!is.character(value) || length(value) != 1L || is.na(value)) {
    history_codec_abort()
  }
  if (integer) {
    if (!grepl("^-?[0-9]{1,10}$", value)) {
      history_codec_abort()
    }
    number <- as.numeric(value)
    if (abs(number) > .Machine$integer.max) {
      history_codec_abort()
    }
    return(as.integer(number))
  }
  if (identical(value, "NaN")) {
    return(NaN)
  }
  if (identical(value, "Inf")) {
    return(Inf)
  }
  if (identical(value, "-Inf")) {
    return(-Inf)
  }
  if (grepl("^0x[0-9a-f]{16}$", value)) {
    bytes <- as.raw(strtoi(
      substring(value, seq(3L, 17L, 2L), seq(4L, 18L, 2L)),
      16L
    ))
    number <- readBin(bytes, "double", size = 8L, endian = "big")
    if (!is.finite(number)) {
      history_codec_abort()
    }
    return(number)
  }
  # Version 1 records saved finite values as decimal text.
  if (
    !grepl(
      "^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][-+]?[0-9]{1,3})?$",
      value
    )
  ) {
    history_codec_abort()
  }
  as.numeric(value)
}

history_decode_text <- function(value) {
  if (is.null(value)) {
    return(NA_character_)
  }
  if (is.list(value) && !is.object(value)) {
    # A string saved as its bytes, with its encoding mark.
    if (
      !identical(names(value), c("b", "e")) ||
        !is.character(value$e) ||
        length(value$e) != 1L ||
        !value$e %in% c("bytes", "unknown", "UTF-8")
    ) {
      history_codec_abort()
    }
    bytes <- history_decode_raw(list(value$b))
    if (!length(bytes) || any(bytes == as.raw(0L))) {
      history_codec_abort()
    }
    text <- rawToChar(bytes)
    Encoding(text) <- value$e
    return(text)
  }
  if (!is.character(value) || length(value) != 1L || is.na(value)) {
    history_codec_abort()
  }
  value
}

history_decode_raw <- function(values) {
  if (
    length(values) != 1L ||
      !is.character(values[[1L]]) ||
      length(values[[1L]]) != 1L ||
      !grepl("^[A-Za-z0-9+/]*={0,2}$", values[[1L]]) ||
      nchar(values[[1L]]) %% 4L != 0L
  ) {
    history_codec_abort()
  }
  jsonlite::base64_dec(values[[1L]])
}

history_decode <- function(node, depth = 0L) {
  if (
    depth > 64L ||
      !is.list(node) ||
      is.null(names(node)) ||
      anyDuplicated(names(node)) ||
      !all(names(node) %in% c("t", "v", "n", "d", "dn")) ||
      !is.character(node$t) ||
      length(node$t) != 1L
  ) {
    history_codec_abort()
  }
  if (identical(node$t, "null")) {
    if (length(node) != 1L) {
      history_codec_abort()
    }
    return(NULL)
  }
  values <- node$v
  if (!is.list(values) || !is.null(names(values))) {
    history_codec_abort()
  }
  x <- switch(
    node$t,
    list = lapply(values, history_decode, depth = depth + 1L),
    # An empty pairlist is NULL, which is saved as "null".
    pairlist = if (length(values)) {
      as.pairlist(lapply(values, history_decode, depth = depth + 1L))
    } else {
      history_codec_abort()
    },
    lgl = vapply(
      values,
      function(value) {
        if (is.null(value)) {
          return(NA)
        }
        if (!is.logical(value) || length(value) != 1L || is.na(value)) {
          history_codec_abort()
        }
        value
      },
      logical(1)
    ),
    int = vapply(values, history_decode_number, integer(1), integer = TRUE),
    dbl = vapply(values, history_decode_number, double(1), integer = FALSE),
    chr = vapply(values, history_decode_text, character(1)),
    raw = history_decode_raw(values),
    cplx = vapply(
      values,
      function(value) {
        if (!is.list(value) || length(value) != 2L || !is.null(names(value))) {
          history_codec_abort()
        }
        complex(
          real = history_decode_number(value[[1L]], integer = FALSE),
          imaginary = history_decode_number(value[[2L]], integer = FALSE)
        )
      },
      complex(1)
    ),
    history_codec_abort()
  )
  if (!is.null(node$d)) {
    if (!is.list(node$d) || !length(node$d)) {
      history_codec_abort()
    }
    dims <- vapply(node$d, history_decode_number, integer(1), integer = TRUE)
    if (anyNA(dims) || any(dims < 0L) || prod(dims) != length(x)) {
      history_codec_abort()
    }
    dim(x) <- dims
    if (!is.null(node$dn)) {
      dimnames <- history_decode(node$dn, depth + 1L)
      if (!is.list(dimnames) || length(dimnames) != length(dims)) {
        history_codec_abort()
      }
      dimnames(x) <- dimnames
    }
  } else if (!is.null(node$dn)) {
    history_codec_abort()
  }
  # After the dimensions, which would drop them.
  if (!is.null(node$n)) {
    if (!is.list(node$n) || length(node$n) != length(x)) {
      history_codec_abort()
    }
    names(x) <- vapply(node$n, history_decode_text, character(1))
  }
  x
}

history_parse <- function(text) {
  history_decode(jsonlite::parse_json(text, simplifyVector = FALSE))
}

subagent_history_format <- "deputy_conversation_subagents"
subagent_history_version <- 2L
subagent_history_codec <- "deputy_portable_json"

subagent_history_envelope <- function(record) {
  list(
    format = subagent_history_format,
    version = subagent_history_version,
    codec = subagent_history_codec,
    conversation_id = record$conversation_id,
    data = history_json(record)
  )
}

# Check saved values before anything reads them: the envelope, the decoded
# record, its scope and every transcript.
subagent_history_read <- function(saved, lead, conversation_id, max_bytes) {
  scalar <- function(value) {
    if (is.list(value) && length(value) == 1L) value[[1L]] else value
  }
  text <- function(value) {
    value <- scalar(value)
    is.character(value) && length(value) == 1L && !is.na(value)
  }
  if (!is.list(saved)) {
    history_codec_abort()
  }
  version <- scalar(saved$version)
  if (
    !identical(scalar(saved$format), subagent_history_format) ||
      !is.numeric(version) ||
      length(version) != 1L ||
      !isTRUE(version %in% c(1, subagent_history_version)) ||
      !identical(scalar(saved$codec), subagent_history_codec) ||
      !identical(scalar(saved$conversation_id), conversation_id) ||
      !text(saved$data) ||
      nchar(scalar(saved$data), type = "bytes") > 2 * max_bytes
  ) {
    history_codec_abort()
  }
  record <- history_parse(scalar(saved$data))
  inspection_portable(record)
  history <- record$history
  if (
    !is.list(record) ||
      !identical(record$conversation_id, conversation_id) ||
      !is.list(history) ||
      !identical(history$schema_version, 1L) ||
      !identical(history$settled, TRUE) ||
      !identical(
        history$scope,
        subagent_history_scope(lead, conversation_id)
      ) ||
      !is.list(history$children) ||
      !is.character(record$keys) ||
      length(record$keys) != length(history$children) ||
      anyDuplicated(record$keys) ||
      !all(grepl("^[0-9a-f]{64}$", record$keys)) ||
      !is.character(record$pending) ||
      anyDuplicated(record$pending) ||
      !all(grepl("^[0-9a-f]{64}$", record$pending)) ||
      any(record$pending %in% record$keys) ||
      !subagent_history_counts(record$omitted, record$pending)
  ) {
    history_codec_abort()
  }
  for (view in history$children) {
    status <- if (is.list(view)) view$outcome$runtime$status
    if (
      !is.list(view) ||
        (!is.null(status) && !isTRUE(status %in% delegation_settled_statuses))
    ) {
      history_codec_abort()
    }
    lapply(view$transcript, inspection_replay)
  }
  record
}
