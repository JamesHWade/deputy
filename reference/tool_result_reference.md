# Find a tool result saved outside the model context

When a
[ContextPolicy](https://jameshwade.github.io/deputy/reference/ContextPolicy.md)
moves a large tool result out of the model context, the result recorded
in the conversation holds a preview and a reference in place of what the
tool returned: in place of its value, of its error, or, for a result
made of content objects, as the last of them. Use this function on the
contents of `agent$get_turns()` to find those results, and
`agent$restore_tool_result()` to put back what the tool returned, for
example to check an answer against the full results its tools returned.

## Usage

``` r
tool_result_reference(x)
```

## Arguments

- x:

  An ellmer
  [ContentToolResult](https://ellmer.tidyverse.org/reference/Content.html),
  or the text of one.

## Value

The `deputy://tool-result/...` reference, a string, or `NULL` when `x`
is not a result saved outside the context.

## See also

[`ContextPolicy()`](https://jameshwade.github.io/deputy/reference/ContextPolicy.md)

## Examples

``` r
tool_result_reference(ellmer::ContentToolResult("A short result"))
#> NULL
```
