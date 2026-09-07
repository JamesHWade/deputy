# Run from the Deputy checkout. This uses synthetic producers and mock Chats;
# no model API is called. Install posit-mcp-repl==0.3.0 explicitly first.
executable <- Sys.getenv("DEPUTY_MCP_REPL_BIN")
output <- Sys.getenv("DEPUTY_MCP_QUALIFICATION_OUTPUT")
if (!nzchar(executable) || !file.exists(executable) || !nzchar(output)) {
  stop(
    "Set DEPUTY_MCP_REPL_BIN and a new DEPUTY_MCP_QUALIFICATION_OUTPUT directory."
  )
}
if (dir.exists(output)) {
  stop("Preserve previous qualification evidence; choose a new directory.")
}
dir.create(output, recursive = TRUE)
source_commit <- system2("git", c("rev-parse", "HEAD"), stdout = TRUE)
invocation <- list(
  source_commit = source_commit,
  started_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
  command = "Rscript dev/evaluations/mcp-repl/qualify.R",
  test_filter = "api|mcp-connection|mcp-repl-lifecycle",
  platform = R.version$platform,
  r_version = as.character(getRversion()),
  packages = lapply(
    c("mcptools", "ellmer", "callr", "testthat"),
    function(package) {
      list(
        package = package,
        version = as.character(utils::packageVersion(package))
      )
    }
  ),
  mcp_repl = list(
    qualified_release = "0.3.0",
    binary_sha256 = digest::digest(file = executable, algo = "sha256")
  ),
  model_requests = 0L
)
jsonlite::write_json(
  invocation,
  file.path(output, "invocation.json"),
  pretty = TRUE,
  auto_unbox = TRUE,
  digits = NA
)
results <- testthat::test_local(
  filter = invocation$test_filter,
  reporter = "summary",
  stop_on_failure = FALSE
)
table <- as.data.frame(results)
columns <- intersect(
  c(
    "file",
    "test",
    "nb",
    "failed",
    "error",
    "warning",
    "skipped",
    "passed",
    "real"
  ),
  names(table)
)
report <- list(
  source_commit = source_commit,
  assertions = sum(table$nb),
  failed = sum(table$failed),
  errors = sum(table$error),
  warnings = sum(table$warning),
  skipped = sum(table$skipped),
  tests = table[columns]
)
jsonlite::write_json(
  report,
  file.path(output, "results.json"),
  pretty = TRUE,
  auto_unbox = TRUE,
  null = "null",
  na = "null",
  digits = NA
)
if (report$failed || report$errors || report$warnings || report$skipped) {
  stop(
    "Qualification was not complete and clean; preserve the recorded outcomes."
  )
}
cat("Qualified assertions:", report$assertions, "Source:", source_commit, "\n")
