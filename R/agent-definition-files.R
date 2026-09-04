#' Read, write, and discover AgentDefinition files
#'
#' @description
#' Deputy's versioned YAML format represents every field in
#' [agent_definition()]. Tools and skills are symbolic references resolved only
#' through explicit host-supplied registries. Reading a file does not load
#' packages, source R code, connect MCP servers, or instantiate an Agent.
#'
#' @param path A YAML file for reading/writing, or a directory for discovery.
#'   Discovery defaults to `.deputy/agents` in the current project and reads
#'   `.yaml` and `.yml` files in that directory, without recursion.
#' @param tools Named list of ellmer tool objects available to the definition.
#'   Registry keys are case-sensitive symbols, such as `read_file`.
#' @param skills Named list of [Skill] objects or skill paths approved by the
#'   host. Files reference these keys, never literal paths.
#' @param definition An [AgentDefinition][agent_definition] to write. Each tool
#'   and skill must match exactly one entry in its supplied registry.
#' @param overwrite Whether to replace an existing file. Defaults to `FALSE`.
#'
#' @return `agent_definition_read()` returns an `AgentDefinition`.
#'   `agent_definition_write()` invisibly returns `path`.
#'   `agent_definitions()` returns a named list of definitions keyed by their
#'   canonical routing names, ready for `LeadAgent$new(sub_agents = ...)`.
#'   A missing discovery directory returns an empty list. Invalid files or
#'   duplicate names abort the entire discovery operation.
#'
#' @section Format version 1:
#' A file is one YAML mapping with `version: 1` and the fields of
#' [agent_definition()]. `name`, `description`, and `prompt` are required.
#' Optional fields use the constructor defaults. `tools` and `skills` are
#' sequences of registry keys; `disallowed_tools`, `memory`, and `mcp_servers`
#' are sequences of strings. `model`, `initial_prompt`, and `permission_mode`
#' are strings, and `max_requests` is a non-negative integer. Explicit `null` is
#' accepted only for constructor fields that allow `NULL`.
#'
#' Unknown fields, versions, references, duplicate keys, and YAML evaluation
#' tags are rejected. YAML type inference applies: quote strings such as
#' `"yes"` or `"123"`. Empty sequences are written as `[]` and optional NULL
#' values as `null`. Writing canonicalizes formatting; it does not preserve
#' comments or names attached to R lists or character sequences. Object order
#' and registry identity are preserved. A single string is accepted as shorthand
#' for a one-element sequence. Only regular files of at most 1 MiB are read.
#' Files are written as UTF-8 with LF line endings on every platform.
#' Writes use a temporary file in the destination directory and replace the
#' destination only after writing succeeds.
#' With `overwrite = FALSE`, installing the file requires hard-link support
#' from the filesystem so a concurrently created destination is never replaced.
#'
#' A definition describes a subagent. Permission modes and request limits
#' remain bounded by its LeadAgent. Nested `sub_agents`, host credentials,
#' runtime objects, and executable code are not part of this format.
#'
#' @examples
#' if (requireNamespace("yaml", quietly = TRUE)) {
#'   registry <- list(read_file = tool_read_file)
#'   definition <- agent_definition(
#'     "reviewer", "Reviews local text", "Read the supplied text carefully.",
#'     tools = unname(registry), permission_mode = "readonly", max_requests = 3
#'   )
#'   path <- tempfile(fileext = ".yaml")
#'   agent_definition_write(definition, path, tools = registry)
#'   restored <- agent_definition_read(path, tools = registry)
#'   restored$name
#'   unlink(path)
#' }
#' @export
agent_definition_read <- function(path, tools = list(), skills = list()) {
  rlang::check_installed("yaml", reason = "to read AgentDefinition files")
  validate_definition_file_path(path)
  validate_definition_registry(tools, "tools")
  validate_definition_registry(skills, "skills")
  info <- file.info(path)
  if (
    !isTRUE(utils::file_test("-f", path)) ||
      is.na(info$size) ||
      isTRUE(info$isdir) ||
      info$size > 1024^2
  ) {
    abort_definition_file(
      "Expected a readable YAML file of at most 1 MiB",
      path
    )
  }
  expression_tag <- FALSE
  spec <- tryCatch(
    yaml::read_yaml(
      path,
      eval.expr = FALSE,
      handlers = list(expr = function(x) {
        expression_tag <<- TRUE
        x
      })
    ),
    error = function(e) abort_definition_file("{conditionMessage(e)}", path),
    warning = function(e) abort_definition_file("{conditionMessage(e)}", path)
  )
  if (expression_tag) {
    abort_definition_file("YAML expression tags are not supported", path)
  }
  definition_from_spec(spec, tools, skills, path)
}

#' @rdname agent_definition_read
#' @export
agent_definition_write <- function(
  definition,
  path,
  tools = list(),
  skills = list(),
  overwrite = FALSE
) {
  rlang::check_installed("yaml", reason = "to write AgentDefinition files")
  validate_definition_file_path(path)
  validate_definition_registry(tools, "tools")
  validate_definition_registry(skills, "skills")
  if (!is.logical(overwrite) || length(overwrite) != 1L || is.na(overwrite)) {
    abort_definition_file("{.arg overwrite} must be TRUE or FALSE", path)
  }
  definition <- copy_agent_definition(definition)
  spec <- c(list(version = 1L), unclass(definition))
  spec$tools <- definition_reference_names(
    definition$tools,
    tools,
    "tools",
    path
  )
  spec$skills <- definition_reference_names(
    definition$skills,
    skills,
    "skills",
    path
  )
  # Keep sequences distinct from scalars, including single-element sequences.
  for (field in c(
    "tools",
    "skills",
    "disallowed_tools",
    "memory",
    "mcp_servers"
  )) {
    if (!is.null(spec[[field]])) spec[[field]] <- unname(as.list(spec[[field]]))
  }
  definition_from_spec(spec, tools, skills, path)
  bytes <- charToRaw(enc2utf8(yaml::as.yaml(spec)))
  if (length(bytes) > 1024^2) {
    abort_definition_file("AgentDefinition YAML exceeds 1 MiB", path)
  }
  if (file.exists(path) && !overwrite) {
    abort_definition_file(
      "File already exists; set {.code overwrite = TRUE} to replace it",
      path
    )
  }
  temporary <- tempfile(".deputy-definition-", tmpdir = dirname(path))
  on.exit(unlink(temporary), add = TRUE)
  tryCatch(
    writeBin(bytes, temporary),
    error = function(e) abort_definition_file("{conditionMessage(e)}", path),
    warning = function(e) abort_definition_file("{conditionMessage(e)}", path)
  )
  # Linking a completed file fails atomically if the destination exists.
  installed <- tryCatch(
    if (overwrite) file.rename(temporary, path) else file.link(temporary, path),
    error = function(e) abort_definition_file("{conditionMessage(e)}", path),
    warning = function(e) abort_definition_file("{conditionMessage(e)}", path)
  )
  if (!installed) {
    abort_definition_file(
      "Could not install the completed definition file",
      path
    )
  }
  invisible(path)
}

#' @rdname agent_definition_read
#' @export
agent_definitions <- function(
  path = file.path(".deputy", "agents"),
  tools = list(),
  skills = list()
) {
  validate_definition_file_path(path)
  validate_definition_registry(tools, "tools")
  validate_definition_registry(skills, "skills")
  if (!dir.exists(path)) {
    if (file.exists(path)) {
      abort_definition_file("Expected a directory", path)
    }
    return(list())
  }
  paths <- sort(list.files(
    path,
    pattern = "\\.ya?ml$",
    full.names = TRUE,
    ignore.case = TRUE
  ))
  if (length(paths) == 0L) {
    return(list())
  }
  definitions <- lapply(
    paths,
    agent_definition_read,
    tools = tools,
    skills = skills
  )
  keys <- vapply(definitions, function(x) x$name, character(1))
  if (anyDuplicated(keys)) {
    repeated <- unique(keys[duplicated(keys)])
    abort_definition_file(
      "Duplicate AgentDefinition names: {.val {repeated}}",
      path
    )
  }
  stats::setNames(definitions, keys)
}

abort_definition_file <- function(message, path = NULL) {
  abort_deputy(
    c(
      "Invalid AgentDefinition file",
      "x" = message,
      if (!is.null(path)) c("i" = "File: {.path {path}}")
    ),
    class = "agent_definition_file",
    path = path,
    .envir = parent.frame()
  )
}

validate_definition_file_path <- function(path) {
  if (!is_nonempty_string(path)) {
    abort_definition_file("{.arg path} must be one non-empty string")
  }
}

validate_definition_registry <- function(registry, field) {
  if (
    !is.list(registry) ||
      (length(registry) > 0 &&
        (is.null(names(registry)) ||
          anyNA(names(registry)) ||
          !all(grepl("^[A-Za-z][A-Za-z0-9_.-]*$", names(registry))) ||
          anyDuplicated(names(registry))))
  ) {
    abort_definition_file(
      "{.arg {field}} must be a list with unique symbolic names"
    )
  }
  for (value in registry) {
    valid <- if (field == "tools") {
      inherits(value, "ellmer::ToolDef") ||
        inherits(value, "ellmer::ToolBuiltIn")
    } else {
      inherits(value, "Skill") || is_nonempty_string(value)
    }
    if (!valid) {
      abort_definition_file("Invalid object in {.arg {field}} registry")
    }
  }
}

definition_string_sequence <- function(value, field, path, nullable = FALSE) {
  if (is.null(value) && nullable) {
    return(NULL)
  }
  if (
    is.list(value) &&
      is.null(names(value)) &&
      all(vapply(value, is_nonempty_string, logical(1)))
  ) {
    value <- unlist(value, use.names = FALSE)
    if (length(value) == 0) value <- character()
  }
  if (
    !is.character(value) ||
      !is.null(names(value)) ||
      anyNA(value) ||
      !all(nzchar(trimws(value)))
  ) {
    abort_definition_file(
      "{.field {field}} must be a sequence of non-empty strings",
      path
    )
  }
  value
}

definition_from_spec <- function(spec, tools, skills, path) {
  fields <- c("version", names(formals(agent_definition)))
  if (
    !is.list(spec) ||
      is.null(names(spec)) ||
      anyDuplicated(names(spec)) ||
      !all(names(spec) %in% fields)
  ) {
    abort_definition_file(
      "Expected a mapping containing only documented fields",
      path
    )
  }
  if (
    !is.numeric(spec$version) ||
      length(spec$version) != 1L ||
      !isTRUE(spec$version == 1)
  ) {
    abort_definition_file("{.field version} must be 1", path)
  }
  if (!all(c("name", "description", "prompt") %in% names(spec))) {
    abort_definition_file(
      "Required fields: {.field name}, {.field description}, {.field prompt}",
      path
    )
  }
  spec$version <- NULL
  for (field in c("tools", "skills")) {
    if (!field %in% names(spec)) {
      next
    }
    keys <- definition_string_sequence(spec[[field]], field, path)
    registry <- if (field == "tools") tools else skills
    missing <- setdiff(keys, names(registry))
    if (length(missing) > 0 || anyDuplicated(keys)) {
      abort_definition_file(
        "Unknown or duplicate {.field {field}} references: {.val {keys}}",
        path
      )
    }
    spec[[field]] <- unname(registry[keys])
  }
  for (field in c("memory", "mcp_servers", "disallowed_tools")) {
    if (field %in% names(spec)) {
      spec[field] <- list(definition_string_sequence(
        spec[[field]],
        field,
        path,
        nullable = TRUE
      ))
    }
  }
  tryCatch(do.call(agent_definition, spec), error = function(e) {
    abort_definition_file("{conditionMessage(e)}", path)
  })
}

definition_reference_names <- function(values, registry, field, path) {
  vapply(
    values,
    function(value) {
      matches <- which(vapply(registry, identical, logical(1), y = value))
      if (length(matches) != 1L) {
        abort_definition_file(
          "Each {.field {field}} object must match exactly one registry entry",
          path
        )
      }
      names(registry)[[matches]]
    },
    character(1),
    USE.NAMES = FALSE
  )
}
