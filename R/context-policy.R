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
#'   Compaction applies this limit to the public evidence in explicit
#'   `ellmer::ContentToolResult` payloads too, retaining a preview and recoverable
#'   reference. Content objects and error conditions use their public text.
#'   A conservative rendered-size bound also covers compact sequences and shared
#'   strings before JSON expansion. Generated summaries retain up to eight direct
#'   recovery references; larger sets use one durable, chunk-readable catalog.
#'   Catalogs preserve earlier entries across compactions and session restores,
#'   including existing references when new result offloading is disabled.
#'   Superseded internal catalogs are reclaimed after replacement, except those
#'   referenced by retained turns or the installed prompt of a live Agent or clone.
#'   Earlier saved sessions keep their own catalog snapshots. Original result
#'   artifacts are retained. New evidence artifacts from aborted compactions
#'   are removed unless another compaction or tool caller has claimed them.
#' @param offload_dir Directory for durable result envelopes. Relative paths
#'   are anchored to the current working directory when the policy is created.
#'   `NULL` uses the Deputy user cache, partitioned by Agent session.
#' @param summary_fallback_chats Ordered, explicitly configured ellmer Chats
#'   authorized to receive summary prompts during automatic compaction. Each
#'   template must have no turns or tools. Transient transport failures may
#'   advance to the next template after ellmer's retries. These destinations
#'   are separate from the Agent's task `fallback_chats`; choosing a summary
#'   destination does not change the task Chat. Manual `$compact()` uses only
#'   its active Chat and `fallback` policy. Templates are cloned at construction.
#' @details
#' Automatic compaction is an asynchronous run phase. `SessionStart` and
#' `UserPromptSubmit` precede `PreCompact`; `PostCompact` follows an accepted
#' replacement. `Stop` and `SessionEnd` include summary failures and usage.
#' Between tool rounds, context is checked at ellmer's next request boundary
#' after all tool results settle. Summary dispatches, including failures, share
#' the run's request/token/cost budget. Unknown costs remain unknown.
#'
#' Summary Chats have no tools, history, system prompt, or inherited callbacks.
#' Cancellation or unrecoverable failure leaves the active context unchanged.
#' An accepted summary remains installed when the budget prevents task dispatch.
#' `$last_compaction()` includes `run_id` and summary `attempts` with destination,
#' usage, and original condition. Summaries are internal context, not task output.
#' This policy does not archive removed turns or restore runtime permissions
#' from a summary.
#' @return A `ContextPolicy` object.
#' @export
ContextPolicy <- function(
  max_tokens = 32000L,
  compact_to = 0.5,
  fallback = c("error", "text"),
  max_tool_result_bytes = 64 * 1024,
  offload_dir = NULL,
  summary_fallback_chats = list()
) {
  fallback <- match.arg(fallback)
  summary_fallback_chats <- normalize_fallback_chats(
    summary_fallback_chats,
    primary = NULL,
    argument = "summary_fallback_chats"
  )
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
      offload_dir = offload_dir,
      summary_fallback_chats = summary_fallback_chats
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
  do.call(ContextPolicy, unclass(policy))
}

#' @export
print.ContextPolicy <- function(x, ...) {
  cli::cli_text("<ContextPolicy>")
  cli::cli_text("  compact at: {x$max_tokens %||% 'disabled'} tokens")
  cli::cli_text("  compact to: {format(x$compact_to * 100)}%")
  cli::cli_text("  fallback: {x$fallback}")
  cli::cli_text("  summary fallback Chats: {length(x$summary_fallback_chats)}")
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
  summary = NULL,
  attempts = list(),
  run_id = NULL
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
      attempts = attempts,
      run_id = run_id,
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
