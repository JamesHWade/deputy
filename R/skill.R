#' @include value-properties.R
NULL

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
  switch(
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
    NA_character_
  )
}

# Compare known provider aliases while preserving exact matching for generic
# providers supported by ellmer::chat().
provider_requirement_key <- function(provider) {
  normalized <- normalize_provider_name(provider)
  if (!is.na(normalized)) {
    return(paste0("known:", normalized))
  }
  if (!is_nonempty_string(provider)) {
    return(NA_character_)
  }

  paste0("generic:", tolower(provider))
}

validate_skill_text <- function(value, arg, optional = FALSE) {
  if (is.null(value) && optional) {
    return(value)
  }
  if (!rlang::is_string(value) || (!optional && !nzchar(trimws(value)))) {
    cli_abort(
      "{.arg {arg}} must be one {if (optional) '' else 'non-empty '}string"
    )
  }
  value
}

validate_skill_requirements <- function(requires) {
  if (!is.list(requires)) {
    cli_abort("{.arg requires} must be a list")
  }
  if (length(requires) == 0L) {
    return(requires)
  }
  keys <- names(requires)
  if (
    is.null(keys) ||
      anyNA(keys) ||
      anyDuplicated(keys) ||
      !all(nzchar(keys))
  ) {
    cli_abort(
      "{.arg requires} must have unique non-empty names"
    )
  }
  validate_skill_requirement_data(requires)
  for (key in intersect(keys, c("packages", "providers"))) {
    value <- requires[[key]]
    valid <- is.null(value) ||
      ((is.character(value) || is.list(value)) &&
        all(vapply(value, is_nonempty_string, logical(1))))
    if (!valid) {
      cli_abort("{.arg requires${key}} must contain non-empty strings")
    }
  }
  requires
}

validate_skill_requirement_data <- function(value) {
  if (is.null(value) || is.atomic(value)) {
    return(invisible(NULL))
  }
  if (!is.list(value)) {
    cli_abort(
      "{.arg requires} must contain only declarative data, not executable or reference objects"
    )
  }
  for (element in value) {
    validate_skill_requirement_data(element)
  }
  invisible(NULL)
}

#' Reusable instructions and tools
#'
#' @description
#' A skill bundles extra system prompt text, tools, and the packages and
#' providers it needs, so you can add them to an [Agent] in one step with
#' `agent$load_skill(skill)`.
#'
#' @param name Skill name.
#' @param version Version string. Defaults to `"0.0.0"` ([skill_create()]
#'   defaults to `"1.0.0"`).
#' @param description Optional description.
#' @param prompt Optional text to add to the system prompt.
#' @param tools List of tools created with `ellmer::tool()`.
#' @param requires List with optional `packages` and `providers` entries, each
#'   a character vector. Other entries are kept but not checked. It must hold
#'   only plain data, not functions or environments.
#' @param path Optional path to the skill directory. It is recorded, not read.
#'
#' @details
#' Create skills with `Skill()`, [skill_create()], or [skill_load()]. Skills
#' are read-only: read fields with `$`, and to change one, edit
#' `S7::props(skill)` and pass the list back to `Skill()` with `do.call()`, as
#' in the example.
#'
#' Tools are stored as given, not copied, so any state they hold is shared
#' with the originals. Creating a skill or checking its requirements never runs
#' tool code; [skill_load()] runs the R files a skill's tools come from.
#'
#' @return A read-only `Skill` S7 object.
#' @examples
#' concise <- Skill("concise", prompt = "Answer in one short paragraph.")
#' fields <- S7::props(concise)
#' fields$prompt <- "Answer in one sentence."
#' shorter <- do.call(Skill, fields)
#' shorter$prompt
#' concise$prompt
#' skill_check_requirements(concise)$ok
#' @export
Skill <- S7::new_class(
  "Skill",
  package = "deputy",
  properties = list(
    name = readonly_property("name", S7::class_character),
    version = readonly_property("version", S7::class_character),
    description = readonly_property(
      "description",
      S7::new_union(NULL, S7::class_character)
    ),
    prompt = readonly_property(
      "prompt",
      S7::new_union(NULL, S7::class_character)
    ),
    tools = readonly_property("tools", S7::class_list),
    requires = readonly_property("requires", S7::class_list),
    path = readonly_property("path", S7::new_union(NULL, S7::class_character))
  ),
  constructor = function(
    name,
    version = "0.0.0",
    description = NULL,
    prompt = NULL,
    tools = list(),
    requires = list(),
    path = NULL
  ) {
    name <- validate_skill_text(name, "name")
    version <- validate_skill_text(version, "version")
    description <- validate_skill_text(
      description,
      "description",
      optional = TRUE
    )
    prompt <- validate_skill_text(prompt, "prompt", optional = TRUE)
    path <- validate_skill_text(path, "path", optional = TRUE)
    if (!is.list(tools)) {
      cli_abort("{.arg tools} must be a list")
    }
    requires <- validate_skill_requirements(requires)
    value <- S7::new_object(
      S7::S7_object(),
      name = name,
      version = version,
      description = description,
      prompt = prompt,
      tools = tools,
      requires = requires,
      path = path
    )
    freeze_value(value)
  }
)

local({
  S7::method(`$`, Skill) <- function(x, name) S7::prop(x, name)
})

#' Check a skill's requirements
#'
#' @description
#' Checks whether the packages a [Skill] needs are installed and, if you give
#' `current_provider`, whether the skill supports that provider. Nothing is
#' installed, loaded or run.
#'
#' @param skill A [Skill].
#' @param current_provider Optional provider name, such as `"openai"` or
#'   `"anthropic"`. Common aliases match their provider (`"claude"` and
#'   `"chat_anthropic"` both mean `"anthropic"`); other names must match
#'   exactly, ignoring case. `NULL` skips the provider check.
#' @return A list with `ok` (`TRUE` if nothing is missing or mismatched),
#'   `missing` (such as `"package:readr"`), `provider_mismatch`,
#'   `current_provider`, and `required_providers`.
#' @examples
#' skill <- Skill("calculator", requires = list(packages = "stats"))
#' skill_check_requirements(skill)
#' @export
skill_check_requirements <- function(skill, current_provider = NULL) {
  if (!S7::S7_inherits(skill, Skill)) {
    cli_abort("{.arg skill} must be a Skill object")
  }
  missing <- character()
  provider_mismatch <- FALSE
  required_packages <- skill$requires[["packages"]]
  required_providers <- skill$requires[["providers"]]

  # Check required packages
  if (!is.null(required_packages)) {
    for (pkg in required_packages) {
      if (!rlang::is_installed(pkg)) {
        missing <- c(missing, paste0("package:", pkg))
      }
    }
  }

  # Check provider requirements if current_provider is specified
  if (!is.null(current_provider) && !is.null(required_providers)) {
    if (length(required_providers) > 0) {
      provider_key <- provider_requirement_key(current_provider)
      required_keys <- vapply(
        required_providers,
        provider_requirement_key,
        character(1),
        USE.NAMES = FALSE
      )
      required_keys <- required_keys[!is.na(required_keys)]

      if (
        is.na(provider_key) ||
          length(required_keys) == 0L ||
          !provider_key %in% required_keys
      ) {
        provider_mismatch <- TRUE
      }
    }
  }

  list(
    ok = length(missing) == 0 && !provider_mismatch,
    missing = missing,
    provider_mismatch = provider_mismatch,
    current_provider = current_provider,
    required_providers = required_providers
  )
}

S7::method(print, Skill) <- function(x, ...) {
  cli::cat_line(cli::cli_format_method({
    cli::cli_text("<Skill: {x$name} >")
    cli::cli_div(theme = list(div = list("margin-left" = 2)))
    cli::cli_text("version: {x$version}")
    if (!is.null(x$description)) {
      cli::cli_text("description: {truncate_string(x$description, 60)}")
    }
    cli::cli_text("tools: {length(x$tools)}")
    if (length(x$tools) > 0) {
      tool_names <- vapply(
        x$tools,
        function(tool) {
          name <- tryCatch(tool@name, error = function(e) NULL)
          if (is_nonempty_string(name)) name else "<unnamed>"
        },
        character(1)
      )
      cli::cli_text("{paste(tool_names, collapse = \", \")}")
    }
    if (!is.null(x$prompt)) {
      cli::cli_text("prompt: {nchar(x$prompt)} chars")
    }
    if (!is.null(x$path)) {
      cli::cli_text("path: {x$path}")
    }
  }))
  invisible(x)
}
