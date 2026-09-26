# List available skills in a directory

Finds skills in `path`: subdirectories that contain `SKILL.yaml` or
`SKILL.md`, and Markdown files directly inside `path`.

## Usage

``` r
skills_list(path = "skills")
```

## Arguments

- path:

  Directory to search. Defaults to `"skills"` in the working directory.

## Value

A data frame with `name` and `path` columns, empty if `path` doesn't
exist.

## Examples

``` r
if (FALSE) { # \dontrun{
# List skills in default location
skills_list()

# List skills in custom location
skills_list("~/my_skills")
} # }
```
