# Get tools for a Commons 0.2.0 object

Wraps the public `$search()` and `$measure()` methods of a model-free
[`commons::commons()`](https://posit-dev.github.io/commons/r/reference/commons.html)
object (from **commons** 0.2.0 or later) as Deputy tools:
`commons_search` and `commons_measure`. Call `tools_commons()` once and
share the returned tools across a lead agent and its specialists so that
a single `commons_measure` tool object acts as the producer for
[`TrustedResults()`](https://jameshwade.github.io/deputy/reference/TrustedResults.md).

Neither SQL nor arbitrary R execution is exposed. When no approved
measure matches a search, `commons_search` reports that no approved
calculation covers the question.

## Usage

``` r
tools_commons(commons)
```

## Arguments

- commons:

  A `commons` object created by
  [`commons::commons()`](https://posit-dev.github.io/commons/r/reference/commons.html)
  (version 0.2.0 or later), without a chat client.

## Value

A named list of two ellmer tools: `commons_search` and
`commons_measure`.

## Details

You remain responsible for creating and authorizing the `commons` object
for the current viewer. Both returned tools are annotated as read-only
and closed-world (`read_only_hint = TRUE`, `destructive_hint = FALSE`,
`open_world_hint = FALSE`, `idempotent_hint = TRUE`) so they work in
read-only policies and alongside
[`TrustedResults()`](https://jameshwade.github.io/deputy/reference/TrustedResults.md)
without mutating tool metadata. Deputy does not inspect what a measure
function does internally, so pass only a `commons` object whose measures
are read-only and authorized for the viewer.

Public Commons methods return R values rather than the native
tool-result evidence that
[`commons::agent()`](https://posit-dev.github.io/commons/r/reference/agent.html)
attaches to its own tool calls (such as `commons_tag`, compiled SQL, or
bound query parameters). `commons_measure` wraps returned values in
Deputy's bounded display cards and trusted-result receipts without
fabricating query metadata or claiming native Commons card parity.
Measures that return an
[`ellmer::ContentToolResult`](https://ellmer.tidyverse.org/reference/Content.html)
keep their own value and display fields.

## See also

[`TrustedResults()`](https://jameshwade.github.io/deputy/reference/TrustedResults.md),
[`tools_data()`](https://jameshwade.github.io/deputy/reference/tools_data.md),
[`tool_metadata()`](https://jameshwade.github.io/deputy/reference/tool_metadata.md)

## Examples

``` r
if (FALSE) { # \dontrun{
cm <- commons::commons(
  data_sources = commons::data_source(sales = sales_df),
  semantic_layer = commons::semantic_layer(
    commons::measure("total_revenue", "Total revenue.", function() sum(sales_df$revenue))
  )
)
tools <- tools_commons(cm)
agent <- Agent$new(
  chat = ellmer::chat("anthropic/claude-sonnet-5-5"),
  tools = tools,
  permissions = Permissions(mode = "readonly", tool_allowlist = names(tools)),
  trusted_results = TrustedResults(measure = tools$commons_measure)
)
} # }
```
