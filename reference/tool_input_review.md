# Tabulate a tool call's arguments for review

Builds a data frame with one row per argument, pairing the value the
model proposed with the tool's declared type and description. Nested
objects are flattened to dotted names such as `plan.treatment`. Use it
in a `can_use_tool` callback, a `PreToolUse` hook or an approval screen
to show a person a table instead of
[`dput()`](https://rdrr.io/r/base/dput.html) output.

Permission callbacks and `PreToolUse` hooks get the tool's declared
arguments as `context$tool_arguments`. The table is for display only;
validate inputs in the tool itself.

## Usage

``` r
tool_input_review(tool_input, tool_arguments = NULL)
```

## Arguments

- tool_input:

  Named list of proposed arguments, as passed to permission callbacks
  and hooks, or the `request$tool_input` of a pending approval from
  [`approval_read()`](https://jameshwade.github.io/deputy/reference/approval_read.md).

- tool_arguments:

  The tool's declared arguments: an ellmer `TypeObject` such as
  `context$tool_arguments` or `tool@arguments`, or `NULL` if you don't
  have one.

## Value

A data frame with character columns `argument`, `type`, `description`
and `value`, and logical columns `required` and `declared`. Input fields
the tool doesn't declare are kept with `declared = FALSE`; declared
fields missing from the input have value `NA`. The `"paths"` attribute
holds each row's path as a character vector, which stays exact when a
name itself contains a dot.

## Examples

``` r
arguments <- ellmer::type_object(
  city = ellmer::type_string("City to forecast"),
  days = ellmer::type_integer("Number of days", required = FALSE)
)
tool_input_review(list(city = "Oslo", days = 3L), arguments)
#>   argument    type required declared      description value
#> 1     city  string     TRUE     TRUE City to forecast  Oslo
#> 2     days integer    FALSE     TRUE   Number of days     3
```
