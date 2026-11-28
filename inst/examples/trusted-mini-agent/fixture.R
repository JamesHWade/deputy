# Local deterministic model transport. No API keys and no external model calls.
study_fixture <- function(plan) {
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
    system <- paste(
      vapply(
        Filter(function(x) x$role == "system", request$messages),
        function(x) as.character(x$content),
        character(1)
      ),
      collapse = " "
    )
    has_result <- any(vapply(
      request$messages,
      function(x) x$role == "tool",
      logical(1)
    ))
    call_id <- paste0("study-call-", count)
    body <- if (has_result) {
      local_openai_sse(
        id = "study",
        model = "fixture",
        text = "Model commentary: a deliberately incorrect answer is 999 grams. Use the designated result panel instead."
      )
    } else if (grepl("STUDY_EXECUTOR", system, fixed = TRUE)) {
      local_openai_sse(
        id = "study",
        model = "fixture",
        calls = list(list(
          id = call_id,
          name = "compute_summary",
          arguments = list(plan = args$plan)
        ))
      )
    } else if (grepl("STUDY_ANALYST", system, fixed = TRUE)) {
      local_openai_sse(
        id = "study",
        model = "fixture",
        calls = list(list(
          id = call_id,
          name = "propose_analysis",
          arguments = list(plan = args$plan)
        ))
      )
    } else {
      local_openai_sse(
        id = "study",
        model = "fixture",
        calls = list(list(
          id = call_id,
          name = "delegate_to_agent",
          arguments = list(
            agent_name = "analyst",
            task = "Propose a descriptive comparison of trt2 and ctrl using the known dataset."
          )
        ))
      )
    }
    local_openai_sse_response(body)
  }

  server <- shared$start_local_openai_fixture(
    prefix = "study-transport-",
    handler = handler,
    args = list(plan = plan),
    error_label = "The local study fixture did not start."
  )
  list(
    chat = function(role) {
      ellmer::chat_openai_compatible(
        base_url = server$url,
        model = "gpt-4o-mini",
        credentials = function() "local-fixture",
        echo = "none"
      )
    },
    requests = function() length(server$requests()),
    close = server$close
  )
}
