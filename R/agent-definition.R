#' @include value-properties.R
NULL

# Agent definition values and routing normalization

normalize_agent_definition_name <- function(name, arg = "name") {
  if (!is_nonempty_string(name)) {
    cli_abort("{.arg {arg}} must be one non-empty string")
  }

  name <- tolower(trimws(name))
  if (!grepl("^[a-z][a-z0-9_-]*$", name)) {
    cli_abort(c(
      "{.arg {arg}} must be a valid AgentDefinition routing key",
      "i" = paste(
        "Use a letter first, followed only by lowercase letters, numbers,",
        "underscores, or hyphens."
      )
    ))
  }

  name
}

validate_agent_definition_text <- function(value, arg, optional = FALSE) {
  if (is.null(value) && optional) {
    return(NULL)
  }
  if (!is_nonempty_string(value)) {
    cli_abort("{.arg {arg}} must be one non-empty string")
  }
  value
}

validate_agent_definition_character <- function(
  value,
  arg,
  optional = TRUE,
  normalize = FALSE
) {
  if (is.null(value) && optional) {
    return(NULL)
  }
  if (
    !is.character(value) ||
      anyNA(value) ||
      !all(nzchar(trimws(value)))
  ) {
    cli_abort("{.arg {arg}} must be a character vector of non-empty strings")
  }

  value <- trimws(value)
  if (normalize) {
    value <- tolower(value)
  }
  unique(value)
}

copy_agent_definition <- function(definition, arg = "definition") {
  if (!S7::S7_inherits(definition, AgentDefinition)) {
    cli_abort("{.arg {arg}} must be an AgentDefinition object")
  }

  fields <- setdiff(names(formals(agent_definition)), "...")
  do.call(agent_definition, S7::props(definition)[fields])
}

normalize_agent_definitions <- function(definitions, arg = "sub_agents") {
  if (!is.list(definitions)) {
    cli_abort("{.arg {arg}} must be a list of AgentDefinition objects")
  }

  definitions <- lapply(
    seq_along(definitions),
    function(index) {
      copy_agent_definition(
        definitions[[index]],
        arg = paste0(arg, "[[", index, "]]")
      )
    }
  )
  keys <- vapply(
    definitions,
    function(definition) definition$name,
    character(1)
  )
  duplicate_keys <- unique(keys[duplicated(keys)])
  if (length(duplicate_keys) > 0) {
    cli_abort(c(
      "Duplicate AgentDefinition routing keys are not allowed",
      "x" = "Duplicated: {.val {duplicate_keys}}"
    ))
  }

  stats::setNames(definitions, keys)
}

#' Define a subagent
#'
#' @description
#' Describe a subagent that a [LeadAgent] can delegate to: its name, a
#' description the lead's model reads when choosing, a system prompt, tools
#' and other settings. Each delegation creates a new subagent from the
#' definition.
#'
#' @param name Name used to select the subagent. It is trimmed and
#'   lowercased, and must start with a letter followed by letters, numbers,
#'   underscores or hyphens.
#' @param description What the subagent does. The lead's model reads it when
#'   choosing where to delegate.
#' @param prompt System prompt for the subagent.
#' @param tools List of tools for the subagent. It doesn't inherit the lead's
#'   tools.
#' @param model Model to use. `"inherit"` (the default) uses a copy of the
#'   lead's chat. A bare model id such as `"gpt-6-luna"` keeps the lead's
#'   provider and credentials but switches the model. A `"provider/model"`
#'   string such as `"anthropic/claude-sonnet-5"` creates a new chat with
#'   [ellmer::chat()].
#' @param skills List of [Skill] objects or skill directory paths to load.
#' @param disallowed_tools Names of tools to remove from the subagent,
#'   including tools from skills. Case is ignored.
#' @param memory Notes appended to the subagent's system prompt under a
#'   "Memory" heading.
#' @param mcp_servers Names of MCP servers the subagent needs. Deputy doesn't
#'   connect to them: such a definition needs a [DelegationPolicy] with
#'   `resource_mode = "owned"`, whose `resources` function creates the MCP
#'   tools.
#' @param initial_prompt Text sent ahead of every task delegated to this
#'   subagent.
#' @param max_requests Maximum model requests per delegation. The remaining
#'   budget of the lead's run also applies.
#' @param permission_mode Permission mode for the subagent; defaults to the
#'   lead's. It can otherwise only be `"readonly"`, unless the lead's mode is
#'   `"full"`. Use `disallowed_tools` and `max_requests` for finer limits.
#'
#' @details
#' An `AgentDefinition` is read-only; read its fields with `$`. To change a
#' field, build a new definition from `S7::props()`, as in the examples.
#' `agent_definition()` and `AgentDefinition()` are the same function.
#'
#' Tools and skills are stored as given, not copied, so a tool that keeps
#' state in its closure shares that state wherever the definition is used. To
#' save a definition as YAML, use [agent_definition_write()] and
#' [agent_definition_read()].
#' @name agent_definition
#' @return An `AgentDefinition` object.
#'
#' @examples
#' # Define a code review agent
#' code_reviewer <- agent_definition(
#'   name = "code_reviewer",
#'   description = "Reviews code for bugs, style issues, and best practices",
#'   prompt = "You are an expert code reviewer...",
#'   tools = list(tool_read_file, tool_list_files)
#' )
#'
#' code_reviewer$name
#' fields <- S7::props(code_reviewer)
#' fields$max_requests <- 3L
#' do.call(agent_definition, fields)
#'
#' \dontrun{
#' # Use with a lead agent
#' lead <- LeadAgent$new(
#'   chat = ellmer::chat("openai/gpt-6-luna"),
#'   sub_agents = list(code_reviewer)
#' )
#' }
#'
#' @export
AgentDefinition <- S7::new_class(
  "AgentDefinition",
  package = "deputy",
  properties = list(
    name = readonly_property("name", S7::class_character),
    description = readonly_property("description", S7::class_character),
    prompt = readonly_property("prompt", S7::class_character),
    tools = readonly_property("tools", S7::class_list),
    model = readonly_property("model", S7::class_character),
    skills = readonly_property("skills", S7::class_list),
    disallowed_tools = readonly_property(
      "disallowed_tools",
      S7::new_union(NULL, S7::class_character)
    ),
    memory = readonly_property(
      "memory",
      S7::new_union(NULL, S7::class_character)
    ),
    mcp_servers = readonly_property(
      "mcp_servers",
      S7::new_union(NULL, S7::class_character)
    ),
    initial_prompt = readonly_property(
      "initial_prompt",
      S7::new_union(NULL, S7::class_character)
    ),
    max_requests = readonly_property(
      "max_requests",
      S7::new_union(NULL, S7::class_integer)
    ),
    permission_mode = readonly_property(
      "permission_mode",
      S7::new_union(NULL, S7::class_character)
    )
  ),
  constructor = function(
    name,
    description,
    prompt,
    tools = list(),
    model = "inherit",
    skills = list(),
    disallowed_tools = NULL,
    memory = NULL,
    mcp_servers = NULL,
    initial_prompt = NULL,
    max_requests = NULL,
    permission_mode = NULL
  ) {
    name <- normalize_agent_definition_name(name)
    description <- validate_agent_definition_text(description, "description")
    prompt <- validate_agent_definition_text(prompt, "prompt")
    model <- validate_agent_definition_text(model, "model")
    if (!is.list(tools)) {
      cli_abort("{.arg tools} must be a list")
    }
    if (!is.list(skills)) {
      cli_abort("{.arg skills} must be a list")
    }
    disallowed_tools <- validate_agent_definition_character(
      disallowed_tools,
      "disallowed_tools",
      normalize = TRUE
    )
    memory <- validate_agent_definition_character(memory, "memory")
    mcp_servers <- validate_agent_definition_character(
      mcp_servers,
      "mcp_servers"
    )
    initial_prompt <- validate_agent_definition_text(
      initial_prompt,
      "initial_prompt",
      optional = TRUE
    )
    if (!is.null(permission_mode)) {
      permission_mode <- validate_permission_mode_value(
        permission_mode,
        arg = "permission_mode"
      )
    }
    if (!is.null(max_requests)) {
      max_requests <- validate_usage_limit(
        max_requests,
        "max_requests",
        integer = TRUE
      )
    }

    value <- S7::new_object(
      S7::S7_object(),
      name = name,
      description = description,
      prompt = prompt,
      tools = tools,
      model = model,
      skills = skills,
      disallowed_tools = disallowed_tools,
      memory = memory,
      mcp_servers = mcp_servers,
      initial_prompt = initial_prompt,
      max_requests = max_requests,
      permission_mode = permission_mode
    )
    freeze_value(value)
  }
)

#' @rdname agent_definition
#' @export
agent_definition <- AgentDefinition

local({
  S7::method(`$`, AgentDefinition) <- function(x, name) S7::prop(x, name)
})

S7::method(print, AgentDefinition) <- function(x, ...) {
  cli::cat_line(cli::cli_format_method({
    cli::cli_text("<AgentDefinition: {x$name} >")
    cli::cli_div(theme = list(div = list("margin-left" = 2)))
    cli::cli_text("description: {truncate_string(x$description, 60)}")
    cli::cli_text("tools: {length(x$tools)}")
    cli::cli_text("skills: {length(x$skills)}")
    cli::cli_text("model: {x$model}")
    if (!is.null(x$permission_mode)) {
      cli::cli_text("permission_mode: {x$permission_mode}")
    }
  }))
  invisible(x)
}
