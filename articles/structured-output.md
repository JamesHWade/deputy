# Structured output

Deputy uses ellmer’s types, provider schema transport, JSON extraction,
and R conversion. A structured result is the value ellmer returns,
available directly in `AgentResult$structured_output`. There is no
separate Deputy schema format.

## Extract directly

Use `chat_structured()` when the conversation already contains the
information to extract. It makes a governed structured request and
suppresses ordinary tools, as ellmer does. `chat_structured_async()`
returns a promise with the same value.

``` r

agent <- Agent$new(ellmer::chat("openai/gpt-5.6-luna"))
review_type <- ellmer::type_object(
  status = ellmer::type_enum(c("ok", "needs_review")),
  findings = ellmer::type_array(ellmer::type_string())
)
data <- agent$chat_structured("The review found no problems.", type = review_type)
agent$last_run()$usage
```

Existing JSON Schema can enter through
`ellmer::type_from_schema(text = ...)`. Schema support and conversion
remain ellmer’s contract.

``` r

status_type <- ellmer::type_from_schema(
  '{"type":"object","properties":{"status":{"type":"string"}},"required":["status"],"additionalProperties":false}'
)
```

## Complete a task, then extract

`run_sync(type = ...)`, `run_async(type = ...)`, and the semantic
`run(type = ...)` stream first complete an ordinary tool-using task,
then ask ellmer to extract from that conversation. Both phases share one
run ID, hook lifecycle, permission policy, and request/token/cost
budget. The extraction never repeats tool work. The `response` is the
task’s text; `structured_output` is the extracted value. Even a task
without tools uses these two explicit phases; use `chat_structured()`
for direct extraction in one request.

``` r

agent <- Agent$new(
  ellmer::chat("openai/gpt-5.6-luna"),
  tools = tools_file(),
  permissions = permissions_readonly(),
  usage_limits = UsageLimits(max_requests = 8)
)
result <- agent$run_sync("Review the README", type = status_type)
stopifnot(result$is_success())
result$structured_output
```

## Bounded application validation

A `validate` function receives ellmer’s converted value and returns
`TRUE`, `FALSE`, or non-empty text explaining a failed application rule.
Set `max_corrections` to a finite non-negative integer to permit more
structured requests. The default is zero. Corrections have no tools and
consume the remaining run budget. They retain failed values, available
turns, feedback, and conditions in `structured_attempt` events. These
local events can contain user data; Deputy’s tracing adapter omits that
content.

``` r

data <- agent$chat_structured(
  "Extract the review status.",
  type = status_type,
  validate = function(x) {
    if (identical(x$status, "ok")) TRUE else "status must equal ok"
  },
  max_corrections = 1L
)
```

Corrections cover failed application validation and JSON parsing
failures confirmed through ellmer’s recorded `ContentJson`. Unclassified
conversion errors and application callback errors are terminal,
preserving their original conditions. An exhausted correction policy
signals `deputy_structured_output_invalid`. An exception or `NA` from
the validator is terminal. Provider failures are not application
corrections. Incomplete responses rejected by ellmer before a turn can
be recorded are terminal; the caller must change the token/context
policy. Cancellation is cooperative: an in-flight structured request can
finish, but no correction starts after cancellation. With
`on_exceed = "stop"`, a budget stop returns a result with a stop reason
and no successful structured value; with `on_exceed = "error"`, it
signals the typed limit condition. Inspect `last_run()` for
completed-run evidence even after an error.

## Native structured streaming

`stream(type = ...)` and `stream_async(type = ...)` forward to ellmer’s
native structured streaming API. Chunks contain raw JSON text/content;
the completed upstream assistant turn stores `ContentJson`. These
methods do not add an application correction loop. Providers requiring
ellmer’s schema-tool fallback must use `chat_structured()` instead.

The former `output_format` argument and its `parsed`/`valid` wrapper
were removed before Deputy’s first CRAN release. Update callers to
ellmer types and consume `structured_output` directly.
