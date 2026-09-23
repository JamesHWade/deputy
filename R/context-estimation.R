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
# reports every provider without a specialised method as unsupported. Methods
# are registered when a package loads, so an observation is kept only while
# the same namespaces and ellmer Chat method remain.
ellmer_token_count_provider <- function(chat) {
  provider <- tryCatch(chat$get_provider(), error = function(e) NULL)
  if (is.null(provider)) {
    return(NULL)
  }
  paste(class(provider), collapse = "/")
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

ellmer_token_count_observe <- function(chat, error) {
  if (
    !inherits(error, "not_implemented") ||
      !grepl(
        "doesn't support token counting",
        conditionMessage(error),
        fixed = TRUE
      )
  ) {
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
