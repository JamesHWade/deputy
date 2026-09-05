# Package availability audit (#57)

Audited against main at 64e6c37. The historical issue count has changed as the
runtime evolved; this covers all availability checks currently in R/.

## Requirements

These paths use `rlang::check_installed()` with a feature-specific reason:

| Path | Package | Requirement |
| --- | --- | --- |
| `convert_to_markdown_markitdown()` | reticulate | Execute the requested converter |
| `parse_multi_edits()` with JSON input | jsonlite | Parse edits; list input needs no package |
| `run_r_code_impl()` | callr | Preserve subprocess isolation |
| `tools_mcp_repl()` | jsonlite | Validate MCP configuration |
| `tool_web_fetch`, `tool_web_search` | httr2 | Execute the HTTP request |
| `skill_load()` with SKILL.yaml | yaml | Read skill metadata |
| `parse_markdown_frontmatter()` with frontmatter | yaml | Avoid silently discarding metadata |
| `read_pdf_text_pages()` after backend selection fails | pdftools | Offer the preferred backend, then retry reading after interactive installation |

## Branches retained

| Path | Package checks | Alternative behavior |
| --- | --- | --- |
| `read_pdf_text_pages()` | pdftools, reticulate | Choose between R and Python PDF backends |
| `run_bash_impl()` | callr | Existing system-command fallback |
| CSV tool | readr | Base R CSV reader |
| `HookRegistry` timeout selection and warning | callr (two sites) | Existing in-process callback with explicit timeout warning |
| `Skill$check_requirements()` | declared packages | Return an availability report rather than interrupt it |
| `skills_list()` | yaml | Directory basename when optional YAML name lookup is unavailable |
| `format_schema_json()` | jsonlite | Text representation for display |
| `extract_web_content()` | rvest, xml2 | Basic HTML extraction |
| `parse_duckduckgo_results()` | rvest, xml2 | Regex search-result extraction |
| `has_pandoc()` | rmarkdown | Report unavailable converter so caller can choose another path |

The namespace import directive is not a runtime check. Python-module and system
executable checks are not R package requirements. Existing fallback policies
are preserved; this audit does not introduce new timeout or validation policy.
