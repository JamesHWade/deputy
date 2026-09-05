runtime_compaction_chat <- function(server, model = "gpt-4o-mini", ...) {
  chat <- runtime_chat(server, model, ...)
  rlang::env_binding_unlock(chat, "token_count")
  chat$token_count <- function(...) 1000
  fixture <- jsonlite::fromJSON(
    test_path("fixtures", "compaction", "evidence-review.json"),
    simplifyVector = FALSE
  )
  chat$set_turns(lapply(fixture$turns, function(turn) {
    if (identical(turn$role, "user")) {
      ellmer::UserTurn(contents = list(ellmer::ContentText(turn$text)))
    } else {
      ellmer::AssistantTurn(contents = list(ellmer::ContentText(turn$text)))
    }
  }))
  chat
}

compaction_hook_log <- function(agent) {
  seen <- new.env(parent = emptyenv())
  seen$events <- character()
  seen$run_ids <- character()
  for (event in c(
    "SessionStart",
    "UserPromptSubmit",
    "PreCompact",
    "PostCompact",
    "Stop",
    "SessionEnd"
  )) {
    agent$add_hook(HookMatcher$new(
      event = event,
      timeout = 0,
      callback = local({
        name <- event
        function(context, ...) {
          seen$events <- c(seen$events, name)
          seen$run_ids <- c(seen$run_ids, context$run_id)
          NULL
        }
      })
    ))
  }
  seen
}
