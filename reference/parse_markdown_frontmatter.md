# Parse Markdown frontmatter

Reads the YAML block between `---` lines at the top of a Markdown file.
Warns and returns empty `meta` if the YAML can't be parsed.

## Usage

``` r
parse_markdown_frontmatter(path)
```

## Arguments

- path:

  Path to a Markdown file

## Value

List with `meta` (list) and `body` (character)
