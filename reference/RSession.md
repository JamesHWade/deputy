# Persistent R session for a conversation

An R process that keeps variables and loaded packages between calls in
one agent's conversation. Register `$tools()` on the agent to give the
model a `run_r_code` tool that uses it. Calls run in order and return
promises, so other conversations aren't blocked.

The process runs with your user account's access to files and the
network; it is not an OS sandbox. The default permissions deny the tool;
allow it with `r_code = TRUE` in
[`Permissions()`](https://jameshwade.github.io/deputy/reference/Permissions.md).
`$run()` runs code directly, without permission checks. See
[`vignette("code-execution")`](https://jameshwade.github.io/deputy/articles/code-execution.md).

The process doesn't inherit your environment variables, and R there
doesn't read `.Renviron`. It gets the variables that locate programs,
libraries, locales and temporary files, such as `PATH`, `HOME`, `LANG`
and `TMPDIR`, plus the ones you name in `env`. This keeps keys out of
what the code is given, not out of its reach: code running as your user
account can still read your R session's starting environment through the
operating system, and any file your account can read, `.Renviron`
included. To keep keys from the code, run it under an account that can't
read them, or in a sandbox.

## Working directory and resets

Each call starts in the agent's working directory;
[`setwd()`](https://rdrr.io/r/base/getwd.html) lasts until the next
call. `$cancel()` and timeouts kill the R process and discard its
variables and queued calls; the next call starts fresh and says so.
Effects outside R, such as written files, are not undone. The session
belongs to one agent and stops accepting calls if the agent's session
changes. Call `$close()` when the conversation ends.

## Results and saved conversations

Each result holds ellmer text and image content, HTML for display, and
an `extra$deputy_r` record of the call. Saved turns keep the code,
output and plots but not the variables, which must be recreated after a
restart. Agent snapshots keep only the current model context, so with
compaction, store the full display history yourself. Base, ggplot2, grid
and patchwork plots are captured; htmlwidgets and rich HTML tables
report `unsupported_output`, so print the data instead.

## Calling agent tools from R

With `tools = c("name")`, code run through the agent's `run_r_code` tool
can call `tools$name(...)`. The calls go through the agent's
permissions, hooks and usage limits, and their events carry
`parent_tool_call_id`. Selected tools must already be registered on the
agent, use `convert = FALSE` and validate their raw JSON arguments;
`run_r_code` itself can't be selected. R gets the tool's original return
value, even if a `PostToolUse` hook sets `updated_tool_output`. A call
must finish within the remaining `timeout`, or the session resets.

With selected tools, `$run()` is unavailable and the agent can't have an
`approval_dir`. Requests are limited to 256 KiB and results to 8 MiB
serialized. The tool functions run in your main R process; selecting
them doesn't limit what the R code can do.

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

Create a session. The R process starts on the first call.

#### Usage

    RSession$new(
      agent,
      timeout = 30,
      startup_timeout = 60,
      queue_limit = 16L,
      max_output_bytes = 8 * 1024 * 1024,
      plot_width = 1000L,
      plot_height = 650L,
      tools = character(),
      env = NULL,
      libpath = NULL
    )

#### Arguments

- `agent`:

  The agent that owns the session.

- `timeout`:

  Maximum seconds for each call. A call that takes longer resets the
  session.

- `startup_timeout`:

  Maximum seconds for the R process to start.

- `queue_limit`:

  Maximum number of calls waiting behind the running one.

- `max_output_bytes`:

  Maximum bytes of output kept per call. This limits captured output,
  not memory use.

- `plot_width, plot_height`:

  PNG plot size in pixels, at most 4096.

- `tools`:

  Names of tools registered on `agent` that R code may call as
  `tools$<name>(...)`. None by default.

- `env`:

  The names of other environment variables the R code may read, such as
  `c("HTTPS_PROXY", "NO_PROXY")` behind a proxy. `"inherit"` passes your
  whole environment, including every key it holds.

- `libpath`:

  The library directories the R process loads packages from, searched in
  order. `NULL` uses your session's
  [`.libPaths()`](https://rdrr.io/r/base/libPaths.html) each time a
  process starts.

------------------------------------------------------------------------

### `RSession$tools()`

Return the `run_r_code` tool for this session, to register on the agent.

#### Usage

    RSession$tools()

#### Returns

A list containing one ellmer tool.

------------------------------------------------------------------------

### `RSession$run()`

Run code directly, without the agent's permissions or hooks. Errors at
once if `code` is invalid or the queue is full.

#### Usage

    RSession$run(code)

#### Arguments

- `code`:

  One non-empty string of R code, at most 256 KiB.

#### Returns

A promise for an
[`ellmer::ContentToolResult`](https://ellmer.tidyverse.org/reference/Content.html).
R errors, crashes and cancelled calls resolve to a result that describes
them.

------------------------------------------------------------------------

### `RSession$status()`

Report the session's state without running code.

#### Usage

    RSession$status()

#### Returns

A list with `id`, `state`, `generation` (incremented each time a fresh R
process starts), `queued`, `last_reset`, `pid` and `working_dir`.

------------------------------------------------------------------------

### `RSession$cancel()`

Cancel running and queued calls and discard the session's variables.

#### Usage

    RSession$cancel()

#### Returns

Invisible `NULL`.

------------------------------------------------------------------------

### `RSession$close()`

Close the session for good and stop its R process.

#### Usage

    RSession$close()
