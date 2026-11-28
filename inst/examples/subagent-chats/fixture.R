# Deterministic local OpenAI-compatible fixture. No credentials or paid service.
# Run the transport in a separate process so Shiny stays responsive.
child_chat_fixture <- function(curated = FALSE) {
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

  directory <- tempfile("deputy-child-demo-")
  dir.create(directory, recursive = TRUE)
  saveRDS(
    list(fail = FALSE, large = FALSE),
    file.path(directory, "scenario.rds")
  )

  handler <- function(request, count, directory, args) {
    emit <- function(delta, finish = NULL) {
      local_openai_sse_chunk(
        id = "demo",
        model = "gpt-4o-mini",
        delta = delta,
        finish_reason = finish
      )
    }
    system <- paste(
      vapply(
        Filter(function(msg) msg$role == "system", request$messages),
        local_openai_message_text,
        character(1)
      ),
      collapse = " "
    )
    child <- if (grepl("DEMO_ANALYST", system, fixed = TRUE)) {
      "analyst"
    } else if (grepl("DEMO_AUDITOR", system, fixed = TRUE)) {
      "auditor"
    } else {
      NULL
    }
    results <- Filter(function(msg) msg$role == "tool", request$messages)
    scenario <- readRDS(file.path(directory, "scenario.rds"))
    # Leave enough time to inspect and cancel a running child by hand.
    Sys.sleep(if (is.null(child)) 0.3 else 5)
    if (
      identical(child, "auditor") &&
        isTRUE(scenario$fail) &&
        length(results)
    ) {
      return(local_openai_error_response(
        "Deterministic audit failure after evidence inspection",
        status = 403L,
        type = "fixture_error"
      ))
    }
    if (is.null(child)) {
      latest <- utils::tail(
        Filter(function(msg) msg$role == "user", request$messages),
        1L
      )
      repeat_one <- length(latest) &&
        grepl(
          "Repeat analyst",
          local_openai_message_text(latest[[1L]]),
          fixed = TRUE
        )
      # Each new user request gets its own delegation round.
      last_user <- max(which(vapply(
        request$messages,
        function(msg) msg$role == "user",
        logical(1)
      )))
      has_result <- any(vapply(
        request$messages[seq.int(last_user, length(request$messages))],
        function(msg) msg$role == "tool",
        logical(1)
      ))
      if (!has_result) {
        names <- if (repeat_one) "analyst" else c("analyst", "auditor")
        calls <- lapply(seq_along(names), function(i) {
          list(
            index = i - 1L,
            id = paste0("delegate-", count, "-", i),
            type = "function",
            `function` = list(
              name = if (args$curated) {
                paste0("ask_", names[[i]])
              } else {
                "delegate_to_agent"
              },
              arguments = as.character(jsonlite::toJSON(
                c(
                  if (!args$curated) list(agent_name = names[[i]]),
                  list(
                    task = paste(
                      "Inspect the",
                      names[[i]],
                      "evidence and report limitations."
                    )
                  )
                ),
                auto_unbox = TRUE
              ))
            )
          )
        })
        body <- emit(
          list(role = "assistant", tool_calls = calls),
          "tool_calls"
        )
      } else {
        body <- emit(
          list(
            role = "assistant",
            content = "The specialists returned. Their execution status and evidence are available in the child activity cards. A completed run does not verify the findings."
          ),
          "stop"
        )
      }
    } else if (!length(results)) {
      body <- emit(
        list(
          role = "assistant",
          content = "I will inspect the supplied evidence.",
          tool_calls = list(list(
            index = 0L,
            id = paste0("evidence-", count),
            type = "function",
            `function` = list(name = "inspect_evidence", arguments = "{}")
          ))
        ),
        "tool_calls"
      )
    } else {
      answer <- paste0(
        "### ",
        tools::toTitleCase(child),
        " notes\n\nThe retained tool result contains the evidence. **Unresolved:** confirm the measurement conditions.\n\n<script>window.deputyInjected = true</script>\n<img src=x onerror=\"window.deputyInjected=true\">\n\nThis markup is untrusted fixture text.\n\nInline code: `a < b & c > d`.\n\n```r\na < b & c > d\n```"
      )
      if (isTRUE(scenario$large)) {
        answer <- paste(
          answer,
          strrep("Bounded evidence observation. ", 1000)
        )
      }
      body <- paste0(
        emit(list(role = "assistant", content = substr(answer, 1, 70))),
        emit(list(content = substring(answer, 71)), "stop")
      )
    }
    usage <- local_openai_sse_chunk(
      id = "demo",
      model = "gpt-4o-mini",
      choices = list(),
      usage = list(
        prompt_tokens = 40L,
        completion_tokens = 20L,
        total_tokens = 60L
      )
    )
    local_openai_sse_response(paste0(body, usage, "data: [DONE]\n\n"))
  }

  server <- shared$start_local_openai_fixture(
    prefix = "deputy-child-demo-",
    handler = handler,
    args = list(curated = curated),
    directory = directory,
    timeout = 15,
    error_label = "Local demo transport did not start"
  )
  list(
    chat = function() {
      ellmer::chat_openai_compatible(
        base_url = server$url,
        model = "gpt-4o-mini",
        credentials = function() "fixture",
        echo = "none"
      )
    },
    scenario = function(fail, large) {
      saveRDS(
        list(fail = fail, large = large),
        file.path(server$directory, "scenario.rds")
      )
    },
    requests = function() length(server$requests()),
    close = server$close
  )
}

# Fingerprint display data, never the environments attached to error conditions.
child_chat_signature <- function(turns) {
  display_data <- function(x) {
    if (inherits(x, "condition")) {
      return(conditionMessage(x))
    }
    if (is.environment(x) || is.function(x)) {
      return(NULL)
    }
    if (is.list(x)) {
      return(lapply(x, display_data))
    }
    x
  }
  digest::digest(display_data(lapply(turns, ellmer::contents_record)))
}
