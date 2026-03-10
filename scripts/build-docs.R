root <- normalizePath(".")
if (!file.exists(file.path(root, "DESCRIPTION"))) {
  stop("Run scripts/build-docs.R from the repository root.")
}

source(file.path(root, "scripts", "check-docs.R"), local = TRUE)

Sys.setenv(
  DEPUTY_DOCS_MODE = "replay",
  DEPUTY_DOCS_ROOT = root
)

pkgload::load_all(path = root, export_all = FALSE, helpers = FALSE)

check_docs(root)

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
