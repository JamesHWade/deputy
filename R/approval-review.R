#' Review a pending tool call in Shiny
#'
#' @description
#' A Shiny module for human review of the inputs to a tool call suspended by a
#' durable approval (see `approval_dir` in [Agent] and
#' [PermissionResultPending]). The call stays blocked until the reviewer acts.
#' The module shows each argument with its declared type, description, and
#' proposed value, using [tool_input_review()]. The reviewer can edit simple
#' fields, then approve or deny.
#'
#' Enum, string, number, integer, and boolean fields are editable. Arrays,
#' undeclared fields, and other types are shown read-only. Editors start at
#' the proposed value; a missing optional field starts as "Not provided" and
#' stays missing unless the reviewer sets it. Approval with
#' edits resumes with the edited input, which the tool must validate. Approval
#' without edits resumes with the original input. Deny executes nothing.
#'
#' This is the input review step of Will Landau and Sam Parmar's
#' [trusted mini-agent](https://trustedminiagents.dev/definition.html) pattern:
#' a person checks the model-generated inputs before a trusted tool runs.
#'
#' The server registers a `Stop` hook on `agent`, so the review refreshes when
#' a run suspends. Call it once per Agent, while no run is active.
#'
#' @param id Shiny module ID.
#' @param agent An [Agent] configured with `approval_dir`.
#' @param decide Optional function `(path, decision, tool_input)` that carries
#'   out the decision. The default calls `agent$resume_approval()`
#'   synchronously, which runs the model continuation in this R process.
#'   Supply your own function to run it elsewhere, for example with
#'   `shiny::ExtendedTask`. Its return value is available from `outcome()`.
#' @param session Shiny session.
#' @return `approval_review_ui()` returns a UI tag list.
#'   `approval_review_server()` returns a list of reactives: `pending()` (the
#'   current [ApprovalContinuation] or `NULL`), `outcome()` (a list with
#'   `decision`, `tool_input`, and `result` or `error` after the last decision),
#'   and a `refresh()` function.
#' @seealso [tool_input_review()], [TrustedResults], [approval_read()]
#' @examples
#' if (interactive() && rlang::is_installed("bslib")) {
#'   library(shiny)
#'   ui <- bslib::page_fluid(approval_review_ui("review"))
#'   server <- function(input, output, session) {
#'     agent <- Agent$new(
#'       ellmer::chat("openai/gpt-5.6-luna"),
#'       approval_dir = tempfile()
#'     )
#'     approval_review_server("review", agent)
#'   }
#' }
#' @export
approval_review_ui <- function(id) {
  rlang::check_installed("shiny", reason = "to review tool calls")
  ns <- shiny::NS(id)
  shiny::tags$div(
    class = "deputy-approval-review",
    `aria-live` = "polite",
    shiny::uiOutput(ns("review"))
  )
}

#' @rdname approval_review_ui
#' @export
approval_review_server <- function(
  id,
  agent,
  decide = NULL,
  session = shiny::getDefaultReactiveDomain()
) {
  rlang::check_installed("shiny", reason = "to review tool calls")
  if (!inherits(agent, "Agent")) {
    cli_abort("{.arg agent} must be a deputy Agent.")
  }
  if (!is.null(decide) && !is.function(decide)) {
    cli_abort("{.arg decide} must be NULL or a function.")
  }
  decide <- decide %||%
    function(path, decision, tool_input) {
      agent$resume_approval(path, decision, tool_input = tool_input)
    }
  shiny::moduleServer(
    id,
    function(input, output, session) {
      ns <- session$ns
      version <- shiny::reactiveVal(0L)
      outcome <- shiny::reactiveVal(NULL)
      refresh <- function() {
        version(shiny::isolate(version()) + 1L)
        invisible(NULL)
      }
      agent$add_hook(HookMatcher(
        "Stop",
        timeout = 0,
        callback = function(...) {
          refresh()
          NULL
        }
      ))
      pending <- shiny::reactive({
        version()
        record <- agent$pending_approval()
        if (is.null(record) || !identical(record$status, "pending")) {
          return(NULL)
        }
        record
      })
      review <- shiny::reactive({
        record <- pending()
        if (is.null(record)) {
          return(NULL)
        }
        request <- record$request
        tool_name <- request$tool_name %||% request$name
        tool <- agent$get_tools()[[tool_name]]
        arguments <- if (inherits(tool, "ellmer::ToolDef")) {
          (attr(tool, "deputy_runtime_source_tool", exact = TRUE) %||%
            tool)@arguments
        }
        list(
          record = record,
          tool_name = tool_name,
          input = request$tool_input %||% list(),
          arguments = arguments,
          table = tool_input_review(request$tool_input %||% list(), arguments)
        )
      })

      output$review <- shiny::renderUI({
        current <- review()
        if (is.null(current)) {
          return(shiny::tags$p(
            "No tool call is waiting for review.",
            class = "text-muted"
          ))
        }
        table <- current$table
        rows <- lapply(seq_len(nrow(table)), function(i) {
          row <- table[i, , drop = FALSE]
          shiny::tags$tr(
            shiny::tags$th(scope = "row", row$argument),
            shiny::tags$td(shiny::tags$code(
              if (is.na(row$type)) "undeclared" else row$type
            )),
            shiny::tags$td(approval_review_editor(
              ns,
              i,
              row,
              approval_review_leaf_type(current$arguments, row$argument)
            )),
            shiny::tags$td(
              if (is.na(row$description)) "" else row$description,
              class = "text-muted"
            )
          )
        })
        reason <- current$record$request$reason
        shiny::tagList(
          shiny::tags$p(
            shiny::tags$strong(current$tool_name, .noWS = "after"),
            if (is_nonempty_string(reason)) paste0(": ", reason)
          ),
          shiny::tags$div(
            class = "table-responsive",
            shiny::tags$table(
              class = "table table-sm align-middle",
              shiny::tags$thead(shiny::tags$tr(
                shiny::tags$th(scope = "col", "Argument"),
                shiny::tags$th(scope = "col", "Type"),
                shiny::tags$th(scope = "col", "Value"),
                shiny::tags$th(scope = "col", "Description")
              )),
              shiny::tags$tbody(rows)
            )
          ),
          shiny::actionButton(
            ns("approve"),
            "Approve these inputs",
            class = "btn-primary"
          ),
          shiny::actionButton(ns("deny"), "Deny")
        )
      })

      edited_input <- function(current) {
        value <- current$input
        table <- current$table
        for (i in seq_len(nrow(table))) {
          type <- approval_review_leaf_type(
            current$arguments,
            table$argument[[i]]
          )
          if (is.null(approval_review_kind(type))) {
            next
          }
          new <- input[[paste0("field_", i)]]
          # Leaving a missing field blank keeps it missing.
          if (
            is.null(new) ||
              (is.na(table$value[[i]]) &&
                (identical(new, "") || all(is.na(new))))
          ) {
            next
          }
          # Compare before coercing, so an untouched invalid value such as a
          # boolean "yes" reaches the tool unchanged for it to reject.
          if (approval_review_unchanged(new, table$value[[i]], type)) {
            next
          }
          path <- strsplit(table$argument[[i]], ".", fixed = TRUE)[[1L]]
          value <- approval_review_set(
            value,
            path,
            approval_review_coerce(new, type)
          )
        }
        value
      }

      act <- function(decision) {
        current <- shiny::isolate(review())
        if (is.null(current)) {
          return(invisible(NULL))
        }
        tool_input <- NULL
        if (identical(decision, "approve")) {
          edited <- shiny::isolate(edited_input(current))
          if (!identical(edited, current$input)) {
            tool_input <- edited
          }
        }
        path <- current$record$source$path
        result <- tryCatch(
          list(result = decide(path, decision, tool_input)),
          error = function(error) list(error = conditionMessage(error))
        )
        outcome(c(
          list(decision = decision, tool_input = tool_input),
          result
        ))
        refresh()
        invisible(NULL)
      }
      shiny::observeEvent(input$approve, act("approve"))
      shiny::observeEvent(input$deny, act("deny"))

      list(pending = pending, outcome = outcome, refresh = refresh)
    },
    session = session
  )
}

approval_review_leaf_type <- function(arguments, path) {
  type <- arguments
  for (part in strsplit(path, ".", fixed = TRUE)[[1L]]) {
    if (!inherits(type, "ellmer::TypeObject")) {
      return(NULL)
    }
    type <- type@properties[[part]]
  }
  type
}

approval_review_kind <- function(type) {
  if (inherits(type, "ellmer::TypeEnum")) {
    return("enum")
  }
  if (
    inherits(type, "ellmer::TypeBasic") &&
      type@type %in% c("string", "number", "integer", "boolean")
  ) {
    return(type@type)
  }
  NULL
}

# Editors start at the proposed value. A missing field starts empty, and an
# out-of-range enum value stays selectable, so approving without edits never
# substitutes a value the reviewer did not choose.
approval_review_editor <- function(ns, index, row, type) {
  id <- ns(paste0("field_", index))
  value <- row$value
  missing <- is.na(value)
  label <- shiny::tags$span(
    class = "visually-hidden",
    paste("Value for", row$argument)
  )
  choices <- function(values) {
    values <- unique(c(if (!missing) value, values))
    if (missing) c("Not provided" = "", values) else values
  }
  switch(
    approval_review_kind(type) %||% "readonly",
    enum = shiny::selectInput(
      id,
      label,
      choices = choices(type@values),
      selected = if (missing) "" else value
    ),
    boolean = shiny::selectInput(
      id,
      label,
      choices = choices(c("true", "false")),
      selected = if (missing) "" else value
    ),
    string = shiny::textInput(id, label, if (missing) "" else value),
    number = ,
    integer = shiny::numericInput(
      id,
      label,
      if (missing) NA else as.numeric(value)
    ),
    shiny::tags$code(if (missing) "(missing)" else value)
  )
}

approval_review_unchanged <- function(new, label, type) {
  if (is.na(label)) {
    return(FALSE)
  }
  if (approval_review_kind(type) %in% c("number", "integer")) {
    original <- suppressWarnings(as.numeric(label))
    return(isTRUE(all.equal(original, as.numeric(new))))
  }
  identical(as.character(new), label)
}

# Assign a nested leaf, creating absent parent objects.
approval_review_set <- function(value, path, leaf) {
  if (length(path) == 1L) {
    value[[path]] <- leaf
    return(value)
  }
  child <- value[[path[[1L]]]]
  if (!is.list(child)) {
    child <- list()
  }
  value[[path[[1L]]]] <- approval_review_set(child, path[-1L], leaf)
  value
}

approval_review_coerce <- function(value, type) {
  switch(
    approval_review_kind(type),
    integer = as.integer(value),
    number = as.numeric(value),
    boolean = identical(value, "true"),
    value
  )
}
