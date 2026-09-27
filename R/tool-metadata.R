#' Inspect a tool's origin and annotations
#'
#' Reports where a tool comes from and which annotations it declares. It works
#' on tools as you created them and on the wrapped copies an agent or subagent
#' holds. The tool is not called.
#'
#' @param tool An ellmer tool, or a provider's built-in tool.
#' @return A list with `name`, `source`, `annotations` (as declared),
#'   `missing_annotations`, and `effective_annotations` (the declared values,
#'   with cautious defaults filling the gaps). `source$type` is `"function"`,
#'   `"package"` (with `package`), `"provider"`, or `"mcp"` (with `server` and
#'   `tool`). Whether a call is allowed still depends on the agent's
#'   permissions.
#' @seealso [PermissionMode], [tools_mcp], [Agent]
#' @export
#' @examples
#' tool_metadata(tool_read_file)
tool_metadata <- function(tool) {
  if (!inherits(tool, c("ellmer::ToolDef", "ellmer::ToolBuiltIn"))) {
    tool_registration_error("{.arg tool} must be an ellmer tool definition.")
  }
  tool <- attr(tool, "deputy_runtime_source_tool", exact = TRUE) %||% tool
  annotations <- tool@annotations
  validate_tool_annotations(annotations, tool@name)
  source <- attr(tool, "deputy_tool_source", exact = TRUE)
  if (is.null(source)) {
    source <- if (inherits(tool, "ellmer::ToolBuiltIn")) {
      list(type = "provider")
    } else if (isNamespace(environment(tool))) {
      list(type = "package", package = getNamespaceName(environment(tool)))
    } else {
      list(type = "function")
    }
  }
  supplied <- names(annotations)[!vapply(annotations, is.null, logical(1))]
  list(
    name = tool@name,
    source = source,
    annotations = annotations,
    missing_annotations = setdiff(names(tool_annotation_defaults), supplied),
    effective_annotations = effective_tool_annotations(annotations)
  )
}

is_mcp_tool_context <- function(context) {
  identical(context$tool_metadata$source$type, "mcp")
}

# Deputy's own tools carry this private marker. Permission policy gives native
# names (read_file, run_bash, ask_user, ...) their native treatment only for
# marked tools, never for a host, skill, package or MCP tool that shares a
# name. The marker is an attribute, so tool_metadata() and approval
# fingerprints are unchanged.
deputy_native_tool_marker <- new.env(parent = emptyenv())

mark_native_tool <- function(tool) {
  attr(tool, "deputy_native_tool") <- deputy_native_tool_marker
  tool
}

is_native_tool <- function(tool) {
  source <- attr(tool, "deputy_runtime_source_tool", exact = TRUE) %||% tool
  identical(
    attr(source, "deputy_native_tool", exact = TRUE),
    deputy_native_tool_marker
  )
}

# A runtime permission context names the executable's origin in its tool
# metadata. A direct policy query without that metadata keeps name-based
# classification, as does a provider-native tool checked at registration.
permission_trusts_native_name <- function(context) {
  !is_mcp_tool_context(context) &&
    (is.null(context$tool_metadata$source) ||
      isTRUE(context$.deputy_native_tool))
}
