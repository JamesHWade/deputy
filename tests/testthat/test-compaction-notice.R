test_that("the Shiny notice clears busy status after failed or cancelled compaction", {
  skip_if_not_installed("shiny")
  withr::local_options(ellmer_max_tries = 1)
  example <- new.env(parent = baseenv())
  sys.source(
    system.file(
      "examples",
      "shiny-chat",
      "compaction-notice.R",
      package = "deputy"
    ),
    envir = example
  )

  for (outcome in c("failure", "cancel")) {
    for (previous_summary in c(FALSE, TRUE)) {
      response <- if (outcome == "failure") {
        runtime_failure(401L)
      } else {
        structure(runtime_reply("Unaccepted summary"), fixture_delay = 0.5)
      }
      server <- local_runtime_server(list(response))
      agent <- Agent$new(
        runtime_compaction_chat(server),
        context_policy = ContextPolicy(max_tokens = 50)
      )
      session <- shiny::MockShinySession$new()
      withr::defer(session$close())
      module <- list(
        history = list(
          conversation_id = shiny::reactiveVal("conversation-a"),
          on_restore = function(callback) NULL
        )
      )
      shiny::withReactiveDomain(session, {
        example$compaction_notice_server("compaction", agent, module, session)
      })
      if (previous_summary) {
        agent$compact(keep_last = 4, summary = "Accepted <draft> & evidence.")
        session$flushReact()
        expect_match(
          session$getOutput("compaction")$html,
          "Accepted &lt;draft&gt; &amp; evidence.",
          fixed = TRUE
        )
      }
      busy <- NULL
      agent$add_hook(HookMatcher(
        event = "PreCompact",
        callback = function(...) {
          session$flushReact()
          busy <<- session$getOutput("compaction")$html
          if (outcome == "cancel") {
            later::later(function() agent$interrupt(), 0.05)
          }
          NULL
        }
      ))
      before <- agent$get_turns()
      result <- shiny::withReactiveDomain(session, {
        tryCatch(agent$run_sync("Continue"), error = identity)
      })
      session$flushReact()
      expect_match(busy, "Summarizing earlier messages", fixed = TRUE)
      if (outcome == "failure") {
        expect_s3_class(result, "deputy_compaction_error")
      } else {
        expect_identical(agent$last_run()$stop_reason, "interrupted")
      }
      expect_identical(agent$get_turns(), before)
      if (previous_summary) {
        html <- session$getOutput("compaction")$html
        expect_match(
          html,
          "Accepted &lt;draft&gt; &amp; evidence.",
          fixed = TRUE
        )
        expect_false(grepl(
          "Summarizing earlier messages|Unaccepted summary",
          html
        ))
      } else {
        expect_null(session$getOutput("compaction"))
      }
    }
  }
})
