#' @include skill.R
NULL

# Skill loading system for deputy agents

#' Load a skill from a directory
#'
#' @description
#' Loads a skill from a directory containing `SKILL.yaml` (metadata and tools),
#' `SKILL.md` (prompt text) or both, or from a single Markdown file. Loading a
#' skill with tools runs its R files, so only load skills you trust.
#'
#' @param path Path to the skill directory or Markdown file.
#' @param check_requirements If `TRUE` (the default), warn when required
#'   packages are missing.
#' @return A [Skill].
#'
#' @details
#' `SKILL.yaml` needs a `name`. Each entry under `tools` names an R file in the
#' skill directory and the object in it created with `ellmer::tool()`; entries
#' that can't be loaded are skipped with a warning.
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
#' The body of `SKILL.md` is added to the agent's system prompt. Its optional
#' YAML front matter overrides fields from `SKILL.yaml`:
#' ```yaml
#' ---
#' name: my_skill
#' description: Optional description
#' requires:
#'   packages: [dplyr]
#' ---
#' ```
#' A skill without a name is named after its directory or file. Reading YAML
#' needs the yaml package.
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
      warn_unmet_skill_requirements(skill)
    }
    return(skill)
  }

  # Check for SKILL.yaml or SKILL.md in directory
  files <- find_skill_files(path)
  yaml_path <- files$yaml
  md_path <- files$md

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
    warn_unmet_skill_requirements(skill)
  }

  skill
}

# Load a skill directly from a SKILL.md file
find_skill_files <- function(dir) {
  yaml_path <- file.path(dir, "SKILL.yaml")
  if (!file.exists(yaml_path)) {
    yaml_path <- file.path(dir, "skill.yaml")
  }
  md_path <- file.path(dir, "SKILL.md")
  if (!file.exists(md_path)) {
    md_path <- file.path(dir, "skill.md")
  }
  list(yaml = yaml_path, md = md_path)
}

warn_unmet_skill_requirements <- function(skill) {
  req_check <- skill_check_requirements(skill)
  if (!req_check$ok) {
    cli_warn(c(
      "Skill {.val {skill$name}} has unmet requirements",
      "x" = "Missing: {.val {req_check$missing}}"
    ))
  }
  invisible(req_check)
}

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
#' @return List of tools
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
        if (!inherits(tool, "ellmer::ToolDef")) {
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

#' Create a skill in code
#'
#' @description
#' Creates a [Skill] in R instead of loading one from disk. It is the same as
#' `Skill()`, except that `version` defaults to `"1.0.0"`.
#'
#' @param name Skill name.
#' @param description Short description.
#' @param prompt Text to add to the system prompt.
#' @param tools List of tools created with `ellmer::tool()`.
#' @param version Version string. Defaults to `"1.0.0"`.
#' @param requires List with optional `packages` and `providers` character
#'   vectors.
#' @return A [Skill].
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
#' Finds skills in `path`: subdirectories that contain `SKILL.yaml` or
#' `SKILL.md`, and Markdown files directly inside `path`.
#'
#' @param path Directory to search. Defaults to `"skills"` in the working
#'   directory.
#' @return A data frame with `name` and `path` columns, empty if `path`
#'   doesn't exist.
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

  skill_names <- character()
  skill_paths <- character()

  for (dir in subdirs) {
    files <- find_skill_files(dir)
    yaml_path <- files$yaml
    md_path <- files$md

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

      skill_names <- c(skill_names, name)
      skill_paths <- c(skill_paths, dir)
    }
  }

  # Include standalone markdown skills in the root
  for (md_path in md_files) {
    name <- tools::file_path_sans_ext(basename(md_path))
    if (rlang::is_installed("yaml")) {
      parsed <- parse_markdown_frontmatter(md_path)
      name <- parsed$meta$name %||% name
    }
    skill_names <- c(skill_names, name)
    skill_paths <- c(skill_paths, md_path)
  }

  data.frame(
    name = skill_names,
    path = skill_paths,
    stringsAsFactors = FALSE
  )
}

# The text `$load_skill()` appends to the system prompt for one skill.
skill_prompt_block <- function(skill) {
  paste0("\n\n# Skill: ", skill$name, "\n", skill$prompt)
}

# `prompt` followed by the block of each skill with a prompt that `prompt`
# does not already contain. A prompt in several parts is joined first, as
# ellmer's `$set_system_prompt()` joins it.
prompt_with_skill_prompts <- function(prompt, skills) {
  blocks <- vapply(
    Filter(function(skill) nzchar(skill$prompt %||% ""), skills),
    skill_prompt_block,
    character(1)
  )
  # A prompt that isn't text goes to ellmer as given, which rejects it.
  if (length(blocks) == 0L || !(is.null(prompt) || is.character(prompt))) {
    return(prompt)
  }
  base <- paste(prompt %||% "", collapse = "\n\n")
  # Look for the block without the blank line before it, so a prompt that was
  # trimmed or joined with single newlines doesn't get a second copy.
  present <- vapply(
    blocks,
    function(block) grepl(sub("^\n\n", "", block), base, fixed = TRUE),
    logical(1)
  )
  paste0(base, paste(blocks[!present], collapse = ""))
}

#' Parse Markdown frontmatter
#'
#' Reads the YAML block between `---` lines at the top of a Markdown file.
#' Warns and returns empty `meta` if the YAML can't be parsed.
#'
#' @param path Path to a Markdown file
#' @return List with `meta` (list) and `body` (character)
#' @keywords internal
parse_markdown_frontmatter <- function(path) {
  lines <- readLines(path, warn = FALSE)
  if (length(lines) == 0) {
    return(list(meta = list(), body = ""))
  }

  if (trimws(lines[1]) != "---") {
    return(list(meta = list(), body = paste(lines, collapse = "\n")))
  }

  end_idx <- which(trimws(lines[-1]) == "---")
  if (length(end_idx) == 0) {
    return(list(meta = list(), body = paste(lines, collapse = "\n")))
  }

  # Adjust for offset (lines[-1])
  end_idx <- end_idx[1] + 1
  meta_lines <- lines[2:(end_idx - 1)]
  body_lines <- lines[(end_idx + 1):length(lines)]

  rlang::check_installed("yaml", reason = "to parse skill YAML frontmatter")
  meta <- tryCatch(
    yaml::read_yaml(text = paste(meta_lines, collapse = "\n")),
    error = function(e) {
      cli::cli_warn(c(
        "Failed to parse YAML frontmatter in {.path {path}}",
        "x" = e$message
      ))
      list()
    }
  )

  list(
    meta = meta %||% list(),
    body = paste(body_lines, collapse = "\n")
  )
}

agent_load_skill <- function(
  self,
  private,
  skill,
  allow_conflicts = FALSE,
  call = rlang::caller_env()
) {
  check_conversation_lease(self, NULL)
  if (is.character(skill)) {
    # Load from path
    skill <- skill_load(skill)
  }

  if (!S7::S7_inherits(skill, Skill)) {
    cli_abort(
      "{.arg skill} must be a Skill object or path to a skill directory",
      call = call
    )
  }

  # Get current provider for validation
  current_provider <- tryCatch(
    {
      provider_info <- self$provider()
      # provider() returns a list with name and model
      provider_info$name
    },
    error = function(e) {
      # Log unexpected errors (not just "no provider configured")
      if (!grepl("no provider|not configured", e$message, ignore.case = TRUE)) {
        cli_warn(c(
          "Could not determine provider for skill validation",
          "x" = e$message,
          "i" = "Provider compatibility check will be skipped"
        ))
      }
      NULL
    }
  )

  # Check requirements with provider
  req_check <- skill_check_requirements(skill, current_provider)

  # Report missing packages
  if (length(req_check$missing) > 0) {
    cli_warn(c(
      "Loading skill with missing packages: {.val {skill$name}}",
      "x" = "Missing: {.val {req_check$missing}}"
    ))
  }

  # Report provider mismatch
  if (isTRUE(req_check$provider_mismatch)) {
    required <- paste(req_check$required_providers, collapse = ", ")
    cli_warn(c(
      "Skill {.val {skill$name}} may not work optimally with current provider",
      "i" = "Current provider: {.val {current_provider}}",
      "i" = "Skill requires: {.val {required}}",
      "!" = "Some features may not work as expected"
    ))
  }

  # Register tools with conflict detection
  if (length(skill$tools) > 0) {
    current_tools <- private$.chat$get_tools()
    current_tool_names <- names(current_tools)

    new_tool_names <- vapply(
      skill$tools,
      function(tool) tool@name,
      character(1)
    )

    conflicts <- new_tool_names[new_tool_names %in% current_tool_names]
    if (length(conflicts) > 0) {
      if (isTRUE(allow_conflicts)) {
        cli_warn(c(
          "Skill {.val {skill$name}} overwrites existing tool(s)",
          "!" = "Conflicting tools: {.val {conflicts}}",
          "i" = "Previous definitions will be replaced"
        ))
      } else {
        cli_abort(
          c(
            "Skill {.val {skill$name}} conflicts with existing tool(s)",
            "!" = "Conflicting tools: {.val {conflicts}}",
            "i" = "Use {.code allow_conflicts = TRUE} to overwrite existing tools"
          ),
          call = call
        )
      }
    }

    self$register_tools(skill$tools, replace = allow_conflicts)
  }

  # Append prompt to system prompt
  if (!is.null(skill$prompt) && nchar(skill$prompt) > 0) {
    current_prompt <- private$.chat$get_system_prompt() %||% ""
    new_prompt <- paste0(current_prompt, skill_prompt_block(skill))
    private$.conversation_state$set_prompt(
      private$.chat,
      new_prompt,
      reconcile = FALSE
    )
  }

  # Store reference to loaded skill
  if (is.null(private$loaded_skills)) {
    private$loaded_skills <- list()
  }
  private$loaded_skills[[skill$name]] <- NULL
  private$loaded_skills[[skill$name]] <- skill

  cli_alert_success("Loaded skill: {.val {skill$name}}")
  invisible(self)
}
