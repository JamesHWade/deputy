# Run from the package root. Only synthetic widget data is used.
output <- commandArgs(trailingOnly = TRUE)
if (length(output) != 1L) {
  stop("Supply an output HTML path.")
}
pkgload::load_all(quiet = TRUE)
source("tests/testthat/helper-r-session.R")
build_fixture <- function(output) {
  new_agent <- function() {
    Agent$new(
      ellmer::chat_openai_compatible(
        base_url = "http://127.0.0.1:1",
        model = "gpt-4o-mini",
        credentials = function() "fixture"
      ),
      agent_id = "preview",
      session_id = "verification"
    )
  }
  owner <- function() {
    RSession$new(
      new_agent(),
      artifact_dir = tempdir(),
      artifact_owner_id = "browser-test"
    )
  }
  worker <- owner()
  on.exit(worker$close(), add = TRUE)
  ids <- character()
  examples <- c(
    DT = "DT::datatable(data.frame(name=c('zeta','alpha'),value=c(2,1)), rownames=FALSE, options=list(order=list(list(0,'desc'))))",
    Plotly = "plotly::plot_ly(x=1:3,y=c(3,1,2),type='scatter',mode='markers')",
    Leaflet = "leaflet::addCircleMarkers(leaflet::leaflet(), lng=-83, lat=42, radius=8, popup='Local station')",
    gt = "gt::gt(data.frame(x=1:2, y=c('A','B')))",
    flextable = "flextable::flextable(data.frame(x=1:2, y=c('A','B')))"
  )
  for (name in names(examples)) {
    result <- r_session_await(worker$run(examples[[name]]))
    if (!identical(result@extra$deputy_r$outcome, "complete")) {
      stop(r_session_text(result))
    }
    segment <- Filter(
      function(x) identical(x$type, "artifact"),
      result@extra$deputy_r$segments
    )[[1L]]
    cat(
      name,
      segment$artifact$bytes,
      "HTML bytes |",
      segment$artifact$fallback,
      "\n"
    )
    stopifnot(length(segment$png) > 0L, is.null(segment$html))
    pixels <- png::readPNG(segment$png)
    stopifnot(stats::sd(as.numeric(pixels)) > 0.001)
    cat("  PNG", paste(dim(pixels), collapse = "x"), "nonblank\n")
    ids[name] <- segment$artifact$id
  }
  worker$close()
  reopened <- owner()
  on.exit(reopened$close(), add = TRUE)
  page <- paste0(
    "<!doctype html><meta charset='utf-8'><h1 id='host-marker'>Host page</h1>",
    paste(
      vapply(
        ids,
        function(id) as.character(reopened$artifact_frame(id)),
        character(1)
      ),
      collapse = "\n"
    )
  )
  writeLines(page, output)
}
build_fixture(output)
