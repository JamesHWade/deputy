# Getting Started with Deputy

This guide uses Deputy to explain an R package from its source files.
You will run a task, inspect the answer and tool calls, then create an
agent that can write a summary file.

## Install and connect

Install Deputy from GitHub:

``` r

# install.packages("pak")
pak::pak("JamesHWade/deputy")
```

You need credentials for an [ellmer
provider](https://ellmer.tidyverse.org/reference/index.html). These
examples use OpenAI with `gpt-5.6-luna`. Set `OPENAI_API_KEY` in your R
environment before running them. You can edit your user `.Renviron` file
with
[`usethis::edit_r_environ()`](https://usethis.r-lib.org/reference/edit.html)
if you have usethis installed; restart R after saving it. Keep
credentials out of scripts and version control.

Use another ellmer chat constructor if you prefer a different provider.
Deputy keeps the model and parameters of the chat you supply.

## Create an agent

Open an R session in the package you want to inspect, then run:

``` r

library(deputy)

workspace <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)

agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-5.6-luna"),
  tools = tools_preset("minimal"),
  permissions = permissions_readonly(),
  usage_limits = UsageLimits(max_requests = 6, max_tool_calls = 8),
  working_dir = workspace
)
```

Each setting has one job:

- `chat` connects to the model through ellmer.
- `tools` gives the model three tools: `read_file`, `read_markdown`, and
  `list_files`.
- `permissions` allows those reads and denies writes, code execution,
  and web requests.
- `usage_limits` stops the run after at most six model requests or eight
  tool calls.
- `working_dir = workspace` sets the base for relative file paths. To
  inspect a package elsewhere, replace
  [`getwd()`](https://rdrr.io/r/base/getwd.html) in the
  `workspace <- normalizePath(...)` line with that package’s path.

The read-only policy still allows access to files outside `working_dir`
when the R process can read them. It is not a filesystem sandbox.

## Run a task

Ask for an answer that the available files can support:

``` r

result <- agent$run_sync(
  "Read DESCRIPTION and list R/. Explain what this package does and cite the files you used."
)

result$response
```

`run_sync()` waits until the run stops, then returns an `AgentResult`.
The answer depends on the package and model. Check whether it finished
before using the response:

``` r

result$stop_reason
result$usage
```

`"complete"` means the task finished. Other reasons include
`"request_limit"` and `"tool_call_limit"`. A stopped run can still have
a partial response. `result$usage` reports requests, tokens, and any
cost reported by the provider.

Inspect the tool calls to see which files the agent used:

``` r

result$tool_calls()
result$tool_results()
```

The [AgentResult
reference](https://jameshwade.github.io/deputy/reference/AgentResult.md)
describes the other fields, including events and run identifiers.

## Show progress in the console

Add a logging hook before the next run to see tool activity as it
happens:

``` r

agent$add_hook(hook_log_tools())
result <- agent$run_sync("Read DESCRIPTION and name the package's imported dependencies.")
result$response
```

[`hook_log_tools()`](https://jameshwade.github.io/deputy/reference/hook_log_tools.md)
uses cli for console output. See
[Hooks](https://jameshwade.github.io/deputy/articles/hooks.md) to write
a callback or change what gets reported.

## Write a summary file

Writing needs a different permission policy. Create a new agent:
permissions on an existing agent can be narrowed, but cannot be expanded
beyond those set at construction.

This policy permits native file writes inside `workspace`. R execution,
shell commands, web requests, and package installation remain disabled
by default.

``` r

write_agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-5.6-luna"),
  tools = tools_file(),
  permissions = Permissions$new(file_write = workspace),
  usage_limits = UsageLimits(max_requests = 6, max_tool_calls = 8),
  enable_file_checkpointing = TRUE,
  working_dir = workspace
)

checkpoint_id <- write_agent$checkpoint("before package summary")

write_result <- write_agent$run_sync(
  "Read DESCRIPTION and write a short package summary to deputy-summary.md. Leave other files unchanged."
)

write_result$stop_reason
write_result$tool_calls()
```

Open `deputy-summary.md` and review the changes in Git. Deputy saved the
previous contents of files changed by its native write tools after the
checkpoint. If you want to undo those changes, run:

``` r

write_agent$rewind_files(checkpoint_id)
```

Checkpoints cover Deputy’s native write, edit, and multi-edit tools.
They do not capture changes made by R code, shell commands, or other
programs. See
[Permissions](https://jameshwade.github.io/deputy/articles/permissions.md)
for the limits of file policies and code execution.

## Troubleshooting

### The provider cannot authenticate

Check the credential expected by your ellmer provider. Try a plain
ellmer chat to confirm the connection before adding tools or Deputy
settings.

### A tool call is denied

Check that the tool is registered and that its required permission is
enabled. For custom tools, check their annotations and any allowlist as
well. The [Tools
guide](https://jameshwade.github.io/deputy/articles/tools.md) includes a
complete custom-tool example.

### The run stops before finishing

Inspect `result$stop_reason` and `result$usage`. Try a smaller task, or
raise the limit that was reached. `"tool_loop"` means an identical tool
call returned the same result three times in a row. `"cost_unavailable"`
means a cost limit was set, but the provider did not report enough cost
information to enforce it. See
[`UsageLimits()`](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
for all stop reasons.

## Next steps

- [Tools](https://jameshwade.github.io/deputy/articles/tools.md): select
  a preset or register an R function.
- [Structured
  output](https://jameshwade.github.io/deputy/articles/structured-output.md):
  extract data with ellmer types.
- [Shiny
  chat](https://jameshwade.github.io/deputy/articles/example-shiny-chat.md):
  use the agent in an app.
- [Multiple
  agents](https://jameshwade.github.io/deputy/articles/multi-agent.md):
  give separate tasks to other agents.
