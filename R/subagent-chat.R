subagent_chat_dependencies <- function() {
  rlang::check_installed(
    c("shiny", "shinychat", "bslib", "commonmark", "xml2"),
    reason = "to display child conversations"
  )
  if (utils::packageVersion("shinychat") < "0.5.0") {
    cli::cli_abort("Child chat inspection requires shinychat >= 0.5.0.")
  }
}

subagent_chat_lineage <- function(runtime, compact = FALSE) {
  if (!is.list(runtime)) {
    return("")
  }
  parts <- character()
  depth <- runtime$depth
  if (
    is.numeric(depth) &&
      length(depth) == 1L &&
      !is.na(depth) &&
      is.finite(depth)
  ) {
    parts <- c(parts, paste0("Depth ", as.integer(depth)))
  }
  if (isTRUE(compact)) {
    return(paste(parts, collapse = " \u00b7 "))
  }
  parent_delegation_id <- runtime$parent_delegation_id
  if (is_nonempty_string(parent_delegation_id)) {
    parts <- c(
      parts,
      paste0(
        "Parent delegation ",
        inspection_text(parent_delegation_id, 80L)
      )
    )
  } else if (is_nonempty_string(runtime$parent_agent_id)) {
    parts <- c(
      parts,
      paste0("Parent agent ", inspection_text(runtime$parent_agent_id, 80L))
    )
  }
  if (is_nonempty_string(runtime$root_agent_id)) {
    parts <- c(
      parts,
      paste0("Root ", inspection_text(runtime$root_agent_id, 80L))
    )
  }
  paste(parts, collapse = " \u00b7 ")
}

#' Inspect child conversations in an optional Shiny panel
#'
#' Compose this panel beside the host's lead chat. Activity cards select one
#' separately retained child conversation. Public ellmer Content is rendered
#' through shinychat's public APIs, including native tool cards and attachments.
#' The panel has no prompt handler and cannot resume or approve a child.
#' @param id Shiny module ID.
#' @param height Height of the read-only child chat, default `"420px"`.
#' @return A bslib card. Requires optional shiny, shinychat >= 0.5.0, bslib,
#'   commonmark and xml2.
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
        choices = character(),
        selectize = FALSE
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
#' @param lead A host-owned Agent or LeadAgent, or a function returning it.
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
    state$requester <- NULL
    state$history <- NULL
    state$partial <- ""
    state$partial_cursor <- NULL
    state$rendered <- NULL
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
      state$partial_cursor <- NULL
      state$rendered <- NULL
    }
    failure <- function(error) {
      detach()
      selected(NULL)
      update_views(list())
      clear()
      notice("This child view is unavailable or access was denied.")
      invisible(NULL)
    }
    render_child <- function(force = FALSE) {
      id <- selected()
      if (is.null(id) || closed()) {
        return(FALSE)
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
      current <- filter_views(current)
      if (!length(current)) {
        selected(NULL)
        clear()
        notice("The selected child history is missing or no longer available.")
        return(FALSE)
      }
      view <- current[[1L]]
      if (!force && identical(view, state$rendered)) {
        return(FALSE)
      }
      previous_cursor <- if (
        !force &&
          identical(
            state$rendered$outcome$runtime$delegation_id,
            id
          )
      ) {
        state$partial_cursor
      }
      clear()
      state$rendered <- view
      if (!is.null(state$reader)) {
        state$partial_cursor <- previous_cursor %||%
          state$reader$snapshot()$cursor
      }
      for (message in subagent_chat_messages(view$turns)) {
        shinychat::chat_append_message(
          "transcript",
          message,
          chunk = FALSE,
          session = session
        )
      }
      runtime <- view$outcome$runtime
      lineage <- subagent_chat_lineage(runtime, compact = TRUE)
      notice(paste(
        "Child",
        runtime$agent_name,
        "\u2014",
        runtime$status,
        if (!is.null(runtime$stop_reason)) {
          paste0("(", runtime$stop_reason, ")")
        } else {
          ""
        },
        if (nzchar(lineage)) paste0("\u00b7 ", lineage) else ""
      ))
      TRUE
    }
    filter_views <- function(next_views) {
      Filter(
        function(view) {
          id <- view$outcome$runtime$delegation_id
          is.character(id) && length(id) == 1L && !is.na(id) && nzchar(id)
        },
        next_views
      )
    }
    update_views <- function(next_views) {
      next_views <- filter_views(next_views)
      ids <- vapply(
        next_views,
        function(view) view$outcome$runtime$delegation_id,
        character(1)
      )
      if (!is.null(selected()) && !selected() %in% ids) {
        selected(NULL)
        clear()
        notice("The selected child is no longer available.")
      }
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
              view$outcome$runtime$agent_name %||% "Child",
              view$outcome$runtime$status %||% "Status unavailable",
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
          saved <- value(history)
          current_lead <- value(lead)
          current_requester <- requester()
          requester_changed <- !identical(current_requester, state$requester)
          if (requester_changed) {
            detach()
            clear()
            state$requester <- current_requester
          }
          if (!is.null(saved)) {
            detach()
            current <- delegation_history(
              saved,
              requester(),
              value(disclosure),
              value(scope)
            )
            current <- filter_views(current)
            if (
              requester_changed ||
                !identical(saved, state$history) ||
                !identical(current, views())
            ) {
              state$history <- saved
              update_views(current)
              render_child()
            }
            return()
          }
          if (!inherits(current_lead, "Agent")) {
            cli::cli_abort("No live lead is available.")
          }
          if (closed()) {
            detach()
            current <- filter_views(current_lead$inspect_subagents(
              current_requester
            ))
            if (!identical(current, views())) {
              update_views(current)
            }
            return()
          }
          changed <- !identical(current_lead, state$lead) ||
            !is.null(state$history)
          state$history <- NULL
          if (changed || is.null(state$reader)) {
            detach()
            clear()
            state$lead <- current_lead
            state$reader <- current_lead$observe_subagents(current_requester)
            update_views(state$reader$snapshot()$children)
            render_child()
          }
          update <- state$reader$poll()
          fresh_views <- filter_views(current_lead$inspect_subagents(
            current_requester
          ))
          disclosure_changed <- !identical(fresh_views, views())
          if (
            length(update$events) || length(update$gaps) || disclosure_changed
          ) {
            update_views(fresh_views)
          }
          # Re-read selected content under the current policy, even when only
          # mutable host disclosure state changed. Repaint only changed views.
          render_child(force = length(update$gaps) > 0L)
          if (length(update$gaps)) {
            notice(
              "Some live events were missed. Recovered retained child history."
            )
          }
          if (!is.null(selected()) && !closed()) {
            if (is.null(state$partial_cursor)) {
              state$partial_cursor <- update$cursor
            } else {
              # Re-read the bounded retained event suffix to reapply redaction
              # to cached streamed text as well as newly arriving text.
              reader <- current_lead$observe_subagents(
                current_requester,
                selected(),
                after = state$partial_cursor
              )
              recent <- tryCatch(reader$poll(), finally = reader$close())
              partial <- ""
              truncated <- FALSE
              if (length(recent$gaps)) {
                render_child(force = TRUE)
                state$partial_cursor <- recent$cursor
                notice(
                  "Some live events were missed. Recovered retained child history."
                )
              } else {
                for (event in recent$events) {
                  # Completed requests now live in retained history. A new
                  # request starts a fresh preview; settlement clears it.
                  if (
                    isTRUE(
                      event$type %in%
                        c("request_start", "request_end", "settled")
                    )
                  ) {
                    partial <- ""
                    truncated <- FALSE
                  }
                  if (identical(event$type, "text")) {
                    combined <- paste0(partial, event$data$text)
                    truncated <- truncated ||
                      nchar(enc2utf8(combined), type = "bytes") > 8192L
                    partial <- inspection_text(combined, 8192L)
                  }
                  if (!is.null(event$data$content_omitted)) {
                    notice(
                      "Large live content was omitted. Retained history remains available."
                    )
                  }
                }
              }
              # Ellmer may already expose its accumulated partial turn in the
              # authorized snapshot. Use that native rendering as the sole
              # display until it is committed; do not echo the same text below.
              if (
                any(vapply(
                  state$rendered$turns,
                  inherits,
                  logical(1),
                  "ellmer::AssistantPartialTurn"
                ))
              ) {
                partial <- ""
                truncated <- FALSE
              }
              if (truncated) {
                notice(
                  "Live text preview was truncated. Retained history remains available."
                )
              }
              if (!identical(partial, state$partial)) {
                state$partial <- partial
                shinychat::markdown_stream(
                  "partial",
                  subagent_chat_markdown(partial),
                  session = session
                )
              }
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
        shiny::updateSelectInput(session, "choice", selected = "")
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
          lineage <- subagent_chat_lineage(runtime, compact = TRUE)
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
              Filter(
                function(value) !is.na(value) && nzchar(value),
                c(runtime$status %||% "", runtime$stop_reason %||% "", lineage)
              ),
              sep = " \u00b7 ",
              collapse = " \u00b7 "
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
          isTRUE(view$outcome$runtime$status %in% c("queued", "running"))
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
      lineage <- subagent_chat_lineage(runtime)
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
          if (nzchar(lineage)) {
            shiny::tags$p(paste("Ancestry:", lineage))
          },
          shiny::tags$pre(delegation_json(list(
            runtime = runtime,
            manifest = view$manifest
          )))
        ),
        if (nzchar(view$outcome$answer %||% "")) {
          shiny::tags$details(
            shiny::tags$summary(
              if (identical(runtime$status, "completed")) {
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
    if (inherits(turn, "ellmer::UserTurn")) {
      is_result <- vapply(
        turn@contents,
        function(x) inherits(x, "ellmer::ContentToolResult"),
        logical(1)
      )
      if (any(is_result)) {
        results <- turn
        results@contents <- lapply(
          turn@contents[is_result],
          subagent_chat_safe_content
        )
        content <- shinychat::contents_shinychat(results)
        last <- length(messages)
        if (last && identical(messages[[last]]$role, "assistant")) {
          messages[[last]]$content <- c(messages[[last]]$content, content)
        } else {
          messages[[last + 1L]] <- list(role = "assistant", content = content)
        }
        turn@contents <- turn@contents[!is_result]
      }
      role <- "user"
    } else {
      role <- "assistant"
    }
    # Native user messages are plain text; only assistant messages use Markdown.
    if (identical(role, "assistant")) {
      turn@contents <- lapply(turn@contents, subagent_chat_safe_content)
    }
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

# Render Markdown once, then rebuild only inert HTML. Sanitizing the rendered
# tree preserves literal characters in inline, fenced and indented code.
subagent_chat_markdown <- function(text) {
  if (!nzchar(text)) {
    return("")
  }
  html <- commonmark::markdown_html(text, extensions = TRUE)
  document <- xml2::read_html(paste0("<html><body>", html, "</body></html>"))
  allowed <- c(
    "p",
    "br",
    "hr",
    "pre",
    "code",
    "em",
    "strong",
    "del",
    "blockquote",
    "ul",
    "ol",
    "li",
    paste0("h", 1:6),
    "a",
    "img",
    "table",
    "thead",
    "tbody",
    "tr",
    "th",
    "td"
  )
  safe_url <- function(value) {
    scheme <- gsub("[[:space:][:cntrl:]]", "", value)
    !grepl(":", sub("[/?#].*$", "", scheme)) ||
      grepl("^(https?|mailto):", scheme, ignore.case = TRUE)
  }
  render <- function(node) {
    if (identical(xml2::xml_type(node), "text")) {
      return(xml2::xml_text(node))
    }
    name <- xml2::xml_name(node)
    if (!name %in% allowed) {
      # Unknown markup is visible as text, never sent as executable HTML.
      return(as.character(node))
    }
    attributes <- as.list(xml2::xml_attrs(node))
    attributes <- attributes[intersect(names(attributes), c("title", "alt"))]
    url_field <- switch(name, a = "href", img = "src", NULL)
    if (!is.null(url_field)) {
      url <- xml2::xml_attr(node, url_field)
      if (!is.na(url) && safe_url(url)) attributes[[url_field]] <- url
    }
    if (identical(name, "code")) {
      language <- xml2::xml_attr(node, "class")
      if (!is.na(language) && grepl("^language-[a-zA-Z0-9_-]+$", language)) {
        attributes$class <- language
      }
    }
    if (identical(name, "ol")) {
      start <- xml2::xml_attr(node, "start")
      if (!is.na(start) && grepl("^[0-9]+$", start)) attributes$start <- start
    }
    children <- lapply(xml2::xml_contents(node), render)
    htmltools::tag(name, c(attributes, children))
  }
  body <- xml2::xml_find_first(document, "//body")
  as.character(htmltools::tagList(lapply(xml2::xml_contents(body), render)))
}

subagent_chat_safe_content <- function(content) {
  if (inherits(content, "ellmer::ContentJson")) {
    content <- ellmer::ContentText(ellmer::contents_markdown(content))
  }
  if (inherits(content, "ellmer::ContentText")) {
    content@text <- subagent_chat_markdown(content@text)
  } else if (inherits(content, "ellmer::ContentToolResult")) {
    value <- content@value
    if (
      inherits(value, "ellmer::ContentText") ||
        inherits(value, "ellmer::ContentJson")
    ) {
      value <- list(value)
    }
    # Native tool cards display plain values and errors as code. Only mixed
    # Content lists use Markdown for their text items.
    if (
      is.list(value) &&
        any(vapply(value, inherits, logical(1), "ellmer::Content"))
    ) {
      content@value <- lapply(value, function(item) {
        if (inherits(item, "ellmer::Content")) {
          subagent_chat_safe_content(item)
        } else {
          subagent_chat_markdown(paste(as.character(item), collapse = "\n"))
        }
      })
    }
  }
  content
}
