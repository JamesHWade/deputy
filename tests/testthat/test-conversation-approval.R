test_that("compacted conversation evidence survives durable approval without replay", {
  directory <- withr::local_tempdir()
  dir.create(file.path(directory, "approvals"))
  server <- local_runtime_server(list(
    runtime_reply(tool = "effect", arguments = list(value = "a")),
    runtime_reply("The first effect is complete."),
    runtime_reply(tool = "effect", arguments = list(value = "b")),
    runtime_reply("The approved effect is complete.")
  ))
  effects <- character()
  tool <- ellmer::tool(
    function(value) {
      effects <<- c(effects, value)
      paste("Completed", value)
    },
    name = "effect",
    description = "Record an effect",
    arguments = list(value = ellmer::type_string()),
    convert = FALSE,
    annotations = ellmer::tool_annotations(
      read_only_hint = FALSE,
      destructive_hint = FALSE,
      open_world_hint = FALSE
    )
  )
  make_agent <- function() {
    Agent$new(
      runtime_chat(server),
      tools = list(tool),
      permissions = Permissions(can_use_tool = function(name, input, context) {
        if (identical(input$value, "b")) {
          PermissionResultPending("Review b")
        } else {
          PermissionResultAllow()
        }
      }),
      approval_dir = file.path(directory, "approvals"),
      working_dir = directory,
      context_policy = ContextPolicy(
        max_tokens = NULL,
        offload_dir = file.path(directory, "offload")
      ),
      session_id = "history_approval_session",
      agent_id = "history_approval_agent"
    )
  }
  agent <- make_agent()
  agent$run_sync("Perform a")
  agent$compact(
    keep_last = 0L,
    summary = "a is already complete; do not repeat it."
  )
  prefix <- lapply(agent$get_turns(), ellmer::contents_record)
  paused <- agent$run_sync("Perform b after review")
  expect_identical(paused$stop_reason, "approval_pending")
  expect_identical(effects, "a")
  pending <- agent$pending_approval()
  expect_s7_class(pending, ApprovalContinuation)
  path <- pending$source$path
  expect_identical(approval_read(path)$status, "pending")

  snapshot <- file.path(directory, "display.rds")
  suppressMessages(agent$save_session(snapshot))
  display <- make_agent()
  suppressMessages(display$load_session(snapshot))
  expect_identical(
    lapply(head(display$get_turns(), 4L), ellmer::contents_record),
    prefix
  )
  expect_null(display$pending_approval())
  expect_identical(approval_read(path)$status, "pending")
  expect_identical(effects, "a")

  resumed <- make_agent()
  result <- resumed$resume_approval(path, "approve")
  expect_identical(result$stop_reason, "complete")
  expect_identical(effects, c("a", "b"))
  expect_identical(approval_read(path)$status, "completed")
  expect_length(resumed$get_turns(), 9L)
  expect_length(resumed$get_context_turns(), 5L)
  expect_equal(
    lapply(head(resumed$get_turns(), 4L), ellmer::contents_record),
    prefix,
    ignore_attr = TRUE
  )
  expect_null(resumed$get_turns()[[2L]]@contents[[1L]]@tool)
  expect_length(server$requests(), 4L)
})
