# Interrupt or reset an mcp-repl session

Sends Ctrl-C (`"interrupt"`) or Ctrl-D (`"reset"`) to the R session
behind a
[`mcp_repl_connection()`](https://jameshwade.github.io/deputy/reference/mcp_repl_connection.md).
An interrupt may not stop the code. A reset starts a fresh interpreter
and discards its variables. Check the returned result to see what
happened.

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

A promise for mcp-repl's reply. The call goes straight to the server,
not through the agent, and errors if the connection is already handling
a request.
