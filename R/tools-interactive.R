# Interactive tools for human-in-the-loop workflows

# Package-level storage for the user input callback
.deputy_env <- new.env(parent = emptyenv())
.deputy_env$ask_user_callback <- NULL

#' Set callback for non-interactive user input
#'
#' @description
#' In non-interactive sessions (scripts, Shiny apps, etc.), set a callback
#' function that will be called when the agent needs user input.
#'
#' @param callback A function that takes `question` (character), `choices`
#'   (character vector or NULL), and `type` (one of "text", "choice", "confirm").
#'   Should return the user's response as a character string.
#'   Set to NULL to clear the callback.
#'
#' @return Invisibly returns the previous callback (or NULL).
#'
#' @examples
#' \dontrun{
#' # For a Shiny app, you might set up a callback like:
#' set_ask_user_callback(function(question, choices, type) {
#'   # Show modal dialog and wait for input
#'   showModal(modalDialog(
#'     title = "Agent Question",
#'     question,
#'     textInput("response", "Your answer:")
#'   ))
#'   # Return the response when available
#'   input$response
#' })
#' }
#'
#' @export
set_ask_user_callback <- function(callback) {
  if (!is.null(callback) && !is.function(callback)) {
    cli::cli_abort("{.arg callback} must be a function or NULL")
  }
  old <- .deputy_env$ask_user_callback
  .deputy_env$ask_user_callback <- callback
  invisible(old)
}

#' Get the current user input callback
#'
#' @return The current callback function, or NULL if none set.
#' @keywords internal
#' @export
get_ask_user_callback <- function() {
  .deputy_env$ask_user_callback
}

#' Ask user a question (internal implementation)
#'
#' @param question The question to ask
#' @param choices Optional character vector of choices
#' @param type One of "text", "choice", or "confirm"
#' @return The user's response
#' @keywords internal
ask_user_impl <- function(question, choices = NULL, type = "text") {
  # Check for custom callback first

  callback <- get_ask_user_callback()
  if (!is.null(callback)) {
    return(callback(question, choices, type))
  }

  # Check if we're in an interactive session

if (!interactive()) {
    cli::cli_abort(c(
      "Cannot ask user: session is not interactive",
      "i" = "Use {.fn set_ask_user_callback} to provide a callback for non-interactive use"
    ))
  }

  # Display the question
  cli::cli_h3("Agent Question")
  cli::cli_text(question)

  if (type == "confirm") {
    # Yes/No confirmation
    cli::cli_text("(yes/no)")
    repeat {
      response <- readline("> ")
      response_lower <- tolower(trimws(response))
      if (response_lower %in% c("yes", "y", "no", "n")) {
        return(if (response_lower %in% c("yes", "y")) "yes" else "no")
      }
      cli::cli_alert_warning("Please answer 'yes' or 'no'")
    }
  } else if (type == "choice" && !is.null(choices) && length(choices) > 0) {
    # Multiple choice
    cli::cli_text("")
    for (i in seq_along(choices)) {
      cli::cli_text("{i}. {choices[i]}")
    }
    cli::cli_text("")
    cli::cli_text("Enter number or type your own response:")

    repeat {
      response <- readline("> ")
      response_trimmed <- trimws(response)

      # Check if it's a number
      if (grepl("^[0-9]+$", response_trimmed)) {
        idx <- as.integer(response_trimmed)
        if (idx >= 1 && idx <= length(choices)) {
          return(choices[idx])
        }
        cli::cli_alert_warning("Please enter a number between 1 and {length(choices)}")
      } else if (nchar(response_trimmed) > 0) {
        # Accept free-form response
        return(response_trimmed)
      } else {
        cli::cli_alert_warning("Please enter a response")
      }
    }
  } else {
    # Free-form text
    response <- readline("> ")
    return(trimws(response))
  }
}

#' Ask user for input
#'
#' @description
#' A tool that allows the agent to ask the user a question and receive a response.
#' This enables human-in-the-loop workflows where the agent can request
#' clarification, confirmation, or choices from the user.
#'
#' @format A tool definition created with `ellmer::tool()`.
#'
#' @details
#' The tool supports three types of questions:
#'
#' - **text**: Free-form text input (default)
#' - **choice**: Present options for the user to choose from
#' - **confirm**: Yes/No confirmation
#'
#' In interactive R sessions, the tool uses `readline()` to get input.
#' For non-interactive use (scripts, Shiny apps), set a callback with
#' [set_ask_user_callback()].
#'
#' @examples
#' \dontrun{
#' # Add to agent's tools
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-4o"),
#'   tools = c(tools_file(), tool_ask_user)
#' )
#'
#' # The agent can then ask questions like:
#' # "Should I proceed with deleting these files?" (confirm)
#' # "Which format do you prefer?" with choices (choice)
#' # "What is the project name?" (text)
#' }
#'
#' @seealso [set_ask_user_callback()] for non-interactive usage
#'
#' @export
tool_ask_user <- ellmer::tool(
  fun = function(question, choices = NULL, type = "text") {
    # Validate type
    valid_types <- c("text", "choice", "confirm")
    if (!type %in% valid_types) {
      ellmer::tool_reject(paste(
        "Invalid type. Must be one of:",
        paste(valid_types, collapse = ", ")
      ))
    }

    # Validate choices for choice type
    if (type == "choice" && (is.null(choices) || length(choices) == 0)) {
      ellmer::tool_reject("choices must be provided when type is 'choice'")
    }

    # Get user input
    tryCatch(
      {
        response <- ask_user_impl(question, choices, type)
        paste("User responded:", response)
      },
      error = function(e) {
        ellmer::tool_reject(paste("Failed to get user input:", e$message))
      }
    )
  },
  name = "ask_user",
  description = paste(
    "Ask the user a question and get their response.",
    "Use this when you need clarification, confirmation, or to present choices.",
    "Types: 'text' for free-form input, 'choice' to present options,",
    "'confirm' for yes/no questions."
  ),
  arguments = list(
    question = ellmer::type_string(
      "The question to ask the user. Be clear and specific."
    ),
    choices = ellmer::type_array(
      items = ellmer::type_string("A choice option"),
      description = paste(
        "Optional list of choices for the user to pick from.",
        "Only used when type is 'choice'. User can also type a custom response."
      ),
      required = FALSE
    ),
    type = ellmer::type_enum(
      values = c("text", "choice", "confirm"),
      description = paste(
        "Type of question:",
        "'text' = free-form response,",
        "'choice' = pick from options,",
        "'confirm' = yes/no"
      ),
      required = FALSE
    )
  ),
  annotations = ellmer::tool_annotations(
    read_only_hint = TRUE,
    destructive_hint = FALSE,
    open_world_hint = FALSE
  )
)

#' Tools for interactive workflows
#'
#' @description
#' Returns a list of tools that enable human-in-the-loop interactions.
#' Currently includes `tool_ask_user` for asking questions.
#'
#' @return A list of tool definitions.
#'
#' @examples
#' \dontrun{
#' agent <- Agent$new(
#'   chat = ellmer::chat("openai/gpt-4o"),
#'   tools = c(tools_file(), tools_interactive())
#' )
#' }
#'
#' @seealso [tool_ask_user], [set_ask_user_callback()]
#'
#' @export
tools_interactive <- function() {
  list(tool_ask_user)
}
