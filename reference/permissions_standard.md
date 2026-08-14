# Create a standard permission policy

Creates a permission policy suitable for most use cases. Allows reads of
files accessible to the R process, confines file writes to the working
directory, and permits R code execution. Denies bash commands, web
access, and package installation.

## Usage

``` r
permissions_standard(
  working_dir = getwd(),
  max_turns = 25,
  max_cost_usd = NULL
)
```

## Arguments

- working_dir:

  Root directory for file writes (default: current directory). This does
  not restrict otherwise accessible file reads.

- max_turns:

  Maximum number of turns (default 25)

- max_cost_usd:

  Maximum cost in USD (default NULL = unlimited)

## Value

A
[Permissions](https://jameshwade.github.io/deputy/reference/Permissions.md)
object

## Examples

``` r
perms <- permissions_standard()
perms$check("write_file", list(path = "output.txt"))
#> $decision
#> [1] "allow"
#> 
#> $message
#> NULL
#> 
#> attr(,"class")
#> [1] "PermissionResultAllow" "PermissionResult"      "list"                 
```
