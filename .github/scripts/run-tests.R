#!/usr/bin/env Rscript
# Discover the complete suite each run: new files automatically join a shard.
args <- commandArgs(trailingOnly = TRUE)
if (
  !length(args) %in% 2:3 ||
    (length(args) == 3L && args[[3L]] != "--list") ||
    !all(grepl("^[1-9][0-9]*$", args[1:2]))
) {
  stop("Usage: Rscript .github/scripts/run-tests.R <index> <count> [--list]")
}
index <- suppressWarnings(as.integer(args[[1L]]))
count <- suppressWarnings(as.integer(args[[2L]]))
if (anyNA(c(index, count)) || index > count) {
  stop("Shard index and count must be valid positive integers; index <= count.")
}

files <- sort(
  testthat::find_test_scripts("tests/testthat", full.names = FALSE),
  method = "radix"
)
if (!length(files) || count > length(files)) {
  stop("Every shard must contain at least one discovered test file.")
}
selected <- files[(seq_along(files) - 1L) %% count + 1L == index]
if (length(args) == 3L) {
  cat(selected, sep = "\n")
  quit(status = 0L)
}

# testthat's filter matches the filename without its test-/test_ prefix or .R.
# Verify the public discovery API selects exactly our partition before execution.
stems <- sub("[.][Rr]$", "", sub("^test[-_]", "", selected))
escaped <- gsub("([][{}()+*^$|\\\\.?])", "\\\\\\1", stems)
filter <- paste0("^(", paste(escaped, collapse = "|"), ")$")
matched <- testthat::find_test_scripts(
  "tests/testthat",
  filter = filter,
  full.names = FALSE
)
if (!setequal(matched, selected)) {
  stop("Test filter does not select exactly the assigned shard.")
}
cat(sprintf("Shard %d/%d: %d files\n", index, count, length(selected)))
cat(selected, sep = "\n")

output <- Sys.getenv(
  "DEPUTY_TEST_SUMMARY_DIR",
  file.path(Sys.getenv("RUNNER_TEMP", tempdir()), "deputy-test-results")
)
dir.create(output, recursive = TRUE, showWarnings = FALSE)
prefix <- file.path(output, sprintf("shard-%d-of-%d", index, count))
writeLines(selected, paste0(prefix, "-files.txt"))
started <- proc.time()[["elapsed"]]
# Streaming parallel events are necessary for meaningful per-test timing.
results <- tryCatch(
  testthat::test_local(
    filter = filter,
    reporter = testthat::ParallelProgressReporter$new(),
    stop_on_failure = FALSE
  ),
  error = identity
)
elapsed <- proc.time()[["elapsed"]] - started
utils::write.csv(
  data.frame(
    shard = index,
    shards = count,
    files = length(selected),
    seconds = elapsed
  ),
  paste0(prefix, "-wall.csv"),
  row.names = FALSE
)
cat(sprintf("Shard elapsed: %.3fs; results: %s\n", elapsed, output))
if (inherits(results, "error")) {
  stop(conditionMessage(results), call. = FALSE)
}
results <- as.data.frame(results)
if (!nrow(results)) {
  stop("Test shard produced no test results.", call. = FALSE)
}
utils::write.csv(
  results[, setdiff(names(results), "result"), drop = FALSE],
  paste0(prefix, "-tests.csv"),
  row.names = FALSE
)
if (any(results$failed > 0L | results$error)) {
  stop(
    "Test shard failed; see test output and result artifacts.",
    call. = FALSE
  )
}
