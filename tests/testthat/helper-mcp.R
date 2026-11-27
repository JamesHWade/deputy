skip_if_mcptools_unqualified <- function() {
  skip_if_not_installed("mcptools")
  version <- as.character(utils::packageVersion("mcptools"))
  skip_if_not(
    mcptools_version_qualified(version),
    paste0(
      "mcptools ",
      version,
      " is not a qualified release (",
      paste(mcptools_qualified_versions, collapse = ", "),
      ")"
    )
  )
}

mcp_test_config <- function(
  capabilities = c("tools", "resources", "prompts"),
  .local_envir = parent.frame()
) {
  skip_if_mcptools_unqualified()
  path <- withr::local_tempfile(fileext = ".json", .local_envir = .local_envir)
  log <- withr::local_tempfile(.local_envir = .local_envir)
  file.create(log)
  jsonlite::write_json(
    list(
      mcpServers = list(
        fixture = list(
          command = file.path(R.home("bin"), "Rscript"),
          args = list(
            normalizePath(test_path("fixtures", "mcp-capabilities.R")),
            log,
            paste(capabilities, collapse = ",")
          )
        ),
        excluded = list(command = "deputy-must-not-start-this-server")
      )
    ),
    path,
    auto_unbox = TRUE
  )
  list(path = path, log = log)
}

mcp_test_await <- function(value, timeout = 10) {
  await_promise(value, timeout = timeout, label = "MCP test promise")
}

# A stdio server whose replies can outlast mcptools' ~4 s response window.
mcp_slow_config <- function(.local_envir = parent.frame()) {
  skip_if_mcptools_unqualified()
  log <- withr::local_tempfile(.local_envir = .local_envir)
  file.create(log)
  fixture <- normalizePath(test_path("fixtures", "mcp-slow.R"))
  rscript <- file.path(R.home("bin"), "Rscript")
  server <- list(command = rscript, args = list(fixture, log))
  path <- withr::local_tempfile(fileext = ".json", .local_envir = .local_envir)
  jsonlite::write_json(
    list(mcpServers = list(slow = server)),
    path,
    auto_unbox = TRUE
  )
  list(path = path, log = log)
}

mcp_slow_calls <- function(config) {
  grep("^call ", readLines(config$log), value = TRUE)
}

# An executable that answers `--version` like MCP Console and otherwise serves
# the MCP Console fixture. The version is read from the launch environment.
mcp_console_fixture <- function(.local_envir = parent.frame()) {
  skip_if_mcptools_unqualified()
  skip_on_os("windows")
  log <- withr::local_tempfile(.local_envir = .local_envir)
  file.create(log)
  fixture <- normalizePath(test_path("fixtures", "mcp-console.R"))
  bin <- withr::local_tempdir(
    pattern = "mcp-console-bin-",
    .local_envir = .local_envir
  )
  command <- file.path(bin, "mcp-console")
  writeLines(
    c(
      "#!/bin/sh",
      "if [ \"$1\" = \"--version\" ]; then",
      "  echo \"mcp-console ${DEPUTY_CONSOLE_FIXTURE_VERSION:-0.4.0}\"",
      "  exit 0",
      "fi",
      paste(
        "exec",
        shQuote(file.path(R.home("bin"), "Rscript")),
        shQuote(fixture),
        shQuote(log),
        "\"$@\""
      )
    ),
    command
  )
  Sys.chmod(command, "0755")
  workspace <- withr::local_tempdir(
    pattern = "mcp-console-workspace-",
    .local_envir = .local_envir
  )
  list(command = command, log = log, workspace = workspace)
}

mcp_console_log <- function(fixture, prefix = "") {
  grep(paste0("^", prefix), readLines(fixture$log), value = TRUE)
}
