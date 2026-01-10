# Create a standard permission policy

Creates a permission policy suitable for most use cases. Allows file
read/write within the working directory and R code execution. Denies
bash commands, web access, and package installation.

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

  Directory for file operations (default: current directory)

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
#> [1] "deny"
#> 
#> $reason
#> [1] "File writing only allowed in: /home/runner/work/deputy/deputy/docs/reference"
#> 
#> $interrupt
#> [1] FALSE
#> 
#> attr(,"class")
#> [1] "PermissionResultDeny" "PermissionResult"     "list"                
```
