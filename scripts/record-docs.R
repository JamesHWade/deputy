root <- normalizePath(".")
if (!file.exists(file.path(root, "DESCRIPTION"))) {
  stop("Run scripts/record-docs.R from the repository root.")
}

required_keys <- c(
  OPENAI_API_KEY = nzchar(Sys.getenv("OPENAI_API_KEY"))
)

if (!all(required_keys)) {
  stop(
    "Missing required API keys for docs recording: ",
    paste(names(required_keys)[!required_keys], collapse = ", ")
  )
}

source(file.path(root, "scripts", "check-docs.R"), local = TRUE)

Sys.setenv(
  DEPUTY_DOCS_MODE = "record",
  DEPUTY_DOCS_ROOT = root
)

pkgload::load_all(path = root, export_all = FALSE, helpers = FALSE)

rmarkdown::render(
  file.path(root, "README.Rmd"),
  output_file = file.path(root, "README.md"),
  quiet = TRUE,
  envir = new.env(parent = globalenv())
)
unlink(file.path(root, "README.html"), force = TRUE)

pkgdown::build_site_github_pages(
  new_process = FALSE,
  install = TRUE
)

check_docs(root)
