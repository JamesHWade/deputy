# Get tools from MCP servers

Fetches ellmer-compatible tools from configured MCP servers using the
mcptools package for use with deputy agents.

MCP (Model Context Protocol) allows agents to access tools from external
services like GitHub, Slack, Google Drive, and more. Tools are
discovered dynamically from running MCP servers.

## Usage

``` r
tools_mcp(config = NULL, servers = NULL)
```

## Arguments

- config:

  Path to MCP configuration file. If NULL (default), uses the mcptools
  default location (`~/.config/mcptools/config.json`).

- servers:

  Optional character vector of server names to load tools from. If NULL
  (default), loads tools from all configured servers. Filtering is
  performed on exact configuration names before connecting servers.

## Value

A list of tool definitions compatible with `Agent$register_tools()`.
[`tool_metadata()`](https://jameshwade.github.io/deputy/reference/tool_metadata.md)
reports exact MCP origin, supplied annotations, and gaps. The metadata
bridge is qualified for mcptools 1.0.2; other versions fail explicitly
rather than silently losing annotations. Reconnecting a server
invalidates tools loaded from its previous connection. Reload and
explicitly replace those tools on the Agent. Load failures warn and
return an empty list. Returns an empty list if mcptools is not installed
or no tools are available.

## Details

The MCP configuration file follows the Claude Desktop format:

    {
      "mcpServers": {
        "github": {
          "command": "npx",
          "args": ["-y", "@modelcontextprotocol/server-github"],
          "env": {"GITHUB_TOKEN": "..."}
        }
      }
    }

## See also

[mcptools package](https://posit-dev.github.io/mcptools/) for
configuration

## Examples

``` r
if (FALSE) { # \dontrun{
# Get all MCP tools from default config
mcp_tools <- tools_mcp()

# Create agent with MCP tools
agent <- Agent$new(
  chat = ellmer::chat_anthropic(),
  tools = c(tools_file(), mcp_tools)
)

# Use custom config file
mcp_tools <- tools_mcp(config = "path/to/config.json")

# Load tools from specific servers only
mcp_tools <- tools_mcp(servers = c("github", "slack"))
} # }
```
