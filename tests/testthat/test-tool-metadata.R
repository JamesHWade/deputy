test_that("tool metadata retains supplied values and explicit gaps", {
  tool <- ellmer::tool(
    function() "value",
    name = "value",
    description = "A local value."
  )
  metadata <- tool_metadata(tool)
  expect_identical(metadata$source, list(type = "function"))
  expect_identical(metadata$annotations, list())
  expect_identical(
    metadata$missing_annotations,
    names(tool_annotation_defaults)
  )
  expect_identical(metadata$effective_annotations, tool_annotation_defaults)
  packaged <- ellmer::tool(
    base::toupper,
    name = "upper",
    description = "Uppercase text.",
    arguments = list(x = ellmer::type_string())
  )
  expect_identical(
    tool_metadata(packaged)$source,
    list(type = "package", package = "base")
  )
  agent <- Agent$new(chat = create_mock_chat(), tools = list(tool))
  expect_identical(tool_metadata(agent$get_tools()$value), metadata)
  expect_identical(tool_metadata(agent$clone()$get_tools()$value), metadata)
})

test_that("MCP annotation mapping preserves false values and extensions", {
  annotations <- mcp_ellmer_annotations(
    list(
      readOnlyHint = FALSE,
      destructiveHint = FALSE,
      openWorldHint = FALSE,
      idempotentHint = FALSE,
      title = "Title",
      custom = list(tag = "kept")
    ),
    "fixture"
  )
  expect_identical(
    annotations,
    list(
      read_only_hint = FALSE,
      destructive_hint = FALSE,
      open_world_hint = FALSE,
      idempotent_hint = FALSE,
      title = "Title",
      custom = list(tag = "kept")
    )
  )
  expect_error(
    mcp_ellmer_annotations(list(readOnlyHint = "true"), "fixture"),
    class = "deputy_tool_registration"
  )
  expect_error(
    mcp_ellmer_annotations(
      list(readOnlyHint = TRUE, read_only_hint = FALSE),
      "fixture"
    ),
    class = "deputy_tool_registration"
  )
})

test_that("tool arguments cannot shadow runtime adapter bindings", {
  tool <- ellmer::tool(
    function(original, execute, process_result, tool_name) {
      paste(original, execute, process_result, tool_name)
    },
    name = "binding_names",
    description = "Return arguments unchanged.",
    arguments = list(
      original = ellmer::type_string(),
      execute = ellmer::type_string(),
      process_result = ellmer::type_string(),
      tool_name = ellmer::type_string()
    )
  )
  agent <- Agent$new(chat = create_mock_chat(), tools = list(tool))
  expect_identical(
    agent$clone()$get_tools()$binding_names("a", "b", "c", "d"),
    "a b c d"
  )
})

test_that("released MCP transport preserves origin, annotations and connection identity", {
  skip_if_not_installed("mcptools", "1.0.2")
  fixture <- normalizePath(test_path("fixtures", "mcp-annotations.R"))
  # Isolate mcptools' process-global connection registry from other tests.
  result <- callr::r(
    function(package, fixture, helpers) {
      if (file.exists(file.path(package, "R", "agent.R"))) {
        pkgload::load_all(package, quiet = TRUE)
      } else {
        library(deputy)
      }
      test_helpers <- new.env(parent = asNamespace("deputy"))
      sys.source(file.path(helpers, "helper-mocks.R"), envir = test_helpers)
      sys.source(file.path(helpers, "helper-runtime.R"), envir = test_helpers)
      config <- tempfile(fileext = ".json")
      on.exit(unlink(config))
      server <- list(
        command = file.path(R.home("bin"), "Rscript"),
        args = list(fixture)
      )
      jsonlite::write_json(
        list(
          mcpServers = list(
            evidence = server,
            excluded = list(command = "deputy-must-not-launch-this-server")
          )
        ),
        config,
        auto_unbox = TRUE
      )
      tools <- tools_mcp(config, servers = "evidence")
      metadata <- lapply(tools, tool_metadata)
      agent <- Agent$new(
        chat = ellmer::chat_openai(
          credentials = function() "test",
          model = "gpt-4o-mini"
        ),
        tools = tools
      )
      clone <- agent$clone()
      context <- function(name) {
        list(
          tool_metadata = tool_metadata(tools[[name]]),
          tool_annotations = tools[[name]]@annotations
        )
      }
      decisions <- vapply(
        names(tools),
        function(name) {
          agent$permissions$check(name, list(), context(name))$decision
        },
        character(1)
      )
      value <- clone$get_tools()$inspect_evidence(
        claim = "claim-1",
        original = "literal"
      )
      remote_path <- clone$get_tools()$read_file(path = "remote/relative.txt")
      # YAML -> explicit registry -> LeadAgent -> child permission -> MCP call.
      definition_path <- tempfile(fileext = ".yaml")
      on.exit(unlink(definition_path), add = TRUE)
      definition <- agent_definition(
        "reviewer",
        "Reviews evidence",
        "Inspect the claim.",
        tools = unname(tools),
        permission_mode = "standard"
      )
      agent_definition_write(definition, definition_path, tools = tools)
      loaded <- agent_definition_read(definition_path, tools = tools)
      journeys <- lapply(
        c("inspect_evidence", "mystery", "read_file"),
        function(name) {
          inputs <- switch(
            name,
            inspect_evidence = list(claim = "yaml-claim"),
            read_file = list(path = "remote/relative.txt"),
            list()
          )
          observed <- NULL
          child <- NULL
          response <- NULL
          fixture_chat <- test_helpers$create_shiny_tool_chat(
            name,
            inputs,
            execute = function(request) {
              response <<- do.call(child$get_tools()[[name]], request@arguments)
            }
          )
          parent_chat <- test_helpers$create_mock_chat()
          parent_chat$clone <- function(...) fixture_chat$chat
          lead <- LeadAgent$new(
            chat = parent_chat,
            sub_agents = list(loaded),
            tools = list(tools$inspect_evidence),
            permissions = Permissions$new(web = FALSE, file_write = FALSE)
          )
          child <- lead$.__enclos_env__$private$create_sub_agent(loaded)
          child$add_hook(HookMatcher$new(
            event = "PreToolUse",
            timeout = 0,
            callback = function(tool_name, tool_input, context) {
              observed <<- context$tool_metadata
              NULL
            }
          ))
          child$run_sync("Inspect the claim.")
          list(
            executed = fixture_chat$state$executed,
            rejected = fixture_chat$state$rejected,
            response = response,
            metadata = observed,
            child_tools = names(child$get_tools()),
            child_web = child$permissions$web
          )
        }
      )
      old_tool <- tools$inspect_evidence
      reloaded <- tools_mcp(config, servers = "evidence")
      stale <- tryCatch(
        old_tool(claim = "claim-2"),
        deputy_mcp_metadata = function(e) class(e)
      )
      # Loading a second configuration must not return the previous connection's tools.
      jsonlite::write_json(
        list(mcpServers = list(second = server)),
        config,
        auto_unbox = TRUE
      )
      second <- tools_mcp(config)
      jsonlite::write_json(
        list(mcpServers = list(evidence = server, second = server)),
        config,
        auto_unbox = TRUE
      )
      conflict <- tryCatch(
        {
          withCallingHandlers(tools_mcp(config), warning = function(e) {
            if (
              grepl("Duplicate tool name", conditionMessage(e), fixed = TRUE)
            ) {
              stop(e)
            }
          })
          FALSE
        },
        warning = function(e) TRUE
      )
      list(
        metadata = metadata,
        clone_metadata = lapply(clone$get_tools(), tool_metadata),
        decisions = decisions,
        value = value,
        remote_path = remote_path,
        stale = stale,
        journeys = journeys,
        conflict = conflict,
        second_sources = lapply(second, function(tool) {
          tool_metadata(tool)$source
        })
      )
    },
    args = list(
      package = normalizePath(test_path("..", "..")),
      fixture = fixture,
      helpers = normalizePath(test_path())
    )
  )
  expect_named(result$metadata, c("inspect_evidence", "mystery", "read_file"))
  expect_identical(
    result$metadata$inspect_evidence$source,
    list(type = "mcp", server = "evidence", tool = "inspect_evidence")
  )
  expect_identical(
    result$metadata$inspect_evidence$missing_annotations,
    character()
  )
  expect_identical(
    result$metadata$inspect_evidence$annotations,
    list(
      read_only_hint = TRUE,
      destructive_hint = FALSE,
      idempotent_hint = TRUE,
      open_world_hint = FALSE,
      title = "Inspect evidence"
    )
  )
  expect_identical(
    result$metadata$mystery$missing_annotations,
    names(tool_annotation_defaults)
  )
  expect_identical(result$clone_metadata, result$metadata)
  expect_identical(unname(result$decisions), c("allow", "deny", "deny"))
  expect_match(
    paste(result$value, collapse = ""),
    "called:inspect_evidence:claim-1",
    fixed = TRUE
  )
  expect_match(
    paste(result$remote_path, collapse = ""),
    "remote/relative.txt",
    fixed = TRUE
  )
  expect_true("deputy_mcp_metadata" %in% result$stale)
  expect_identical(
    vapply(result$journeys, function(x) x$executed, logical(1)),
    c(TRUE, FALSE, FALSE)
  )
  expect_identical(
    vapply(result$journeys, function(x) x$rejected, logical(1)),
    c(FALSE, TRUE, TRUE)
  )
  expect_identical(
    result$journeys[[1]]$metadata,
    result$metadata$inspect_evidence
  )
  expect_identical(result$journeys[[1]]$child_tools, names(result$metadata))
  expect_false(result$journeys[[1]]$child_web)
  expect_match(
    paste(result$journeys[[1]]$response, collapse = ""),
    "yaml-claim",
    fixed = TRUE
  )
  expect_true(result$conflict)
  expect_true(all(vapply(
    result$second_sources,
    function(source) identical(source$server, "second"),
    logical(1)
  )))
})
