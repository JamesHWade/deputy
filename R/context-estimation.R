# ellmer 0.5.0 cannot build its token-preview table when retained tool results
# have no subsequent assistant response. Ask its public estimator using the
# last completed pair (whose reported input includes prior context), plus
# subsequent content. This view is only for estimation; canonical turns stay
# intact and no provider encoding or synthetic response is introduced.
context_count_after_unpaired_result <- function(chat, messages) {
  tryCatch(
    {
      turns <- chat$get_turns()
      completed <- which(vapply(
        turns,
        function(turn) {
          inherits(turn, "ellmer::AssistantTurn") &&
            !inherits(turn, "ellmer::AssistantPartialTurn")
        },
        logical(1)
      ))
      user_count <- sum(vapply(
        turns,
        inherits,
        logical(1),
        what = "ellmer::UserTurn"
      ))
      if (user_count == length(completed)) {
        return(NULL)
      }
      if (!length(completed)) {
        return(NULL)
      }
      last <- tail(completed, 1L)
      users <- which(vapply(
        utils::head(turns, last - 1L),
        inherits,
        logical(1),
        what = "ellmer::UserTurn"
      ))
      if (!length(users)) {
        return(NULL)
      }
      estimate <- clone_governed_chat(chat)
      estimate$set_turns(list(turns[[tail(users, 1L)]], turns[[last]]))
      pending <- if (last < length(turns)) {
        unlist(
          lapply(turns[(last + 1L):length(turns)], function(turn) {
            turn@contents
          }),
          recursive = FALSE
        )
      } else {
        list()
      }
      chat_token_count(estimate, c(pending, messages))
    },
    error = function(error) NULL
  )
}

# Ask a Chat for its complete context size, or NULL when it cannot count.
# Calls to ellmer's own token_count() skip failures already observed: the
# unpaired token table, and providers without a token-counting method.
chat_token_count <- function(chat, messages) {
  ellmer_count <- is_ellmer_token_count(chat)
  turns <- NULL
  if (ellmer_count) {
    if (ellmer_token_count_unsupported(chat)) {
      return(NULL)
    }
    turns <- tryCatch(chat$get_turns(), error = function(e) NULL)
    if (!is.null(turns) && ellmer_token_table_fails(turns)) {
      return(NULL)
    }
  }
  tryCatch(
    do.call(chat$token_count, c(messages, list(include = "complete"))),
    error = function(error) {
      if (ellmer_count) {
        ellmer_token_count_observe(chat, error)
        ellmer_token_table_observe(turns, error)
      }
      NULL
    }
  )
}

is_ellmer_token_count <- function(chat) {
  is_ellmer_chat_method(chat, "token_count") &&
    is_ellmer_chat_method(chat, "get_tokens") &&
    is_ellmer_chat_method(chat, "get_provider")
}

# ellmer dispatches token counting on the provider's S7 class; its base method
# reports every provider without a specialised method as unsupported, and some
# compatible endpoints (such as API gateways) lack the counting route that
# their class calls. Observations are keyed by class and base URL, so one
# endpoint cannot disable counting for another of the same class. Methods are
# registered when a package loads, so an observation is kept only while the
# same namespaces and ellmer Chat method remain.
ellmer_token_count_provider <- function(chat) {
  provider <- tryCatch(chat$get_provider(), error = function(e) NULL)
  if (is.null(provider)) {
    return(NULL)
  }
  base_url <- tryCatch(provider@base_url, error = function(e) NULL)
  if (!is.character(base_url) || length(base_url) != 1L || is.na(base_url)) {
    base_url <- ""
  }
  paste0(paste(class(provider), collapse = "/"), " ", base_url)
}

ellmer_token_count_current <- function(observed) {
  !is.null(observed) &&
    identical(observed$body, body(ellmer::Chat$public_methods$token_count)) &&
    identical(observed$namespaces, loadedNamespaces())
}

ellmer_token_count_unsupported <- function(chat) {
  observed <- ellmer_observations$token_count
  if (!length(observed$unsupported) || !is_ellmer_token_count(chat)) {
    return(FALSE)
  }
  provider <- ellmer_token_count_provider(chat)
  !is.null(provider) &&
    provider %in% observed$unsupported &&
    ellmer_token_count_current(observed)
}

# ellmer's "not implemented" error, or an HTTP status meaning the endpoint has
# no counting route. Other failures (rate limits, outages) may be transient.
token_count_unavailable_error <- function(error) {
  if (inherits(error, "not_implemented")) {
    return(grepl(
      "doesn't support token counting",
      conditionMessage(error),
      fixed = TRUE
    ))
  }
  if (!inherits(error, "httr2_http")) {
    return(FALSE)
  }
  status <- error$status
  if (!is.numeric(status) || length(status) != 1L) {
    status <- suppressWarnings(as.numeric(sub(
      "^httr2_http_",
      "",
      grep("^httr2_http_[0-9]+$", class(error), value = TRUE)[1L]
    )))
  }
  length(status) == 1L && !is.na(status) && status %in% c(404, 405, 501)
}

ellmer_token_count_observe <- function(chat, error) {
  if (!token_count_unavailable_error(error)) {
    return(invisible(NULL))
  }
  provider <- ellmer_token_count_provider(chat)
  if (is.null(provider)) {
    return(invisible(NULL))
  }
  observed <- ellmer_observations$token_count
  if (!ellmer_token_count_current(observed)) {
    observed <- list(
      body = body(ellmer::Chat$public_methods$token_count),
      namespaces = loadedNamespaces(),
      unsupported = character()
    )
  }
  observed$unsupported <- union(observed$unsupported, provider)
  ellmer_observations$token_count <- observed
  invisible(NULL)
}

# Local context estimates ---------------------------------------------------

# Deliberately conservative: typical English text and JSON average about four
# characters per token, and one image costs at most about 1,600 tokens on
# common providers. Text is measured in UTF-8 bytes, not characters: ASCII is
# one byte per character, while CJK text and emoji take three or four bytes
# for what can be a whole token each, so a per-character ratio would badly
# under-count them. Over-estimating compacts slightly early; under-estimating
# can overflow the model's context.
context_estimate_bytes_per_token <- 3
context_estimate_image_tokens <- 1600
# A document page: providers send its extracted text and, for PDFs, often an
# image of the page as well.
context_estimate_page_tokens <- 3000

estimate_text_tokens <- function(text) {
  text <- as.character(text)
  if (!length(text)) {
    return(0)
  }
  bytes <- nchar(enc2utf8(text), type = "bytes")
  ceiling(sum(bytes) / context_estimate_bytes_per_token)
}

# Tokens for model-facing content: turns, content objects, strings or lists.
# Tool requests count their JSON arguments; tool results their public text or
# JSON value, the same projection compaction summarizes.
estimate_content_tokens <- function(content) {
  if (is.null(content)) {
    return(0)
  }
  if (is.character(content)) {
    return(estimate_text_tokens(content))
  }
  if (inherits(content, "ellmer::Turn")) {
    return(estimate_content_tokens(content@contents))
  }
  if (inherits(content, "ellmer::ContentImage")) {
    return(context_estimate_image_tokens)
  }
  if (inherits(content, "ellmer::ContentPDF")) {
    return(estimate_document_tokens(content@data, "application/pdf"))
  }
  if (inherits(content, "ellmer::ContentDocument")) {
    return(estimate_document_tokens(content@data, content@mime_type))
  }
  if (inherits(content, "ellmer::ContentToolRequest")) {
    return(estimate_text_tokens(c(
      content@id,
      content@name,
      public_json_text(content@arguments)
    )))
  }
  if (inherits(content, "ellmer::ContentToolResult")) {
    if (!is.null(content@error)) {
      error <- content@error
      return(estimate_text_tokens(
        if (inherits(error, "condition")) conditionMessage(error) else error
      ))
    }
    value <- content@value
    if (inherits(value, "ellmer::Content") || is_native_content_list(value)) {
      return(estimate_content_tokens(value))
    }
    return(estimate_text_tokens(public_tool_value_text(
      project_tool_content(value)
    )))
  }
  if (inherits(content, "ellmer::Content")) {
    return(estimate_text_tokens(public_content_text(content)))
  }
  if (is.list(content)) {
    return(sum(vapply(content, estimate_content_tokens, numeric(1))))
  }
  estimate_text_tokens(tryCatch(
    public_json_text(content),
    error = function(error) paste(format(content), collapse = "\n")
  ))
}

# An inline document is sent whole, so it costs far more than its short
# display text. A PDF counts per page (page objects in its body, or its size
# at ~50 KB a page when they are compressed out of sight); any other document
# at least counts its payload as text.
estimate_document_tokens <- function(data, mime_type = "") {
  payload <- tryCatch(
    jsonlite::base64_dec(paste(data, collapse = "")),
    error = function(error) NULL
  )
  bytes <- if (is.null(payload)) {
    ceiling(sum(nchar(data, type = "bytes")) * 3 / 4)
  } else {
    length(payload)
  }
  by_payload <- ceiling(bytes / context_estimate_bytes_per_token)
  if (!identical(mime_type, "application/pdf")) {
    return(max(context_estimate_page_tokens, by_payload))
  }
  pages <- if (is.null(payload)) {
    0L
  } else {
    length(grepRaw("/Type[[:space:]]*/Page[^s]", payload, all = TRUE))
  }
  if (pages == 0L) {
    pages <- max(1, ceiling(bytes / 50000))
  }
  pages * context_estimate_page_tokens
}

# Tool definitions are sent with every request; count their names,
# descriptions and argument schema text.
estimate_tool_tokens <- function(tools) {
  schema_text <- function(value) {
    if (is.character(value)) {
      return(value)
    }
    if (S7::S7_inherits(value)) {
      value <- S7::props(value)
    }
    if (is.list(value)) {
      return(c(
        names(value),
        unlist(lapply(value, schema_text), use.names = FALSE)
      ))
    }
    character()
  }
  sum(vapply(
    tools,
    function(tool) {
      estimate_text_tokens(c(
        tool@name,
        tool@description,
        schema_text(tool@arguments)
      ))
    },
    numeric(1)
  ))
}

# The index and size of the latest completed response's reported context:
# its input (which covers the system prompt, tools and earlier turns), cached
# input and output, which is now part of the context. `after` excludes turns
# whose usage describes a different context, such as one before compaction.
reported_context_usage <- function(turns, after = 0L) {
  for (index in rev(seq_along(turns))) {
    if (index <= after) {
      break
    }
    turn <- turns[[index]]
    if (
      !inherits(turn, "ellmer::AssistantTurn") ||
        inherits(turn, "ellmer::AssistantPartialTurn")
    ) {
      next
    }
    tokens <- suppressWarnings(as.numeric(turn@tokens))
    if (length(tokens) < 1L || !is.finite(tokens[[1L]])) {
      next
    }
    output <- if (length(tokens) >= 2L && is.finite(tokens[[2L]])) {
      tokens[[2L]]
    } else {
      estimate_content_tokens(turn)
    }
    cached <- if (length(tokens) >= 3L && is.finite(tokens[[3L]])) {
      tokens[[3L]]
    } else {
      0
    }
    return(list(index = index, tokens = tokens[[1L]] + cached + output))
  }
  NULL
}

# A local estimate of the complete context. With `use_usage`, the latest
# trustworthy reported usage replaces the estimate of everything it covered.
local_context_estimate <- function(
  system_prompt,
  tools,
  turns,
  messages,
  use_usage = TRUE,
  usage_after = 0L,
  frame_snapshots = list()
) {
  pending <- estimate_content_tokens(messages)
  frame <- estimate_frame_tokens(system_prompt, tools)
  usage <- if (use_usage) reported_context_usage(turns, usage_after)
  if (!is.null(usage)) {
    later <- if (usage$index < length(turns)) {
      turns[(usage$index + 1L):length(turns)]
    } else {
      list()
    }
    return(
      usage$tokens +
        frame_growth(frame, frame_snapshots, usage$index) +
        estimate_content_tokens(later) +
        pending
    )
  }
  frame + estimate_content_tokens(turns) + pending
}

# The system prompt and tool definitions every request carries.
estimate_frame_tokens <- function(system_prompt, tools) {
  estimate_text_tokens(system_prompt %||% character()) +
    estimate_tool_tokens(tools)
}

# How much the prompt and tools have grown since the request that produced
# the usage anchored at `index`. Reported usage covers the prompt and tools
# of that request; `$set_system_prompt()`, `$set_tools()` and friends can
# enlarge them afterwards. `snapshots` records the frame before each
# estimated request (with the turn count then), so the frame the anchor's
# request carried is the latest snapshot taken before that turn. Turns
# installed wholesale have a baseline at turn 0 (the frame when they were
# installed); without any record, the anchor is trusted as it is. Shrinkage
# is not subtracted: over-estimating only compacts early.
frame_growth <- function(frame, snapshots, index) {
  before <- Filter(function(snapshot) snapshot$turns < index, snapshots)
  if (!length(before)) {
    return(0)
  }
  max(0, frame - before[[length(before)]]$frame)
}
