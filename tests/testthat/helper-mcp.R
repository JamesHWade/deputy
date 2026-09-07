mcp_test_config <- function(capabilities = c("tools", "resources", "prompts")) {
  skip_if_not_installed("mcptools", "1.0.2")
  skip_if(as.character(utils::packageVersion("mcptools")) != "1.0.2")
  path <- tempfile(fileext = ".json")
  log <- tempfile()
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
  done <- FALSE
  result <- NULL
  error <- NULL
  promises::then(
    value,
    function(x) {
      result <<- x
      done <<- TRUE
    },
    function(e) {
      error <<- e
      done <<- TRUE
    }
  )
  until <- Sys.time() + timeout
  while (!done && Sys.time() < until) {
    later::run_now(0.01)
  }
  if (!done) {
    stop("MCP test promise did not settle.")
  }
  if (!is.null(error)) {
    stop(error)
  }
  result
}
