# List available skills in a directory

Scans a directory for subdirectories containing SKILL.yaml files.

## Usage

``` r
skills_list(path = "skills")
```

## Arguments

- path:

  Path to search for skills (default: "skills" in working dir)

## Value

Data frame with skill names and paths

## Examples

``` r
if (FALSE) { # \dontrun{
# List skills in default location
skills_list()

# List skills in custom location
skills_list("~/my_skills")
} # }
```
