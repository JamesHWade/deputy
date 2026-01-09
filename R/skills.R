# Skill loading system for deputy agents

#' Normalize provider name for comparison
#'
#' @param provider Provider name (e.g., "openai", "OpenAI", "anthropic")
#' @return Lowercase normalized provider name, or NA_character_ if invalid
#' @keywords internal
normalize_provider_name <- function(provider) {
  if (is.null(provider) || !is.character(provider) || length(provider) != 1) {
    return(NA_character_)
  }

  # Convert to lowercase
  provider <- tolower(provider)

  # Handle common variations
  provider <- switch(
    provider,
    "openai" = "openai",
    "chat_openai" = "openai",
    "gpt" = "openai",
    "gpt-4" = "openai",
    "gpt-4o" = "openai",
    "anthropic" = "anthropic",
    "chat_anthropic" = "anthropic",
    "claude" = "anthropic",
    "google" = "google",
    "chat_google" = "google",
    "gemini" = "google",
    "ollama" = "ollama",
    "chat_ollama" = "ollama",
    "azure" = "azure",
    "chat_azure" = "azure",
    "bedrock" = "bedrock",
    "chat_bedrock" = "bedrock",
    "vllm" = "vllm",
    "chat_vllm" = "vllm",
    "openrouter" = "openrouter",
    "chat_openrouter" = "openrouter",
    "groq" = "groq",
    "chat_groq" = "groq",
    # Default: return as-is
    provider
  )

  provider
}

#' Skill R6 Class
#'
#' @description
#' Represents a skill that can be loaded into an agent. Skills bundle together
#' a system prompt extension, tools, and metadata about requirements.
#'
#' @export
Skill <- R6::R6Class(
  "Skill",

  public = list(
    #' @field name Skill name
    name = NULL,

    #' @field version Skill version
    version = NULL,

    #' @field description Brief description of the skill
    description = NULL,

    #' @field prompt System prompt extension (from SKILL.md)
    prompt = NULL,

    #' @field tools List of tools provided by this skill
    tools = NULL,

    #' @field requires Requirements (packages, providers)
    requires = NULL,

    #' @field path Path to the skill directory
    path = NULL,

    #' @description
    #' Create a new Skill object.
    #'
    #' @param name Skill name
    #' @param version Skill version (default: "0.0.0")
    #' @param description Brief description
    #' @param prompt System prompt extension
    #' @param tools List of tools
    #' @param requires List of requirements
    #' @param path Path to skill directory
    #' @return A new `Skill` object
    initialize = function(
      name,
      version = "0.0.0",
      description = NULL,
      prompt = NULL,
      tools = list(),
      requires = list(),
      path = NULL
    ) {
      self$name <- name
      self$version <- version
      self$description <- description
      self$prompt <- prompt
      self$tools <- tools
      self$requires <- requires
      self$path <- path
    },

    #' @description
    #' Check if skill requirements are met.
    #'
    #' @param current_provider Optional current provider name for validation
    #' @return List with `ok` (logical), `missing` (character vector), and
    #'   `provider_mismatch` (logical)
    check_requirements = function(current_provider = NULL) {
      missing <- character()
      provider_mismatch <- FALSE
      mismatched_provider <- NULL

      # Check required packages
      if (!is.null(self$requires$packages)) {
        for (pkg in self$requires$packages) {
          if (!rlang::is_installed(pkg)) {
            missing <- c(missing, paste0("package:", pkg))
          }
        }
      }

      # Check provider requirements if current_provider is specified
      if (!is.null(current_provider) && !is.null(self$requires$providers)) {
        required_providers <- self$requires$providers
        if (length(required_providers) > 0) {
          # Normalize provider name for comparison
          normalized_provider <- normalize_provider_name(current_provider)

          # Only check if we could normalize the provider name
          if (!is.na(normalized_provider)) {
            # Check if current provider is in the required list
            normalized_required <- vapply(
              required_providers,
              normalize_provider_name,
              character(1),
              USE.NAMES = FALSE
            )
            # Remove any NULLs that became NA
            normalized_required <- normalized_required[!is.na(normalized_required)]

            if (length(normalized_required) > 0 &&
              !normalized_provider %in% normalized_required) {
              provider_mismatch <- TRUE
              mismatched_provider <- current_provider
            }
          }
        }
      }

      list(
        ok = length(missing) == 0 && !provider_mismatch,
        missing = missing,
        provider_mismatch = provider_mismatch,
        current_provider = current_provider,
        required_providers = self$requires$providers
      )
    },

    #' @description
    #' Print the skill.
    print = function() {
      cat("<Skill:", self$name, ">\n")
      cat("  version:", self$version, "\n")
      if (!is.null(self$description)) {
        cat("  description:", truncate_string(self$description, 60), "\n")
      }
      cat("  tools:", length(self$tools), "\n")
      if (length(self$tools) > 0) {
        tool_names <- sapply(self$tools, function(t) t@name)
        cat("    ", paste(tool_names, collapse = ", "), "\n")
      }
      if (!is.null(self$prompt)) {
        cat("  prompt:", nchar(self$prompt), "chars\n")
      }
      if (!is.null(self$path)) {
        cat("  path:", self$path, "\n")
      }
      invisible(self)
    }
  )
)

#' Load a skill from a directory
#'
#' @description
#' Loads a skill from a directory containing `SKILL.yaml` (metadata) and
#' optionally `SKILL.md` (system prompt extension).
#'
#' @param path Path to the skill directory
#' @param check_requirements If TRUE (default), verify requirements are met
#' @return A [Skill] object
#'
#' @details
#' The skill directory should contain:
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
#' **SKILL.md** (optional):
#' Markdown content that will be appended to the agent's system prompt
#' when this skill is loaded.
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

  # Check for SKILL.yaml

  yaml_path <- file.path(path, "SKILL.yaml")
  if (!file.exists(yaml_path)) {
    # Also check for skill.yaml (lowercase)
    yaml_path <- file.path(path, "skill.yaml")
    if (!file.exists(yaml_path)) {
      cli_abort(c(
        "Skill directory must contain SKILL.yaml",
        "x" = "Not found in: {.path {path}}"
      ))
    }
  }

  # Parse YAML
  if (!rlang::is_installed("yaml")) {
    cli_abort(c(
      "Package {.pkg yaml} is required to load skills",
      "i" = "Install with: {.code install.packages('yaml')}"
    ))
  }

  meta <- yaml::read_yaml(yaml_path)

  # Validate required fields
  if (is.null(meta$name)) {
    cli_abort("SKILL.yaml must contain a 'name' field")
  }

  # Load SKILL.md if present
  prompt <- NULL
  md_path <- file.path(path, "SKILL.md")
  if (!file.exists(md_path)) {
    md_path <- file.path(path, "skill.md")
  }
  if (file.exists(md_path)) {
    prompt <- paste(readLines(md_path, warn = FALSE), collapse = "\n")
  }

  # Load tools if specified
  tools <- list()
  if (!is.null(meta$tools) && length(meta$tools) > 0) {
    tools <- load_skill_tools(path, meta$tools)
  }

  # Create skill object
  skill <- Skill$new(
    name = meta$name,
    version = meta$version %||% "0.0.0",
    description = meta$description,
    prompt = prompt,
    tools = tools,
    requires = meta$requires %||% list(),
    path = path
  )

  # Check requirements if requested
  if (check_requirements) {
    req_check <- skill$check_requirements()
    if (!req_check$ok) {
      cli_warn(c(
        "Skill {.val {skill$name}} has unmet requirements",
        "x" = "Missing: {.val {req_check$missing}}"
      ))
    }
  }

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
  Skill$new(
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

  # Find subdirectories with SKILL.yaml
  subdirs <- list.dirs(path, recursive = FALSE, full.names = TRUE)
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

    if (file.exists(yaml_path)) {
      # Try to get the name from YAML
      name <- basename(dir)
      tryCatch(
        {
          if (rlang::is_installed("yaml")) {
            meta <- yaml::read_yaml(yaml_path)
            name <- meta$name %||% basename(dir)
          }
        },
        error = function(e) {
          cli_warn(c(
            "Failed to parse SKILL.yaml in {.path {dir}}",
            "x" = e$message,
            "i" = "Using directory name as skill name"
          ))
        }
      )

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

  skills
}

# Add load_skill method to Agent class
# This is added here to keep skill-related code together
# Note: These methods are dynamically added and documented in the Agent class

Agent$set("public", "load_skill", function(skill) {
  if (is.character(skill)) {
    # Load from path
    skill <- skill_load(skill)
  }

  if (!inherits(skill, "Skill")) {
    cli_abort(
      "{.arg skill} must be a Skill object or path to a skill directory"
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
  req_check <- skill$check_requirements(current_provider)

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
    # Get current tool names to detect conflicts
    current_tools <- self$chat$get_tools()
    current_tool_names <- names(current_tools)

    # Get names of tools being registered
    new_tool_names <- vapply(
      skill$tools,
      function(t) {
        # Handle both S7 (@ access) and list-style tools
        tryCatch(
          t@name,
          error = function(e1) {
            tryCatch(
              t$name %||% {
                cli_warn("Could not determine tool name for conflict detection")
                "unknown"
              },
              error = function(e2) {
                cli_warn(c(
                  "Failed to extract tool name",
                  "x" = e1$message
                ))
                "unknown"
              }
            )
          }
        )
      },
      character(1)
    )

    # Check for conflicts
    conflicts <- new_tool_names[new_tool_names %in% current_tool_names]
    if (length(conflicts) > 0) {
      cli_warn(c(
        "Skill {.val {skill$name}} overwrites existing tool(s)",
        "!" = "Conflicting tools: {.val {conflicts}}",
        "i" = "Previous definitions will be replaced"
      ))
    }

    self$chat$register_tools(skill$tools)
  }

  # Append prompt to system prompt
  if (!is.null(skill$prompt) && nchar(skill$prompt) > 0) {
    current_prompt <- self$chat$get_system_prompt() %||% ""
    new_prompt <- paste(
      current_prompt,
      "",
      paste0("# Skill: ", skill$name),
      skill$prompt,
      sep = "\n"
    )
    self$chat$set_system_prompt(new_prompt)
  }

  # Store reference to loaded skill
  if (is.null(private$loaded_skills)) {
    private$loaded_skills <- list()
  }
  private$loaded_skills[[skill$name]] <- skill

  cli_alert_success("Loaded skill: {.val {skill$name}}")
  invisible(self)
})

Agent$set("public", "skills", function() {
  if (is.null(private$loaded_skills)) {
    return(list())
  }
  private$loaded_skills
})
