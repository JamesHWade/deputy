# Interrupt or restart an MCP Console session

Sends MCP Console's `send(control = ...)` through the same connection.
`"interrupt"` requests SIGINT for the active evaluation or dependency
resolver and keeps in-memory state. Interruption is cooperative, so
check the returned output: it can still end in
`[running; poll with an empty send]`. `"restart"` replaces the worker
and discards R, Python and DuckDB state.

## Usage

``` r
mcp_console_control(connection, action = c("interrupt", "restart"))
```

## Arguments

- connection:

  A connection created by
  [`mcp_console_connection()`](https://jameshwade.github.io/deputy/reference/mcp_console_connection.md).

- action:

  `"interrupt"` or `"restart"`.

## Value

A promise for the upstream result. This is a direct host operation, not
an Agent run. A connection with an active request rejects overlap.

## Details

Restart has no upstream deadline. If the replacement is not ready within
the client's response window (about 4 seconds), Deputy closes the
connection and reports a `deputy_mcp_console_restart` error. The server
and its worker are then stopped; create a new connection to continue.
