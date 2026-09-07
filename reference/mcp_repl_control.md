# Request an upstream REPL interrupt or reset

Sends mcp-repl's documented Ctrl-C or Ctrl-D input through the same
connection. Interrupt is best effort; reset requests a fresh interpreter
and discards its state. The returned upstream result describes what
happened. Neither action is treated as proof of success merely because a
request was sent.

## Usage

``` r
mcp_repl_control(connection, action = c("interrupt", "reset"))
```

## Arguments

- connection:

  A connection created by
  [`mcp_repl_connection()`](https://jameshwade.github.io/deputy/reference/mcp_repl_connection.md).

- action:

  `"interrupt"` or `"reset"`.

## Value

A promise for the upstream ellmer-compatible result. This is a direct
host operation, not an Agent run. Busy client connections reject
overlap.
