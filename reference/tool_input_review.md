# Tabulate tool arguments for human review

Builds a data frame with one row per argument field, pairing the model's
proposed value with the tool's declared ellmer type and description.
Nested objects are flattened to dotted paths such as `plan.treatment`.
Use it in a `can_use_tool` callback, PreToolUse hook, or durable
approval review to show a reviewer a table instead of
[`dput()`](https://rdrr.io/r/base/dput.html) text.

Permission callbacks and PreToolUse hooks receive the registered tool's
declared arguments as `context$tool_arguments`. Values are formatted for
display only. Validate inputs in the tool itself; review does not
establish that a value is correct.

## Usage

``` r
tool_input_review(tool_input, tool_arguments = NULL)
```

## Arguments

- tool_input:

  Named list of proposed arguments, as given to permission callbacks and
  hooks or found in `pending$request$tool_input`.

- tool_arguments:

  The tool's declared arguments: an ellmer `TypeObject` such as
  `context$tool_arguments` or `tool@arguments`, or `NULL` when no
  declaration is available.

## Value

A data frame with character columns `argument`, `type`, `description`,
and `value`, and logical columns `required` and `declared`. Undeclared
input fields are kept with `declared = FALSE`; declared fields missing
from the input have value `NA`.

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
