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

mcp_test_config <- function(capabilities = c("tools", "resources", "prompts")) {
  skip_if_mcptools_unqualified()
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

# A stdio server whose replies can outlast mcptools' ~4 s response window.
mcp_slow_config <- function(repl = FALSE) {
  skip_if_mcptools_unqualified()
  log <- tempfile()
  file.create(log)
  fixture <- normalizePath(test_path("fixtures", "mcp-slow.R"))
  rscript <- file.path(R.home("bin"), "Rscript")
  server <- if (repl) {
    skip_on_os("windows")
    # mcp_repl_connection() admits only an mcp-repl executable name.
    bin <- tempfile("mcp-repl-bin-")
    dir.create(bin)
    command <- file.path(bin, "mcp-repl")
    writeLines(
      c(
        "#!/bin/sh",
        paste("exec", shQuote(rscript), shQuote(fixture), shQuote(log))
      ),
      command
    )
    Sys.chmod(command, "0755")
    list(command = command, args = list("--sandbox", "workspace-write"))
  } else {
    list(command = rscript, args = list(fixture, log))
  }
  path <- tempfile(fileext = ".json")
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
