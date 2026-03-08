# Write persisted todo items

Replace the current JSON todo list used by compatibility workflows.

## Usage

``` r
tool_todo_write(todos, path = ".deputy/todos.json")
```

## Format

A tool definition created with
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).

## Arguments

- todos:

  List or JSON array of todo items (tool argument)

- path:

  Path to the todo file (tool argument)
