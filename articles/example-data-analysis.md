# Example: Autonomous Data Analysis Agent

This example builds an autonomous agent that performs exploratory data
analysis on a dataset. The agent decides what to investigate, writes and
runs R code, and iterates until it has a thorough understanding of the
data.

This follows the **Autonomous Agent** pattern: a single agent with
tools, given a goal and left to iterate through analysis steps on its
own.

## When to Use an Autonomous Agent

An autonomous agent works well when:

- The task is open-ended (you don’t know the exact steps in advance)
- The agent needs to react to intermediate results (e.g., spotting
  outliers and then investigating them)
- You want the LLM to drive the analysis methodology

For tasks with a fixed sequence of steps, consider prompt chaining
instead (see
[`vignette("example-extraction-pipeline")`](https://jameshwade.github.io/deputy/articles/example-extraction-pipeline.md)).

## Setup

We create an agent with data and code tools, plus the built-in
`data_analysis` skill:

``` r
library(deputy)

chat <- ellmer::chat_anthropic(model = "claude-sonnet-4-20250514")

agent <- Agent$new(
  chat = chat,
  tools = c(tools_data(), tools_code()),
  system_prompt = "You are a data scientist. When exploring a dataset:
    1. Start with structure and summary statistics
    2. Check for missing values and data quality issues
    3. Examine distributions of key variables
    4. Look for interesting relationships and correlations
    5. Summarise your findings clearly

    Use R code for all analysis. Show your reasoning at each step."
)

# Load the built-in data analysis skill for extra tools
skill_path <- system.file("skills/data_analysis", package = "deputy")
agent$load_skill(skill_path)
```

The `data_analysis` skill adds specialised tools like `eda_summary` and
`describe_column` that complement the general-purpose `run_r_code` tool.

## Running the Analysis

With `run_sync()`, the agent works through the analysis autonomously. It
calls tools, inspects results, and decides what to do next:

``` r
result <- agent$run_sync(
  "Explore the airquality dataset that comes with R. Give me a
   thorough understanding of the data including quality issues,
   distributions, and interesting patterns.",
  max_turns = 15
)

cat(result$response)
```

The agent typically:

1.  Loads the data and examines its structure
2.  Checks for missing values (airquality has `NA`s in `Ozone` and
    `Solar.R`)
3.  Computes summary statistics for each variable
4.  Looks at correlations between `Ozone`, `Solar.R`, `Wind`, and `Temp`
5.  Investigates seasonal patterns across `Month`
6.  Summarises findings

## Streaming Output

For interactive use, `run()` streams events as they happen. You see text
arrive token by token and tools fire in real time:

``` r
chat <- ellmer::chat_anthropic(model = "claude-sonnet-4-20250514")

agent <- Agent$new(
  chat = chat,
  tools = c(tools_data(), tools_code()),
  system_prompt = "You are a data scientist. Be thorough but concise."
)

for (event in agent$run("Summarise the mtcars dataset")) {
  switch(event$type,
    "text" = cat(event$text),
    "tool_start" = cli::cli_alert_info("Calling {event$tool_name}..."),
    "tool_end" = cli::cli_alert_success("{event$tool_name} done"),
    "stop" = cli::cli_alert("Finished in {event$total_turns} turns")
  )
}
```

## Inspecting Results

`AgentResult` captures everything about the run:

``` r
# Did it succeed?
result$is_success()
result$stop_reason

# How many turns did the agent take?
result$n_turns()

# What tools were called?
tool_calls <- result$tool_calls()
length(tool_calls)

# How long and how much?
result$duration
result$cost
```

## Adding Guardrails

For production use, add permissions and hooks to monitor and constrain
the agent:

``` r
chat <- ellmer::chat_anthropic(model = "claude-sonnet-4-20250514")

agent <- Agent$new(
  chat = chat,
  tools = c(tools_data(), tools_code()),
  permissions = Permissions$new(
    r_code = TRUE,
    bash = FALSE,
    file_write = FALSE,
    max_turns = 20,
    max_cost_usd = 0.50
  )
)

# Log every tool call
agent$add_hook(hook_log_tools(verbose = TRUE))

# Block dangerous bash commands (if bash were enabled)
agent$add_hook(hook_block_dangerous_bash())

result <- agent$run_sync(
  "Analyse the airquality dataset and report key findings."
)
```

The agent can read data and run R code, but cannot write files, run bash
commands, or exceed the cost limit.

## Next Steps

- [`vignette("tools")`](https://jameshwade.github.io/deputy/articles/tools.md)
  – Tool bundles and custom tools
- [`vignette("agent-configuration")`](https://jameshwade.github.io/deputy/articles/agent-configuration.md)
  – Skills, system prompts, and sessions
- [`vignette("example-extraction-pipeline")`](https://jameshwade.github.io/deputy/articles/example-extraction-pipeline.md)
  – Prompt chaining for structured extraction
