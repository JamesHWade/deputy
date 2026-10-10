# Seconds to allow a child R process that loads deputy. Under covr every such
# load first instruments the whole package, which takes more than ten seconds,
# and longer on a busy runner.
child_load_allowance <- function(seconds) {
  if (identical(Sys.getenv("R_COVR"), "true")) seconds + 120 else seconds
}
