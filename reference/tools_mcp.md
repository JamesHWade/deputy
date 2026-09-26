# Get tools from MCP servers

Starts the servers in an mcptools configuration file and returns their
tools, ready to register on an
[Agent](https://jameshwade.github.io/deputy/reference/Agent.md). MCP
(Model Context Protocol) servers give agents tools for services such as
GitHub, Slack or Google Drive.

## Usage

``` r
tools_mcp(config = NULL, servers = NULL)
```

## Arguments

- config:

  Path to an MCP configuration file. Defaults to mcptools' default
  location, `~/.config/mcptools/config.json`.

- servers:

  Names of the servers to load, matched exactly. Servers not named are
  not started. `NULL` (the default) loads every configured server.

## Value

A list of tools. If mcptools isn't installed or loading fails,
`tools_mcp()` warns and returns an empty list.

## Details

The configuration file uses the Claude Desktop format:

    {
      "mcpServers": {
        "github": {
          "command": "npx",
          "args": ["-y", "@modelcontextprotocol/server-github"],
          "env": {"GITHUB_TOKEN": "..."}
        }
      }
    }

Deputy supports mcptools 1.0.2 and 1.0.3; other versions give a warning
and no tools. Annotations a server leaves out get cautious defaults, so
MCP tools usually need `web = TRUE` in
[`Permissions()`](https://jameshwade.github.io/deputy/reference/Permissions.md).
[`tool_metadata()`](https://jameshwade.github.io/deputy/reference/tool_metadata.md)
shows what a tool declares.

Loading a server again restarts it and breaks the tools from the earlier
load; register the new ones with `replace = TRUE`. A stdio server that
takes more than about 4 seconds to answer a call is stopped, and the
call fails.
[McpConnection](https://jameshwade.github.io/deputy/reference/McpConnection.md)
gives you a fixed tool allowlist, timeouts and control over shutdown.

## See also

The [mcptools package](https://posit-dev.github.io/mcptools/) for
configuration, and
[`vignette("mcp")`](https://jameshwade.github.io/deputy/articles/mcp.md).

## Examples

``` r
if (FALSE) { # \dontrun{
# Get all MCP tools from the default config
mcp_tools <- tools_mcp()

# Create an agent with MCP tools
agent <- Agent$new(
  chat = ellmer::chat("anthropic/claude-sonnet-5"),
  tools = c(tools_file(), mcp_tools),
  permissions = Permissions(web = TRUE)
)

# Use custom config file
mcp_tools <- tools_mcp(config = "path/to/config.json")

# Load tools from specific servers only
mcp_tools <- tools_mcp(servers = c("github", "slack"))
} # }
```
