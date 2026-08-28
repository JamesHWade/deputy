# Getting Started with Deputy

Deputy turns an ellmer chat into a governed R Agent. In this guide you
will create a bounded, read-only Agent; inspect its result; then
deliberately grant one workspace-scoped write capability and protect it
with a checkpoint.

## Before you begin

Before Deputy’s first CRAN release, install the development version from
GitHub:

``` r

# install.packages("pak")
pak::pak("JamesHWade/deputy")
```

After the release is available from CRAN, install the released package
with:

``` r

install.packages("deputy")
```

You also need credentials for one [ellmer
provider](https://ellmer.tidyverse.org/reference/index.html). The
examples use OpenAI, but the Deputy API is provider-independent.

## 1. Define the workspace and limits

Make the authority for the first run visible before creating a chat. The
`minimal` preset contains only `read_file`, `read_markdown`, and
`list_files`. The permission policy denies writes, code execution, shell
commands, web requests, and package installation. The run also has
finite request and tool-call budgets.

``` r

library(deputy)

workspace <- normalizePath(getwd(), winslash = "/")
first_tools <- tools_preset("minimal")
first_permissions <- permissions_readonly()
first_limits <- UsageLimits(max_requests = 6, max_tool_calls = 8)

stopifnot(
  dir.exists(workspace),
  length(first_tools) == 3L,
  identical(first_permissions$mode, "readonly"),
  identical(first_limits$max_tool_calls, 8L)
)
```

Run this from the package you want to inspect, or replace
[`getwd()`](https://rdrr.io/r/base/getwd.html) with that package’s
absolute path.

`working_dir` gives relative paths a stable base. It does not create a
read sandbox: a read permission can reach files that the R process can
reach. Keep the task narrow and run Deputy with operating-system
isolation when the input or generated code is untrusted.

## 2. Create the Agent

An `Agent` combines an ellmer chat with the runtime policy you just
defined. This chunk makes a provider request, so it is displayed but not
run while the vignette is built.

``` r

chat <- ellmer::chat("openai")

agent <- Agent$new(
  chat = chat,
  tools = first_tools,
  permissions = first_permissions,
  usage_limits = first_limits,
  working_dir = workspace,
  agent_name = "package-scout"
)
```

The chat owns provider interaction. Deputy owns the tool loop around it:
permissions, hooks, limits, events, persistence, checkpoints, and
delegation.

## 3. Run one useful task

Ask for an answer that the available tools can support. A read-only
package inspection is a better first task than an open-ended request to
“improve the code.”

``` r

result <- agent$run_sync(
  paste(
    "Read DESCRIPTION and list the R/ directory.",
    "Explain the package purpose and identify three good entry-point files.",
    "Cite the paths you used. Do not propose or make edits."
  )
)
```

`run_sync()` blocks until the run stops and returns an `AgentResult`.
The result keeps the outcome and the evidence needed to understand how
it happened:

``` r

cat(result$response)

result$stop_reason
result$usage
result$session_id
result$run_id
result$tool_calls()
result$tool_results()
```

Check `stop_reason` before treating the response as complete. A request,
tool-call, token, or cost limit produces a typed stop reason rather than
a silently truncated success.

## 4. Grant writes deliberately

When a task really needs to create a file, replace the read-only policy
with an explicit one. This policy permits Deputy’s native file tools to
write only inside the canonical workspace. R execution, shell access,
web access, and package installation remain off.

``` r

write_permissions <- Permissions$new(
  mode = "standard",
  file_read = TRUE,
  file_write = workspace,
  bash = FALSE,
  r_code = FALSE,
  web = FALSE,
  install_packages = FALSE
)

stopifnot(
  identical(write_permissions$file_write, workspace),
  identical(write_permissions$r_code, FALSE),
  identical(write_permissions$bash, FALSE)
)
```

Create a separate Agent with file checkpointing enabled. The checkpoint
marks the state before the task. Deputy records preimages when its
native write, edit, and multi-edit tools change files.

``` r

write_agent <- Agent$new(
  chat = chat$clone()$set_turns(list()),
  tools = tools_file(),
  permissions = write_permissions,
  usage_limits = first_limits,
  enable_file_checkpointing = TRUE,
  working_dir = workspace,
  agent_name = "summary-writer"
)

checkpoint_id <- write_agent$checkpoint("before package summary")

write_result <- write_agent$run_sync(
  paste(
    "Read DESCRIPTION and write a concise package summary to deputy-summary.md.",
    "Do not modify any other file."
  )
)
```

Review the result and the actual diff. If the native file-tool changes
are not useful, rewind them:

``` r

write_result$stop_reason
write_agent$list_checkpoints()
write_agent$rewind_files(checkpoint_id)
```

Checkpoints do not capture changes made outside Deputy’s native file
tools, and they do not replace Git or backups.

## Common failures

### The provider cannot authenticate

Configure the credential expected by your chosen ellmer provider, then
verify a plain ellmer chat before adding Deputy. Deputy does not manage
provider keys.

### A tool call is denied

Treat the denial as useful policy feedback. Check that the tool belongs
in this task, that it is registered, and that the relevant capability is
explicit. Do not switch to
[`permissions_full()`](https://jameshwade.github.io/deputy/reference/permissions_full.md)
merely to make the error disappear.

### The run stops at a limit

Inspect `result$stop_reason` and `result$usage`. Tighten the task first;
increase only the specific limit whose additional work is justified.

### Code execution sounds safer than it is

`run_r_code` starts a separate R process, but process separation is not
an OS sandbox. `run_bash` runs with the current user’s privileges. Use
containers, virtual machines, or another real isolation boundary for
untrusted code.

### A Shiny task reads the wrong directory

Shiny process working directories can differ from the app directory.
Pass an existing absolute `working_dir` and construct any
directory-valued write grant from that same path.

## Where next?

| If you want to… | Continue with… |
|----|----|
| Choose or build tools | [`vignette("tools", package = "deputy")`](https://jameshwade.github.io/deputy/articles/tools.md) |
| Design permission policy | [`vignette("permissions", package = "deputy")`](https://jameshwade.github.io/deputy/articles/permissions.md) |
| Observe and intervene in runs | [`vignette("hooks", package = "deputy")`](https://jameshwade.github.io/deputy/articles/hooks.md) |
| Stream an Agent into an app | [`vignette("example-shiny-chat", package = "deputy")`](https://jameshwade.github.io/deputy/articles/example-shiny-chat.md) |
| Delegate to specialist Agents | [`vignette("multi-agent", package = "deputy")`](https://jameshwade.github.io/deputy/articles/multi-agent.md) |
| Require typed model output | [`vignette("structured-output", package = "deputy")`](https://jameshwade.github.io/deputy/articles/structured-output.md) |
| Build a concrete workflow | [`vignette("example-data-analysis", package = "deputy")`](https://jameshwade.github.io/deputy/articles/example-data-analysis.md) |

The durable pattern is the same in every host: make the workspace,
tools, permissions, and limits explicit; run one bounded job; then
inspect the typed result before granting more authority.
