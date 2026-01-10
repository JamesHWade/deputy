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
  (default), loads tools from all configured servers. Filtering is based
  on pattern matching against tool names.

## Value

A list of tool definitions compatible with `Agent$register_tools()`.
Returns an empty list if mcptools is not installed or no tools are
available.

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

- [`mcp_available()`](https://jameshwade.github.io/deputy/reference/mcp_available.md)
  to check if MCP support is installed

- [mcptools package](https://posit-dev.github.io/mcptools/) for
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
