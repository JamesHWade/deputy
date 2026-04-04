# Run a one-shot Agent SDK compatibility query

`agent_sdk_query()` is an additive alias for `claude_sdk_query()`.

## Usage

``` r
claude_sdk_query(prompt, options = claude_sdk_options(), output_format = NULL)

agent_sdk_query(prompt, options = agent_sdk_options(), output_format = NULL)
```

## Arguments

- prompt:

  User prompt to send

- options:

  Claude SDK compatibility options

- output_format:

  Optional structured output format passed to deputy

## Value

An
[AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md)
