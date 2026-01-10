# Check if MCP support is available

Returns TRUE if the mcptools package is installed and available.

## Usage

``` r
mcp_available()
```

## Value

Logical indicating if MCP support is available

## Examples

``` r
if (mcp_available()) {
  message("MCP support is available")
}
#> MCP support is available
```
