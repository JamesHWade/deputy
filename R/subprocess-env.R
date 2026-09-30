# Environment for subprocesses that run model-written code.
#
# callr copies the host's whole environment into each child it starts, so
# model-written code was handed every credential the host was started with
# (#224). The code tools and RSession's worker instead get a base of system
# variables plus the names the host allows. callr unsets a variable whose
# value is NA for the child, and the child's user environ file is the null
# device, so it doesn't reread `~/.Renviron` or a project `.Renviron`, where
# R users usually keep their keys.
#
# This is hygiene, not isolation. A child running as the same user can
# still read the host's starting environment through the operating system
# (`/proc/<pid>/environ` on Linux), and any file that user can read. The
# site `Renviron.site` and, for the one-shot tools, a project `.Rprofile`
# still apply, as they configure the installation and the project rather
# than hold a person's keys.

# Variables that locate programs, libraries, locales and temporary files, or
# cap threads, and carry no credentials. Windows needs its system variables
# for most programs to start at all.
subprocess_env_base <- c(
  "PATH",
  "HOME",
  "USER",
  "LOGNAME",
  "SHELL",
  "TERM",
  "LANG",
  "LANGUAGE",
  "TZ",
  "TZDIR",
  "TMPDIR",
  "TMP",
  "TEMP",
  "R_LIBS",
  "R_LIBS_USER",
  "R_LIBS_SITE",
  "R_USER",
  "LD_LIBRARY_PATH",
  "LOCALE_ARCHIVE",
  "PKG_CONFIG_PATH",
  "R_MAKEVARS_USER",
  "R_MAKEVARS_SITE",
  "R_CONFIG_ACTIVE",
  "R_ZIPCMD",
  "R_UNZIPCMD",
  "R_GZIPCMD",
  "R_BZIPCMD",
  "R_PAPERSIZE",
  "RSTUDIO_PANDOC",
  "QUARTO_PATH",
  "JAVA_HOME",
  "RETICULATE_PYTHON",
  "RETICULATE_PYTHON_ENV",
  "OMP_NUM_THREADS",
  "OPENBLAS_NUM_THREADS",
  "MKL_NUM_THREADS",
  "SSL_CERT_FILE",
  "SSL_CERT_DIR",
  "CURL_CA_BUNDLE",
  "SYSTEMROOT",
  "SYSTEMDRIVE",
  "WINDIR",
  "COMSPEC",
  "PATHEXT",
  "USERPROFILE",
  "HOMEDRIVE",
  "HOMEPATH",
  "APPDATA",
  "LOCALAPPDATA",
  "PROGRAMDATA",
  "PROGRAMFILES",
  "PROGRAMFILES(X86)",
  "USERNAME",
  "USERDOMAIN",
  "NUMBER_OF_PROCESSORS",
  "PROCESSOR_ARCHITECTURE",
  "OS"
)

# Locale categories (LC_ALL, LC_CTYPE, ...) and Rtools on Windows
# (RTOOLS44_HOME, ...).
subprocess_env_pattern <- "^LC_|^RTOOLS[0-9]*_HOME$"

# Check an `env` argument: NULL (the base only), "inherit", or the names of
# host variables to pass as well. `class` adds error classes for the caller.
check_subprocess_env <- function(env, arg = "env", class = NULL) {
  if (is.null(env) || identical(env, "inherit")) {
    return(env)
  }
  if (
    !is.character(env) ||
      !is.null(names(env)) ||
      anyNA(env) ||
      !all(nzchar(env)) ||
      any(grepl("[=\\s]", env, perl = TRUE))
  ) {
    abort_deputy(
      "{.arg {arg}} must be {.val inherit} or the names of environment variables to pass, such as {.code c(\"MY_VAR\")}.",
      class = c(class, "subprocess_env"),
      .envir = rlang::env(arg = arg)
    )
  }
  if ("inherit" %in% env) {
    abort_deputy(
      "{.arg {arg}} can be {.val inherit} only on its own.",
      class = c(class, "subprocess_env"),
      .envir = rlang::env(arg = arg)
    )
  }
  unique(env)
}

# Which of `names` a child may see: the base, the locale categories and the
# names the host allowed. Windows compares names without case, and so do
# proxy settings everywhere: programs read `https_proxy` and `HTTPS_PROXY`
# alike, and libcurl reads only the lower-case `http_proxy`.
subprocess_env_allowed <- function(names, allow = NULL) {
  wanted <- c(subprocess_env_base, allow)
  if (identical(.Platform$OS.type, "windows")) {
    return(
      toupper(names) %in%
        toupper(wanted) |
        grepl(subprocess_env_pattern, toupper(names))
    )
  }
  proxy <- grepl("_proxy$", names, ignore.case = TRUE) &
    toupper(names) %in% toupper(allow)
  names %in% wanted | proxy | grepl(subprocess_env_pattern, names)
}

# The named vector for callr's `env` argument. `base` holds callr's own
# defaults, which always apply. With "inherit" the child sees the host's
# environment, as callr does by default.
subprocess_env <- function(allow = NULL, base = callr::rcmd_safe_env()) {
  if (identical(allow, "inherit")) {
    return(base)
  }
  current <- names(Sys.getenv())
  hidden <- current[!subprocess_env_allowed(current, allow)]
  env <- stats::setNames(rep(NA_character_, length(hidden)), hidden)
  env[names(base)] <- base
  # The null device rather than an empty file: a file could be written to by
  # one child and then read by every later one.
  if (!subprocess_env_allowed("R_ENVIRON_USER", allow)) {
    env[["R_ENVIRON_USER"]] <- nullfile()
  }
  env
}
