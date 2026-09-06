
<!-- README.md is generated from README.Rmd. Please edit that file -->

# deputy <a href="https://jameshwade.github.io/deputy/"><img src="man/figures/logo.png" align="right" height="138" alt="deputy website" /></a>

<!-- badges: start -->

[![R-CMD-check](https://github.com/JamesHWade/deputy/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/JamesHWade/deputy/actions/workflows/R-CMD-check.yaml)
[![pkgdown](https://github.com/JamesHWade/deputy/actions/workflows/pkgdown.yaml/badge.svg)](https://github.com/JamesHWade/deputy/actions/workflows/pkgdown.yaml)
[![Lifecycle:
experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![Codecov test
coverage](https://codecov.io/gh/JamesHWade/deputy/graph/badge.svg)](https://app.codecov.io/gh/JamesHWade/deputy)
<!-- badges: end -->

Deputy runs tasks with an [ellmer](https://ellmer.tidyverse.org/) chat
and R tools. Use it to review source files, analyse data, or extract
information, with permissions that control tool access and limits on
each run.

ellmer handles the model connection and tool calls. Deputy checks
permissions, tracks usage, and records why the run stopped. You can
inspect the result in R, stream it into Shiny, or save the conversation
for later.

## Installation

Install the development version from GitHub:

``` r
# install.packages("pak")
pak::pak("JamesHWade/deputy")
```

Deputy requires ellmer 0.5.0 or later. It is not yet on CRAN.

## Review an R package

Run this from an R package directory. Set `OPENAI_API_KEY` before
creating the chat, or use another [ellmer
provider](https://ellmer.tidyverse.org/reference/index.html). The
example uses the same model as Deputy’s terminal app.

``` r
library(deputy)

agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-5.6-luna"),
  tools = tools_preset("minimal"),
  permissions = permissions_readonly(),
  usage_limits = UsageLimits(max_requests = 6, max_tool_calls = 8),
  working_dir = getwd()
)

result <- agent$run_sync(
  "Read DESCRIPTION and list R/. Explain what this package does and cite the files you used."
)

result$response
result$stop_reason
```

The agent can read files and list directories. It cannot write files or
run R or shell code. `working_dir` sets the base for relative paths;
reads can still reach other files accessible to your R process.

`run_sync()` waits for the run to finish and returns an `AgentResult`. A
`stop_reason` of `"complete"` means the agent finished; a limit or error
may leave a partial response. Inspect the work behind the answer with:

``` r
result$usage
result_tool_calls(result)
result_tool_results(result)
```

The [getting-started
guide](https://jameshwade.github.io/deputy/articles/getting-started.html)
explains these settings, shows how to allow file writes, and covers
common errors.

## Work with familiar R tools

- Define a tool from an R function with `ellmer::tool()`. Deputy uses
  ellmer’s argument types and tool annotations. See
  [Tools](https://jameshwade.github.io/deputy/articles/tools.html).
- Extract lists and data frames with ellmer’s `type_object()` and
  `type_array()`. See [Structured
  output](https://jameshwade.github.io/deputy/articles/structured-output.html).
- Report tool activity with `hook_log_tools()`, or write a hook that
  uses `cli::cli_inform()`. See
  [Hooks](https://jameshwade.github.io/deputy/articles/hooks.html).
- Pass an Agent to `shinychat::chat_server()` to build a chat app. See
  [Shiny
  chat](https://jameshwade.github.io/deputy/articles/example-shiny-chat.html).

## Choose a guide

| Task | Guide |
|----|----|
| Choose which files and tools an agent can use | [Permissions](https://jameshwade.github.io/deputy/articles/permissions.html) |
| Explore a dataset with R | [Data analysis](https://jameshwade.github.io/deputy/articles/example-data-analysis.html) |
| Pass structured results between steps | [Extraction pipeline](https://jameshwade.github.io/deputy/articles/example-extraction-pipeline.html) |
| Assign parts of a task to separate agents | [Multiple agents](https://jameshwade.github.io/deputy/articles/multi-agent.html) |
| Configure fallback models, context limits, or tracing | [Runtime integration](https://jameshwade.github.io/deputy/articles/runtime-integration.html) |

## Run from a terminal

Deputy includes a command-line app built with
[Rapp](https://github.com/r-lib/Rapp). Use
[ir](https://github.com/r-lib/ir) to run it or install a launcher:

``` bash
uv tool install r-lib-ir
rx --from github::JamesHWade/deputy deputy --help
rx --from github::JamesHWade/deputy deputy --tools minimal \
  "Summarize the R files in this project"

ir tool install github::JamesHWade/deputy
deputy --tools minimal
```

The CLI defaults to OpenAI with `gpt-5.6-luna`. Use `--model` to choose
a model or `--provider` to choose a provider, such as
`--provider anthropic`.

## Status

Deputy is experimental: its API may change. Report bugs or suggest
improvements in [GitHub
Issues](https://github.com/JamesHWade/deputy/issues).

## License

MIT © James Wade
