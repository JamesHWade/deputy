# Deterministic local OpenAI-compatible fixture. No credentials or paid service.
# Run the transport in a separate process so Shiny stays responsive.
child_chat_fixture <- function() {
  directory <- tempfile("deputy-child-demo-")
  dir.create(directory)
  saveRDS(
    list(fail = FALSE, large = FALSE),
    file.path(directory, "scenario.rds")
  )
  process <- callr::r_bg(
    function(directory) {
      `%||%` <- function(x, y) if (is.null(x)) y else x
      count <- 0L
      port <- httpuv::randomPort()
      emit <- function(delta, finish = NULL) {
        paste0(
          "data: ",
          jsonlite::toJSON(
            list(
              id = "demo",
              model = "gpt-4o-mini",
              choices = list(list(
                index = 0L,
                delta = delta,
                finish_reason = finish
              ))
            ),
            auto_unbox = TRUE,
            null = "null"
          ),
          "\n\n"
        )
      }
      server <- httpuv::startServer(
        "127.0.0.1",
        port,
        list(call = function(req) {
          count <<- count + 1L
          request <- jsonlite::fromJSON(
            rawToChar(req$rook.input$read()),
            simplifyVector = FALSE
          )
          saveRDS(
            request,
            file.path(directory, paste0("request-", count, ".rds"))
          )
          text <- function(message) {
            if (is.character(message$content)) {
              message$content
            } else {
              paste(
                vapply(
                  message$content,
                  function(part) part$text %||% "",
                  character(1)
                ),
                collapse = " "
              )
            }
          }
          system <- paste(
            vapply(
              Filter(function(msg) msg$role == "system", request$messages),
              text,
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
          Sys.sleep(if (is.null(child)) 0.3 else 1.5)
          if (
            identical(child, "auditor") &&
              isTRUE(scenario$fail) &&
              length(results)
          ) {
            return(list(
              status = 403L,
              headers = list("Content-Type" = "application/json"),
              body = '{"error":{"message":"Deterministic audit failure after evidence inspection","type":"fixture_error"}}'
            ))
          }
          if (is.null(child)) {
            latest <- tail(
              Filter(function(msg) msg$role == "user", request$messages),
              1L
            )
            repeat_one <- length(latest) &&
              grepl("Repeat analyst", text(latest[[1L]]), fixed = TRUE)
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
                    name = "delegate_to_agent",
                    arguments = as.character(jsonlite::toJSON(
                      list(
                        agent_name = names[[i]],
                        task = paste(
                          "Inspect the",
                          names[[i]],
                          "evidence and report limitations."
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
              " notes\n\nThe retained tool result contains the evidence. **Unresolved:** confirm the measurement conditions.\n\n<script>window.deputyInjected = true</script>\n<img src=x onerror=\"window.deputyInjected=true\">\n\nThis markup is untrusted fixture text."
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
          usage <- paste0(
            'data: {"id":"demo","model":"gpt-4o-mini","choices":[],"usage":{"prompt_tokens":40,"completion_tokens":20,"total_tokens":60}}\n\n'
          )
          list(
            status = 200L,
            headers = list("Content-Type" = "text/event-stream"),
            body = paste0(body, usage, "data: [DONE]\n\n")
          )
        })
      )
      on.exit(server$stop(), add = TRUE)
      saveRDS(port, file.path(directory, "port.rds"))
      repeat {
        httpuv::service(50)
      }
    },
    args = list(directory = directory)
  )
  deadline <- Sys.time() + 15
  while (!file.exists(file.path(directory, "port.rds"))) {
    if (!process$is_alive() || Sys.time() > deadline) {
      cli::cli_abort("Local demo transport did not start")
    }
    Sys.sleep(0.05)
  }
  list(
    chat = function() {
      ellmer::chat_openai_compatible(
        base_url = paste0(
          "http://127.0.0.1:",
          readRDS(file.path(directory, "port.rds")),
          "/v1"
        ),
        model = "gpt-4o-mini",
        credentials = function() "fixture",
        echo = "none"
      )
    },
    scenario = function(fail, large) {
      saveRDS(
        list(fail = fail, large = large),
        file.path(directory, "scenario.rds")
      )
    },
    requests = function() length(list.files(directory, pattern = "^request-")),
    close = function() {
      process$kill()
      unlink(directory, recursive = TRUE)
    }
  )
}
