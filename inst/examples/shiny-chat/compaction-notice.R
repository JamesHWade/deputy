# Host-owned presentation: these hooks observe compaction without adding turns.
compaction_notice_ui <- function(id) {
  shiny::uiOutput(
    id,
    class = "small text-body-secondary mb-2",
    style = "display: block; max-width: 42rem; margin: 0.75rem auto;"
  )
}

compaction_notice_server <- function(id, agent, chat_module, session) {
  notice <- shiny::reactiveVal(NULL)
  conversation_id <- function() {
    shiny::isolate(chat_module$history$conversation_id())
  }

  agent$add_hook(deputy::HookMatcher(
    event = "PreCompact",
    callback = function(...) {
      current <- shiny::isolate(notice())
      if (!identical(current$conversation_id, conversation_id())) {
        current <- NULL
      }
      notice(list(
        conversation_id = conversation_id(),
        busy = TRUE,
        summary = current$summary
      ))
      NULL
    }
  ))
  agent$add_hook(deputy::HookMatcher(
    event = "PostCompact",
    callback = function(result, ...) {
      notice(list(
        conversation_id = conversation_id(),
        busy = FALSE,
        summary = result$summary
      ))
      NULL
    }
  ))
  agent$add_hook(deputy::HookMatcher(
    event = "Stop",
    callback = function(...) {
      current <- shiny::isolate(notice())
      if (!is.null(current)) {
        current$busy <- FALSE
        notice(current)
      }
      NULL
    }
  ))

  # Native history restores the full transcript, not this summary context.
  # Clear even when navigating branches within the same conversation.
  chat_module$history$on_restore(function(...) notice(NULL))

  session$output[[id]] <- shiny::renderUI({
    current <- notice()
    if (
      is.null(current) ||
        (!isTRUE(current$busy) && is.null(current$summary)) ||
        !identical(
          current$conversation_id,
          chat_module$history$conversation_id()
        )
    ) {
      return(NULL)
    }
    shiny::tagList(
      shiny::tags$p(
        role = "status",
        `aria-live` = "polite",
        class = "mb-1",
        if (isTRUE(current$busy)) {
          "Summarizing earlier messages…"
        } else if (!is.null(current$summary)) {
          paste(
            "Earlier messages summarized for the assistant.",
            "Your full conversation is still available."
          )
        }
      ),
      if (!is.null(current$summary)) {
        shiny::tags$details(
          shiny::tags$summary("View summary"),
          shiny::tags$p(
            class = "mt-2 mb-2",
            paste(
              "The assistant uses this summary alongside recent messages.",
              "Some earlier details may be omitted."
            )
          ),
          shiny::tags$div(
            style = paste(
              "white-space: pre-wrap; overflow-wrap: anywhere;",
              "max-height: 16rem; overflow-y: auto;"
            ),
            current$summary
          )
        )
      }
    )
  })
  invisible(NULL)
}
