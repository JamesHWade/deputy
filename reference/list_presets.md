# List available tool presets

Returns information about available tool presets, including their names,
descriptions, and the tools they contain.

## Usage

``` r
list_presets()
```

## Value

A data frame with preset information

## Examples

``` r
list_presets()
#>       name                          description
#> 1  minimal Read-only tools for safe exploration
#> 2 standard   Balanced toolset for R development
#> 3      dev   Full development with shell access
#> 4     data          Data analysis focused tools
#> 5     full                  All available tools
#>                                                                                      tools
#> 1                                                                    read_file, list_files
#> 2                                            read_file, write_file, list_files, run_r_code
#> 3                                  read_file, write_file, list_files, run_r_code, run_bash
#> 4                                              read_file, list_files, read_csv, run_r_code
#> 5 read_file, write_file, list_files, run_r_code, run_bash, read_csv, web_fetch, web_search
```
