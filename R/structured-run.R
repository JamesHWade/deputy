# A finite application correction policy around ellmer's structured API.
# There is no Deputy JSON parser, provider serializer, or type conversion here.
structured_run_spec <- function(
  type,
  validate = NULL,
  max_corrections = 0L,
  echo = "none",
  convert = TRUE
) {
  if (is.null(type)) {
    if (
      !is.null(validate) ||
        !identical(max_corrections, 0L) && !identical(max_corrections, 0)
    ) {
      abort_deputy(
        "{.arg validate} and {.arg max_corrections} require {.arg type}"
      )
    }
    return(NULL)
  }
  if (!inherits(type, "ellmer::Type")) {
    abort_deputy("{.arg type} must be an ellmer type")
  }
  if (!is.null(validate) && !is.function(validate)) {
    abort_deputy("{.arg validate} must be a function or NULL")
  }
  if (
    !is.numeric(max_corrections) ||
      length(max_corrections) != 1L ||
      is.na(max_corrections) ||
      !is.finite(max_corrections) ||
      max_corrections < 0 ||
      max_corrections != floor(max_corrections)
  ) {
    abort_deputy("{.arg max_corrections} must be a finite non-negative integer")
  }
  list(
    type = type,
    validate = validate,
    max_corrections = max_corrections,
    echo = echo,
    convert = convert
  )
}

governed_structured_request <- function(agent, messages, spec) {
  private <- agent$.__enclos_env__$private
  state <- private$current_run_state
  coro::async(function() {
    attempt <- 0L
    repeat {
      begin_model_request(agent)
      attempt <- attempt + 1L
      before <- length(private$.chat$get_turns())
      condition <- NULL
      value <- tryCatch(
        coro::await(with_run_trace(
          state,
          do.call(
            private$.chat$chat_structured_async,
            c(messages, spec[c("type", "echo", "convert")])
          )
        )),
        error = function(error) {
          condition <<- error
          NULL
        }
      )
      if (isTRUE(private$should_stop)) {
        return(NULL)
      }
      turn <- NULL
      if (length(private$.chat$get_turns()) > before) {
        turn <- private$.chat$last_turn()
      }
      if (
        !is.null(condition) &&
          !structured_parse_failure(turn, condition)
      ) {
        record_model_failure(agent, condition, structured = TRUE)
        rlang::cnd_signal(condition)
      }
      end_model_request(agent, turn)
      feedback <- NULL
      if (!is.null(condition)) {
        feedback <- conditionMessage(condition)
      }
      if (is.null(condition) && !is.null(spec$validate)) {
        # Exceptions/NA mean the validator could not decide. They are terminal,
        # not evidence that asking the model again can repair the result.
        validation <- spec$validate(value)
        if (identical(validation, FALSE)) {
          feedback <- "The result did not pass application validation."
        } else if (
          is.character(validation) &&
            length(validation) &&
            !anyNA(validation) &&
            all(nzchar(validation))
        ) {
          feedback <- paste(validation, collapse = "\n")
        } else if (!isTRUE(validation)) {
          cli_abort(
            "The validator must return TRUE, FALSE, or non-empty feedback text",
            class = c("deputy_validation_unavailable", "deputy_error")
          )
        }
      }
      private$record_run_event(private$agent_event(
        "structured_attempt",
        attempt = attempt,
        valid = is.null(feedback),
        value = value,
        turn = turn,
        condition = condition,
        feedback = feedback
      ))
      if (is.null(feedback)) {
        return(value)
      }
      if (attempt > spec$max_corrections) {
        cli_abort(
          "Structured output did not pass validation after {attempt} attempt{?s}",
          class = c("deputy_structured_output_invalid", "deputy_error"),
          parent = condition
        )
      }
      messages <- list(paste(
        "Correct the structured result using the existing conversation.",
        "Do not repeat the completed task. Validation feedback:",
        feedback,
        sep = "\n"
      ))
    }
  })()
}

# ellmer owns parsing. Reproduce only its public ContentJson parse failure;
# an arbitrary rejection after a recorded turn is not validation feedback.
# Unclassified conversion or application errors remain terminal.
structured_parse_failure <- function(turn, condition) {
  if (!inherits(turn, "ellmer::AssistantTurn")) {
    return(FALSE)
  }
  json <- Filter(function(x) inherits(x, "ellmer::ContentJson"), turn@contents)
  if (!length(json)) {
    return(FALSE)
  }
  # A failed S7 getter can leave its recursion guard on the original object.
  # Use its public class constructor for a fresh value, preserving the turn.
  constructor <- S7::S7_class(json[[1]])
  fresh <- constructor(data = json[[1]]@data, string = json[[1]]@string)
  failure <- tryCatch(
    {
      S7::prop(fresh, "parsed")
      NULL
    },
    error = identity
  )
  inherits(failure, "error") &&
    identical(class(failure), class(condition)) &&
    identical(conditionMessage(failure), conditionMessage(condition))
}
