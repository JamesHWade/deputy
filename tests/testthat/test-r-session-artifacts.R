rich_artifact_agent <- function(
  directory,
  agent_id = "agent-rich-artifacts",
  session_id = "session-rich-artifacts",
  conversation_id = "rich-artifacts"
) {
  Agent$new(
    chat = create_mock_chat(),
    working_dir = directory,
    agent_id = agent_id,
    session_id = session_id,
    run_context = list(conversation_id = conversation_id)
  )
}

rich_artifact_segments <- function(result) {
  Filter(
    function(segment) identical(segment$type, "artifact"),
    result@extra$deputy_r$segments
  )
}

expect_rich_artifact <- function(result, expected = 1L) {
  expect_s7_class(result, ellmer::ContentToolResult)
  expect_identical(result@extra$deputy_r$outcome, "complete")
  artifacts <- rich_artifact_segments(result)
  expect_length(artifacts, expected)

  for (segment in artifacts) {
    expect_true(is.character(segment$text))
    expect_true(nzchar(trimws(segment$text)))
    expect_true(is.list(segment$artifact))
    expect_true(all(
      c(
        "id",
        "media_type",
        "bytes",
        "renderer",
        "dependencies",
        "fallback"
      ) %in%
        names(segment$artifact)
    ))
    expect_match(segment$artifact$id, "^r_artifact_[0-9a-f]{64}$")
    expect_identical(segment$artifact$media_type, "text/html")
    expect_gt(as.numeric(segment$artifact$bytes), 0)
    expect_true(nzchar(paste(segment$artifact$renderer, collapse = "")))
    expect_true(!is.null(segment$artifact$dependencies))
    expect_true(!is.null(segment$artifact$fallback))
    if (!is.null(segment$png)) {
      expect_true(is.raw(segment$png))
      expect_gte(length(segment$png), 24L)
      expect_identical(
        segment$png[seq_len(8L)],
        as.raw(c(137, 80, 78, 71, 13, 10, 26, 10))
      )
    }
  }

  expect_true(all(vapply(
    result@value,
    function(value) {
      inherits(value, "ellmer::ContentText") ||
        inherits(value, "ellmer::ContentImage")
    },
    logical(1)
  )))
  display <- as.character(result@extra$display$html)
  expect_false(grepl("<iframe", display, fixed = TRUE))
  for (segment in artifacts) {
    expect_match(display, segment$artifact$id, fixed = TRUE)
  }
  invisible(artifacts)
}

expect_rich_producer <- function(code, package, renderer) {
  skip_if_not_installed(package)
  directory <- withr::local_tempdir("deputy-r-rich-work-")
  artifact_dir <- withr::local_tempdir("deputy-r-rich-store-")
  session <- RSession$new(
    rich_artifact_agent(directory),
    artifact_dir = artifact_dir,
    artifact_owner_id = paste0("tenant-rich-", package)
  )
  withr::defer(session$close())

  result <- r_session_await(session$run(code))
  artifacts <- expect_rich_artifact(result)
  expect_match(artifacts[[1L]]$artifact$renderer, renderer, ignore.case = TRUE)
  result
}

test_that("plotly artifacts retain provenance and reopen for the same owner", {
  skip_if_not_installed("plotly")

  directory <- withr::local_tempdir("deputy-r-rich-work-")
  artifact_dir <- withr::local_tempdir("deputy-r-rich-store-")
  agent <- rich_artifact_agent(directory)
  session <- RSession$new(
    agent,
    artifact_dir = artifact_dir,
    artifact_owner_id = "tenant-rich-artifacts"
  )
  withr::defer(session$close())

  result <- r_session_await(session$run(paste(
    "cat('before\\n');",
    "plotly::plot_ly(x = 1:3, y = c(3, 1, 2),",
    "type = 'scatter', mode = 'markers')"
  )))
  artifacts <- expect_rich_artifact(result)
  id <- artifacts[[1L]]$artifact$id
  expect_match(r_session_text(result), "before", fixed = TRUE)
  expect_match(artifacts[[1L]]$text, "plotly|scatter", ignore.case = TRUE)

  frame <- htmltools::renderTags(session$artifact_frame(id))$html
  expect_match(frame, "<iframe", fixed = TRUE)
  expect_match(frame, 'sandbox="allow-scripts"', fixed = TRUE)
  expect_match(frame, "srcdoc=", fixed = TRUE)
  expect_match(frame, "Content-Security-Policy", fixed = TRUE)
  expect_match(frame, "default-src", fixed = TRUE)

  session$close()
  reopened <- RSession$new(
    rich_artifact_agent(directory),
    artifact_dir = artifact_dir,
    artifact_owner_id = "tenant-rich-artifacts"
  )
  withr::defer(reopened$close())
  expect_identical(
    htmltools::renderTags(reopened$artifact_frame(id))$html,
    frame
  )

  other <- RSession$new(
    rich_artifact_agent(directory, agent_id = "agent-rich-other"),
    artifact_dir = artifact_dir,
    artifact_owner_id = "tenant-rich-artifacts"
  )
  withr::defer(other$close())
  expect_error(
    other$artifact_frame(id),
    class = "deputy_r_session_artifact"
  )

  stored <- list.files(
    artifact_dir,
    pattern = paste0(id, "[.]html$"),
    full.names = TRUE
  )
  expect_length(stored, 1L)
  bytes <- readBin(
    stored[[1L]],
    "raw",
    as.integer(file.info(stored[[1L]])$size)
  )
  bytes[[length(bytes)]] <- as.raw(
    bitwXor(as.integer(bytes[[length(bytes)]]), 1L)
  )
  writeBin(bytes, stored[[1L]])
  expect_error(
    reopened$artifact_frame(id),
    class = "deputy_r_session_artifact"
  )
})

test_that("rich output keeps ordinary text, multiple artifacts and errors ordered", {
  skip_if_not_installed("plotly")

  directory <- withr::local_tempdir("deputy-r-rich-order-work-")
  artifact_dir <- withr::local_tempdir("deputy-r-rich-order-store-")
  session <- RSession$new(
    rich_artifact_agent(
      directory,
      agent_id = "agent-rich-order",
      session_id = "session-rich-order"
    ),
    artifact_dir = artifact_dir,
    artifact_owner_id = "tenant-rich-order"
  )
  withr::defer(session$close())

  result <- r_session_await(session$run(paste(
    "cat('before\\n');",
    "plotly::plot_ly(x = 1:3, y = c(3, 1, 2), type = 'scatter');",
    "cat('between\\n');",
    "plotly::plot_ly(x = 1:3, y = c(1, 2, 3), type = 'scatter');",
    "cat('after\\n')"
  )))
  artifacts <- expect_rich_artifact(result, expected = 2L)
  ids <- vapply(artifacts, function(x) x$artifact$id, character(1))
  expect_length(unique(ids), 2L)
  text <- r_session_text(result)
  positions <- vapply(
    c("before", "between", "after"),
    function(marker) regexpr(marker, text, fixed = TRUE),
    integer(1)
  )
  expect_true(all(positions > 0L))
  expect_true(all(diff(positions) > 0L))

  failed <- r_session_await(session$run(paste(
    "cat('partial\\n');",
    "plotly::plot_ly(x = 1:2, y = 2:1, type = 'scatter');",
    "stop('expected rich-output failure')"
  )))
  expect_identical(failed@extra$deputy_r$outcome, "error")
  expect_length(rich_artifact_segments(failed), 1L)
  expect_match(
    r_session_text(failed),
    "expected rich-output failure",
    fixed = TRUE
  )
})

test_that("DT values use the rich artifact contract", {
  expect_rich_producer(
    paste(
      "DT::datatable(data.frame(name = c('zeta', 'alpha'),",
      "value = c(2, 1)), rownames = FALSE)"
    ),
    "DT",
    "DT"
  )
})

test_that("Leaflet values use the rich artifact contract", {
  expect_rich_producer(
    paste(
      "leaflet::addCircleMarkers(leaflet::leaflet(),",
      "lng = -83, lat = 42, radius = 8, popup = 'Local station')"
    ),
    "leaflet",
    "leaflet"
  )
})

test_that("gt values use the rich artifact contract", {
  expect_rich_producer(
    "gt::gt(data.frame(x = 1:2, y = c('A', 'B')))",
    "gt",
    "gt"
  )
})

test_that("flextable values use the rich artifact contract", {
  expect_rich_producer(
    "flextable::flextable(data.frame(x = 1:2, y = c('A', 'B')))",
    "flextable",
    "flextable"
  )
})

test_that("a rich result that exceeds the output budget is not published", {
  skip_if_not_installed("plotly")
  directory <- withr::local_tempdir("deputy-r-rich-budget-work-")
  artifact_dir <- withr::local_tempdir("deputy-r-rich-budget-store-")
  session <- RSession$new(
    rich_artifact_agent(directory, agent_id = "agent-rich-budget"),
    artifact_dir = artifact_dir,
    artifact_owner_id = "tenant-rich-budget",
    max_output_bytes = 1024L
  )
  withr::defer(session$close())

  result <- r_session_await(session$run(
    "plotly::plot_ly(x = 1:3, y = c(3, 1, 2), type = 'scatter')"
  ))
  expect_true(
    result@extra$deputy_r$outcome %in%
      c(
        "unsupported_output",
        "artifact_unavailable"
      )
  )
  expect_false(any(vapply(
    rich_artifact_segments(result),
    function(segment) !is.null(segment$artifact$id),
    logical(1)
  )))
  expect_length(list.files(artifact_dir, pattern = "[.]html$"), 0L)
  expect_match(r_session_text(result), "output|budget", ignore.case = TRUE)
})

test_that("saved rich tool displays survive load and a fresh R process", {
  skip_if_not_installed("plotly")
  skip_if_not_installed("pkgload")

  directory <- withr::local_tempdir("deputy-r-rich-agent-work-")
  artifact_dir <- withr::local_tempdir("deputy-r-rich-agent-store-")
  session_path <- file.path(directory, "rich-session.rds")
  server <- local_runtime_server(list(
    runtime_reply(
      tool = "run_r_code",
      arguments = list(
        code = paste(
          "plotly::plot_ly(x = 1:3, y = c(3, 1, 2),",
          "type = 'scatter', mode = 'markers')"
        )
      )
    ),
    runtime_reply("done")
  ))
  agent <- Agent$new(
    chat = runtime_chat(server),
    working_dir = directory,
    agent_id = "agent-rich-agent-display",
    session_id = "session-rich-agent-display",
    permissions = Permissions(r_code = TRUE),
    run_context = list(conversation_id = "rich-agent-display")
  )
  session <- RSession$new(
    agent,
    artifact_dir = artifact_dir,
    artifact_owner_id = "tenant-rich-agent-display"
  )
  withr::defer(session$close())
  agent$register_tools(session$tools())
  suppressMessages(agent$chat("Run the interactive calculation."))
  expect_identical(agent$last_run()$stop_reason, "complete")

  contents <- unlist(
    lapply(agent$get_turns(), function(turn) turn@contents),
    recursive = FALSE
  )
  result <- Filter(
    function(value) inherits(value, "ellmer::ContentToolResult"),
    contents
  )[[1L]]
  artifacts <- expect_rich_artifact(result)
  id <- artifacts[[1L]]$artifact$id
  display <- as.character(result@extra$display$html)
  suppressMessages(agent$save_session(session_path))

  restored <- Agent$new(
    chat = runtime_chat(server),
    working_dir = directory,
    agent_id = "agent-rich-agent-display",
    session_id = "session-rich-agent-display",
    run_context = list(conversation_id = "rich-agent-display")
  )
  suppressMessages(restored$load_session(session_path))
  restored_contents <- unlist(
    lapply(restored$get_turns(), function(turn) turn@contents),
    recursive = FALSE
  )
  restored_result <- Filter(
    function(value) inherits(value, "ellmer::ContentToolResult"),
    restored_contents
  )[[1L]]
  expect_identical(as.character(restored_result@extra$display$html), display)
  expect_match(display, id, fixed = TRUE)
  expect_false(grepl("<iframe", display, fixed = TRUE))

  package_dir <- getNamespaceInfo(asNamespace("deputy"), "path")
  portable <- callr::r(
    function(package_dir, session_path, work_dir, store, artifact_id) {
      if (base::file.exists(base::file.path(package_dir, "R", "agent.R"))) {
        base::getExportedValue("pkgload", "load_all")(
          package_dir,
          quiet = TRUE,
          helpers = FALSE
        )
      } else {
        package_lib <- base::dirname(package_dir)
        base::library("deputy", lib.loc = package_lib, character.only = TRUE)
      }
      saved <- base::readRDS(session_path)
      saved_contents <- base::unlist(
        base::lapply(saved$turns, function(turn) turn@contents),
        recursive = FALSE
      )
      saved_result <- base::Filter(
        function(value) inherits(value, "ellmer::ContentToolResult"),
        saved_contents
      )[[1L]]
      child_agent <- deputy::Agent$new(
        chat = ellmer::chat_openai_compatible(
          base_url = "http://127.0.0.1:9/v1",
          credentials = function() "offline-fixture",
          model = "offline-fixture",
          echo = "none"
        ),
        working_dir = work_dir,
        agent_id = "agent-rich-agent-display",
        session_id = "session-rich-agent-display",
        run_context = list(conversation_id = "rich-agent-display")
      )
      reopened <- deputy::RSession$new(
        child_agent,
        artifact_dir = store,
        artifact_owner_id = "tenant-rich-agent-display"
      )
      base::on.exit(reopened$close(), add = TRUE)
      list(
        display = base::as.character(saved_result@extra$display$html),
        frame = htmltools::renderTags(
          reopened$artifact_frame(artifact_id)
        )$html
      )
    },
    list(
      package_dir = package_dir,
      session_path = session_path,
      work_dir = directory,
      store = artifact_dir,
      artifact_id = id
    )
  )
  expect_identical(portable$display, display)
  expect_match(portable$frame, 'sandbox="allow-scripts"', fixed = TRUE)
  expect_match(portable$frame, "Content-Security-Policy", fixed = TRUE)
})
