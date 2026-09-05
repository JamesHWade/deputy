# Context management policy -------------------------------------------------

#' Configure automatic context management
#'
#' @description
#' Defines when an [Agent] compacts its conversation and when large tool
#' results are replaced with durable references. The default policy compacts
#' before a request would exceed 32,000 estimated tokens and offloads tool
#' results larger than 64 KiB.
#'
#' @param max_tokens Estimated complete-context token threshold that triggers
#'   compaction. Use `NULL` to disable automatic compaction.
#' @param compact_to Fraction of `max_tokens` that the retained recent context
#'   should occupy after compaction.
#' @param fallback What to do when LLM summary generation fails. `"error"` fails
#'   closed; `"text"` uses a deterministic truncated-text summary. Summary
#'   generation uses an isolated clone of the active Chat and does not select
#'   from the Agent's task `fallback_chats`.
#' @param max_tool_result_bytes Serialized size above which a tool result is
#'   stored outside the model context. Use `NULL` to disable result offloading.
#' @param offload_dir Directory for durable result envelopes. Relative paths
#'   are anchored to the current working directory when the policy is created.
#'   `NULL` uses the Deputy user cache, partitioned by Agent session.
#' @return A `ContextPolicy` object.
#' @export
ContextPolicy <- function(
  max_tokens = 32000L,
  compact_to = 0.5,
  fallback = c("error", "text"),
  max_tool_result_bytes = 64 * 1024,
  offload_dir = NULL
) {
  fallback <- match.arg(fallback)
  max_tokens <- context_policy_whole_number(max_tokens, "max_tokens")
  max_tool_result_bytes <- context_policy_whole_number(
    max_tool_result_bytes,
    "max_tool_result_bytes"
  )

  if (
    !is.numeric(compact_to) ||
      length(compact_to) != 1L ||
      is.na(compact_to) ||
      compact_to <= 0 ||
      compact_to >= 1
  ) {
    cli_abort("{.arg compact_to} must be one number between 0 and 1")
  }

  if (
    !is.null(offload_dir) &&
      (!is.character(offload_dir) ||
        length(offload_dir) != 1L ||
        is.na(offload_dir) ||
        !nzchar(trimws(offload_dir)))
  ) {
    cli_abort("{.arg offload_dir} must be NULL or one non-empty path")
  }
  if (!is.null(offload_dir)) {
    offload_dir <- path.expand(offload_dir)
    if (!is_absolute_path(offload_dir)) {
      offload_dir <- file.path(getwd(), offload_dir)
    }
    offload_dir <- expand_and_normalize(offload_dir)
    if (is.na(offload_dir)) {
      cli_abort("{.arg offload_dir} could not be resolved")
    }
  }

  structure(
    list(
      max_tokens = max_tokens,
      compact_to = as.numeric(compact_to),
      fallback = fallback,
      max_tool_result_bytes = max_tool_result_bytes,
      offload_dir = offload_dir
    ),
    class = c("ContextPolicy", "list")
  )
}

context_policy_whole_number <- function(value, argument) {
  if (is.null(value)) {
    return(NULL)
  }
  if (
    !is.numeric(value) ||
      length(value) != 1L ||
      is.na(value) ||
      !is.finite(value) ||
      value < 1 ||
      value > .Machine$integer.max ||
      value != floor(value)
  ) {
    cli_abort("{.arg {argument}} must be NULL or one positive whole number")
  }
  as.integer(value)
}

context_policy_nonnegative_whole_number <- function(value, argument) {
  if (
    !is.numeric(value) ||
      length(value) != 1L ||
      is.na(value) ||
      !is.finite(value) ||
      value < 0 ||
      value > .Machine$integer.max ||
      value != floor(value)
  ) {
    cli_abort("{.arg {argument}} must be one non-negative whole number")
  }
  as.integer(value)
}

normalize_context_policy <- function(policy) {
  if (is.null(policy)) {
    return(ContextPolicy())
  }
  if (!inherits(policy, "ContextPolicy")) {
    cli_abort("{.arg context_policy} must be a ContextPolicy object")
  }
  policy
}

#' @export
print.ContextPolicy <- function(x, ...) {
  cli::cli_text("<ContextPolicy>")
  cli::cli_text("  compact at: {x$max_tokens %||% 'disabled'} tokens")
  cli::cli_text("  compact to: {format(x$compact_to * 100)}%")
  cli::cli_text("  fallback: {x$fallback}")
  cli::cli_text(
    "  offload above: {x$max_tool_result_bytes %||% 'disabled'} bytes"
  )
  invisible(x)
}

new_compaction_result <- function(
  method,
  automatic,
  turns_compacted,
  turns_kept,
  estimated_tokens,
  usage = AgentUsage(),
  summary = NULL
) {
  structure(
    list(
      method = method,
      automatic = isTRUE(automatic),
      turns_compacted = as.integer(turns_compacted),
      turns_kept = as.integer(turns_kept),
      estimated_tokens = estimated_tokens,
      usage = usage,
      summary = summary,
      compacted_at = Sys.time()
    ),
    class = c("DeputyCompaction", "list")
  )
}

#' @export
print.DeputyCompaction <- function(x, ...) {
  cli::cli_text("<DeputyCompaction>")
  cli::cli_text("  method: {x$method}")
  cli::cli_text("  automatic: {x$automatic}")
  cli::cli_text("  compacted: {x$turns_compacted} turns")
  cli::cli_text("  kept: {x$turns_kept} turns")
  invisible(x)
}
