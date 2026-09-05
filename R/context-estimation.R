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
        head(turns, last - 1L),
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
      do.call(
        estimate$token_count,
        c(pending, messages, list(include = "complete"))
      )
    },
    error = function(error) NULL
  )
}
