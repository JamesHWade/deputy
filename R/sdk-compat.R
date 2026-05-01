# Agent SDK compatibility facade for deputy.

# Default Anthropic model used by the compatibility layer.
default_claude_sdk_model <- function() {
  "anthropic/claude-sonnet-4-5-20250929"
}

# Normalize a model string for ellmer::chat().
normalize_claude_sdk_model <- function(model = NULL) {
  normalized <- model %||% default_claude_sdk_model()
  if (!is.character(normalized) || length(normalized) != 1) {
    cli::cli_abort("{.arg model} must be NULL or a length-1 character string")
  }

  normalized <- trimws(normalized)
  if (!nzchar(normalized)) {
    cli::cli_abort("{.arg model} must not be empty")
  }

  if (!grepl("/", normalized, fixed = TRUE)) {
    normalized <- paste0("anthropic/", normalized)
  }

  normalized
}

# Copy tool annotations from an existing ellmer tool.
tool_annotations_copy <- function(tool) {
  tryCatch(
    tool@annotations,
    error = function(e) ellmer::tool_annotations()
  )
}

# Create a Claude-shaped alias for an existing tool function.
make_tool_alias <- function(fun, name, description, arguments, annotations) {
  ellmer::tool(
    fun = fun,
    name = name,
    description = description,
    arguments = arguments,
    annotations = annotations
  )
}

# Anthropic-compatible tool aliases.
sdk_tool_read <- make_tool_alias(
  fun = function(file_path, pages = NULL) {
    tool_read_file(path = file_path, pages = pages)
  },
  name = "Read",
  description = "Read a file from disk.",
  arguments = list(
    file_path = ellmer::type_string("Path to the file to read"),
    pages = ellmer::type_string(
      "Optional PDF page selector like '1,3-5'. Only valid for PDF files.",
      required = FALSE
    )
  ),
  annotations = tool_annotations_copy(tool_read_file)
)

sdk_tool_write <- make_tool_alias(
  fun = function(file_path, content, append = FALSE) {
    tool_write_file(path = file_path, content = content, append = append)
  },
  name = "Write",
  description = "Write content to a file on disk.",
  arguments = list(
    file_path = ellmer::type_string("Path to the file to write"),
    content = ellmer::type_string("Content to write"),
    append = ellmer::type_boolean(
      "If TRUE, append instead of overwriting. Default is FALSE.",
      required = FALSE
    )
  ),
  annotations = tool_annotations_copy(tool_write_file)
)

sdk_tool_edit <- make_tool_alias(
  fun = function(file_path, old_string, new_string, replace_all = FALSE) {
    tool_edit_file(
      path = file_path,
      old_text = old_string,
      new_text = new_string,
      replace_all = replace_all
    )
  },
  name = "Edit",
  description = "Replace exact text in an existing file.",
  arguments = list(
    file_path = ellmer::type_string("Path to the file to edit"),
    old_string = ellmer::type_string("Existing text to replace"),
    new_string = ellmer::type_string("Replacement text"),
    replace_all = ellmer::type_boolean(
      "If TRUE, replace every occurrence of old_string. Default is FALSE.",
      required = FALSE
    )
  ),
  annotations = tool_annotations_copy(tool_edit_file)
)

sdk_tool_multi_edit <- make_tool_alias(
  fun = function(file_path, edits) {
    tool_multi_edit(path = file_path, edits = edits)
  },
  name = "MultiEdit",
  description = "Apply multiple exact text replacements to a file.",
  arguments = list(
    file_path = ellmer::type_string("Path to the file to edit"),
    edits = ellmer::type_string(
      "JSON array describing edit operations.",
      required = FALSE
    )
  ),
  annotations = tool_annotations_copy(tool_multi_edit)
)

sdk_tool_glob <- make_tool_alias(
  fun = function(pattern, path = ".", recursive = TRUE) {
    tool_glob_files(pattern = pattern, path = path, recursive = recursive)
  },
  name = "Glob",
  description = "Find files matching a glob pattern.",
  arguments = list(
    pattern = ellmer::type_string("Glob pattern to match"),
    path = ellmer::type_string(
      "Base directory to search. Default is current directory.",
      required = FALSE
    ),
    recursive = ellmer::type_boolean(
      "If TRUE, search recursively. Default is TRUE.",
      required = FALSE
    )
  ),
  annotations = tool_annotations_copy(tool_glob_files)
)

sdk_tool_grep <- make_tool_alias(
  fun = function(
    pattern,
    path = ".",
    recursive = TRUE,
    ignore_case = FALSE,
    max_matches = 100
  ) {
    tool_grep_files(
      pattern = pattern,
      path = path,
      recursive = recursive,
      ignore_case = ignore_case,
      max_matches = max_matches
    )
  },
  name = "Grep",
  description = "Search file contents with a regex pattern.",
  arguments = list(
    pattern = ellmer::type_string("Regex pattern to search for"),
    path = ellmer::type_string(
      "Base directory to search. Default is current directory.",
      required = FALSE
    ),
    recursive = ellmer::type_boolean(
      "If TRUE, search recursively. Default is TRUE.",
      required = FALSE
    ),
    ignore_case = ellmer::type_boolean(
      "If TRUE, ignore case while matching. Default is FALSE.",
      required = FALSE
    ),
    max_matches = ellmer::type_integer(
      "Maximum matching lines to return. Default is 100.",
      required = FALSE
    )
  ),
  annotations = tool_annotations_copy(tool_grep_files)
)

sdk_tool_ls <- make_tool_alias(
  fun = function(path = ".", pattern = NULL, recursive = FALSE) {
    tool_list_files(path = path, pattern = pattern, recursive = recursive)
  },
  name = "LS",
  description = "List files in a directory.",
  arguments = list(
    path = ellmer::type_string(
      "Directory path to list. Default is current directory.",
      required = FALSE
    ),
    pattern = ellmer::type_string(
      "Optional regex pattern to filter files.",
      required = FALSE
    ),
    recursive = ellmer::type_boolean(
      "If TRUE, list files recursively. Default is FALSE.",
      required = FALSE
    )
  ),
  annotations = tool_annotations_copy(tool_list_files)
)

sdk_tool_todo_read <- make_tool_alias(
  fun = function(path = ".deputy/todos.json") {
    tool_todo_read(path = path)
  },
  name = "TodoRead",
  description = "Read the current todo list.",
  arguments = list(
    path = ellmer::type_string(
      "Path to the todo file. Default is .deputy/todos.json.",
      required = FALSE
    )
  ),
  annotations = tool_annotations_copy(tool_todo_read)
)

sdk_tool_todo_write <- make_tool_alias(
  fun = function(todos, path = ".deputy/todos.json") {
    tool_todo_write(todos = todos, path = path)
  },
  name = "TodoWrite",
  description = "Replace the current todo list.",
  arguments = list(
    todos = ellmer::type_string(
      "JSON array or structured list of todo items.",
      required = FALSE
    ),
    path = ellmer::type_string(
      "Path to the todo file. Default is .deputy/todos.json.",
      required = FALSE
    )
  ),
  annotations = tool_annotations_copy(tool_todo_write)
)

sdk_tool_web_fetch <- make_tool_alias(
  fun = function(url) {
    tool_web_fetch(url = url)
  },
  name = "WebFetch",
  description = "Fetch a web page and return its contents.",
  arguments = list(
    url = ellmer::type_string("URL to fetch")
  ),
  annotations = tool_annotations_copy(tool_web_fetch)
)

sdk_tool_web_search <- make_tool_alias(
  fun = function(query, num_results = 10) {
    tool_web_search(query = query, num_results = num_results)
  },
  name = "WebSearch",
  description = "Search the web for information.",
  arguments = list(
    query = ellmer::type_string("Search query"),
    num_results = ellmer::type_integer(
      "Maximum number of results to return. Default is 10.",
      required = FALSE
    )
  ),
  annotations = tool_annotations_copy(tool_web_search)
)

# Create Agent/Task aliases dynamically from a lead-agent delegate tool.
make_delegate_tool_alias <- function(delegate_tool, name = "Agent") {
  make_tool_alias(
    fun = function(subagent_type, description) {
      delegate_tool(agent_name = subagent_type, task = description)
    },
    name = name,
    description = "Delegate work to a specialized sub-agent.",
    arguments = list(
      subagent_type = ellmer::type_string("Registered sub-agent name"),
      description = ellmer::type_string("Task description to delegate")
    ),
    annotations = tool_annotations_copy(delegate_tool)
  )
}

# Compatibility registry for resolving named built-in tools.
compat_named_tool_registry <- function(delegate_tool = NULL) {
  registry <- list(
    read_file = tool_read_file,
    write_file = tool_write_file,
    edit_file = tool_edit_file,
    multi_edit = tool_multi_edit,
    list_files = tool_list_files,
    glob_files = tool_glob_files,
    grep_files = tool_grep_files,
    todo_read = tool_todo_read,
    todo_write = tool_todo_write,
    web_fetch = tool_web_fetch,
    web_search = tool_web_search,
    AskUserQuestion = tool_ask_user,
    Read = sdk_tool_read,
    Write = sdk_tool_write,
    Edit = sdk_tool_edit,
    MultiEdit = sdk_tool_multi_edit,
    LS = sdk_tool_ls,
    Glob = sdk_tool_glob,
    Grep = sdk_tool_grep,
    TodoRead = sdk_tool_todo_read,
    TodoWrite = sdk_tool_todo_write,
    WebFetch = sdk_tool_web_fetch,
    WebSearch = sdk_tool_web_search
  )

  if (!is.null(delegate_tool)) {
    registry$Agent <- make_delegate_tool_alias(delegate_tool, name = "Agent")
    registry$Task <- make_delegate_tool_alias(delegate_tool, name = "Task")
  }

  registry
}

# Resolve tool names from settings or compat options.
compat_resolve_named_tools <- function(tool_names, delegate_tool = NULL) {
  if (is.null(tool_names) || length(tool_names) == 0) {
    return(list())
  }

  if (
    is.list(tool_names) &&
      length(tool_names) > 0 &&
      all(vapply(tool_names, inherits, logical(1), what = "ellmer::ToolDef"))
  ) {
    return(tool_names)
  }

  normalized <- tool_names
  if (
    is.character(normalized) &&
      length(normalized) == 1 &&
      grepl(",", normalized)
  ) {
    normalized <- strsplit(normalized, ",", fixed = TRUE)[[1]]
  }
  normalized <- trimws(as.character(unlist(
    normalized,
    recursive = TRUE,
    use.names = FALSE
  )))
  normalized <- normalized[nzchar(normalized)]

  registry <- compat_named_tool_registry(delegate_tool = delegate_tool)
  resolved <- lapply(normalized, function(name) {
    tool <- registry[[name]]
    if (is.null(tool)) {
      cli::cli_abort("Unknown compatibility tool: {.val {name}}")
    }
    tool
  })

  names(resolved) <- normalized
  unname(resolved)
}

# Default tool set used by the compatibility client.
compat_default_tools <- function(delegate_tool = NULL) {
  tools <- list(
    sdk_tool_read,
    sdk_tool_write,
    sdk_tool_edit,
    sdk_tool_multi_edit,
    sdk_tool_ls,
    sdk_tool_glob,
    sdk_tool_grep,
    sdk_tool_todo_read,
    sdk_tool_todo_write,
    sdk_tool_web_fetch,
    sdk_tool_web_search,
    tool_ask_user
  )

  if (!is.null(delegate_tool)) {
    tools <- c(
      tools,
      list(
        make_delegate_tool_alias(delegate_tool, name = "Agent"),
        make_delegate_tool_alias(delegate_tool, name = "Task")
      )
    )
  }

  tools
}

compat_delegate_tool_names <- c("Agent", "Task")

compat_normalize_tool_names <- function(tool_names) {
  if (is.null(tool_names) || length(tool_names) == 0) {
    return(character())
  }

  normalized <- tool_names
  if (
    is.character(normalized) &&
      length(normalized) == 1 &&
      grepl(",", normalized)
  ) {
    normalized <- strsplit(normalized, ",", fixed = TRUE)[[1]]
  }
  normalized <- trimws(as.character(unlist(
    normalized,
    recursive = TRUE,
    use.names = FALSE
  )))
  normalized[nzchar(normalized)]
}

compat_requested_tools <- function(options, delegate_tool = NULL) {
  requested <- options$tools
  if (is.null(requested)) {
    return(compat_default_tools(delegate_tool = delegate_tool))
  }

  if (
    is.list(requested) &&
      length(requested) == 0
  ) {
    return(list())
  }

  if (
    is.list(requested) &&
      length(requested) > 0 &&
      all(vapply(requested, inherits, logical(1), what = "ellmer::ToolDef"))
  ) {
    return(requested)
  }

  if (!is.character(requested)) {
    cli::cli_abort(
      "{.arg tools} must be NULL, a character vector of tool names, or a list of ellmer tools"
    )
  }

  names <- compat_normalize_tool_names(requested)
  if (is.null(delegate_tool)) {
    names <- setdiff(names, compat_delegate_tool_names)
  }

  compat_resolve_named_tools(names, delegate_tool = delegate_tool)
}

compat_delegate_tool_requested <- function(options, name) {
  if (is.null(options$tools)) {
    return(TRUE)
  }
  requested <- options$tools
  if (!is.character(requested)) {
    return(FALSE)
  }
  name %in% compat_normalize_tool_names(requested)
}

compat_apply_managed_settings <- function(settings, options) {
  managed <- options$managed_settings
  if (is.null(managed)) {
    return(settings)
  }
  if (!is.list(managed)) {
    cli::cli_abort("{.arg managed_settings} must be NULL or a named list")
  }

  settings$settings <- merge_named_lists(settings$settings %||% list(), managed)
  settings
}

compat_filter_settings_skills <- function(settings, options) {
  requested <- options$skills
  if (is.null(requested) || identical(requested, "all")) {
    return(settings)
  }

  if (length(requested) == 0) {
    settings$skills <- list()
    return(settings)
  }

  if (is.character(requested)) {
    skill_names <- compat_normalize_tool_names(requested)
    settings$skills <- settings$skills[intersect(names(settings$skills), skill_names)]
  }

  settings
}

compat_load_explicit_skills <- function(agent, options, settings) {
  requested <- options$skills
  if (is.null(requested) || identical(requested, "all") || length(requested) == 0) {
    return(invisible(NULL))
  }

  loaded_names <- names(settings$skills %||% list())
  if (is.character(requested)) {
    for (skill in requested) {
      if (skill %in% loaded_names) {
        next
      }
      if (file.exists(skill)) {
        agent$load_skill(skill, allow_conflicts = TRUE)
      }
    }
    return(invisible(NULL))
  }

  if (is.list(requested)) {
    for (skill in requested) {
      if (inherits(skill, "Skill") || is.character(skill)) {
        agent$load_skill(skill, allow_conflicts = TRUE)
      }
    }
  }

  invisible(NULL)
}

compat_get_nested <- function(x, path) {
  out <- x
  for (key in path) {
    if (!is.list(out) || is.null(out[[key]])) {
      return(NULL)
    }
    out <- out[[key]]
  }
  out
}

compat_first_setting <- function(settings_data, paths) {
  for (path in paths) {
    value <- compat_get_nested(settings_data, path)
    if (!is.null(value)) {
      return(value)
    }
  }
  NULL
}

compat_output_format_setting <- function(settings_data) {
  value <- compat_first_setting(settings_data, list(
    c("outputFormat"),
    c("output_format")
  ))
  if (is.character(value) && length(value) == 1) {
    normalized <- tolower(trimws(value))
    if (normalized %in% c("json", "json_object")) {
      return(list(type = "json_object"))
    }
  }
  value
}

compat_include_partial_setting <- function(settings_data) {
  value <- compat_first_setting(settings_data, list(
    c("includePartialMessages"),
    c("include_partial_messages")
  ))
  if (is.null(value)) {
    return(NULL)
  }
  isTRUE(value)
}

# Validate HookMatcher input for the compatibility facade.
validate_compat_hooks <- function(hooks) {
  if (is.null(hooks)) {
    return(list())
  }

  if (inherits(hooks, "HookMatcher")) {
    hooks <- list(hooks)
  }

  if (!is.list(hooks)) {
    cli::cli_abort(
      "{.arg hooks} must be a HookMatcher or list of HookMatcher objects"
    )
  }

  invalid <- !vapply(hooks, inherits, logical(1), what = "HookMatcher")
  if (any(invalid)) {
    cli::cli_abort("{.arg hooks} must contain only HookMatcher objects")
  }

  hooks
}

# Clone a provided chat when possible so each compat client starts cleanly.
clone_compat_chat <- function(chat, model = NULL) {
  if (!is.null(chat)) {
    validate_chat(chat)

    cloned <- tryCatch(
      chat$clone(),
      error = function(e) chat
    )
    tryCatch(cloned$set_turns(list()), error = function(e) invisible(NULL))
    return(cloned)
  }

  ellmer::chat(normalize_claude_sdk_model(model))
}

# Build a permissions object from Claude-shaped options.
compat_permissions <- function(options) {
  mode <- options$permission_mode %||% "default"
  allowlist <- options$allowed_tools
  denylist <- options$disallowed_tools
  prompt_tool <- options$permission_prompt_tool_name
  can_use_tool <- options$can_use_tool

  switch(
    mode,
    default = Permissions$new(
      mode = "default",
      file_read = TRUE,
      file_write = options$cwd,
      bash = FALSE,
      r_code = TRUE,
      web = TRUE,
      install_packages = FALSE,
      max_turns = options$max_turns,
      max_cost_usd = options$max_cost_usd,
      can_use_tool = can_use_tool,
      tool_allowlist = allowlist,
      tool_denylist = denylist,
      permission_prompt_tool_name = prompt_tool
    ),
    auto = Permissions$new(
      mode = "auto",
      file_read = TRUE,
      file_write = options$cwd,
      bash = FALSE,
      r_code = TRUE,
      web = TRUE,
      install_packages = FALSE,
      max_turns = options$max_turns,
      max_cost_usd = options$max_cost_usd,
      can_use_tool = can_use_tool,
      tool_allowlist = allowlist,
      tool_denylist = denylist,
      permission_prompt_tool_name = prompt_tool
    ),
    dontAsk = Permissions$new(
      mode = "dontAsk",
      file_read = TRUE,
      file_write = options$cwd,
      bash = FALSE,
      r_code = TRUE,
      web = TRUE,
      install_packages = FALSE,
      max_turns = options$max_turns,
      max_cost_usd = options$max_cost_usd,
      can_use_tool = can_use_tool,
      tool_allowlist = allowlist,
      tool_denylist = denylist,
      permission_prompt_tool_name = NULL
    ),
    acceptEdits = Permissions$new(
      mode = "acceptEdits",
      file_read = TRUE,
      file_write = options$cwd,
      bash = FALSE,
      r_code = TRUE,
      web = TRUE,
      install_packages = FALSE,
      max_turns = options$max_turns,
      max_cost_usd = options$max_cost_usd,
      can_use_tool = can_use_tool,
      tool_allowlist = allowlist,
      tool_denylist = denylist,
      permission_prompt_tool_name = prompt_tool
    ),
    readonly = Permissions$new(
      mode = "readonly",
      file_read = TRUE,
      file_write = FALSE,
      bash = FALSE,
      r_code = FALSE,
      web = TRUE,
      install_packages = FALSE,
      max_turns = options$max_turns,
      max_cost_usd = options$max_cost_usd,
      can_use_tool = can_use_tool,
      tool_allowlist = allowlist,
      tool_denylist = denylist,
      permission_prompt_tool_name = prompt_tool
    ),
    plan = Permissions$new(
      mode = "plan",
      file_read = TRUE,
      file_write = FALSE,
      bash = FALSE,
      r_code = FALSE,
      web = TRUE,
      install_packages = FALSE,
      max_turns = options$max_turns,
      max_cost_usd = options$max_cost_usd,
      can_use_tool = can_use_tool,
      tool_allowlist = allowlist,
      tool_denylist = denylist,
      permission_prompt_tool_name = prompt_tool
    ),
    bypassPermissions = Permissions$new(
      mode = "bypassPermissions",
      file_read = TRUE,
      file_write = TRUE,
      bash = TRUE,
      r_code = TRUE,
      web = TRUE,
      install_packages = TRUE,
      max_turns = options$max_turns,
      max_cost_usd = options$max_cost_usd,
      can_use_tool = can_use_tool,
      tool_allowlist = allowlist,
      tool_denylist = denylist,
      permission_prompt_tool_name = prompt_tool
    ),
    cli::cli_abort(
      "Unsupported Claude SDK permission mode: {.val {mode}}"
    )
  )
}

# Merge explicit and settings-defined sub-agents.
merge_compat_agents <- function(options, settings) {
  explicit <- options$agents %||% list()
  from_settings <- settings$agents %||% list()
  c(explicit, unname(from_settings))
}

# Build a Deputy agent from Agent SDK compatibility options.
build_compat_agent <- function(options) {
  settings <- options$settings
  if (is.null(settings)) {
    settings <- claude_settings_load(
      options$setting_sources,
      working_dir = options$cwd
    )
  }
  settings <- compat_apply_managed_settings(settings, options)
  settings <- compat_filter_settings_skills(settings, options)

  sub_agents <- merge_compat_agents(options, settings)
  permissions <- compat_permissions(options)
  chat <- clone_compat_chat(options$chat, model = options$model)

  agent <- if (length(sub_agents) > 0) {
    lead <- LeadAgent$new(
      chat = chat,
      sub_agents = sub_agents,
      tools = compat_requested_tools(options),
      system_prompt = options$system_prompt,
      permissions = permissions,
      working_dir = options$cwd
    )

    delegate_tool <- lead$chat$get_tools()[["delegate_to_agent"]]
    if (compat_delegate_tool_requested(options, "Agent")) {
      lead$register_tool(make_delegate_tool_alias(delegate_tool, name = "Agent"))
    }
    if (compat_delegate_tool_requested(options, "Task")) {
      lead$register_tool(make_delegate_tool_alias(delegate_tool, name = "Task"))
    }
    lead
  } else {
    Agent$new(
      chat = chat,
      tools = compat_requested_tools(options),
      system_prompt = options$system_prompt,
      permissions = permissions,
      working_dir = options$cwd
    )
  }

  for (tool in options$custom_tools) {
    agent$register_tool(tool)
  }

  if (
    !is.null(settings) &&
      (length(settings$memory) > 0 ||
        length(settings$skills) > 0 ||
        length(settings$commands) > 0 ||
        length(settings$settings) > 0)
  ) {
    settings_no_agents <- settings
    settings_no_agents$agents <- list()
    claude_settings_apply(agent, settings_no_agents)
  }

  compat_load_explicit_skills(agent, options, settings)

  for (hook in options$hooks) {
    agent$add_hook(hook)
  }

  agent$configure_sdk_compat(list(
    persist_session = options$persist_session,
    session_store_dir = options$session_store_dir,
    session_store = options$session_store,
    session_id = options$session_id %||% generate_session_id()
  ))

  agent
}

# Run a code block in the configured working directory.
with_compat_working_dir <- function(cwd, code) {
  old <- getwd()
  on.exit(setwd(old), add = TRUE)
  setwd(cwd)
  force(code)
}

#' Create Agent SDK compatibility options
#'
#' `agent_sdk_options()` is an additive alias for teams that prefer the newer
#' Agent SDK naming while keeping the same deputy runtime and behavior.
#'
#' @param chat Optional ellmer chat object to use directly
#' @param model Model string used when `chat` is not supplied
#' @param system_prompt Optional system prompt
#' @param hooks Optional HookMatcher or list of HookMatcher objects
#' @param tools Optional SDK-style built-in tool names or ellmer tools to register
#' @param custom_tools Optional list of additional ellmer tools
#' @param agents Optional list of [agent_definition()] objects
#' @param setting_sources Optional Claude-style setting sources
#' @param settings Optional pre-loaded settings list from [claude_settings_load()]
#' @param managed_settings Optional settings values that override loaded settings
#' @param allowed_tools Optional explicit tool allowlist
#' @param disallowed_tools Optional explicit tool denylist
#' @param permission_prompt_tool_name Tool name to suggest when approval is required
#' @param permission_mode Compatibility permission mode
#' @param can_use_tool Optional permission callback
#' @param cwd Working directory for the agent
#' @param persist_session Whether to persist compat snapshots to disk
#' @param session_store_dir Directory where compat session snapshots are stored
#' @param session_store Optional external session store adapter
#' @param resume_session_id Optional session id to resume later
#' @param resume_session_at Optional timestamp to resume at or before
#' @param fork_session Whether to fork the resumed session into a new session id
#' @param max_turns Maximum turns per query
#' @param max_cost_usd Maximum cost per query
#' @param include_partial_messages Whether query results keep partial text events
#' @param output_format Optional default structured output format
#' @param skills Optional SDK-style skill selection (`"all"`, names, paths, or skills)
#' @param sandbox,plugins,thinking,effort,title,user,fallback_model,betas,cli_path,add_dirs,env,extra_args,max_buffer_size,stderr,enable_file_checkpointing,load_timeout_ms,task_budget Additional SDK-shaped options that are preserved for compatibility. deputy applies the subset that maps to its R-native runtime.
#'
#' @return A `ClaudeSDKOptions` object
#' @export
claude_sdk_options <- function(
  chat = NULL,
  model = NULL,
  system_prompt = NULL,
  hooks = list(),
  tools = NULL,
  custom_tools = list(),
  agents = list(),
  setting_sources = NULL,
  settings = NULL,
  managed_settings = NULL,
  allowed_tools = NULL,
  disallowed_tools = NULL,
  permission_prompt_tool_name = "AskUserQuestion",
  permission_mode = "default",
  can_use_tool = NULL,
  cwd = getwd(),
  persist_session = TRUE,
  session_store_dir = session_store_default_dir(),
  session_store = NULL,
  resume_session_id = NULL,
  resume_session_at = NULL,
  fork_session = FALSE,
  max_turns = 25,
  max_cost_usd = NULL,
  include_partial_messages = TRUE,
  output_format = NULL,
  skills = NULL,
  sandbox = NULL,
  plugins = NULL,
  thinking = NULL,
  effort = NULL,
  title = NULL,
  user = NULL,
  fallback_model = NULL,
  betas = NULL,
  cli_path = NULL,
  add_dirs = NULL,
  env = NULL,
  extra_args = NULL,
  max_buffer_size = NULL,
  stderr = NULL,
  enable_file_checkpointing = FALSE,
  load_timeout_ms = NULL,
  task_budget = NULL
) {
  hooks <- validate_compat_hooks(hooks)

  if (!is.null(chat)) {
    validate_chat(chat)
  }

  if (!is.list(custom_tools)) {
    cli::cli_abort("{.arg custom_tools} must be a list of tools")
  }

  if (!is.null(tools) && !is.character(tools) && !is.list(tools)) {
    cli::cli_abort(
      "{.arg tools} must be NULL, a character vector of tool names, or a list of ellmer tools"
    )
  }

  if (!is.null(can_use_tool) && !is.function(can_use_tool)) {
    cli::cli_abort("{.arg can_use_tool} must be NULL or a function")
  }

  if (!is.list(agents)) {
    cli::cli_abort("{.arg agents} must be a list of AgentDefinition objects")
  }
  if (length(agents) > 0) {
    invalid_agents <- !vapply(
      agents,
      inherits,
      logical(1),
      what = "AgentDefinition"
    )
    if (any(invalid_agents)) {
      cli::cli_abort("{.arg agents} must contain only AgentDefinition objects")
    }
  }

  permission_mode <- validate_permission_mode_value(
    permission_mode,
    arg = "permission_mode"
  )

  if (!is.null(setting_sources) && !is.character(setting_sources)) {
    cli::cli_abort("{.arg setting_sources} must be NULL or a character vector")
  }

  if (!is.null(task_budget)) {
    if (!is.numeric(task_budget) || length(task_budget) != 1 || is.na(task_budget)) {
      cli::cli_abort("{.arg task_budget} must be NULL or a length-1 number")
    }
    max_turns <- task_budget
  }

  structure(
    list(
      chat = chat,
      model = normalize_claude_sdk_model(model),
      system_prompt = system_prompt,
      hooks = hooks,
      tools = tools,
      custom_tools = custom_tools,
      agents = agents,
      setting_sources = setting_sources %||% character(),
      settings = settings,
      managed_settings = managed_settings,
      allowed_tools = allowed_tools,
      disallowed_tools = disallowed_tools,
      permission_prompt_tool_name = permission_prompt_tool_name,
      permission_mode = permission_mode,
      can_use_tool = can_use_tool,
      cwd = normalizePath(cwd, mustWork = TRUE),
      persist_session = isTRUE(persist_session),
      session_store_dir = normalize_session_store_dir(session_store_dir),
      session_store = session_store,
      resume_session_id = resume_session_id,
      resume_session_at = resume_session_at,
      fork_session = isTRUE(fork_session),
      max_turns = as.integer(max_turns),
      max_cost_usd = max_cost_usd,
      include_partial_messages = isTRUE(include_partial_messages),
      output_format = output_format,
      skills = skills,
      sandbox = sandbox,
      plugins = plugins,
      thinking = thinking,
      effort = effort,
      title = title,
      user = user,
      fallback_model = fallback_model,
      betas = betas,
      cli_path = cli_path,
      add_dirs = add_dirs,
      env = env,
      extra_args = extra_args,
      max_buffer_size = max_buffer_size,
      stderr = stderr,
      enable_file_checkpointing = isTRUE(enable_file_checkpointing),
      load_timeout_ms = load_timeout_ms,
      task_budget = task_budget,
      session_id = NULL
    ),
    class = "ClaudeSDKOptions"
  )
}

#' @param ... Passed through to [claude_sdk_options()]
#' @rdname claude_sdk_options
#' @export
agent_sdk_options <- function(...) {
  claude_sdk_options(...)
}

#' Agent SDK compatibility client
#'
#' `AgentSDKClient` is an additive alias for [ClaudeSDKClient].
#'
#' @export
ClaudeSDKClient <- R6::R6Class(
  "ClaudeSDKClient",

  public = list(
    #' @field options Stored [claude_sdk_options()] used to configure the client
    options = NULL,

    #' @field agent The underlying Deputy agent instance
    agent = NULL,

    #' @description
    #' Create a new compatibility client.
    #'
    #' @param options Claude SDK compatibility options
    initialize = function(options = claude_sdk_options()) {
      if (!inherits(options, "ClaudeSDKOptions")) {
        cli::cli_abort(
          "{.arg options} must be created with claude_sdk_options()"
        )
      }

      self$options <- options
      self$agent <- build_compat_agent(options)

      if (!is.null(options$resume_session_id)) {
        self$resume(
          session_id = options$resume_session_id,
          at = options$resume_session_at,
          fork = options$fork_session
        )
      }
    },

    #' @description
    #' Run a prompt through the compatibility client.
    #'
    #' @param prompt User prompt to send
    #' @param output_format Optional structured output format passed to deputy
    #' @return An [AgentResult]
    query = function(prompt, output_format = NULL) {
      if (is.null(self$agent)) {
        self$agent <- build_compat_agent(self$options)
      }

      settings_data <- self$agent$settings()$settings %||% list()
      output_format <- output_format %||%
        self$options$output_format %||%
        compat_output_format_setting(settings_data)
      include_partial_messages <- self$options$include_partial_messages
      settings_include_partial <- compat_include_partial_setting(settings_data)
      if (!is.null(settings_include_partial)) {
        include_partial_messages <- settings_include_partial
      }

      with_compat_working_dir(
        self$options$cwd,
        self$agent$run_sync(
          prompt,
          include_partial_messages = include_partial_messages,
          output_format = output_format
        )
      )
    },

    #' @description
    #' List persisted compatibility sessions.
    #'
    #' @return Data frame describing stored sessions
    list_sessions = function() {
      session_store_list_sessions(self$options$session_store_dir)
    },

    #' @description
    #' List summaries from an external session store, when configured.
    #'
    #' @return Data frame or character vector supplied by the store adapter
    list_session_summaries = function() {
      if (is.null(self$options$session_store)) {
        return(self$list_sessions())
      }
      session_store_summaries_external(self$options$session_store)
    },

    #' @description
    #' Delete a stored compatibility session.
    #'
    #' @param session_id Session identifier to delete
    #' @return Invisible self
    delete_session = function(session_id) {
      session_store_delete_session(self$options$session_store_dir, session_id)
      if (!is.null(self$options$session_store)) {
        session_store_delete_external(self$options$session_store, session_id)
      }
      invisible(self)
    },

    #' @description
    #' Get MCP runtime status from the underlying agent.
    #'
    #' @return Data frame describing MCP load attempts
    get_mcp_status = function() {
      if (is.null(self$agent)) {
        self$agent <- build_compat_agent(self$options)
      }
      self$agent$mcp_status()
    },

    #' @description
    #' Resume or fork a persisted compatibility session.
    #'
    #' @param session_id Session identifier to restore
    #' @param at Optional timestamp to restore at or before
    #' @param fork If TRUE, restore into a new session id
    #' @return Invisible self
    resume = function(session_id, at = NULL, fork = FALSE) {
      snapshot <- NULL
      if (!is.null(self$options$session_store) && is.null(at)) {
        payload <- tryCatch(
          session_store_load_external(self$options$session_store, session_id),
          error = function(e) {
            cli::cli_warn(c(
              "External session store load failed; falling back to local snapshots",
              "x" = e$message
            ))
            NULL
          }
        )
        if (!is.null(payload)) {
          snapshot <- list(
            path = paste0("session_store:", session_id),
            payload = payload,
            snapshot_at = session_store_payload_time(payload)
          )
        }
      }

      if (is.null(snapshot)) {
        snapshot <- session_store_select_snapshot(
          root = self$options$session_store_dir,
          session_id = session_id,
          at = at
        )
      }

      self$agent <- build_compat_agent(self$options)

      with_compat_working_dir(
        self$options$cwd,
        self$agent$.__enclos_env__$private$restore_session_payload(
          snapshot$payload,
          restore_tools = TRUE,
          source = snapshot$path
        )
      )

      active_session_id <- if (isTRUE(fork)) {
        generate_session_id()
      } else {
        session_id
      }
      self$options$session_id <- active_session_id
      self$agent$configure_sdk_compat(list(
        persist_session = self$options$persist_session,
        session_store_dir = self$options$session_store_dir,
        session_store = self$options$session_store,
        session_id = active_session_id
      ))

      notice <- if (isTRUE(fork)) {
        paste0(
          "Forked session ",
          session_id,
          " into ",
          active_session_id,
          "."
        )
      } else {
        paste0("Resumed session ", session_id, ".")
      }
      code <- if (isTRUE(fork)) "session_forked" else "session_resumed"
      self$agent$.__enclos_env__$private$notify(
        notice,
        level = "info",
        code = code,
        source_session_id = session_id,
        active_session_id = active_session_id,
        snapshot_path = snapshot$path
      )

      if (isTRUE(fork) && isTRUE(self$options$persist_session)) {
        self$agent$.__enclos_env__$private$snapshot_compat_state(
          reason = "fork_restore"
        )
      }

      invisible(self)
    }
  )
)

#' @rdname ClaudeSDKClient
#' @export
AgentSDKClient <- R6::R6Class(
  "AgentSDKClient",
  inherit = ClaudeSDKClient
)

#' Run a one-shot Agent SDK compatibility query
#'
#' `agent_sdk_query()` is an additive alias for [claude_sdk_query()].
#'
#' @param prompt User prompt to send
#' @param options Claude SDK compatibility options
#' @param output_format Optional structured output format passed to deputy
#'
#' @return An [AgentResult]
#' @export
claude_sdk_query <- function(
  prompt,
  options = claude_sdk_options(),
  output_format = NULL
) {
  ClaudeSDKClient$new(options = options)$query(
    prompt = prompt,
    output_format = output_format
  )
}

#' @rdname claude_sdk_query
#' @export
agent_sdk_query <- function(
  prompt,
  options = agent_sdk_options(),
  output_format = NULL
) {
  AgentSDKClient$new(options = options)$query(
    prompt = prompt,
    output_format = output_format
  )
}
