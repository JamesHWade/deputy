#' Inspect a tool's origin and annotation coverage
#'
#' Returns metadata for the executable source of an ellmer tool, including
#' tools wrapped by an Agent or copied into a delegated Agent. This does not
#' call the tool, connect a server, or authorize execution.
#'
#' @param tool An ellmer function tool or supported provider-native tool.
#' @return A list with `name`, `source`, supplied `annotations`,
#'   `missing_annotations`, and `effective_annotations`. Source types are
#'   `"function"`, `"package"` (with package name), `"provider"`, or `"mcp"`
#'   (with exact server and tool names). Unknown origins are not guessed from
#'   tool names. Effective annotations describe the conservative defaults;
#'   permission modes, capabilities, lists, and callbacks still decide access.
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
