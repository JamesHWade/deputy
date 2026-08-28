# deputy

Deputy turns an [ellmer](https://ellmer.tidyverse.org/) chat into a
governed R Agent. Give it tools, a workspace, and explicit limits; get
back an observable run you can inspect, stream into Shiny, save, or
delegate.

## Why Deputy?

ellmer gives R a provider-independent chat interface and tools. Deputy
adds the runtime around that chat when a tool-using conversation becomes
a real job:

| Start with ellmer       | Add Deputy when you need                          |
|-------------------------|---------------------------------------------------|
| Chats and provider APIs | Explicit tool permissions and run limits          |
| Tool registration       | Hooks, semantic events, and inspectable results   |
| Streaming model output  | A stable stream for terminals and Shiny hosts     |
| Conversation state      | Explicit session persistence and file checkpoints |
| One tool-using chat     | Correlated delegation to specialist Agents        |

The core object model stays small:

``` text
ellmer Chat + Tools + Permissions + Limits
                     |
                  Deputy Agent
                     |
        AgentResult + Events + Checkpoints
```

## Installation

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

For the optional Shiny host, also install shinychat:

``` r

install.packages("shinychat")
```

## A safe first run

Start with a small, read-only toolset and a bounded run. This setup is
provider-independent and is executed whenever the README is rendered:

``` r

library(deputy)

workspace <- normalizePath(getwd(), winslash = "/")
first_tools <- tools_preset("minimal")
first_permissions <- permissions_readonly()
first_limits <- UsageLimits(max_requests = 6, max_tool_calls = 8)

stopifnot(
  length(first_tools) == 3L,
  identical(first_permissions$mode, "readonly"),
  identical(first_limits$max_requests, 6L)
)
```

Then choose any provider supported by ellmer and run a task. The model
call is not executed while building the documentation:

``` r

chat <- ellmer::chat("openai")

agent <- Agent$new(
  chat = chat,
  tools = first_tools,
  permissions = first_permissions,
  usage_limits = first_limits,
  working_dir = workspace
)

result <- agent$run_sync(
  "Explain what this R package does. Support the answer with file paths."
)
```

`run_sync()` returns an `AgentResult`, not just text:

``` r

cat(result$response)
result$stop_reason
result$usage
result$tool_calls()
result$tool_results()
```

Read [Getting
Started](https://jameshwade.github.io/deputy/articles/getting-started.html)
to turn on a workspace-scoped write permission deliberately, create a
file checkpoint, and recover from common failures.

## The safety boundary

Deputy enforces application-level policy at tool boundaries. It does not
turn model-generated code into untrusted code you can execute safely:

- [`permissions_readonly()`](https://jameshwade.github.io/deputy/reference/permissions_readonly.md)
  denies Deputy’s write, shell, R execution, web, and package-install
  capabilities.
- A directory-valued `file_write` permission confines Deputy’s native
  file writes to that canonical root. File reads remain limited by the R
  process, not by an operating-system sandbox.
- `run_r_code` uses a separate R process; that process separation is not
  an OS security sandbox. `run_bash` executes with the current user’s
  privileges.
- File checkpoints cover Deputy’s native write, edit, and multi-edit
  tools. They are recovery machinery, not a substitute for version
  control or backups.

Start read-only, grant the narrowest capability that completes the job,
and use a real isolation boundary for untrusted code.

## Choose your path

| Goal | Read next |
|----|----|
| Understand tools and presets | [Tools](https://jameshwade.github.io/deputy/articles/tools.html) |
| Design a least-authority policy | [Permissions and Safety](https://jameshwade.github.io/deputy/articles/permissions.html) |
| Observe or intervene in a run | [Hooks](https://jameshwade.github.io/deputy/articles/hooks.html) |
| Embed an Agent in an app | [Shiny Chat](https://jameshwade.github.io/deputy/articles/example-shiny-chat.html) |
| Delegate to specialist Agents | [Multi-Agent Orchestration](https://jameshwade.github.io/deputy/articles/multi-agent.html) |
| Build a concrete workflow | [Recipes](https://jameshwade.github.io/deputy/articles/example-data-analysis.html) |

## Terminal use

Deputy also ships a [Rapp](https://github.com/r-lib/Rapp) package
executable. Run it without a global Deputy installation, or install a
persistent launcher:

``` bash
uv tool install r-lib-ir
rx --from github::JamesHWade/deputy deputy --help
rx --from github::JamesHWade/deputy deputy \
  --provider openai "Summarize the R files in this project"

ir tool install github::JamesHWade/deputy
deputy --provider openai --tools minimal
```

## Status

Deputy is experimental. Its contracts are being sharpened through real
package, CLI, and Shiny integrations. Please report problems and design
gaps in [GitHub Issues](https://github.com/JamesHWade/deputy/issues).

## License

MIT © James Wade
