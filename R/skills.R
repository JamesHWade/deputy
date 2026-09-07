#' @include skill.R
NULL

# Skill loading system for deputy agents

#' Load a skill from a directory
#'
#' @description
#' Loads a skill from a directory containing `SKILL.yaml` (metadata) and/or
#' `SKILL.md` (system prompt extension). You can also pass a direct path to
#' a `SKILL.md` file.
#'
#' @param path Path to the skill directory
#' @param check_requirements If TRUE (default), verify requirements are met
#' @return A [Skill] object
#'
#' @details
#' The skill directory should contain one of:
#'
#' **SKILL.yaml** (required):
#' ```yaml
#' name: my_skill
#' version: "1.0.0"
#' description: What this skill does
#' requires:
#'   packages: [dplyr, ggplot2]
#'   providers: [openai, anthropic]
#' tools:
#'   - name: my_tool
#'     file: tools.R
#'     function: tool_my_tool
#' ```
#'
#' **SKILL.md** (optional, or standalone file):
#' Markdown content that will be appended to the agent's system prompt
#' when this skill is loaded. Frontmatter is supported:
#' ```yaml
#' ---
#' name: my_skill
#' description: Optional description
#' requires:
#'   packages: [dplyr]
#' ---
#' ```
#'
#' **tools.R** (optional):
#' R file containing tool definitions referenced in SKILL.yaml.
#'
#' @examples
#' \dontrun{
#' # Load a skill
#' skill <- skill_load("path/to/my_skill")
#'
#' # Add to agent
#' agent$load_skill(skill)
#' }
#'
#' @export
skill_load <- function(path, check_requirements = TRUE) {
  path <- normalizePath(path, mustWork = TRUE)

  info <- file.info(path)
  if (is.na(info$isdir)) {
    cli_abort("Skill path is not accessible: {.path {path}}")
  }

  # Support loading directly from a SKILL.md file
  if (!isTRUE(info$isdir)) {
    if (!grepl("\\.md$", path, ignore.case = TRUE)) {
      cli_abort("Skill file must be a Markdown file: {.path {path}}")
    }
    skill <- load_skill_from_markdown(path)
    if (check_requirements) {
      req_check <- skill_check_requirements(skill)
      if (!req_check$ok) {
        cli_warn(c(
          "Skill {.val {skill$name}} has unmet requirements",
          "x" = "Missing: {.val {req_check$missing}}"
        ))
      }
    }
    return(skill)
  }

  # Check for SKILL.yaml or SKILL.md in directory
  yaml_path <- file.path(path, "SKILL.yaml")
  md_path <- file.path(path, "SKILL.md")
  if (!file.exists(yaml_path)) {
    yaml_path <- file.path(path, "skill.yaml")
  }
  if (!file.exists(md_path)) {
    md_path <- file.path(path, "skill.md")
  }

  if (!file.exists(yaml_path) && !file.exists(md_path)) {
    cli_abort(c(
      "Skill directory must contain SKILL.yaml or SKILL.md",
      "x" = "Not found in: {.path {path}}"
    ))
  }

  meta <- list()
  prompt <- NULL

  # Parse SKILL.yaml when present
  if (file.exists(yaml_path)) {
    rlang::check_installed("yaml", reason = "to load SKILL.yaml")
    meta <- yaml::read_yaml(yaml_path)
    if (is.null(meta$name)) {
      cli_abort("SKILL.yaml must contain a 'name' field")
    }
  }

  # Load SKILL.md if present (with optional frontmatter)
  if (file.exists(md_path)) {
    parsed <- parse_markdown_frontmatter(md_path)
    prompt <- parsed$body
    if (length(parsed$meta) > 0) {
      meta <- utils::modifyList(meta, parsed$meta, keep.null = TRUE)
    }
  }

  # Load tools if specified (SKILL.yaml)
  tools <- list()
  if (!is.null(meta$tools) && length(meta$tools) > 0) {
    tools <- load_skill_tools(path, meta$tools)
  }

  # Create skill object
  skill <- Skill(
    name = meta$name %||% basename(path),
    version = meta$version %||% "0.0.0",
    description = meta$description,
    prompt = prompt,
    tools = tools,
    requires = meta$requires %||% list(),
    path = path
  )

  # Check requirements if requested
  if (check_requirements) {
    req_check <- skill_check_requirements(skill)
    if (!req_check$ok) {
      cli_warn(c(
        "Skill {.val {skill$name}} has unmet requirements",
        "x" = "Missing: {.val {req_check$missing}}"
      ))
    }
  }

  skill
}

# Load a skill directly from a SKILL.md file
load_skill_from_markdown <- function(path) {
  parsed <- parse_markdown_frontmatter(path)
  meta <- parsed$meta %||% list()
  prompt <- parsed$body

  skill <- Skill(
    name = meta$name %||% tools::file_path_sans_ext(basename(path)),
    version = meta$version %||% "0.0.0",
    description = meta$description,
    prompt = prompt,
    tools = list(),
    requires = meta$requires %||% list(),
    path = dirname(path)
  )

  skill
}

#' Load tools from skill directory
#'
#' @param skill_path Path to skill directory
#' @param tool_specs List of tool specifications from SKILL.yaml
#' @return List of tool definitions
#'
#' @keywords internal
load_skill_tools <- function(skill_path, tool_specs) {
  tools <- list()

  for (spec in tool_specs) {
    if (is.null(spec$file) || is.null(spec$`function`)) {
      cli_warn(c(
        "Tool specification missing 'file' or 'function'",
        "i" = "Skipping tool: {.val {spec$name %||% 'unnamed'}}"
      ))
      next
    }

    tool_file <- file.path(skill_path, spec$file)
    if (!file.exists(tool_file)) {
      cli_warn(c(
        "Tool file not found: {.path {tool_file}}",
        "i" = "Skipping tool: {.val {spec$name %||% 'unnamed'}}"
      ))
      next
    }

    # Source the file in an environment that has access to ellmer
    # We use the deputy namespace as parent so ellmer is available
    tool_env <- new.env(parent = asNamespace("deputy"))
    tryCatch(
      {
        source(tool_file, local = tool_env)

        # Get the tool function
        fn_name <- spec$`function`
        if (!exists(fn_name, envir = tool_env)) {
          cli_warn(c(
            "Function {.fn {fn_name}} not found in {.path {spec$file}}",
            "i" = "Skipping tool: {.val {spec$name %||% fn_name}}"
          ))
          next
        }

        tool <- get(fn_name, envir = tool_env)
        # Check for S7 ToolDef class (ellmer uses S7)
        tool_class <- class(tool)
        is_tool <- any(grepl("ToolDef", tool_class))
        if (!is_tool) {
          cli_warn(c(
            "{.fn {fn_name}} is not a tool definition",
            "i" = "Use {.fn ellmer::tool} to create tools",
            "i" = "Skipping tool: {.val {spec$name %||% fn_name}}"
          ))
          next
        }

        tools <- c(tools, list(tool))
      },
      error = function(e) {
        cli_warn(c(
          "Error loading tool from {.path {spec$file}}",
          "x" = e$message
        ))
      }
    )
  }

  tools
}

#' Create a skill programmatically
#'
#' @description
#' Create a skill without loading from disk. Useful for defining skills
#' inline in R code.
#'
#' @param name Skill name
#' @param description Brief description
#' @param prompt System prompt extension
#' @param tools List of tools created with `ellmer::tool()`
#' @param version Version string (default: "1.0.0")
#' @param requires List of requirements (packages, providers)
#' @return A [Skill] object
#'
#' @examples
#' \dontrun{
#' # Create a simple skill
#' my_skill <- skill_create(
#'   name = "calculator",
#'   description = "Basic math operations",
#'   prompt = "You are a helpful calculator assistant.",
#'   tools = list(tool_add, tool_multiply)
#' )
#'
#' agent$load_skill(my_skill)
#' }
#'
#' @export
skill_create <- function(
  name,
  description = NULL,
  prompt = NULL,
  tools = list(),
  version = "1.0.0",
  requires = list()
) {
  Skill(
    name = name,
    version = version,
    description = description,
    prompt = prompt,
    tools = tools,
    requires = requires,
    path = NULL
  )
}

#' List available skills in a directory
#'
#' @description
#' Scans a directory for subdirectories containing SKILL.yaml files.
#'
#' @param path Path to search for skills (default: "skills" in working dir)
#' @return Data frame with skill names and paths
#'
#' @examples
#' \dontrun{
#' # List skills in default location
#' skills_list()
#'
#' # List skills in custom location
#' skills_list("~/my_skills")
#' }
#'
#' @export
skills_list <- function(path = "skills") {
  if (!dir.exists(path)) {
    return(data.frame(
      name = character(),
      path = character(),
      stringsAsFactors = FALSE
    ))
  }

  # Find subdirectories with SKILL.yaml or SKILL.md
  subdirs <- list.dirs(path, recursive = FALSE, full.names = TRUE)
  md_files <- list.files(path, pattern = "\\.md$", full.names = TRUE)

  skills <- data.frame(
    name = character(),
    path = character(),
    stringsAsFactors = FALSE
  )

  for (dir in subdirs) {
    yaml_path <- file.path(dir, "SKILL.yaml")
    if (!file.exists(yaml_path)) {
      yaml_path <- file.path(dir, "skill.yaml")
    }
    md_path <- file.path(dir, "SKILL.md")
    if (!file.exists(md_path)) {
      md_path <- file.path(dir, "skill.md")
    }

    if (file.exists(yaml_path) || file.exists(md_path)) {
      # Try to get the name from YAML/frontmatter
      name <- basename(dir)
      if (file.exists(yaml_path) && rlang::is_installed("yaml")) {
        tryCatch(
          {
            meta <- yaml::read_yaml(yaml_path)
            name <- meta$name %||% basename(dir)
          },
          error = function(e) {
            cli_warn(c(
              "Failed to parse SKILL.yaml in {.path {dir}}",
              "x" = e$message,
              "i" = "Using directory name as skill name"
            ))
          }
        )
      } else if (file.exists(md_path) && rlang::is_installed("yaml")) {
        parsed <- parse_markdown_frontmatter(md_path)
        name <- parsed$meta$name %||% basename(dir)
      }

      skills <- rbind(
        skills,
        data.frame(
          name = name,
          path = dir,
          stringsAsFactors = FALSE
        )
      )
    }
  }

  # Include standalone markdown skills in the root
  for (md_path in md_files) {
    name <- tools::file_path_sans_ext(basename(md_path))
    if (rlang::is_installed("yaml")) {
      parsed <- parse_markdown_frontmatter(md_path)
      name <- parsed$meta$name %||% name
    }
    skills <- rbind(
      skills,
      data.frame(
        name = name,
        path = md_path,
        stringsAsFactors = FALSE
      )
    )
  }

  skills
}
