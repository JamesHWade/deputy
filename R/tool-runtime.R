# Runtime tool adaptation ---------------------------------------------------

native_file_tool_names <- c(
  "read_file",
  "read_markdown",
  "write_file",
  "edit_file",
  "multi_edit",
  "list_files",
  "glob_files",
  "grep_files",
  "read_csv"
)

runtime_wrap_tool <- function(tool, agent) {
  if (!inherits(tool, "ellmer::ToolDef")) {
    cli_abort("{.arg tool} must be an ellmer tool definition")
  }
  if (isTRUE(attr(tool, "deputy_runtime_tool"))) {
    return(tool)
  }

  wrapper_env <- rlang::env(
    original = tool,
    agent = agent,
    tool_name = tool@name
  )
  wrapper <- rlang::new_function(
    formals(tool),
    quote({
      arguments <- as.list(environment(), all.names = TRUE)
      arguments <- agent$.__enclos_env__$private$resolve_tool_arguments(
        tool_name,
        arguments
      )
      value <- do.call(original, arguments)
      if (promises::is.promising(value)) {
        return(promises::then(value, function(resolved) {
          agent$.__enclos_env__$private$offload_tool_result(
            tool_name,
            resolved
          )
        }))
      }
      agent$.__enclos_env__$private$offload_tool_result(tool_name, value)
    }),
    wrapper_env
  )

  wrapped <- ellmer::tool(
    fun = wrapper,
    name = tool@name,
    description = tool@description,
    arguments = tool@arguments@properties,
    convert = tool@convert,
    annotations = tool@annotations
  )
  attr(wrapped, "deputy_runtime_tool") <- TRUE
  wrapped
}

resolve_runtime_tool_arguments <- function(tool_name, arguments, working_dir) {
  if (
    !tool_name %in% native_file_tool_names ||
      is.null(arguments$path) ||
      !is.character(arguments$path) ||
      length(arguments$path) != 1L ||
      is.na(arguments$path) ||
      !nzchar(arguments$path)
  ) {
    return(arguments)
  }

  if (!is_absolute_path(arguments$path)) {
    arguments$path <- file.path(working_dir, arguments$path)
  }
  arguments
}

tool_result_offload_dir <- function(policy, session_id) {
  root <- policy$offload_dir %||%
    file.path(tools::R_user_dir("deputy", "cache"), "tool-results")
  file.path(path.expand(root), session_id)
}

offload_tool_result <- function(
  value,
  tool_name,
  policy,
  session_id,
  agent_id
) {
  threshold <- policy$max_tool_result_bytes
  if (is.null(threshold) || inherits(value, "ellmer::ContentToolResult")) {
    return(NULL)
  }

  serialized <- serialize(value, NULL, version = 3)
  bytes <- length(serialized)
  if (bytes <= threshold) {
    return(NULL)
  }

  sha256 <- digest::digest(serialized, algo = "sha256", serialize = FALSE)
  result_id <- paste0("result_", sha256)
  directory <- tool_result_offload_dir(policy, session_id)
  if (!dir.exists(directory)) {
    dir.create(directory, recursive = TRUE, showWarnings = FALSE)
    Sys.chmod(directory, mode = "0700")
  }
  if (!dir.exists(directory)) {
    cli_abort("Could not create the tool-result offload directory")
  }

  path <- file.path(directory, paste0(result_id, ".rds"))
  if (!file.exists(path)) {
    envelope <- list(
      schema_version = 1L,
      id = result_id,
      tool_name = tool_name,
      session_id = session_id,
      agent_id = agent_id,
      bytes = bytes,
      sha256 = sha256,
      created_at = Sys.time(),
      value = value
    )
    temporary <- tempfile("result-", tmpdir = directory, fileext = ".rds")
    on.exit(unlink(temporary), add = TRUE)
    saveRDS(envelope, temporary, version = 3)
    Sys.chmod(temporary, mode = "0600")
    if (!file.rename(temporary, path)) {
      cli_abort("Could not commit the offloaded tool result")
    }
  }

  list(
    id = result_id,
    uri = paste0("deputy://tool-result/", result_id),
    bytes = bytes,
    sha256 = sha256,
    path = path
  )
}

tool_result_reference_text <- function(record) {
  paste(
    "[Tool result offloaded by Deputy]",
    paste0("reference: ", record$uri),
    paste0("bytes: ", record$bytes),
    paste0("sha256: ", record$sha256),
    "Use Agent$resolve_tool_result(reference) to retrieve the complete value.",
    sep = "\n"
  )
}

parse_tool_result_reference <- function(reference) {
  if (
    !is.character(reference) ||
      length(reference) != 1L ||
      is.na(reference)
  ) {
    cli_abort("{.arg reference} must be one Deputy tool-result reference")
  }
  match <- regexec("deputy://tool-result/(result_[a-f0-9]{64})", reference)
  captured <- regmatches(reference, match)[[1]]
  if (length(captured) != 2L) {
    cli_abort("{.arg reference} is not a Deputy tool-result reference")
  }
  captured[[2]]
}
