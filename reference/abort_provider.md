# Abort with a provider error

Signals that the LLM provider encountered an error.

## Usage

``` r
abort_provider(
  message,
  provider_name = NULL,
  model = NULL,
  parent = NULL,
  ...,
  .envir = parent.frame()
)
```

## Arguments

- message:

  The error message (supports cli formatting)

- provider_name:

  Name of the provider (e.g., "openai", "anthropic")

- model:

  The model being used (optional)

- parent:

  The parent error from the provider (optional)

- ...:

  Additional context fields

- .envir:

  Environment for cli interpolation

## Examples

``` r
if (FALSE) { # \dontrun{
abort_provider(
  c("API error from {.val {provider_name}}", "x" = "Rate limit exceeded"),
  provider_name = "openai",
  model = "gpt-4o"
)
} # }
```
