# Create a standard permission policy

Creates a `"standard"` policy for everyday use. The agent can read any
file your R session can read, and write files inside `working_dir`. R
code, shell commands, web access and package installation are denied.
Turn on code execution only when you trust the model and the task: the
code runs with your user's access, not in an OS sandbox.

## Usage

``` r
permissions_standard(working_dir = getwd())
```

## Arguments

- working_dir:

  An existing absolute path to the directory the agent may write to.
  Defaults to the current directory. Reads are not limited to it.

## Value

A
[Permissions](https://jameshwade.github.io/deputy/reference/Permissions.md)
object.

## Examples

``` r
perms <- permissions_standard()
permissions_check(perms, "write_file", list(path = "output.txt"))
#> <deputy::PermissionResultAllow>
#>  @ decision: chr "allow"
#>  @ message : NULL
```
