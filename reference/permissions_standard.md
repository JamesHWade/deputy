# Create a standard permission policy

Creates a permission policy suitable for most use cases. Allows reads of
files accessible to the R process, confines file writes to the working
directory. Denies arbitrary R code, bash commands, web access, and
package installation. Grant code execution explicitly only when the
model and task are trusted; process separation is not an OS sandbox.

## Usage

``` r
permissions_standard(working_dir = getwd())
```

## Arguments

- working_dir:

  Existing absolute root directory for file writes (default: current
  directory). This does not restrict otherwise accessible file reads.

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
