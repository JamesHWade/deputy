# Configure automatic context management

Defines when an
[Agent](https://jameshwade.github.io/deputy/reference/Agent.md) compacts
its conversation and when large tool results are replaced with durable
references. The default policy compacts before a request would exceed
32,000 estimated tokens and offloads tool results larger than 64 KiB.

## Usage

``` r
ContextPolicy(
  max_tokens = 32000L,
  compact_to = 0.5,
  fallback = c("error", "text"),
  max_tool_result_bytes = 64 * 1024,
  offload_dir = NULL
)
```

## Arguments

- max_tokens:

  Estimated complete-context token threshold that triggers compaction.
  Use `NULL` to disable automatic compaction.

- compact_to:

  Fraction of `max_tokens` that the retained recent context should
  occupy after compaction.

- fallback:

  What to do when LLM summary generation fails. `"error"` fails closed;
  `"text"` uses a deterministic truncated-text summary.

- max_tool_result_bytes:

  Serialized size above which a tool result is stored outside the model
  context. Use `NULL` to disable result offloading.

- offload_dir:

  Directory for durable result envelopes. Relative paths are anchored to
  the current working directory when the policy is created. `NULL` uses
  the Deputy user cache, partitioned by Agent session.

## Value

A `ContextPolicy` object.
