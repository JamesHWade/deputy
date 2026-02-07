# Example: Multi-Agent Code Review

This example builds a code review system using multiple specialised
agents coordinated by a lead agent. Each reviewer focuses on a different
aspect of code quality, and the lead synthesises their findings into a
structured report.

This follows the **Orchestrator-Workers** pattern: a lead agent
delegates to specialised sub-agents, each with their own expertise and
tools.

## When to Use Multi-Agent

Multi-agent orchestration works well when:

- Different aspects of a task need different expertise
- Sub-tasks benefit from isolated system prompts
- You want per-agent audit trails and cost tracking
- A single “do everything” prompt would be too broad

For simpler tasks, a single agent is usually enough. For sequential
pipelines, see
[`vignette("example-extraction-pipeline")`](https://jameshwade.github.io/deputy/articles/example-extraction-pipeline.md).

## Define the Reviewer Agents

Each reviewer agent focuses on one dimension of code quality. They all
use
[`tools_file()`](https://jameshwade.github.io/deputy/reference/tools_file.md)
for read-only file access:

``` r
library(deputy)

bug_hunter <- agent_definition(
  name = "bug_hunter",
  description = "Finds logic errors, edge cases, off-by-one errors,
    and potential runtime failures in R code",
  prompt = "You are a bug-hunting specialist for R code. Focus on:
    - Logic errors and incorrect conditions
    - Edge cases (NULL, NA, empty inputs, zero-length vectors)
    - Off-by-one errors in indexing
    - Missing error handling for external calls
    - Type coercion issues

    Read the source files carefully. Report specific issues with
    file paths and line numbers. Be precise -- only report real bugs,
    not style preferences.",
  tools = tools_file()
)

style_reviewer <- agent_definition(
  name = "style_reviewer",
  description = "Checks code against tidyverse style conventions,
    naming patterns, and code organisation",
  prompt = "You are an R style reviewer following tidyverse conventions.
    Focus on:
    - snake_case naming for functions and variables
    - Consistent use of <- for assignment (not =)
    - Function length (flag functions over ~50 lines)
    - Clear, descriptive names
    - Proper use of R6 conventions for classes

    Be pragmatic -- flag patterns that hurt readability, not
    minor nitpicks.",
  tools = tools_file()
)

doc_checker <- agent_definition(
  name = "doc_checker",
  description = "Reviews roxygen2 documentation for completeness,
    accuracy, and clarity",
  prompt = "You are a documentation reviewer for R packages. Focus on:
    - Missing roxygen2 tags (@param, @return, @export)
    - Inaccurate parameter descriptions
    - Missing @examples sections on exported functions
    - Unclear or misleading descriptions
    - Missing @seealso cross-references

    Read both the roxygen comments and the function bodies to verify
    that documentation matches the actual behaviour.",
  tools = tools_file()
)
```

## Create the Lead Agent

The `LeadAgent` coordinates the reviewers. It has a `delegate_to_agent`
tool that lets it assign tasks to any registered sub-agent:

``` r
chat <- ellmer::chat_openai()

lead <- LeadAgent$new(
  chat = chat,
  sub_agents = list(bug_hunter, style_reviewer, doc_checker),
  system_prompt = "You are a lead code reviewer coordinating a team of
    specialists. For each review request:

    1. Delegate to each specialist with a clear, specific task
    2. Collect their findings
    3. Synthesise into a unified review with findings sorted by severity
    4. Remove duplicate findings across reviewers

    Severity levels: critical, warning, suggestion.
    Always include the file path and a concrete suggestion for each finding.",
  permissions = permissions_readonly()
)

lead$available_sub_agents()
#> [1] "bug_hunter" "style_reviewer" "doc_checker"
```

## Add Monitoring Hooks

Hooks provide real-time visibility as the agent works. Use them for
logging and blocking; use `AgentResult` for post-hoc analysis.

``` r
# Log when each sub-agent finishes
hook_sub_agent_log <- HookMatcher$new(
  event = "SubagentStop",
  callback = function(agent_name, task, result, context) {
    cli::cli_alert_info("Sub-agent {.val {agent_name}} finished")
    HookResultSubagentStop()
  }
)

# Log tool calls with the built-in hook
lead$add_hook(hook_sub_agent_log)
lead$add_hook(hook_log_tools(verbose = TRUE))
```

## Run the Review

``` r
result <- lead$run_sync(
  "Review the R source files in R/ for code quality issues.
   Have each specialist review the code from their perspective,
   then synthesise the findings into a unified report."
)

cat(result$response)
```

## Structured Review Output

For machine-readable results, add a structured output schema to capture
individual findings:

``` r
review_schema <- list(
  type = "object",
  properties = list(
    summary = list(type = "string"),
    total_findings = list(type = "integer"),
    findings = list(
      type = "array",
      items = list(
        type = "object",
        properties = list(
          severity = list(
            type = "string",
            enum = c("critical", "warning", "suggestion")
          ),
          category = list(
            type = "string",
            enum = c("bug", "style", "documentation")
          ),
          file = list(type = "string"),
          line = list(type = "integer"),
          issue = list(type = "string"),
          suggestion = list(type = "string"),
          reviewer = list(type = "string")
        ),
        required = c(
          "severity",
          "category",
          "file",
          "issue",
          "suggestion",
          "reviewer"
        )
      )
    )
  ),
  required = c("summary", "total_findings", "findings")
)

chat <- ellmer::chat_openai()

lead <- LeadAgent$new(
  chat = chat,
  sub_agents = list(bug_hunter, style_reviewer, doc_checker),
  system_prompt = "You coordinate code reviewers. Delegate to each
    specialist, then combine their findings into structured JSON.
    Deduplicate findings across reviewers.",
  permissions = permissions_readonly()
)

result <- lead$run_sync(
  "Review the R/ directory and return structured findings.",
  output_format = list(type = "json_schema", schema = review_schema)
)
```

## Processing the Results

With structured output, you can filter, sort, and summarise findings
programmatically:

``` r
review <- result$structured_output$parsed

# Summary
cli::cli_h1("Code Review: {review$summary}")
cli::cli_alert_info("Total findings: {review$total_findings}")

# Filter by severity
critical <- Filter(
  function(f) f$severity == "critical",
  review$findings
)
warnings <- Filter(
  function(f) f$severity == "warning",
  review$findings
)

cli::cli_alert_danger("{length(critical)} critical issue(s)")
cli::cli_alert_warning("{length(warnings)} warning(s)")

# Display critical findings
for (finding in critical) {
  cli::cli_h2("{finding$file}")
  cli::cli_alert_danger("{finding$issue}")
  cli::cli_alert_info("Suggestion: {finding$suggestion}")
  cli::cli_text("Found by: {finding$reviewer}")
}

# Summarise by category
findings_df <- do.call(rbind, lapply(review$findings, as.data.frame))
table(findings_df$category, findings_df$severity)
```

## Cost and Performance

`AgentResult` captures cost and tool usage for post-hoc analysis:

``` r
# Total cost and duration
result$cost
result$duration

# All tool calls made during the review
tool_calls <- result$tool_calls()
cli::cli_alert_info("Total tool calls: {length(tool_calls)}")

# How many turns did it take?
result$n_turns()
```

## Next Steps

- [`vignette("multi-agent")`](https://jameshwade.github.io/deputy/articles/multi-agent.md)
  – LeadAgent and agent_definition() reference
- [`vignette("hooks")`](https://jameshwade.github.io/deputy/articles/hooks.md)
  – Hook events and pre-built hooks
- [`vignette("structured-output")`](https://jameshwade.github.io/deputy/articles/structured-output.md)
  – JSON schema output and validation
