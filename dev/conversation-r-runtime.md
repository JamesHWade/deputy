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

The worker starts from an allow-listed environment rather than the host's
(#224): system variables that locate programs, libraries, locales and
temporary files, plus the names the host passes as `RSession$new(env = )`
(proxy names match in either case). Every other host variable is unset for
the child, and its user environ file is the null device, so it doesn't
reread `~/.Renviron` or a project `.Renviron`, and no child can leave
settings there for the next. `env = "inherit"` restores the inherited
environment. `tools_code(env = )`, `tools_preset(env = )`, `tools_all(env = )`
and the CLI's `--code-env` do the same for the one-shot `run_r_code` and
`run_bash` tools.

This is hygiene, not isolation. The child runs as the host's user, so it can
read the host's starting environment from `/proc/<pid>/environ` (unsetting a
variable in the host does not clear it there) and any file the account can
read, `.Renviron` included. callr copies the site `Renviron.site` into the
child, and the one-shot tools keep callr's default of running a project
`.Rprofile`. For the one-shot tools callr applies the child's environment to
the host process for the length of the call, so the host's own variables are
unset until the call returns. Keeping credentials from model-written code
needs a separate account or the sandboxed MCP workers, which still start with
the host's environment.

## Compose selected tools from R

A host can select tools that R code may request through Deputy:

```r
fetch_measurements <- ellmer::tool(
  function(project) {
    if (!identical(project, "pilot")) stop("Unknown project")
    data.frame(temperature = c(10, 20, 30), yield = c(2, 4, 6))
  },
  name = "fetch_measurements",
  description = "Fetch measurements for a project.",
  arguments = list(project = ellmer::type_string("Project name.")),
  convert = FALSE,
  annotations = ellmer::tool_annotations(
    read_only_hint = TRUE, destructive_hint = FALSE, open_world_hint = FALSE
  )
)
agent$register_tool(fetch_measurements)
r_session <- deputy::RSession$new(agent, tools = "fetch_measurements")
agent$register_tools(r_session$tools(), replace = TRUE)
```

During governed `run_r_code` execution, generated R can then use:

```r
measurements <- tools$fetch_measurements(project = "pilot")
fit <- lm(yield ~ temperature, data = measurements)
# A later run_r_code call can use the same objects:
summary(fit)
```

The host retains the executable tool and permission policy. The worker gets a
data bridge and callable stubs, without serialized host closures. Its existing
trusted account and environment access still applies. Selection limits the available
names; it does not grant permission. Every nested invocation passes through
Agent governance, counts toward tool limits, and records its own call ID with
`parent_tool_call_id` identifying the enclosing `run_r_code` call. The tool's
ordinary R data result is available for subsequent computation.

Selected tools must use `convert = FALSE` and validate their inputs. The bridge
passes raw JSON-compatible arguments; it does not use ellmer's private argument
converter. Recursive execution and delegation tools are unsupported. Direct
host `$run()` cannot invoke selected tools outside a governed execution.
Sessions with selected tools cannot be created when the Agent has `approval_dir`
configured. A permission callback that requests pending approval also fails
before the nested effect: the R stack cannot be suspended and restored. Use a
separate direct tool call for that approval.

The bridge supports asynchronous tools, but arbitrary synchronous host tools
can still block the host. A nested tool must return within the remaining
execution `timeout`; otherwise the execution times out, the session resets and
its variables are lost, and the nested call is recorded as a tool error under
its own call ID. R receives the tool's original value: a `PostToolUse` hook's
`updated_tool_output` changes the event and transcript, not the R result.
Cancellation discards the worker channel and prevents
a late response from reaching another execution; it cannot undo a service
effect already performed. This is still trusted local execution, not sandbox
enforcement or automatic recovery. See ADR-0028 and issues #187 and #188 for
those follow-ups.

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

Agent session snapshots retain the current model turns (including their code,
output, displays and plots) and offload artifacts. Compaction can remove earlier
turns. Hosts must persist full display/execution records separately when they
need a complete visible conversation history across compaction.
`RSession$checkpoint()` can capture selected ordinary data after a completed
call when the host configures a private checkpoint directory. The supervisor
publishes a versioned artifact after the worker exports the data. Import
requires the same host owner, Agent and conversation IDs. The host checks
integrity and identity before starting the fresh worker, where binding
validation precedes assignment. The restore receipt lists the imported
bindings and generation. Unselected state must be recreated.

Conversation history, data checkpoints and job or approval evidence have
independent lifecycles. Checkpoint import evaluates no recorded code and issues
no historical tool requests. The host keeps the receipt ID, manages retention,
and reviews indeterminate effects through the existing job or approval record.
#188 tracks the remaining sandboxed recovery work.

## Prior art and verification

The evaluate display-list approach follows the pattern in
[Commons' worker](https://github.com/posit-dev/commons/blob/c5925bacb844a1ae47d293233e2ffbed0609e4c7/pkg-r/inst/worker/worker.R),
which credits btw. Deputy owns scheduling, permissions, lifecycle and content
bounds, and has no Commons or Suppose dependency. Focused tests use real callr
workers and a local HTTP provider fixture, including native image serialization,
ordered output, follow-up variables, independent owners, timeout, interruption,
saved display and finite context allowances. They make no paid model calls.

## Interactive output artifacts

The worker adapts visible htmlwidgets and supported rich tables through the
producer's public export API. The rendered document, text summary and static
preview share the call's output budget. The supervisor publishes the document
in an opt-in host store indexed by owner, Agent, session and SHA-256. Saved
tool results retain an ordered artifact receipt with media type, renderer,
dependency provenance and preview outcome.

The host uses `RSession$artifact_frame(id)` after authorizing the conversation.
Reopening verifies the file and presents it in an opaque-origin iframe. Saved
turns retain the reference and static evidence. The host manages storage and
retention independently of R heap checkpoints.
