# Claude Agent SDK-compatible settings loading

#' Load Claude-style settings from settingSources
#'
#' @description
#' Loads Claude-style settings from a list of `setting_sources`, mirroring the
#' Claude Agent SDK behavior. Supports project and user sources, and returns
#' memory, skills, and slash commands discovered in `.claude` directories.
#'
#' Supported sources:
#' - `"project"`: loads project `.claude` settings, skills, commands, and memory
#' - `"user"`: loads `~/.claude` settings, skills, commands, and memory
#' - explicit file paths to `.json` settings files
#'
#' @param setting_sources Character vector of sources, e.g. `c("project", "user")`.
#' @param working_dir Working directory used for project sources.
#'
#' @return A list with `settings`, `memory`, `skills`, `commands`, and metadata.
#' @export
claude_settings_load <- function(setting_sources, working_dir = getwd()) {
  if (is.null(setting_sources) || length(setting_sources) == 0) {
    return(list(
      settings = list(),
      memory = character(),
      skills = list(),
      commands = list(),
      sources = list()
    ))
  }

  sources <- normalize_setting_sources(setting_sources)
  resolved <- resolve_setting_sources(sources, working_dir)

  settings <- load_settings_files(resolved$settings_files)
  memory <- load_memory_files(resolved$memory_files)
  skills <- load_skills_from_dirs(resolved$skill_dirs)
  commands <- load_commands_from_dirs(resolved$command_dirs)

  list(
    settings = settings,
    memory = memory,
    skills = skills,
    commands = commands,
    sources = resolved
  )
}

#' Apply Claude-style settings to an Agent
#'
#' @description
#' Applies settings loaded by [claude_settings_load()] to an [Agent], including
#' memory injection, skill loading, and slash command registration.
#'
#' @param agent An [Agent] object.
#' @param settings Settings list returned by [claude_settings_load()].
#' @param apply_memory Logical. If TRUE (default), append memory to system prompt.
#' @param load_skills Logical. If TRUE (default), load skills into the agent.
#' @param load_commands Logical. If TRUE (default), register slash commands.
#'
#' @return Invisibly returns the agent.
#' @export
claude_settings_apply <- function(
  agent,
  settings,
  apply_memory = TRUE,
  load_skills = TRUE,
  load_commands = TRUE
) {
  if (!inherits(agent, "Agent")) {
    cli::cli_abort("{.arg agent} must be an Agent object")
  }

  if (is.null(settings) || !is.list(settings)) {
    cli::cli_abort("{.arg settings} must be a list from claude_settings_load()")
  }

  # Append memory to system prompt
  if (isTRUE(apply_memory) && length(settings$memory) > 0) {
    current_prompt <- agent$chat$get_system_prompt() %||% ""
    memory_block <- paste(settings$memory, collapse = "\n\n")
    new_prompt <- paste(
      current_prompt,
      "",
      "# Memory",
      memory_block,
      sep = "\n"
    )
    agent$chat$set_system_prompt(new_prompt)
  }

  # Load skills
  if (isTRUE(load_skills) && length(settings$skills) > 0) {
    for (skill in settings$skills) {
      agent$load_skill(skill, allow_conflicts = TRUE)
    }
  }

  # Register slash commands
  if (isTRUE(load_commands) && length(settings$commands) > 0) {
    if (is.null(agent$.__enclos_env__$private$slash_commands_data)) {
      agent$.__enclos_env__$private$slash_commands_data <- list()
    }
    agent$.__enclos_env__$private$slash_commands_data <- merge_named_lists(
      agent$.__enclos_env__$private$slash_commands_data,
      settings$commands
    )
  }

  # Store settings for inspection
  agent$.__enclos_env__$private$settings_data <- settings

  invisible(agent)
}

# Normalize settingSources input
normalize_setting_sources <- function(setting_sources) {
  if (!is.character(setting_sources)) {
    cli::cli_abort("{.arg setting_sources} must be a character vector")
  }
  trimws(setting_sources[setting_sources != ""])
}

# Resolve settingSources into concrete paths
resolve_setting_sources <- function(setting_sources, working_dir) {
  settings_files <- character()
  memory_files <- character()
  skill_dirs <- character()
  command_dirs <- character()

  working_dir <- normalizePath(working_dir, mustWork = TRUE)
  user_root <- path.expand("~/.claude")

  for (src in setting_sources) {
    if (identical(src, "project")) {
      settings_files <- c(
        settings_files,
        file.path(working_dir, ".claude", "settings.json"),
        file.path(working_dir, ".claude", "settings.local.json")
      )
      memory_files <- c(
        memory_files,
        file.path(working_dir, "CLAUDE.md"),
        file.path(working_dir, ".claude", "CLAUDE.md")
      )
      skill_dirs <- c(skill_dirs, file.path(working_dir, ".claude", "skills"))
      command_dirs <- c(
        command_dirs,
        file.path(working_dir, ".claude", "commands")
      )
      next
    }

    if (identical(src, "user")) {
      settings_files <- c(settings_files, file.path(user_root, "settings.json"))
      memory_files <- c(memory_files, file.path(user_root, "CLAUDE.md"))
      skill_dirs <- c(skill_dirs, file.path(user_root, "skills"))
      command_dirs <- c(command_dirs, file.path(user_root, "commands"))
      next
    }

    # Explicit file path (settings.json)
    settings_files <- c(settings_files, expand_and_normalize(src))
  }

  list(
    settings_files = unique(stats::na.omit(settings_files)),
    memory_files = unique(stats::na.omit(memory_files)),
    skill_dirs = unique(stats::na.omit(skill_dirs)),
    command_dirs = unique(stats::na.omit(command_dirs))
  )
}

# Load and merge settings.json files
load_settings_files <- function(paths) {
  settings <- list()
  if (length(paths) == 0) {
    return(settings)
  }

  if (!rlang::is_installed("jsonlite")) {
    cli::cli_warn(c(
      "Package {.pkg jsonlite} is required to parse settings.json files",
      "i" = "Install with: {.code install.packages('jsonlite')}",
      "i" = "Skipping settings.json parsing"
    ))
    return(settings)
  }

  for (path in paths) {
    if (!file.exists(path)) {
      next
    }
    parsed <- tryCatch(
      jsonlite::fromJSON(path, simplifyVector = FALSE),
      error = function(e) {
        cli::cli_warn(c(
          "Failed to parse settings.json",
          "x" = e$message,
          "i" = "Path: {.path {path}}"
        ))
        NULL
      }
    )
    if (!is.null(parsed)) {
      settings <- merge_named_lists(settings, parsed)
    }
  }

  settings
}

# Load memory files (CLAUDE.md)
load_memory_files <- function(paths) {
  memory <- character()
  for (path in paths) {
    if (!file.exists(path)) {
      next
    }
    contents <- paste(readLines(path, warn = FALSE), collapse = "\n")
    if (nchar(trimws(contents)) > 0) {
      memory <- c(
        memory,
        paste0("<!-- ", basename(path), " -->\n", contents)
      )
    }
  }
  memory
}

# Load skills from directories
load_skills_from_dirs <- function(dirs) {
  skills <- list()
  for (dir in dirs) {
    if (!dir.exists(dir)) {
      next
    }
    entries <- list.files(dir, full.names = TRUE)
    if (length(entries) == 0) {
      next
    }

    for (entry in entries) {
      if (dir.exists(entry)) {
        skill_path <- entry
      } else if (grepl("\\.md$", entry, ignore.case = TRUE)) {
        skill_path <- entry
      } else {
        next
      }

      skill <- tryCatch(
        skill_load(skill_path, check_requirements = FALSE),
        error = function(e) {
          cli::cli_warn(c(
            "Failed to load skill from {.path {skill_path}}",
            "x" = e$message
          ))
          NULL
        }
      )
      if (!is.null(skill)) {
        skills[[skill$name]] <- skill
      }
    }
  }
  skills
}

# Load slash commands from directories
load_commands_from_dirs <- function(dirs) {
  commands <- list()
  for (dir in dirs) {
    if (!dir.exists(dir)) {
      next
    }
    files <- list.files(dir, pattern = "\\.md$", full.names = TRUE)
    for (path in files) {
      cmd <- tryCatch(
        load_slash_command(path),
        error = function(e) {
          cli::cli_warn(c(
            "Failed to load slash command from {.path {path}}",
            "x" = e$message
          ))
          NULL
        }
      )
      if (!is.null(cmd)) {
        commands[[cmd$name]] <- cmd
        if (!is.null(cmd$aliases) && length(cmd$aliases) > 0) {
          for (alias in cmd$aliases) {
            commands[[alias]] <- cmd
          }
        }
      }
    }
  }
  commands
}

# Parse a slash command markdown file
load_slash_command <- function(path) {
  parsed <- parse_markdown_frontmatter(path)
  meta <- parsed$meta
  body <- parsed$body

  name <- meta$name %||% tools::file_path_sans_ext(basename(path))
  description <- meta$description %||% ""
  aliases <- meta$aliases %||% character()

  list(
    name = name,
    description = description,
    prompt = body,
    aliases = aliases,
    source = path
  )
}

# Merge two named lists, with right-hand list taking precedence
merge_named_lists <- function(x, y) {
  if (is.null(x) || length(x) == 0) {
    return(y %||% list())
  }
  if (is.null(y) || length(y) == 0) {
    return(x)
  }

  out <- x
  for (nm in names(y)) {
    if (
      is.list(out[[nm]]) &&
        is.list(y[[nm]]) &&
        !is.null(names(out[[nm]])) &&
        !is.null(names(y[[nm]]))
    ) {
      out[[nm]] <- merge_named_lists(out[[nm]], y[[nm]])
    } else {
      out[[nm]] <- y[[nm]]
    }
  }
  out
}
