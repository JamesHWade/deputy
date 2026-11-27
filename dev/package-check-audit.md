# Package availability audit (#57)

Updated after `jsonlite`, `callr`, `httr2`, and `later` moved into `DESCRIPTION`
`Imports` and `tools_mcp_repl()` was removed (#267). This covers optional
(`Suggests`) package checks remaining in `R/`.

## Requirements

These paths use `rlang::check_installed()` with a feature-specific reason:

| Path | Package | Requirement |
| --- | --- | --- |
| `convert_to_markdown_markitdown()` | reticulate | Execute the requested converter |
| `skill_load()` with SKILL.yaml | yaml | Read skill metadata |
| `parse_markdown_frontmatter()` with frontmatter | yaml | Avoid silently discarding metadata |
| `read_pdf_text_pages()` after backend selection fails | pdftools | Offer the preferred backend, then retry reading after interactive installation |

## Branches retained

| Path | Package checks | Alternative behavior |
| --- | --- | --- |
| `read_pdf_text_pages()` | pdftools, reticulate | Choose between R and Python PDF backends |
| CSV tool | readr | Base R CSV reader |
| `skill_check_requirements()` | declared packages | Return an availability report rather than interrupt it |
| `skills_list()` | yaml | Directory basename when optional YAML name lookup is unavailable |
| `extract_web_content()` | rvest, xml2 | Basic HTML extraction |
| `parse_duckduckgo_results()` | rvest, xml2 | Regex search-result extraction |
| `has_pandoc()` | rmarkdown | Report unavailable converter so caller can choose another path |

The namespace import directive is not a runtime check. Python-module and system
executable checks are not R package requirements. Existing fallback policies
are preserved; this audit does not introduce new timeout or validation policy.
