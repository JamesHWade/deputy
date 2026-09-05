# required feature dependencies provide installation guidance

    Code
      tool_web_fetch("https://example.com")
    Condition
      Error in `rlang::check_installed()`:
      ! The package "httr2" (>= 9999) is required to fetch web content

---

    Code
      tool_web_search("deputy")
    Condition
      Error in `rlang::check_installed()`:
      ! The package "httr2" (>= 9999) is required to search the web

---

    Code
      tools_mcp_repl()
    Condition
      Error in `rlang::check_installed()`:
      ! The package "jsonlite" (>= 9999) is required to validate MCP configuration

---

    Code
      parse_multi_edits("[]")
    Condition
      Error in `rlang::check_installed()`:
      ! The package "jsonlite" (>= 9999) is required to parse JSON edits

---

    Code
      skill_load(skill_dir)
    Condition
      Error in `rlang::check_installed()`:
      ! The package "yaml" (>= 9999) is required to load SKILL.yaml

---

    Code
      parse_markdown_frontmatter(markdown)
    Condition
      Error in `rlang::check_installed()`:
      ! The package "yaml" (>= 9999) is required to parse skill YAML frontmatter

