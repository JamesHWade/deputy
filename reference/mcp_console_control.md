# Interrupt or restart an MCP Console session

`"interrupt"` sends SIGINT to the running code or dependency install and
keeps the session's state. The code may not stop, so check the returned
output: it can still end in `[running; poll with an empty send]`.
`"restart"` replaces the worker and discards all R, Python and DuckDB
state.

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

A promise for MCP Console's reply. The call goes straight to the server,
not through the agent, and errors if the connection is already handling
a request.

## Details

If a restart takes longer than about 4 seconds, the connection closes
with a `deputy_mcp_console_restart` error and the server stops. Create a
new connection to continue.
