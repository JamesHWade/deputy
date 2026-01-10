# List available MCP servers

Lists the MCP servers configured in the mcptools configuration file.

## Usage

``` r
mcp_servers(config = NULL)
```

## Arguments

- config:

  Path to MCP configuration file. If NULL (default), uses
  `~/.config/mcptools/config.json`.

## Value

A character vector of server names. Returns `character(0)` if config
exists but has no servers. Returns NULL on error (mcptools not
installed, config file missing, or parse error).

## Examples

``` r
if (FALSE) { # \dontrun{
# List configured servers
mcp_servers()
} # }
```
