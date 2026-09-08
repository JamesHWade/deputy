#' @include value-properties.R run-usage.R
NULL

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
#'   stored outside the model context. For native content lists, this bounds
#'   aggregate non-image public properties. Structured explicit results also use
#'   a conservative bound before JSON expansion. Use `NULL` to disable this bound.
#'   Compaction applies this limit to the public evidence in explicit
#'   `ellmer::ContentToolResult` payloads too, retaining a preview and recoverable
#'   reference. Large tool-request arguments use the same bound and retain a
#'   recoverable argument record. Content objects and error conditions use their public text.
#'   A conservative rendered-size bound also covers compact sequences and shared
#'   strings before JSON expansion. Generated summaries retain up to eight direct
#'   recovery references; larger sets use one durable, chunk-readable catalog.
#'   Catalogs preserve earlier entries across compactions and session restores,
#'   including existing references when new result offloading is disabled.
#'   Superseded internal catalogs are reclaimed after replacement, except those
#'   referenced by retained turns or the installed prompt of a live Agent sharing
#'   that session directory in the current R process, including independent Agents
#'   and clones.
#'   Earlier saved sessions keep their own catalog snapshots. Original result
#'   artifacts are retained. New evidence artifacts from aborted compactions
#'   are removed unless another compaction or tool caller has claimed them.
#' @param max_tool_result_image_bytes Maximum aggregate serialized public image
#'   payload bytes retained per native tool result (2 MiB by default). Inline
#'   image bytes are encoded; remote images count their URL metadata, not remote
#'   downloads. `NULL` disables this byte bound. Excess content remains in a
#'   recoverable result artifact and the original display metadata is preserved.
#' @param max_tool_result_images Maximum images retained per native tool result
#'   (four by default). Use zero to offload all images, or `NULL` for no count
#'   bound. Image limits are independent of the non-image `max_tool_result_bytes`
#'   limit. Model token limits and automatic compaction continue to apply.
#'   Display metadata is host-facing evidence and is not sent to the model.
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
#'
#' This is a read-only S7 value. Use `$` or `S7::prop()` to read properties,
#' and construct a new policy to change configuration. `S7::props()` returns
#' a plain property list, but nested Chats retain reference semantics. The
#' constructor and an Agent's policy getter clone templates; changing a caller's
#' Chat or a returned policy's Chat does not change the Agent's destinations.
#' Summary dispatch clears tools, history, prompts, and callbacks on its clone.
#' Policies containing Chats are runtime configuration, not portable credentials
#' or session state. Session restore keeps the receiving Agent's policy.
#' @return A read-only `ContextPolicy` S7 object.
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

#' Record a conversation compaction outcome
#'
#' @description
#' [Agent]`$compact()` and `$last_compaction()` return this read-only S7 value.
#' `$` and `S7::prop()` read its properties. `S7::props()` returns a plain list
#' for explicit reporting; nested usage must also be projected for JSON.
#' Original provider conditions in `attempts` retain their identity and any
#' reference semantics. Reporting code should select safe evidence fields
#' rather than serialize arbitrary conditions or provider objects.
#'
#' @param method Outcome: `"none"`, `"cancelled"`, `"custom"`, `"hook"`,
#'   `"llm"`, or `"text"`.
#' @param automatic Whether the run triggered compaction automatically.
#' @param turns_compacted Number of turns removed from the active context.
#' @param turns_kept Number of retained turns.
#' @param estimated_tokens Estimated context size before compaction, or `NULL`
#'   when unavailable.
#' @param usage An [AgentUsage] value for summary generation, including failed
#'   attempts. Unknown provider costs remain unknown.
#' @param summary Installed summary text, or `NULL` when no replacement occurred.
#' @param attempts List of summary attempt records containing `fallback_index`,
#'   `provider`, `model`, `usage`, and the original `condition` (or `NULL`).
#' @param run_id Governed run identifier, or `NULL` for manual compaction.
#' @prop compacted_at Construction time as a `POSIXct` value. Read-only.
#' @return A read-only `DeputyCompaction` S7 object.
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
