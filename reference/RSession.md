# Own a conversation's trusted R session

A host-owned R worker for iterative calculations and plots. Construct an
[Agent](https://jameshwade.github.io/deputy/reference/Agent.md) with
fixed conversation identity in `run_context`, then register `$tools()`.
Each owner has independent R variables and loaded packages. Calls queue
in order and return promises without blocking other conversations.

The worker executes with the local account's access. It provides process
isolation, not an OS security sandbox. Agent permissions gate the
registered tool; `$run()` is an explicit trusted host operation, not a
governed Agent run. With selected `tools`, code calls
`tools$<name>(...)` during a governed `run_r_code` call. Selected tools
must use `convert = FALSE` and validate raw JSON arguments. Calls pass
Agent permissions, hooks and usage limits; their events carry
`parent_tool_call_id`. Direct `$run()` is unavailable when tools are
selected. A nested tool must return within the remaining execution
`timeout`; otherwise the execution times out, the session resets and its
variables are lost, and the nested call is recorded as a tool error. R
receives the tool's original value; a `PostToolUse` hook's
`updated_tool_output` applies only to the event and transcript.
Recursive execution and nested durable approvals are unsupported.
Sessions with selected tools cannot be created when `approval_dir` is
configured. Requests are limited to 256 KiB and ordinary data results to
8 MiB serialized. The bridge never transfers host tool closures. Trusted
account and environment access still applies, and cancellation cannot
undo an external effect.

Each call starts in the Agent's immutable working directory. A
[`setwd()`](https://rdrr.io/r/base/getwd.html) in evaluated code applies
only until the next call.

`$cancel()` and timeouts terminate the worker and discard its variables
and queued calls. Later calls start fresh and report that fact. External
effects are not rolled back. `$close()` is terminal; the host must call
it when the conversation is disposed. Garbage collection also closes the
worker.

Results contain native ellmer text/images, embedded display HTML, and a
plain `extra$deputy_r` execution record. Store conversation turns to
keep code, output and plots reviewable after reopening. Agent snapshots
retain current model turns; hosts must store full display history
separately across compaction. Worker variables are live state, are not
included in Agent session files, and must be recreated after restart.
Static base, ggplot2, grid and patchwork figures are supported. Visible
htmlwidgets and rich HTML tables report `unsupported_output`; they are
not persisted as interactive artifacts. Print underlying data for a text
table. Owners and executable tools cannot be cloned or transferred
between Agents.

## Methods

### Public methods

- [`RSession$new()`](#method-RSession-initialize)

- [`RSession$tools()`](#method-RSession-tools)

- [`RSession$run()`](#method-RSession-run)

- [`RSession$status()`](#method-RSession-status)

- [`RSession$cancel()`](#method-RSession-cancel)

- [`RSession$close()`](#method-RSession-close)

------------------------------------------------------------------------

### `RSession$new()`

Create a lazy R worker owner. No code is executed here.

#### Usage

    RSession$new(
      agent,
      timeout = 30,
      startup_timeout = 60,
      queue_limit = 16L,
      max_output_bytes = 8 * 1024 * 1024,
      plot_width = 1000L,
      plot_height = 650L,
      tools = character()
    )

#### Arguments

- `agent`:

  Agent owning the session and its conversation identity.

- `timeout`:

  Maximum seconds for each dispatched execution.

- `startup_timeout`:

  Maximum seconds for worker startup.

- `queue_limit`:

  Maximum waiting calls, excluding the active call.

- `max_output_bytes`:

  Maximum retained output bytes per execution. This bounds captured
  evidence, not arbitrary R allocations or effects.

- `plot_width, plot_height`:

  PNG plot dimensions in pixels.

- `tools`:

  Character vector of explicitly selected Agent tool names that
  generated R may call through `tools$<name>(...)`. The default keeps
  the worker's existing behavior and exposes no Agent tools.

------------------------------------------------------------------------

### `RSession$tools()`

Return the governed `run_r_code` tool for this owner.

#### Usage

    RSession$tools()

#### Returns

A list containing one ellmer tool definition.

------------------------------------------------------------------------

### `RSession$run()`

Enqueue a trusted host execution. Invalid inputs fail before admission.

#### Usage

    RSession$run(code)

#### Arguments

- `code`:

  One non-empty string of R code, at most 256 KiB.

#### Returns

A promise resolving to an
[`ellmer::ContentToolResult`](https://ellmer.tidyverse.org/reference/Content.html).
R errors, worker failures and cancelled queued calls are retained as
result evidence.

------------------------------------------------------------------------

### `RSession$status()`

Inspect local worker state without executing R code.

#### Usage

    RSession$status()

#### Returns

A plain list with state, generation, queue size and worker PID.

------------------------------------------------------------------------

### `RSession$cancel()`

Cancel active and queued work and discard live R state.

#### Usage

    RSession$cancel()

#### Returns

Invisible `NULL`.

------------------------------------------------------------------------

### `RSession$close()`

Close the owner permanently and release its worker.

#### Usage

    RSession$close()
