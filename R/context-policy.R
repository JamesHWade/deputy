#' @include value-properties.R run-usage.R
NULL

# Context management policy -------------------------------------------------

#' Configure automatic context management
#'
#' @description
#' Sets when an [Agent] compacts its conversation and when large tool results
#' are moved out of the model context. By default, the agent compacts before a
#' request would exceed about 32,000 tokens and saves tool results larger than
#' 64 KiB to disk, leaving a short preview and a `deputy://tool-result/...`
#' reference in the context. The model can read the rest with the
#' `deputy_read_tool_result` tool, and you can with
#' [Agent]`$resolve_tool_result()`.
#'
#' @param max_tokens Estimated context size, in tokens, that triggers
#'   compaction. `NULL` turns automatic compaction off.
#' @param compact_to After compaction, the recent turns that are kept take up
#'   about this fraction of `max_tokens`. Must be between 0 and 1.
#' @param fallback What to do if the model can't write the summary. `"error"`
#'   (the default) stops with an error and leaves the conversation unchanged.
#'   `"text"` uses a plain summary built from the start of each turn instead.
#' @param max_tool_result_bytes Size, in bytes, above which a tool result is
#'   saved to disk and replaced in the model context by a preview and a
#'   reference. Compaction applies the same limit to tool results and tool
#'   call arguments in the turns it summarises. `NULL` turns this off.
#' @param max_tool_result_image_bytes Maximum total size of the images kept in
#'   one tool result's model context, 2 MiB by default. Inline images count
#'   their encoded size; images given by URL count only the URL. Images over
#'   the limit stay in the saved result. `NULL` removes the limit.
#' @param max_tool_result_images Maximum number of images kept in one tool
#'   result's model context, 4 by default. `0` moves all images out; `NULL`
#'   removes the limit. Image limits are separate from
#'   `max_tool_result_bytes`.
#' @param offload_dir Directory for saved tool results; each session gets its
#'   own subdirectory. A relative path is resolved against the R working
#'   directory when the policy is created. `NULL` uses Deputy's user cache
#'   directory.
#' @param summary_fallback_chats A list of ellmer Chats to try, in order, if
#'   the agent's own Chat fails to write the summary during automatic
#'   compaction with a transient error. Each must have no turns or tools.
#'   They are only used for summaries and don't change the agent's Chat;
#'   manual `$compact()` doesn't use them.
#' @details
#' Automatic compaction runs at the start of a run and between rounds of tool
#' calls. Summary requests count toward the run's [UsageLimits]. The summary is
#' appended to the system prompt and the model context keeps only the recent
#' turns; the removed turns stay available from [Agent]`$get_turns()` and in
#' saved sessions. If summarising fails or is cancelled, the conversation is
#' left as it was. [Agent]`$last_compaction()` describes the latest compaction,
#' including every summary attempt.
#'
#' The policy is read-only: read fields with `$`, and create a new policy to
#' change one (the example shows how). The Chats in `summary_fallback_chats`
#' are copied, so later changes to your Chat objects don't affect the policy.
#' Saved sessions don't include the policy; `$load_session()` keeps the
#' loading agent's policy.
#' @return A `ContextPolicy` object.
#' @examples
#' policy <- ContextPolicy(max_tokens = 16000, fallback = "text")
#' policy$max_tokens
#' settings <- S7::props(policy)
#' settings$max_tokens <- 24000L
#' do.call(ContextPolicy, settings)
#' @export
ContextPolicy <- S7::new_class(
  "ContextPolicy",
  package = "deputy",
  properties = list(
    max_tokens = readonly_property(
      "max_tokens",
      S7::new_union(NULL, S7::class_integer)
    ),
    compact_to = readonly_property("compact_to", S7::class_double),
    fallback = readonly_property("fallback", S7::class_character),
    max_tool_result_bytes = readonly_property(
      "max_tool_result_bytes",
      S7::new_union(NULL, S7::class_integer)
    ),
    max_tool_result_image_bytes = readonly_property(
      "max_tool_result_image_bytes",
      S7::new_union(NULL, S7::class_integer)
    ),
    max_tool_result_images = readonly_property(
      "max_tool_result_images",
      S7::new_union(NULL, S7::class_integer)
    ),
    offload_dir = readonly_property(
      "offload_dir",
      S7::new_union(NULL, S7::class_character)
    ),
    summary_fallback_chats = readonly_property(
      "summary_fallback_chats",
      S7::class_list
    )
  ),
  constructor = function(
    max_tokens = 32000L,
    compact_to = 0.5,
    fallback = c("error", "text"),
    max_tool_result_bytes = 64 * 1024,
    offload_dir = NULL,
    summary_fallback_chats = list(),
    max_tool_result_image_bytes = 2 * 1024 * 1024,
    max_tool_result_images = 4L
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

    max_tool_result_image_bytes <- context_policy_whole_number(
      max_tool_result_image_bytes,
      "max_tool_result_image_bytes"
    )
    if (!is.null(max_tool_result_images)) {
      max_tool_result_images <- context_policy_nonnegative_whole_number(
        max_tool_result_images,
        "max_tool_result_images"
      )
    }

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

    value <- S7::new_object(
      S7::S7_object(),
      max_tokens = max_tokens,
      compact_to = as.numeric(compact_to),
      fallback = fallback,
      max_tool_result_bytes = max_tool_result_bytes,
      offload_dir = offload_dir,
      max_tool_result_image_bytes = max_tool_result_image_bytes,
      max_tool_result_images = max_tool_result_images,
      summary_fallback_chats = summary_fallback_chats
    )
    freeze_value(value)
  }
)

local({
  S7::method(`$`, ContextPolicy) <- function(x, name) S7::prop(x, name)
})

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
  if (!S7::S7_inherits(policy, ContextPolicy)) {
    cli_abort("{.arg context_policy} must be a ContextPolicy object")
  }
  do.call(ContextPolicy, S7::props(policy))
}

S7::method(print, ContextPolicy) <- function(x, ...) {
  cli::cat_line(cli::cli_format_method({
    cli::cli_text("<ContextPolicy>")
    cli::cli_div(theme = list(div = list("margin-left" = 2)))
    cli::cli_text("compact at: {x$max_tokens %||% 'disabled'} tokens")
    cli::cli_text("compact to: {format(x$compact_to * 100)}%")
    cli::cli_text("fallback: {x$fallback}")
    cli::cli_text("summary fallback Chats: {length(x$summary_fallback_chats)}")
    cli::cli_text(
      "offload above: {x$max_tool_result_bytes %||% 'disabled'} bytes"
    )
  }))
  invisible(x)
}

#' Create a compaction result
#'
#' @description
#' Describes one compaction. [Agent]`$compact()` and `$last_compaction()`
#' return it; you rarely need to create one yourself. It is read-only; read
#' fields with `$`. `attempts` holds the original error conditions, so pick
#' out the fields you need rather than saving or logging it whole.
#'
#' @param method How the summary was made: `"llm"` (by the model), `"text"`
#'   (the plain fallback), `"custom"` (passed to `$compact()`) or `"hook"`
#'   (from a `PreCompact` hook). `"none"` means there was nothing to compact
#'   and `"cancelled"` means a hook cancelled it.
#' @param automatic Whether a run compacted automatically.
#' @param turns_compacted Number of turns removed from the model context.
#' @param turns_kept Number of turns kept.
#' @param estimated_tokens Estimated context size before compaction, or `NULL`.
#' @param usage [AgentUsage] of the summary requests, including failed ones.
#' @param summary The summary text, or `NULL` if nothing was replaced.
#' @param attempts List of summary attempts, each with `fallback_index`,
#'   `provider`, `model`, `usage` and the error `condition` (or `NULL`).
#' @param run_id ID of the run that compacted, or `NULL` for a manual
#'   compaction.
#' @prop compacted_at When the result was created, as a `POSIXct` value.
#' @return A `DeputyCompaction` object.
#' @examples
#' outcome <- DeputyCompaction("custom", FALSE, 4, 2, summary = "Earlier work")
#' outcome$turns_compacted
#' S7::props(outcome$usage)
#' @export
DeputyCompaction <- S7::new_class(
  "DeputyCompaction",
  package = "deputy",
  properties = list(
    method = readonly_property("method", S7::class_character),
    automatic = readonly_property("automatic", S7::class_logical),
    turns_compacted = readonly_property("turns_compacted", S7::class_integer),
    turns_kept = readonly_property("turns_kept", S7::class_integer),
    estimated_tokens = readonly_property(
      "estimated_tokens",
      S7::new_union(NULL, S7::class_double)
    ),
    usage = readonly_property("usage", AgentUsage),
    summary = readonly_property(
      "summary",
      S7::new_union(NULL, S7::class_character)
    ),
    attempts = readonly_property("attempts", S7::class_list),
    run_id = readonly_property(
      "run_id",
      S7::new_union(NULL, S7::class_character)
    ),
    compacted_at = readonly_property(
      "compacted_at",
      S7::new_S3_class("POSIXct")
    )
  ),
  constructor = function(
    method,
    automatic,
    turns_compacted,
    turns_kept,
    estimated_tokens = NULL,
    usage = AgentUsage(),
    summary = NULL,
    attempts = list(),
    run_id = NULL
  ) {
    method <- match.arg(
      method,
      c("none", "cancelled", "custom", "hook", "llm", "text")
    )
    automatic <- compaction_automatic(automatic)
    fields <- list(summary = summary, run_id = run_id)
    for (field in names(fields)) {
      value <- fields[[field]]
      if (
        !is.null(value) &&
          (!is.character(value) || length(value) != 1L || is.na(value))
      ) {
        cli_abort("{.arg {field}} must be NULL or one string")
      }
    }
    value <- S7::new_object(
      S7::S7_object(),
      method = method,
      automatic = automatic,
      turns_compacted = context_policy_nonnegative_whole_number(
        turns_compacted,
        "turns_compacted"
      ),
      turns_kept = context_policy_nonnegative_whole_number(
        turns_kept,
        "turns_kept"
      ),
      estimated_tokens = validate_usage_limit(
        estimated_tokens,
        "estimated_tokens",
        integer = FALSE
      ),
      usage = usage,
      summary = summary,
      attempts = attempts,
      run_id = run_id,
      compacted_at = Sys.time()
    )
    freeze_value(value)
  }
)

compaction_automatic <- function(value) {
  if (!is.logical(value) || length(value) != 1L || is.na(value)) {
    cli_abort("{.arg automatic} must be TRUE or FALSE")
  }
  value
}

local({
  S7::method(`$`, DeputyCompaction) <- function(x, name) S7::prop(x, name)
})

S7::method(print, DeputyCompaction) <- function(x, ...) {
  cli::cat_line(cli::cli_format_method({
    cli::cli_text("<DeputyCompaction>")
    cli::cli_div(theme = list(div = list("margin-left" = 2)))
    cli::cli_text("method: {x$method}")
    cli::cli_text("automatic: {x$automatic}")
    cli::cli_text("compacted: {x$turns_compacted} turns")
    cli::cli_text("kept: {x$turns_kept} turns")
  }))
  invisible(x)
}
