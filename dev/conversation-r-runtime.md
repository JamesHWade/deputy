# Conversation R execution

`RSession` owns one trusted local R process for one Agent, saved-session identity,
working directory and fixed `run_context`. A host creates one owner per open
conversation, registers its tools, and closes it when disposing the conversation.
It must not share an owner or its tools across conversations or users.

```r
agent <- deputy::Agent$new(
  chat = ellmer::chat_openai(),
  working_dir = workspace,
  run_context = list(conversation_id = conversation_id),
  permissions = deputy::Permissions(r_code = TRUE)
)
r_session <- deputy::RSession$new(agent)
agent$register_tools(r_session$tools())
# Pass the Agent to the host's existing chat or run_shiny flow.
# On conversation disposal (for example, session$onSessionEnded):
r_session$close()
```

The tool is named `run_r_code`; replacing the one-shot preset tool requires
`replace = TRUE`. Registered calls use Agent permission and hook handling.
Direct `$run(code)` is a trusted host operation returning a promise, and does
not ask Agent permission. This is process isolation with the local account's
access, not an OS security sandbox. Hosts needing untrusted multi-user execution
must provide a suitable external isolation boundary.

## Execution and recovery

Variables, functions, options and loaded packages persist in the worker. Calls
queue serially; each starts in the Agent's immutable working directory. Other
owners run independently. Defaults are 30 seconds per dispatched execution,
60 seconds for startup, 16 waiting calls, 256 KiB of code, and 8 MiB of retained
output. These bounds do not limit arbitrary R allocations or external effects.
Base graphics, ggplot2, grid and patchwork compositions are captured as PNGs; print ggplots in loops as
usual. Console output, warnings, messages, plots and R errors preserve order.
An ordinary R error keeps preceding objects and output available.

Agent interruption, `$cancel()`, timeout or process failure kills the worker and
settles queued calls as not executed. The next call starts a new generation and
tells the model and user that previous objects are unavailable. Interrupted
partial output is unavailable; external effects cannot be rolled back.
`$close()` is terminal. Garbage collection is a fallback, not host lifecycle
management. Removing or replacing the tool does not dispose an idle owner.

## Content and saved evidence

Results use `ellmer::ContentToolResult` with ordered native text and image
content, so supported providers receive the image itself. `extra$display`
contains self-contained escaped HTML with code in Details and embedded plots;
shinychat consumes this through its public tool-result display contract.
`extra$deputy_r` is a versioned plain execution record with code, ordered text
and raw PNG segments, outcome, generation and reset provenance.

ContextPolicy bounds model-facing content independently: its ordinary text
allowance defaults to 64 KiB, with 2 MiB of serialized public image properties
and at most four images per result. Each allowance can explicitly be disabled
with NULL. Oversized content is preserved in the existing offload store, while
fitting images remain native. The bounded reader returns textual evidence;
full image recovery requires the host's `resolve_tool_result()` access to the
stored native content. Full display evidence remains available to the host.

Save Agent sessions to retain code, output, displays, plots and offload artifacts.
Live R objects and executable owners are not resumable state. On reopening,
create a new owner and recreate needed variables from recorded code. Do not
claim that a restored plot implies a restored R workspace.

## Prior art and verification

The evaluate display-list approach follows the pattern in
[Commons' worker](https://github.com/posit-dev/commons/blob/c5925bacb844a1ae47d293233e2ffbed0609e4c7/pkg-r/inst/worker/worker.R),
which credits btw. Deputy owns scheduling, permissions, lifecycle and content
bounds, and has no Commons or Suppose dependency. Focused tests use real callr
workers and a local HTTP provider fixture, including native image serialization,
ordered output, follow-up variables, independent owners, timeout, interruption,
saved display and finite context allowances. They make no paid model calls.

## Interactive output extension boundary

This first slice supports static graphics and text tables. Visible htmlwidgets
(including plotly and leaflet), HTML tags, gt and flextable values are detected
and return `unsupported_output` with an explicit diagnostic and no pretend
PNG. The value remains in worker memory if code assigned it. This does not
intercept widgets explicitly printed inside other functions or user-defined
renderers; hosts must not advertise general interactive output support.

A later rich renderer must add a portable user artifact (self-contained HTML
or a bundled dependency directory with a durable host URL) and a distinct
model representation (verified static image plus meaningful text/data). The
execution record must identify renderer, artifact media type, dependency
provenance, content digest and fallback outcome. The host owns artifact
storage, serving and browser isolation; neither temporary file URLs nor blank
PNG captures count as successful widget output. Such a renderer must obey
output bounds and preserve reviewability after session save/load before the
host advertises the capability. No arbitrary HTML renderer callback is exposed
in this slice.
