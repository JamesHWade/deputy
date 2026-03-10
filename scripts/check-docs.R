docs_spec <- list(
  list(
    path = "README.Rmd",
    article = "readme",
    status = "verified-replay"
  ),
  list(
    path = "vignettes/getting-started.Rmd",
    article = "getting-started",
    status = "verified-replay"
  ),
  list(
    path = "vignettes/tools.Rmd",
    article = "tools",
    status = "verified-vcr",
    cassettes = c("vignettes/_vcr/tools-web-tools.yml")
  ),
  list(
    path = "vignettes/permissions.Rmd",
    article = "permissions",
    status = "verified-replay"
  ),
  list(
    path = "vignettes/hooks.Rmd",
    article = "hooks",
    status = "verified-replay"
  ),
  list(
    path = "vignettes/structured-output.Rmd",
    article = "structured-output",
    status = "verified-vcr",
    cassettes = c("vignettes/_vcr/structured-output-main-example.yml")
  ),
  list(
    path = "vignettes/agent-configuration.Rmd",
    article = "agent-configuration",
    status = "verified-replay"
  ),
  list(
    path = "vignettes/multi-agent.Rmd",
    article = "multi-agent",
    status = "verified-replay"
  ),
  list(
    path = "vignettes/example-data-analysis.Rmd",
    article = "example-data-analysis",
    status = "verified-replay"
  ),
  list(
    path = "vignettes/example-extraction-pipeline.Rmd",
    article = "example-extraction-pipeline",
    status = "verified-replay"
  ),
  list(
    path = "vignettes/example-code-review.Rmd",
    article = "example-code-review",
    status = "verified-replay"
  ),
  list(
    path = "vignettes/example-shiny-chat.Rmd",
    article = "example-shiny-chat",
    status = "illustrative"
  )
)

collapse_lines <- function(path) {
  paste(readLines(path, warn = FALSE), collapse = "\n")
}

check_docs <- function(root = normalizePath(".")) {
  paths <- vapply(docs_spec, `[[`, character(1), "path")
  missing <- paths[!file.exists(file.path(root, paths))]
  if (length(missing) > 0) {
    stop("Missing docs sources: ", paste(missing, collapse = ", "))
  }

  support_path <- file.path(root, "R", "docs-support.R")
  if (!file.exists(support_path)) {
    stop("Missing docs support helpers: ", support_path)
  }

  support_text <- collapse_lines(support_path)
  if (grepl(
    "default_options\\s*<-\\s*list\\([^\\)]*eval\\s*=\\s*FALSE",
    support_text,
    perl = TRUE
  )) {
    stop("docs helpers must not set a global eval = FALSE default")
  }

  required_cassettes <- character()

  for (spec in docs_spec) {
    path <- file.path(root, spec$path)
    text <- collapse_lines(path)

    status_pattern <- sprintf(
      "docs_init\\([^\\)]*\"%s\"[^\\)]*\"%s\"",
      spec$article,
      spec$status
    )
    if (!grepl(status_pattern, text, perl = TRUE)) {
      stop("Missing docs status declaration in: ", spec$path)
    }

    if (!grepl("status_block", text, fixed = TRUE)) {
      stop("Missing docs status block in: ", spec$path)
    }

    if (grepl(
      "opts_chunk\\$set\\([^\\)]*eval\\s*=\\s*FALSE",
      text,
      perl = TRUE
    )) {
      stop("Global eval = FALSE is not allowed in docs sources: ", spec$path)
    }

    if (!identical(spec$status, "illustrative") &&
      !grepl("docs\\$should_eval", text, perl = TRUE)) {
      stop("Missing explicit runnable chunk(s) in: ", spec$path)
    }

    if (identical(spec$status, "illustrative") &&
      !grepl("Illustrative example only", text, fixed = TRUE)) {
      stop("Illustrative docs must include a visible notice: ", spec$path)
    }

    required_cassettes <- c(
      required_cassettes,
      if (is.null(spec$cassettes)) character() else spec$cassettes
    )
  }

  missing_cassettes <- required_cassettes[
    !file.exists(file.path(root, required_cassettes))
  ]
  if (length(missing_cassettes) > 0) {
    stop(
      "Missing required docs cassettes: ",
      paste(missing_cassettes, collapse = ", ")
    )
  }

  message("Docs checks passed.")
  invisible(TRUE)
}

if (sys.nframe() == 0) {
  check_docs()
}
