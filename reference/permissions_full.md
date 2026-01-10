# Create a full access permission policy

Creates a permission policy that allows all operations. **Use with
caution!** This bypasses all permission checks.

## Usage

``` r
permissions_full(max_turns = 50, max_cost_usd = NULL)
```

## Arguments

- max_turns:

  Maximum number of turns (default 50)

- max_cost_usd:

  Maximum cost in USD (default NULL = unlimited)

## Value

A
[Permissions](https://jameshwade.github.io/deputy/reference/Permissions.md)
object

## Examples

``` r
perms <- permissions_full()
```
