# Claude Agent SDK compatibility facade for deputy.

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

# Create the Task alias dynamically from a lead-agent delegate tool.
make_task_tool_alias <- function(delegate_tool) {
  make_tool_alias(
    fun = function(subagent_type, description) {
      delegate_tool(agent_name = subagent_type, task = description)
    },
    name = "Task",
    description = "Delegate work to a specialized sub-agent.",
    arguments = list(
      subagent_type = ellmer::type_string("Registered sub-agent name"),
      description = ellmer::type_string("Task description to delegate")
    ),
    annotations = tool_annotations_copy(delegate_tool)
  )
}

# Compatibility registry for resolving named built-in tools.
compat_named_tool_registry <- function(task_tool = NULL) {
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

  if (!is.null(task_tool)) {
    registry$Task <- task_tool
  }

  registry
}

# Resolve tool names from settings or compat options.
compat_resolve_named_tools <- function(tool_names, task_tool = NULL) {
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

  registry <- compat_named_tool_registry(task_tool = task_tool)
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
compat_default_tools <- function(task_tool = NULL) {
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

  if (!is.null(task_tool)) {
    tools <- c(tools, list(task_tool))
  }

  tools
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
      tool_allowlist = allowlist,
      tool_denylist = denylist,
      permission_prompt_tool_name = prompt_tool
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

# Build a Deputy agent from Claude SDK compatibility options.
build_compat_agent <- function(options) {
  settings <- options$settings
  if (is.null(settings)) {
    settings <- claude_settings_load(
      options$setting_sources,
      working_dir = options$cwd
    )
  }

  sub_agents <- merge_compat_agents(options, settings)
  permissions <- compat_permissions(options)
  chat <- clone_compat_chat(options$chat, model = options$model)

  agent <- if (length(sub_agents) > 0) {
    lead <- LeadAgent$new(
      chat = chat,
      sub_agents = sub_agents,
      tools = compat_default_tools(),
      system_prompt = options$system_prompt,
      permissions = permissions,
      working_dir = options$cwd
    )

    delegate_tool <- lead$chat$get_tools()[["delegate_to_agent"]]
    lead$register_tool(make_task_tool_alias(delegate_tool))
    lead
  } else {
    Agent$new(
      chat = chat,
      tools = compat_default_tools(),
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

  for (hook in options$hooks) {
    agent$add_hook(hook)
  }

  agent$configure_sdk_compat(list(
    persist_session = options$persist_session,
    session_store_dir = options$session_store_dir,
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

#' Create Claude Agent SDK compatibility options
#'
#' @param chat Optional ellmer chat object to use directly
#' @param model Model string used when `chat` is not supplied
#' @param system_prompt Optional system prompt
#' @param hooks Optional HookMatcher or list of HookMatcher objects
#' @param custom_tools Optional list of additional ellmer tools
#' @param agents Optional list of [agent_definition()] objects
#' @param setting_sources Optional Claude-style setting sources
#' @param settings Optional pre-loaded settings list from [claude_settings_load()]
#' @param allowed_tools Optional explicit tool allowlist
#' @param disallowed_tools Optional explicit tool denylist
#' @param permission_prompt_tool_name Tool name to suggest when approval is required
#' @param permission_mode Compatibility permission mode
#' @param cwd Working directory for the agent
#' @param persist_session Whether to persist compat snapshots to disk
#' @param session_store_dir Directory where compat session snapshots are stored
#' @param resume_session_id Optional session id to resume later
#' @param resume_session_at Optional timestamp to resume at or before
#' @param fork_session Whether to fork the resumed session into a new session id
#' @param max_turns Maximum turns per query
#' @param max_cost_usd Maximum cost per query
#'
#' @return A `ClaudeSDKOptions` object
#' @export
claude_sdk_options <- function(
  chat = NULL,
  model = NULL,
  system_prompt = NULL,
  hooks = list(),
  custom_tools = list(),
  agents = list(),
  setting_sources = NULL,
  settings = NULL,
  allowed_tools = NULL,
  disallowed_tools = NULL,
  permission_prompt_tool_name = "AskUserQuestion",
  permission_mode = "default",
  cwd = getwd(),
  persist_session = TRUE,
  session_store_dir = session_store_default_dir(),
  resume_session_id = NULL,
  resume_session_at = NULL,
  fork_session = FALSE,
  max_turns = 25,
  max_cost_usd = NULL
) {
  hooks <- validate_compat_hooks(hooks)

  if (!is.null(chat)) {
    validate_chat(chat)
  }

  if (!is.list(custom_tools)) {
    cli::cli_abort("{.arg custom_tools} must be a list of tools")
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

  structure(
    list(
      chat = chat,
      model = normalize_claude_sdk_model(model),
      system_prompt = system_prompt,
      hooks = hooks,
      custom_tools = custom_tools,
      agents = agents,
      setting_sources = setting_sources %||% character(),
      settings = settings,
      allowed_tools = allowed_tools,
      disallowed_tools = disallowed_tools,
      permission_prompt_tool_name = permission_prompt_tool_name,
      permission_mode = permission_mode,
      cwd = normalizePath(cwd, mustWork = TRUE),
      persist_session = isTRUE(persist_session),
      session_store_dir = normalize_session_store_dir(session_store_dir),
      resume_session_id = resume_session_id,
      resume_session_at = resume_session_at,
      fork_session = isTRUE(fork_session),
      max_turns = as.integer(max_turns),
      max_cost_usd = max_cost_usd,
      session_id = NULL
    ),
    class = "ClaudeSDKOptions"
  )
}

#' Claude Agent SDK compatibility client
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

      with_compat_working_dir(
        self$options$cwd,
        self$agent$run_sync(prompt, output_format = output_format)
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
    #' Resume or fork a persisted compatibility session.
    #'
    #' @param session_id Session identifier to restore
    #' @param at Optional timestamp to restore at or before
    #' @param fork If TRUE, restore into a new session id
    #' @return Invisible self
    resume = function(session_id, at = NULL, fork = FALSE) {
      snapshot <- session_store_select_snapshot(
        root = self$options$session_store_dir,
        session_id = session_id,
        at = at
      )

      self$agent <- build_compat_agent(self$options)

      with_compat_working_dir(
        self$options$cwd,
        self$agent$load_session(snapshot$path)
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

#' Run a one-shot Claude Agent SDK compatibility query
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
