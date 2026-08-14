# Create an in-memory SDK-compatible session store

Creates a lightweight session store adapter with
[`append()`](https://rdrr.io/r/base/append.html),
[`load()`](https://rdrr.io/r/base/load.html), `list_sessions()`,
`list_session_summaries()`, and `delete()` methods. This mirrors the
Claude Agent SDK store shape while preserving deputy's R-native session
payloads.

## Usage

``` r
session_store_memory()
```

## Value

A `DeputySessionStore` adapter
