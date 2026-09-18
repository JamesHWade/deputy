subagent_chat_dependencies <- function() {
  rlang::check_installed(c("shiny", "shinychat", "bslib"))
  if (utils::packageVersion("shinychat") < "0.5.0") {
    cli::cli_abort("Child chat inspection requires shinychat >= 0.5.0.")
  }
}

#' Inspect child conversations in an optional Shiny panel
#'
#' Compose this panel beside the host's lead chat. Activity cards select one
#' separately retained child conversation. Public ellmer Content is rendered
#' through shinychat's public APIs, including native tool cards and attachments.
#' The panel has no prompt handler and cannot resume or approve a child.
#' @param id Shiny module ID.
#' @param height Height of the read-only child chat, default `"420px"`.
#' @return A bslib card. Requires optional shiny, shinychat >= 0.5.0 and bslib.
#' @export
subagent_chat_ui <- function(id, height = "420px") {
  subagent_chat_dependencies()
  ns <- shiny::NS(id)
  bslib::card(
    class = "deputy-child-panel",
    fill = FALSE,
    bslib::card_header("Child conversations"),
    bslib::card_body(
      fill = FALSE,
      shiny::uiOutput(ns("activity")),
      shiny::selectInput(
        ns("choice"),
        "Inspect a child conversation",
        choices = character()
      ),
      shiny::tags$div(
        shiny::actionButton(ns("close"), "Close child view", class = "btn-sm"),
        shiny::uiOutput(ns("cancel_control"), inline = TRUE)
      ),
      shiny::tags$h3("Selected child", id = ns("heading"), tabindex = "-1"),
      shiny::tags$div(
        role = "status",
        `aria-live` = "polite",
        shiny::textOutput(ns("notice"))
      ),
      shiny::uiOutput(ns("details")),
      shinychat::chat_ui(
        ns("transcript"),
        class = "deputy-readonly-chat",
        show_history = FALSE,
        enable_cancel = FALSE,
        allow_attachments = FALSE,
        drawer = FALSE,
        height = height,
        width = "100%",
        fill = FALSE
      ),
      shiny::tags$div(
        class = "deputy-child-partial",
        `aria-label` = "Current child output",
        shinychat::output_markdown_stream(ns("partial"), width = "100%")
      ),
      shiny::tags$style(htmltools::HTML(paste(
        ".deputy-readonly-chat .shiny-chat-composer {display:none !important;}",
        ".deputy-child-activity {display:flex;gap:.6rem;overflow-x:auto;padding:.25rem 0 .75rem;flex-shrink:0;}",
        ".deputy-child-card {text-align:left;min-width:13rem;max-width:18rem;white-space:normal;flex-shrink:0;}",
        ".deputy-child-card[aria-pressed=true] {outline:2px solid var(--bs-primary);outline-offset:1px;}",
        ".deputy-child-meta {font-size:.85rem;overflow-wrap:anywhere;}",
        ".deputy-child-panel h3 {font-size:1.1rem;margin-top:1rem;}",
        ".deputy-child-panel pre {max-height:12rem;overflow:auto;white-space:pre-wrap;}",
        ".deputy-child-partial:empty {display:none;}"
      ))),
      shiny::tags$script(htmltools::HTML(
        "if (!window.deputyChildFocusInstalled) { window.deputyChildFocusInstalled = true; Shiny.addCustomMessageHandler('deputy-child-focus', function(x) { const e = document.getElementById(x.id); if(e) e.focus(); }); }"
      ))
    )
  )
}

#' @rdname subagent_chat_ui
#' @param lead A host-owned LeadAgent, or a reactive/function returning it.
#' @param requester Function returning the authenticated host request context.
#' @param history Optional reactive/function returning saved settled child
#'   history; returning NULL selects the live lead. No active recovery occurs.
#' @param disclosure,scope For saved history, current [DelegationDisclosure] and
#'   fixed trusted host scope (or functions returning them). They must come from
#'   host ownership records, independently of the snapshot or browser input.
#' @param on_cancel Optional host-authorized `function(delegation_id, requester)`.
#'   The callback owns action authorization and may call `interrupt_subagent()`.
#'   Omit it for a completely read-only panel. It is never invoked by selection,
#'   replay, observation or closing the panel.
#' @param poll_interval Poll interval in milliseconds, at least 100, default 250.
#' @return `subagent_chat_server()` returns reactive `selected`, `views`, `notice`
#'   and `closed` values for host composition/testing. No runtime generator is
#'   returned or consumed. Optional packages are checked only when invoked.
#' @export
subagent_chat_server <- function(
  id,
  lead,
  requester,
  history = NULL,
  disclosure = NULL,
  scope = NULL,
  on_cancel = NULL,
  poll_interval = 250L
) {
  subagent_chat_dependencies()
  if (
    !is.function(requester) || (!is.null(on_cancel) && !is.function(on_cancel))
  ) {
    cli::cli_abort("requester and any on_cancel callback must be functions.")
  }
  poll_interval <- context_policy_whole_number(poll_interval, "poll_interval")
  if (is.null(poll_interval) || poll_interval < 100L) {
    cli::cli_abort("poll_interval must be at least 100 milliseconds.")
  }
  value <- function(x) if (is.function(x)) x() else x
  shiny::moduleServer(id, function(input, output, session) {
    selected <- shiny::reactiveVal(NULL)
    views <- shiny::reactiveVal(list())
    notice <- shiny::reactiveVal("Select a child to inspect its conversation.")
    closed <- shiny::reactiveVal(FALSE)
    state <- new.env(parent = emptyenv())
    state$reader <- NULL
    state$lead <- NULL
    state$history <- NULL
    state$partial <- ""
    detach <- function() {
      if (!is.null(state$reader)) {
        state$reader$close()
      }
      state$reader <- NULL
    }
    clear <- function() {
      shinychat::chat_clear("transcript", session = session)
      shinychat::markdown_stream("partial", "", session = session)
      state$partial <- ""
    }
    failure <- function(error) {
      detach()
      selected(NULL)
      update_views(list())
      clear()
      notice("This child view is unavailable or access was denied.")
      invisible(NULL)
    }
    render_child <- function() {
      id <- selected()
      if (is.null(id) || closed()) {
        return(invisible(NULL))
      }
      saved <- value(history)
      current <- if (is.null(saved)) {
        value(lead)$inspect_subagents(requester(), id, transcript = TRUE)
      } else {
        Filter(
          function(view) identical(view$outcome$runtime$delegation_id, id),
          delegation_history(
            saved,
            requester(),
            value(disclosure),
            value(scope)
          )
        )
      }
      if (!length(current)) {
        selected(NULL)
        clear()
        notice("The selected child history is missing or no longer available.")
        return(invisible(NULL))
      }
      view <- current[[1L]]
      clear()
      for (message in subagent_chat_messages(view$turns)) {
        shinychat::chat_append_message(
          "transcript",
          message,
          chunk = FALSE,
          session = session
        )
      }
      runtime <- view$outcome$runtime
      notice(paste(
        "Child",
        runtime$agent_name,
        "\u2014",
        runtime$status,
        if (!is.null(runtime$stop_reason)) {
          paste0("(", runtime$stop_reason, ")")
        } else {
          ""
        }
      ))
      invisible(view)
    }
    update_views <- function(next_views) {
      views(next_views)
      choices <- stats::setNames(
        vapply(
          next_views,
          function(view) view$outcome$runtime$delegation_id,
          character(1)
        ),
        vapply(
          next_views,
          function(view) {
            paste(
              view$outcome$runtime$agent_name,
              view$outcome$runtime$status,
              inspection_text(view$task, 50L),
              sep = " \u00b7 "
            )
          },
          character(1)
        )
      )
      shiny::updateSelectInput(
        session,
        "choice",
        choices = c("Choose a child" = "", choices),
        selected = selected() %||% ""
      )
    }
    shiny::observe({
      shiny::invalidateLater(poll_interval, session)
      shiny::isolate(tryCatch(
        {
          if (closed()) {
            return()
          }
          saved <- value(history)
          current_lead <- value(lead)
          if (!is.null(saved)) {
            detach()
            current <- delegation_history(
              saved,
              requester(),
              value(disclosure),
              value(scope)
            )
            if (
              !identical(saved, state$history) || !identical(current, views())
            ) {
              state$history <- saved
              update_views(current)
              render_child()
            }
            return()
          }
          if (!inherits(current_lead, "LeadAgent")) {
            cli::cli_abort("No live lead is available.")
          }
          changed <- !identical(current_lead, state$lead) ||
            !is.null(state$history)
          state$history <- NULL
          if (changed || is.null(state$reader)) {
            detach()
            state$lead <- current_lead
            state$reader <- current_lead$observe_subagents(requester())
            update_views(state$reader$snapshot()$children)
            render_child()
          }
          update <- state$reader$poll()
          fresh_views <- current_lead$inspect_subagents(requester())
          disclosure_changed <- !identical(fresh_views, views())
          if (
            length(update$events) || length(update$gaps) || disclosure_changed
          ) {
            update_views(fresh_views)
            chosen <- Filter(
              function(event) identical(event$delegation_id, selected()),
              update$events
            )
            refresh <- disclosure_changed ||
              length(update$gaps) ||
              any(vapply(
                chosen,
                function(event) {
                  event$type %in%
                    c("tool_start", "tool_end", "turn", "stop", "settled")
                },
                logical(1)
              ))
            if (refresh) {
              render_child()
            }
            if (length(update$gaps)) {
              notice(
                "Some live events were missed. Recovered retained child history."
              )
            }
            if (!refresh) {
              for (event in chosen) {
                if (event$type == "text") {
                  partial <- paste0(state$partial, event$data$text)
                  state$partial <- inspection_text(partial, 8192L)
                  if (nchar(enc2utf8(partial), type = "bytes") > 8192L) {
                    notice(
                      "Live text preview was truncated. Retained history remains available."
                    )
                  }
                }
                if (!is.null(event$data$content_omitted)) {
                  notice(
                    "Large live content was omitted. Retained history remains available."
                  )
                }
              }
              shinychat::markdown_stream(
                "partial",
                htmltools::htmlEscape(state$partial),
                session = session
              )
            }
          }
        },
        error = failure
      ))
    })
    choose <- function(id) {
      if (is.null(id) || !nzchar(id)) {
        return(invisible(NULL))
      }
      if (identical(selected(), id) && !closed()) {
        return(invisible(NULL))
      }
      closed(FALSE)
      selected(id)
      shiny::updateSelectInput(session, "choice", selected = id)
      tryCatch(render_child(), error = failure)
      session$sendCustomMessage(
        "deputy-child-focus",
        list(id = session$ns("heading"))
      )
    }
    shiny::observeEvent(
      input$selected,
      choose(input$selected),
      ignoreInit = TRUE
    )
    shiny::observeEvent(input$choice, choose(input$choice), ignoreInit = TRUE)
    shiny::observeEvent(
      input$close,
      {
        detach()
        closed(TRUE)
        selected(NULL)
        clear()
        notice("Child view closed. Running children continue.")
        session$sendCustomMessage(
          "deputy-child-focus",
          list(id = session$ns("choice"))
        )
      },
      ignoreInit = TRUE
    )
    shiny::observeEvent(
      input$cancel,
      {
        if (
          is.null(on_cancel) || is.null(selected()) || !is.null(value(history))
        ) {
          return()
        }
        tryCatch(
          {
            on_cancel(selected(), requester())
            notice("Cancellation requested. Waiting for the child to settle.")
          },
          error = function(error) {
            notice("The host did not authorize cancellation.")
          }
        )
      },
      ignoreInit = TRUE
    )
    session$onSessionEnded(detach)
    output$notice <- shiny::renderText(notice())
    output$activity <- shiny::renderUI({
      if (!length(views())) {
        return(shiny::tags$p("No child activity to display."))
      }
      shiny::tags$div(
        class = "deputy-child-activity",
        role = "group",
        `aria-label` = "Child activity",
        lapply(views(), function(view) {
          runtime <- view$outcome$runtime
          onclick <- paste0(
            "Shiny.setInputValue(",
            delegation_json(session$ns("selected")),
            ",",
            delegation_json(runtime$delegation_id),
            ",{priority:'event'});"
          )
          shiny::tags$button(
            type = "button",
            class = "btn btn-outline-secondary deputy-child-card",
            `aria-pressed` = if (identical(selected(), runtime$delegation_id)) {
              "true"
            } else {
              "false"
            },
            onclick = onclick,
            shiny::tags$strong(runtime$agent_name),
            shiny::tags$br(),
            inspection_text(view$task, 140L),
            shiny::tags$br(),
            shiny::tags$small(paste(
              runtime$status,
              runtime$stop_reason %||% "",
              sep = " \u00b7 "
            ))
          )
        })
      )
    })
    selected_view <- shiny::reactive({
      matches <- Filter(
        function(view) {
          identical(view$outcome$runtime$delegation_id, selected())
        },
        views()
      )
      if (length(matches)) matches[[1L]] else NULL
    })
    output$cancel_control <- shiny::renderUI({
      view <- selected_view()
      if (
        !is.null(on_cancel) &&
          is.null(value(history)) &&
          !is.null(view) &&
          view$outcome$runtime$status %in% c("queued", "running")
      ) {
        shiny::actionButton(
          session$ns("cancel"),
          "Cancel selected child",
          class = "btn-sm btn-outline-danger"
        )
      }
    })
    output$details <- shiny::renderUI({
      view <- selected_view()
      if (is.null(view) || closed()) {
        return(NULL)
      }
      runtime <- view$outcome$runtime
      cost <- view$usage$cost_usd
      cost_label <- if (is.null(cost) || is.na(cost)) {
        "Cost unknown"
      } else {
        paste0("Estimated cost $", format(cost, digits = 4))
      }
      shiny::tags$div(
        class = "deputy-child-meta",
        shiny::tags$p(paste0(
          view$usage$total_tokens %||% "Unknown",
          " tokens \u00b7 ",
          cost_label,
          " \u00b7 Task success not assessed"
        )),
        shiny::tags$details(
          shiny::tags$summary("Identity and initial context"),
          shiny::tags$pre(delegation_json(list(
            runtime = runtime,
            manifest = view$manifest
          )))
        ),
        if (nzchar(view$outcome$answer %||% "")) {
          shiny::tags$details(
            shiny::tags$summary(
              if (runtime$status == "completed") {
                "Outcome"
              } else {
                "Partial outcome"
              }
            ),
            shiny::tags$pre(view$outcome$answer)
          )
        },
        shiny::tags$p(paste(
          "Missing evidence:",
          view$outcome$claims$missing_evidence %||% "not supplied"
        )),
        shiny::tags$p(paste(
          "Unresolved work:",
          view$outcome$claims$unresolved_work %||% "not supplied"
        )),
        lapply(view$outcome$references, function(ref) {
          shiny::tags$p(
            paste(
              "Artifact",
              ref$availability %||% "unresolved",
              "\u2014 verification not assessed"
            )
          )
        }),
        lapply(Filter(Negate(is.null), view$errors), function(error) {
          shiny::tags$pre(error)
        })
      )
    })
    list(
      selected = shiny::reactive(selected()),
      views = shiny::reactive(views()),
      notice = shiny::reactive(notice()),
      closed = shiny::reactive(closed())
    )
  })
}

# Keep tool requests and results in the same assistant message so shinychat's
# native tool cards can match them, including results carried by user turns.
subagent_chat_messages <- function(turns) {
  messages <- list()
  for (turn in turns) {
    results_only <- length(turn@contents) > 0L &&
      all(vapply(
        turn@contents,
        function(x) inherits(x, "ellmer::ContentToolResult"),
        logical(1)
      ))
    role <- if (inherits(turn, "ellmer::UserTurn") && !results_only) {
      "user"
    } else {
      "assistant"
    }
    turn@contents <- lapply(turn@contents, subagent_chat_safe_content)
    content <- shinychat::contents_shinychat(turn)
    if (!length(content)) {
      next
    }
    last <- length(messages)
    if (last && identical(messages[[last]]$role, role)) {
      messages[[last]]$content <- c(messages[[last]]$content, content)
    } else {
      messages[[last + 1L]] <- list(role = role, content = content)
    }
  }
  messages
}

# Native markdown permits HTML. Escape raw markup in untrusted model/tool text,
# while preserving markdown and typed image/document attachments.
subagent_chat_safe_content <- function(content) {
  if (inherits(content, "ellmer::ContentText")) {
    content@text <- as.character(htmltools::htmlEscape(content@text))
  } else if (
    inherits(content, "ellmer::ContentToolResult") && is.list(content@value)
  ) {
    content@value <- lapply(content@value, subagent_chat_safe_content)
  }
  content
}
