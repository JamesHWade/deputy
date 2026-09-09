# Runtime integration and evaluation

Deputy owns permissions, budgets, hooks, run identity, checkpoints,
context policy, and delegation. ellmer owns provider requests, schema
transport, tool execution, model parameters, and provider tracing. The
integration requires released ellmer 0.5.0 or later.

## Explicit fallback Chats

The caller chooses every destination by supplying configured
`fallback_chats`. Deputy clones these templates, preserves their
credentials, base URL, model parameters, and request callbacks, and
installs the Agent’s conversation, system prompt, governed tools, and
observers. Templates must have no history or tools. Fallback neither
discovers a provider nor silently selects a model.

``` r

agent <- Agent$new(
  ellmer::chat("openai/gpt-5.6-luna"),
  fallback_chats = list(ellmer::chat("openai/gpt-5.6-terra")),
  permissions = permissions_readonly(),
  usage_limits = UsageLimits(max_requests = 5)
)
result <- agent$run_sync("Summarize the supplied evidence.")
```

Fallback is eligible for a connection failure or HTTP 408, 429, 500,
502, 503, or 504 before any response content or requested tool. Upstream
serializers check content/tool compatibility with the selected provider;
Deputy does not drop content or rewrite provider-specific tools to make
a fallback succeed. Authentication errors, application callbacks, and
validation failures are terminal. A partially streamed response or
completed tool effect locks the run to its current Chat; Deputy
preserves the partial result and signals the failure. It never restarts
a completed tool loop. The selected Chat remains active; subsequent runs
can advance to later configured templates, without revisiting earlier
ones. Automatic compaction belongs to the active run. `SessionStart` and
`UserPromptSubmit` precede `PreCompact`, and `PostCompact` follows an
accepted summary. Summary failures still produce an inspectable
`last_run()` with terminal hooks and usage. Between tool rounds,
compaction runs at the next model-request boundary, after all tool
results settle.

If summary failure, cancellation, or a limit stops that boundary,
settled tool results remain in the conversation and survive save/load.
Resuming sends those results once, without repeating the tool or
inventing an assistant response. Host changes to the turns or system
prompt while a summary is in flight reject the stale replacement and
preserve the host’s edits.

Use a separate policy to authorize summary recovery destinations:

``` r

policy <- ContextPolicy(
  summary_fallback_chats = list(ellmer::chat("openai/gpt-5.6-luna"))
)
agent <- Agent$new(
  ellmer::chat("openai/gpt-5.6-terra"),
  context_policy = policy,
  fallback_chats = list(ellmer::chat("openai/gpt-5.6-sol"))
)
```

The primary summary uses an isolated clone of the active Chat. Only a
transient model transport failure can advance to
`summary_fallback_chats`, after ellmer’s own retries. Summary Chats have
no tools, inherited callbacks, or unrelated history. Selecting one does
not change the task provider. Internal summaries are never streamed as
task output, and a successful summary does not prevent a later task
fallback before task output or effects occur.

Every summary dispatch shares the run’s request/token/cost budget,
including failed dispatches. Unknown cost stays unknown and stops a
cost-limited run.
[`ContextPolicy()`](https://jameshwade.github.io/deputy/reference/ContextPolicy.md)
and compaction outcomes are read-only S7 values. Construct another
policy to change configuration; Agent policy getters return snapshots
with cloned summary templates. Chats inside a standalone policy remain
reference objects. `compact()` and `last_compaction()` return
`DeputyCompaction` values, whose attempt records preserve original
provider conditions.

``` r

policy <- ContextPolicy(max_tokens = 16000, fallback = "text")
settings <- S7::props(policy)
settings$max_tokens <- 24000L
revised_policy <- do.call(ContextPolicy, settings)
revised_policy$max_tokens
outcome <- DeputyCompaction("custom", FALSE, 4, 2, summary = "Earlier work")
outcome$turns_compacted
```

For JSON reports, project the outcome and its nested `AgentUsage` values
to plain lists, and select condition classes or other intended
diagnostics.
[`S7::props()`](https://rconsortium.github.io/S7/reference/props.html)
alone does not recursively convert nested values or remove sensitive
provider evidence. Session save/load retains conversation and summary
evidence; it keeps the receiving Agent’s context policy.

`ContextPolicy(fallback = "text")` permits deterministic degraded
recovery when summary generation fails and the run can still continue;
it is opt-in and emits a `Notification` with code `compact_fallback`.
Cancellation leaves the active context unchanged. A completed summary
stays installed if its usage exhausts the budget before task execution.

`agent$last_compaction()` reports the method, run ID, usage, and
destination attempts. Request and fallback events use
`phase = "compaction"` for summary work. Manual `agent$compact()` keeps
its synchronous, active-Chat-only contract. `agent$get_turns()` and
`agent$turns()` retain the complete selected conversation across
compaction. `agent$get_context_turns()` returns only the smaller model
context. The model receives that context and its installed summary;
retaining the display transcript does not send old turns back to the
provider.

The retained prefix lives in memory and grows with the selected
conversation. The host still owns durable history storage, conversation
identity, and branches. `set_turns()` selects a replacement
conversation, clears the old prefix and summary, and uses the supplied
turns as context. Automatic compaction can reduce that restored context
before the next request. A host needing retrieval can expose authorized
bounded reads separately; transcript text grants no authority.

`save_session()` uses snapshot schema 3 to preserve both views without
executable tool references. `load_session()` restores them under the
receiving Agent’s permissions. Older development snapshot schemas are
rejected; restore existing native conversation history through its host,
then create a new snapshot.

LeadAgent’s fallback policy applies to the lead. Child definitions
inherit the selected provider and do not implicitly gain additional
destinations.

`request_start`, `request_end`, `request_error`, and `fallback` events
retain model selection and original conditions with run IDs. These local
events may contain provider error details. `request_error` requires a
recognized httr2 HTTP/transport condition and evidence that the Chat
reached model dispatch. Streaming requests use ellmer’s recorded partial
turn to distinguish dispatch from request callbacks. Ambiguous failures
do not select another provider. Application callback and validation
failures retain any observed `request_end` and a separate `run_error`
with the original condition. Failed dispatches count toward
`max_requests`. Reported token totals include only observed usage;
unknown cost is `NA`, and a cost cap prevents further requests when that
cost cannot be enforced.

ellmer configures httr2 with `ellmer_max_tries` (default 3 total
attempts) and `ellmer_timeout_s` (default 300 seconds). Configure these
once at application startup if needed. Deputy does not change
process-wide options during runs or add another retry loop. HTTP retries
belong to the upstream transport: our real streaming fixture verifies
three HTTP attempts are still one governed model dispatch. The
structured async path uses httr2 1.3.0’s
[`req_perform_promise()`](https://httr2.r-lib.org/reference/req_perform_promise.html),
which explicitly does not perform retries. Our fixture confirms one HTTP
attempt for this path; callers must not assume identical retry behavior.
Deputy does not estimate hidden HTTP attempts from model-request
callbacks or promise immediate cancellation during an upstream backoff
or in-flight structured request.

## Tracing governance

Configure an `otel` provider before loading ellmer and Deputy. Existing
ellmer spans describe invocation, model calls, HTTP work, and actual
tool execution. Deputy adds a `deputy.run` parent span and governance
events, using `deputy.run.id`, `deputy.agent.id`, parent/delegation IDs,
and ellmer’s `gen_ai.conversation.id` mapped to the Deputy session ID.
Async delegated runs retain their trace parent and run correlation.

``` r

# In a fresh R session, this records locally without configuring an exporter.
record <- otelsdk::with_otel_record({
  library(deputy)
  agent <- Agent$new(ellmer::chat("openai/gpt-5.6-luna"))
  agent$run_sync("Summarize this supplied text.")
})
record$value$run_id
record$traces
```

A policy denial records a permission event and does not pretend a tool
ran. Deputy’s trace adapter exports a small allowlist of identifiers and
decisions; it omits prompts, tool inputs/results, validation feedback,
conditions, paths, and product run context. Custom stop text is
represented as `custom`. This allowlist stays in place even when
upstream content capture is enabled.

ellmer’s message capture is separately opt-in via
`OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT=true`, set before
loading ellmer. Deputy does not override it or create a second exporter.
The caller’s upstream tracer may record endpoint URLs and tool
descriptions; configure those without secrets and apply the exporter’s
own privacy policy as appropriate.

## An external evaluation runner

The runnable `10-evaluation.R` example executes a fixed two-row dataset,
applies an application-owned exact-answer rule, and reports
case/run/session IDs, completion status, requests, reported tokens,
cost, duration, and error class. `run_context$evaluation$case_id` links
local evidence to the case. The same run ID appears on the trace,
without enabling message capture.

``` r

source(system.file("examples", "standalone", "10-evaluation.R", package = "deputy"))
evaluation
```

Replace that dataset and scoring rule in your external runner. Deputy
provides `AgentResult`, usage, stop reasons, events, and correlated
traces; it does not own a dataset format, scoring framework, exporter,
or experiment database.
