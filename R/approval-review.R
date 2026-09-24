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
#' A field is editable when its declared type is enum, string, number,
#' integer, or boolean and its editor can show the proposed value exactly.
#' Anything else, including a proposed value that does not fit its type (a
#' boolean `"yes"`, a number `"abc"`), is shown read-only as proposed; deny the
#' call if it is wrong. An absent optional field stays absent unless the
#' reviewer picks a value, or ticks "Provide a value" for text and numbers. Approval with
#' edits resumes with the edited input, which the tool must validate. Approval
#' without edits resumes with the original input. Clearing a number removes
#' the field. Deny executes nothing. Each pending approval is submitted at
#' most once.
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
      # A host decide() may finish later; never submit one approval twice.
      submitted <- character()
      observed <- character()
      refresh <- function() {
        version(shiny::isolate(version()) + 1L)
        invisible(NULL)
      }
      # The hook outlives this session, so it reaches refresh() only through
      # a holder that is cleared when the session ends.
      holder <- new.env(parent = emptyenv())
      holder$refresh <- refresh
      session$onSessionEnded(function() {
        holder$refresh <- NULL
      })
      agent$add_hook(HookMatcher(
        "Stop",
        timeout = 0,
        callback = function(...) {
          if (is.function(holder$refresh)) {
            holder$refresh()
          }
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
        tool_input <- request$tool_input %||% list()
        # An input that cannot be tabulated is shown as submitted and can
        # still be approved unchanged or denied.
        table <- tryCatch(
          tool_input_review(tool_input, arguments),
          error = function(error) NULL
        )
        list(
          record = record,
          key = approval_review_key(record$id),
          tool_name = tool_name,
          input = tool_input,
          table = table,
          fields = if (!is.null(table)) {
            lapply(attr(table, "paths"), function(path) {
              approval_review_field(tool_input, arguments, path)
            })
          }
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
        key <- current$key
        table <- current$table
        body <- if (is.null(table)) {
          shiny::tagList(
            shiny::tags$p(
              "These inputs cannot be shown as a table. They are shown as submitted and cannot be edited."
            ),
            shiny::tags$pre(review_value_label(current$input))
          )
        } else {
          rows <- lapply(seq_len(nrow(table)), function(i) {
            row <- table[i, , drop = FALSE]
            shiny::tags$tr(
              shiny::tags$th(scope = "row", row$argument),
              shiny::tags$td(shiny::tags$code(
                if (is.na(row$type)) "undeclared" else row$type
              )),
              shiny::tags$td(approval_review_editor(
                ns,
                key,
                i,
                row,
                current$fields[[i]]
              )),
              shiny::tags$td(
                if (is.na(row$description)) "" else row$description,
                class = "text-muted"
              )
            )
          })
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
          )
        }
        reason <- current$record$request$reason
        shiny::tagList(
          shiny::tags$p(
            shiny::tags$strong(current$tool_name, .noWS = "after"),
            if (is_nonempty_string(reason)) paste0(": ", reason)
          ),
          body,
          shiny::actionButton(
            ns(paste0("approve_", key)),
            "Approve these inputs",
            class = "btn-primary"
          ),
          shiny::actionButton(ns(paste0("deny_", key)), "Deny")
        )
      })

      edited_input <- function(current) {
        value <- current$input
        for (i in seq_along(current$fields)) {
          field <- current$fields[[i]]
          if (identical(field$mode, "readonly")) {
            next
          }
          new <- input[[approval_review_id("field", current$key, i)]]
          if (is.null(new)) {
            next
          }
          if (identical(field$mode, "optin")) {
            if (!isTRUE(input[[approval_review_id("set", current$key, i)]])) {
              next
            }
          } else if (identical(field$mode, "choose")) {
            if (identical(new, "")) next
          } else if (identical(new, field$shown)) {
            # Untouched: keep the proposed value exactly.
            next
          }
          value <- approval_review_set(
            value,
            field$path,
            approval_review_coerce(new, field$kind)
          )
        }
        value
      }

      act <- function(decision, key) {
        record <- shiny::isolate(pending())
        # Ignore clicks from a screen showing an earlier approval.
        if (
          is.null(record) || !identical(approval_review_key(record$id), key)
        ) {
          return(invisible(NULL))
        }
        path <- record$source$path
        if (path %in% submitted) {
          return(invisible(NULL))
        }
        tool_input <- NULL
        if (identical(decision, "approve")) {
          current <- shiny::isolate(review())
          if (!is.null(current$fields)) {
            edited <- shiny::isolate(edited_input(current))
            if (!identical(edited, current$input)) {
              tool_input <- edited
            }
          }
        }
        submitted <<- c(submitted, path)
        result <- tryCatch(
          list(result = decide(path, decision, tool_input)),
          error = function(error) list(error = conditionMessage(error))
        )
        # A decision that failed before consuming the approval may be retried.
        if (!is.null(result$error)) {
          status <- tryCatch(approval_read(path)$status, error = function(e) {
            NULL
          })
          if (identical(status, "pending")) {
            submitted <<- setdiff(submitted, path)
          }
        }
        outcome(c(list(decision = decision, tool_input = tool_input), result))
        refresh()
        invisible(NULL)
      }

      # Buttons carry the approval key, so each approval has its own
      # observers and a stale click cannot act on a newer approval.
      shiny::observe({
        record <- pending()
        if (is.null(record)) {
          return()
        }
        key <- approval_review_key(record$id)
        if (key %in% observed) {
          return()
        }
        observed <<- c(observed, key)
        shiny::observeEvent(input[[paste0("approve_", key)]], {
          act("approve", key)
        })
        shiny::observeEvent(input[[paste0("deny_", key)]], {
          act("deny", key)
        })
      })

      list(pending = pending, outcome = outcome, refresh = refresh)
    },
    session = session
  )
}

approval_review_leaf_type <- function(arguments, path) {
  type <- arguments
  for (part in path) {
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

approval_review_key <- function(id) {
  gsub("[^A-Za-z0-9]", "_", id)
}

approval_review_id <- function(kind, key, index) {
  paste0(kind, "_", key, "_", index)
}

# Numbers are edited as text showing every significant digit, so the editor
# shows the proposed value exactly and change detection compares strings.
approval_review_number_text <- function(value) {
  text <- trimws(format(value, digits = 17, scientific = FALSE))
  if (!identical(as.numeric(text), as.numeric(value))) {
    return(NULL)
  }
  text
}

# Describe how one reviewed field can be edited. A field is editable only
# when its editor can show the proposed value exactly; otherwise it is shown
# read-only, as proposed, and the reviewer can deny. Absent optional fields
# need an explicit choice ("Not provided" or "Provide a value").
approval_review_field <- function(input, arguments, path) {
  type <- approval_review_leaf_type(arguments, path)
  kind <- approval_review_kind(type)
  raw <- input
  present <- TRUE
  ambiguous <- FALSE
  for (part in path) {
    if (!is.list(raw) || !part %in% names(raw)) {
      present <- FALSE
      raw <- NULL
      break
    }
    # Duplicate keys cannot be shown or edited one at a time.
    ambiguous <- ambiguous || anyDuplicated(names(raw)) > 0L
    raw <- raw[[part]]
  }
  scalar <- length(raw) == 1L && !is.list(raw) && !anyNA(raw)
  shown <- if (present && scalar) {
    switch(
      kind %||% "none",
      enum = if (is.character(raw)) raw,
      # Browsers rewrite carriage returns and a leading newline in form
      # controls, so those strings are read-only.
      string = if (
        is.character(raw) && !grepl("\r", raw) && !startsWith(raw, "\n")
      ) {
        raw
      },
      number = ,
      integer = if (is.numeric(raw) && is.finite(raw)) {
        approval_review_number_text(raw)
      },
      boolean = if (is.logical(raw)) tolower(as.character(raw)),
      NULL
    )
  }
  mode <- if (is.null(kind) || ambiguous || (present && is.null(shown))) {
    "readonly"
  } else if (present) {
    "edit"
  } else if (kind %in% c("enum", "boolean")) {
    "choose"
  } else {
    "optin"
  }
  list(path = path, type = type, kind = kind, shown = shown, mode = mode)
}

approval_review_editor <- function(ns, key, index, row, field) {
  id <- ns(approval_review_id("field", key, index))
  label <- shiny::tags$span(
    class = "visually-hidden",
    paste("Value for", row$argument)
  )
  if (identical(field$mode, "readonly")) {
    return(shiny::tags$code(
      if (is.na(row$value)) "(not provided)" else row$value
    ))
  }
  choose <- identical(field$mode, "choose")
  select <- function(values) {
    # An out-of-range proposed enum value stays selectable, shown as proposed.
    values <- if (choose) {
      c("Not provided" = "", values)
    } else {
      unique(c(field$shown, values))
    }
    shiny::selectInput(
      id,
      label,
      choices = values,
      selected = if (choose) "" else field$shown
    )
  }
  editor <- switch(
    field$kind,
    enum = select(field$type@values),
    boolean = select(c("true", "false")),
    string = if (grepl("\n", field$shown %||% "", fixed = TRUE)) {
      # A single-line input drops line breaks; a text area keeps them.
      shiny::textAreaInput(id, label, field$shown, rows = 3)
    } else {
      shiny::textInput(id, label, field$shown %||% "")
    },
    shiny::textInput(id, label, field$shown %||% "")
  )
  if (!identical(field$mode, "optin")) {
    return(editor)
  }
  shiny::tagList(
    shiny::checkboxInput(
      ns(approval_review_id("set", key, index)),
      paste("Provide a value for", row$argument),
      FALSE
    ),
    editor
  )
}

# Assign a nested leaf, creating absent parent objects. A NULL leaf removes
# the field.
approval_review_set <- function(value, path, leaf) {
  if (length(path) == 1L) {
    value[path] <- if (is.null(leaf)) NULL else list(leaf)
    return(value)
  }
  child <- value[[path[[1L]]]]
  if (!is.list(child)) {
    child <- list()
  }
  value[[path[[1L]]]] <- approval_review_set(child, path[-1L], leaf)
  value
}

approval_review_coerce <- function(value, kind) {
  if (identical(kind, "boolean")) {
    return(identical(value, "true"))
  }
  if (!kind %in% c("number", "integer")) {
    return(value)
  }
  text <- trimws(value)
  # A cleared number removes the field; the tool reports it as missing.
  if (!nzchar(text)) {
    return(NULL)
  }
  number <- suppressWarnings(as.numeric(text))
  # Unparseable text reaches the tool as typed, for it to reject.
  if (is.na(number)) {
    return(value)
  }
  # Fractional or out-of-range integers stay numeric for the tool to reject.
  if (
    identical(kind, "integer") &&
      number == round(number) &&
      abs(number) <= .Machine$integer.max
  ) {
    return(as.integer(number))
  }
  number
}
