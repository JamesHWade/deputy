# Create a simple delegation agent

Convenience function to create a LeadAgent with common sub-agents for
code-related tasks.

## Usage

``` r
agent_with_delegation(chat, permissions = NULL)
```

## Arguments

- chat:

  An ellmer Chat object

- permissions:

  Optional permissions

## Value

A
[LeadAgent](https://jameshwade.github.io/deputy/reference/LeadAgent.md)
object

## Examples

``` r
if (FALSE) { # \dontrun{
agent <- agent_with_delegation(
  chat = ellmer::chat("openai/gpt-4o")
)

result <- agent$run_sync("Review the code in main.R and suggest improvements")
} # }
```
