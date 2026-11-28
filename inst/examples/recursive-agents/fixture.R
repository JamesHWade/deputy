# A deterministic local OpenAI-compatible transport for the recursive example.
# Every response is generated from the request's system prompt and tool history,
# so the example exercises real ellmer streaming without paid model calls.
recursive_local_fixture <- function(delay = 0.15) {
  shared <- new.env(parent = parent.frame())
  shared_path <- system.file(
    "examples",
    "_local-openai-fixture.R",
    package = "deputy"
  )
  if (!nzchar(shared_path) && isNamespaceLoaded("deputy")) {
    candidate <- file.path(
      getNamespaceInfo(asNamespace("deputy"), "path"),
      "inst",
      "examples",
      "_local-openai-fixture.R"
    )
    if (file.exists(candidate)) {
      shared_path <- candidate
    }
  }
  if (!nzchar(shared_path)) {
    shared_path <- "../_local-openai-fixture.R"
  }
  sys.source(shared_path, envir = shared)

  handler <- function(request, count, directory, args) {
    messages <- request$messages %||% list()
    user_positions <- which(vapply(
      messages,
      function(message) identical(message$role, "user"),
      logical(1)
    ))
    current_messages <- if (length(user_positions)) {
      messages[utils::tail(user_positions, 1L):length(messages)]
    } else {
      messages
    }
    system <- paste(
      vapply(
        Filter(
          function(message) identical(message$role, "system"),
          messages
        ),
        local_openai_message_text,
        character(1)
      ),
      collapse = " "
    )
    user_messages <- vapply(
      Filter(
        function(message) identical(message$role, "user"),
        current_messages
      ),
      local_openai_message_text,
      character(1)
    )
    tool_messages <- Filter(
      function(message) identical(message$role, "tool"),
      current_messages
    )
    tool_text <- paste(
      vapply(tool_messages, local_openai_message_text, character(1)),
      collapse = " "
    )
    role <- if (grepl("RECURSIVE_ROOT", system, fixed = TRUE)) {
      "root"
    } else if (grepl("RECURSIVE_ANALYST", system, fixed = TRUE)) {
      "analyst"
    } else {
      "reviewer"
    }
    id <- paste0("recursive-fixture-", count)
    call_id <- paste0("recursive-call-", count)
    response <- if (identical(role, "root")) {
      if (!length(tool_messages)) {
        list(
          id = call_id,
          name = "analyze",
          arguments = list(task = "Analyze the fixture evidence.")
        )
      } else {
        "ROOT: the analyst and reviewer agree on the bounded evidence."
      }
    } else if (identical(role, "analyst")) {
      latest <- if (length(user_messages)) {
        utils::tail(user_messages, 1L)
      } else {
        ""
      }
      if (grepl("follow-up", latest, ignore.case = TRUE)) {
        "ANALYST: follow-up complete using the retained graph history."
      } else if (!any(grepl("fixture evidence", tool_text, fixed = TRUE))) {
        list(id = call_id, name = "inspect_fixture", arguments = list())
      } else if (!any(grepl("REVIEWER", tool_text, fixed = TRUE))) {
        list(
          id = call_id,
          name = "review",
          arguments = list(task = "Review the analyst evidence.")
        )
      } else {
        "ANALYST: evidence reviewed and ready for synthesis."
      }
    } else {
      "REVIEWER: the evidence is internally consistent and bounded."
    }
    Sys.sleep(args$delay)
    local_openai_sse_response(local_openai_sse(
      id = id,
      model = "gpt-4o-mini",
      text = if (is.list(response)) NULL else response,
      calls = if (is.list(response)) list(response) else list()
    ))
  }

  server <- shared$start_local_openai_fixture(
    prefix = "deputy-recursive-agents-",
    handler = handler,
    args = list(delay = delay),
    error_label = "Recursive local fixture did not start"
  )
  list(
    url = server$url,
    chat = function(role, model = paste0("recursive-", role), ...) {
      ellmer::chat_openai_compatible(
        base_url = server$url,
        credentials = function() "fixture",
        model = model,
        echo = "none",
        ...
      )
    },
    requests = server$requests,
    close = server$close
  )
}
