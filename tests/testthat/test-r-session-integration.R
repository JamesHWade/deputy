test_that("Agent sends native plots with bounded text and preserves saved display evidence", {
  skip_if_not_installed("shinychat")
  directory <- withr::local_tempdir()
  code <- "cat(strrep('large output ', 10000)); plot(1:3); title('Saved plot')"
  server <- local_runtime_server(list(
    runtime_reply(tool = "run_r_code", arguments = list(code = code)),
    runtime_reply("The plot is available.")
  ))
  policy <- ContextPolicy(offload_dir = file.path(directory, "offload"))
  agent <- Agent$new(
    chat = runtime_chat(server),
    working_dir = directory,
    context_policy = policy,
    permissions = Permissions(r_code = TRUE),
    run_context = list(conversation_id = "plots")
  )
  session <- RSession$new(agent)
  withr::defer(session$close())
  agent$register_tools(session$tools())
  captured <- NULL
  agent$add_hook(HookMatcher(
    event = "PostToolUse",
    timeout = 0,
    callback = function(tool_name, tool_result, ...) {
      captured <<- tool_result
      NULL
    }
  ))
  agent$chat("Run the calculation and plot it.")
  expect_identical(agent$last_run()$stop_reason, "complete")
  expect_length(server$requests(), 2L)
  wire <- as.character(jsonlite::toJSON(
    server$requests()[[2L]]$body,
    auto_unbox = TRUE
  ))
  expect_match(wire, "data:image/png;base64,", fixed = TRUE)
  expect_match(wire, "deputy://tool-result/", fixed = TRUE)
  expect_identical(
    grepl(strrep("large output ", 100), wire, fixed = TRUE),
    FALSE
  )
  expect_match(
    paste(
      vapply(
        Filter(function(x) inherits(x, "ellmer::ContentText"), captured),
        function(x) x@text,
        character(1)
      ),
      collapse = ""
    ),
    strrep("large output ", 100),
    fixed = TRUE
  )
  contents <- unlist(
    lapply(agent$get_turns(), function(x) x@contents),
    recursive = FALSE
  )
  result <- Filter(
    function(x) inherits(x, "ellmer::ContentToolResult"),
    contents
  )[[1L]]
  expect_length(
    Filter(function(x) inherits(x, "ellmer::ContentImage"), result@value),
    1L
  )
  expect_identical(result@extra$deputy_r$code, code)
  display <- as.character(result@extra$display$html)
  expect_match(display, strrep("large output ", 100), fixed = TRUE)
  path <- file.path(directory, "session.rds")
  suppressMessages(agent$save_session(path))
  portable <- callr::r(
    function(path) {
      saved <- readRDS(path)
      # Independently verify the portable identity in a fresh R process.
      identity <- function(value) {
        if (inherits(value, "ellmer::Content")) {
          return(list(
            type = "content",
            classes = class(value),
            properties = identity(S7::props(value))
          ))
        }
        if (is.list(value)) {
          return(list(
            type = "list",
            attributes = attributes(value),
            items = lapply(value, identity)
          ))
        }
        list(type = "value", value = value)
      }
      contents <- unlist(
        lapply(saved$turns, function(x) x@contents),
        recursive = FALSE
      )
      result <- Filter(
        function(x) inherits(x, "ellmer::ContentToolResult"),
        contents
      )[[1L]]
      list(
        code = result@extra$deputy_r$code,
        display = as.character(result@extra$display$html),
        tool_absent = is.null(result@request@tool),
        artifacts_valid = all(vapply(
          saved$tool_result_envelopes,
          function(envelope) {
            identical(
              envelope$sha256,
              digest::digest(
                serialize(identity(envelope$value), NULL, version = 3),
                algo = "sha256",
                serialize = FALSE
              )
            )
          },
          logical(1)
        ))
      )
    },
    list(path = path)
  )
  expect_identical(portable$code, code)
  expect_identical(portable$display, display)
  expect_true(portable$tool_absent)
  expect_true(portable$artifacts_valid)
  expect_s7_class(result@request@tool, ellmer::ToolDef)
  session$close()
  restored <- Agent$new(
    chat = runtime_chat(server),
    working_dir = directory,
    context_policy = policy
  )
  suppressMessages(restored$load_session(path))
  saved <- unlist(
    lapply(restored$get_turns(), function(x) x@contents),
    recursive = FALSE
  )
  saved_result <- Filter(
    function(x) inherits(x, "ellmer::ContentToolResult"),
    saved
  )[[1L]]
  expect_identical(as.character(saved_result@extra$display$html), display)
  expect_identical(saved_result@extra$deputy_r$code, code)
  expect_null(saved_result@request@tool)
  rendered <- htmltools::renderTags(shinychat::contents_shinychat(
    saved_result
  ))$html
  expect_match(rendered, "data:image/png;base64,", fixed = TRUE)
  expect_match(rendered, "Details: R code", fixed = TRUE)
  fresh <- RSession$new(restored)
  withr::defer(fresh$close())
  expect_match(
    r_session_text(r_session_await(fresh$run("exists('x')"))),
    "fresh R session"
  )
})

test_that("denied execution never starts a worker and Agent interruption cancels it", {
  directory <- withr::local_tempdir()
  denied <- local_runtime_server(list(
    runtime_reply(
      tool = "run_r_code",
      arguments = list(code = "file.create('denied')")
    ),
    runtime_reply("denied")
  ))
  agent <- Agent$new(
    chat = runtime_chat(denied),
    working_dir = directory,
    permissions = Permissions(r_code = FALSE)
  )
  session <- RSession$new(agent)
  withr::defer(session$close())
  agent$register_tools(session$tools())
  suppressWarnings({
    agent$chat("Try R.")
    later::run_now(0.05)
  })
  expect_null(session$status()$pid)
  expect_identical(file.exists(file.path(directory, "denied")), FALSE)

  server <- local_runtime_server(list(
    runtime_reply(
      tool = "run_r_code",
      arguments = list(code = "Sys.sleep(10)")
    ),
    runtime_reply("must not resume")
  ))
  active <- Agent$new(
    chat = runtime_chat(server),
    working_dir = directory,
    permissions = Permissions(r_code = TRUE)
  )
  runtime <- RSession$new(active)
  withr::defer(runtime$close())
  active$register_tools(runtime$tools())
  polling <- TRUE
  withr::defer(polling <- FALSE)
  interrupt <- function() {
    if (!polling) {
      return(invisible(NULL))
    }
    if (identical(runtime$status()$state, "running")) {
      polling <<- FALSE
      active$interrupt()
    } else {
      later::later(interrupt, 0.02)
    }
  }
  later::later(interrupt, 0.02)
  active$chat("Start R.")
  expect_identical(active$last_run()$stop_reason, "interrupted")
  expect_null(runtime$status()$pid)
  expect_length(server$requests(), 1L)
})
