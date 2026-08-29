# Package-owned runtime for the deputy Rapp executable.

#' @importFrom Rapp run
NULL

cli_null_if_na <- function(x) {
  if (is.null(x)) {
    return(NULL)
  }
  if (length(x) == 1L && is.atomic(x) && is.na(x)) {
    return(NULL)
  }
  x
}

cli_split_csv_values <- function(values) {
  if (is.null(values) || length(values) == 0L) {
    return(character())
  }
  if (is.list(values)) {
    values <- unlist(values, recursive = TRUE, use.names = FALSE)
  }
  values <- as.character(values)
  parts <- unlist(strsplit(values, ",", fixed = TRUE), use.names = FALSE)
  parts <- trimws(parts)
  parts[nzchar(parts)]
}

cli_normalize_config <- function(config) {
  expected <- c(
    "provider",
    "model",
    "tools",
    "permissions",
    "max_requests",
    "max_cost",
    "session",
    "save_session",
    "system_prompt",
    "system_prompt_file",
    "no_ask",
    "mcp",
    "mcp_config",
    "mcp_server",
    "dir",
    "verbose",
    "no_color",
    "debug",
    "debug_file",
    "task"
  )
  missing <- setdiff(expected, names(config))
  if (length(missing) > 0L) {
    cli::cli_abort(
      "CLI configuration is missing: {.val {missing}}",
      class = "deputy_cli_config_error"
    )
  }

  nullable <- c(
    "model",
    "max_cost",
    "session",
    "save_session",
    "system_prompt",
    "system_prompt_file",
    "mcp_config",
    "debug_file",
    "task"
  )
  config[nullable] <- lapply(config[nullable], cli_null_if_na)

  if (
    !is.character(config$dir) ||
      length(config$dir) != 1L ||
      is.na(config$dir) ||
      !nzchar(config$dir)
  ) {
    cli::cli_abort(
      "{.arg --dir} must be one non-empty path",
      class = "deputy_cli_config_error"
    )
  }
  if (!dir.exists(config$dir)) {
    cli::cli_abort(
      "Working directory does not exist: {.path {config$dir}}",
      class = "deputy_cli_config_error"
    )
  }
  config$dir <- normalizePath(config$dir, mustWork = TRUE)
  config
}

cli_create_debug_logger <- function(enabled = FALSE, path = NULL) {
  if (!enabled) {
    return(structure(
      function(...) invisible(NULL),
      close = function() invisible(NULL)
    ))
  }

  con <- if (is.null(path)) NULL else file(path, open = "a")
  logger <- function(...) {
    message <- paste(..., collapse = "")
    line <- paste0(
      format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      " [deputy-debug] ",
      message
    )
    if (is.null(con)) {
      cat(line, "\n", file = stderr())
    } else {
      writeLines(line, con = con)
      flush(con)
    }
    invisible(NULL)
  }
  attr(logger, "close") <- function() {
    if (!is.null(con)) {
      close(con)
    }
    invisible(NULL)
  }
  logger
}

cli_create_chat <- function(provider, model) {
  known_providers <- c("anthropic", "openai", "google", "ollama")
  if (!provider %in% known_providers) {
    cli::cli_warn(c(
      "Unknown provider {.val {provider}}",
      "i" = "Known providers: {.val {known_providers}}",
      "i" = "Attempting the generic chat interface"
    ))
  }

  if (is.null(model) && !provider %in% known_providers) {
    cli::cli_abort(
      "{.arg --model} is required for unknown provider {.val {provider}}"
    )
  }

  switch(
    provider,
    anthropic = if (is.null(model)) {
      ellmer::chat_anthropic()
    } else {
      ellmer::chat_anthropic(model = model)
    },
    openai = if (is.null(model)) {
      ellmer::chat_openai()
    } else {
      ellmer::chat_openai(model = model)
    },
    google = if (is.null(model)) {
      ellmer::chat_google_gemini()
    } else {
      ellmer::chat_google_gemini(model = model)
    },
    ollama = ellmer::chat_ollama(model = model %||% "llama3.2"),
    ellmer::chat(paste0(provider, "/", model))
  )
}

cli_get_tools <- function(preset, include_ask = TRUE) {
  tools <- tools_preset(preset)
  if (include_ask) {
    c(tools, list(tool_ask_user))
  } else {
    tools
  }
}

cli_get_permissions <- function(mode, working_dir) {
  mode <- validate_permission_mode_value(
    mode,
    arg = "permission mode"
  )

  switch(
    mode,
    standard = permissions_standard(working_dir),
    plan = permissions_plan(),
    readonly = permissions_readonly(),
    full = permissions_full()
  )
}

cli_get_usage_limits <- function(max_requests = 25L, max_cost = NULL) {
  UsageLimits(max_requests = max_requests, max_cost_usd = max_cost)
}

cli_get_system_prompt <- function(prompt, path) {
  if (is.null(path)) {
    return(prompt)
  }
  if (!file.exists(path)) {
    cli::cli_abort("System prompt file not found: {.path {path}}")
  }
  paste(readLines(path, warn = FALSE), collapse = "\n")
}

cli_print_welcome <- function(agent, tools_preset, permission_mode) {
  provider <- agent$provider()
  mcp_tools <- agent$mcp_tools()

  cli::cli_h1("deputy")
  cli::cli_text("Interactive AI Agent for R")
  cli::cli_text("")
  bullets <- c(
    "*" = "Provider: {.val {provider$name}}",
    "*" = "Model: {.val {provider$model}}",
    "*" = "Tools: {.val {tools_preset}}",
    "*" = "Permissions: {.val {permission_mode}}",
    "*" = "Working dir: {.path {agent$working_dir}}"
  )
  if (length(mcp_tools) > 0L) {
    bullets <- c(bullets, "*" = "MCP tools: {.val {length(mcp_tools)}}")
  }
  cli::cli_bullets(bullets)
  cli::cli_text("")
  cli::cli_alert_info(
    "Type your message and press Enter. Type {.kbd /help} for commands."
  )
  cli::cli_text("")
}

cli_process_command <- function(input, agent) {
  if (!startsWith(input, "/")) {
    return(list(is_command = FALSE))
  }

  parts <- strsplit(trimws(input), "\\s+")[[1L]]
  command <- tolower(parts[[1L]])
  arguments <- parts[-1L]

  switch(
    command,
    "/quit" = ,
    "/exit" = ,
    "/q" = return(list(is_command = TRUE, action = "quit")),
    "/save" = {
      path <- if (length(arguments) == 0L) {
        paste0(
          "deputy_session_",
          format(Sys.time(), "%Y%m%d_%H%M%S"),
          ".rds"
        )
      } else {
        arguments[[1L]]
      }
      tryCatch(
        {
          agent$save_session(path)
          cli::cli_alert_success("Session saved to {.path {path}}")
        },
        error = function(error) {
          cli::cli_alert_danger("Failed to save session: {error$message}")
          cli::cli_alert_info("Check the path is writable: {.path {path}}")
        }
      )
      return(list(is_command = TRUE, action = "continue"))
    },
    "/clear" = {
      agent$set_turns(list())
      cli::cli_alert_success("Conversation cleared")
      return(list(is_command = TRUE, action = "continue"))
    },
    "/compact" = {
      keep <- 4L
      if (length(arguments) > 0L) {
        parsed <- suppressWarnings(as.integer(arguments[[1L]]))
        if (is.na(parsed) || parsed < 1L) {
          cli::cli_alert_warning(
            "Invalid keep value: {.val {arguments[[1L]]}}. Using 4"
          )
        } else {
          keep <- parsed
        }
      }
      tryCatch(
        {
          agent$compact(keep_last = keep)
          cli::cli_alert_success(
            "Conversation compacted; kept {.val {keep}} recent turns"
          )
        },
        error = function(error) {
          cli::cli_alert_danger("Compaction failed: {error$message}")
        }
      )
      return(list(is_command = TRUE, action = "continue"))
    },
    "/cost" = {
      cost <- agent$cost()
      cli::cli_h3("Cost Summary")
      cli::cli_bullets(c(
        "*" = "Input tokens: {.val {cost$input}}",
        "*" = "Output tokens: {.val {cost$output}}",
        "*" = "Cached tokens: {.val {cost$cached}}",
        "*" = "Total cost: {.val {sprintf('$%.4f', cost$total)}}"
      ))
      return(list(is_command = TRUE, action = "continue"))
    },
    "/turns" = {
      turns <- agent$turns()
      cli::cli_alert_info("Conversation has {.val {length(turns)}} turns")
      return(list(is_command = TRUE, action = "continue"))
    },
    "/help" = {
      cli::cli_h3("Available Commands")
      cli::cli_bullets(c(
        "*" = "{.kbd /quit} or {.kbd /exit} - Exit the CLI",
        "*" = "{.kbd /save [path]} - Save the session",
        "*" = "{.kbd /clear} - Clear conversation history",
        "*" = "{.kbd /compact [n]} - Compact and keep n recent turns",
        "*" = "{.kbd /cost} - Show the cost summary",
        "*" = "{.kbd /turns} - Show the turn count",
        "*" = "{.kbd /help} - Show this help"
      ))
      return(list(is_command = TRUE, action = "continue"))
    },
    {
      cli::cli_alert_warning(
        "Unknown command: {.val {command}}. Type {.kbd /help} for commands."
      )
      return(list(is_command = TRUE, action = "continue"))
    }
  )
}

cli_next_event <- function(generator) {
  tryCatch(
    generator(),
    error = function(error) {
      if (grepl("generator has been exhausted", error$message, fixed = TRUE)) {
        return(coro::exhausted())
      }
      stop(error)
    }
  )
}

cli_walk_agent_events <- function(agent, task, callback) {
  generator <- agent$run(task)
  if (!is.function(generator)) {
    cli::cli_abort(
      "Agent$run() did not return a generator",
      class = "deputy_cli_generator_error"
    )
  }

  stop_event <- NULL
  repeat {
    event <- cli_next_event(generator)
    if (coro::is_exhausted(event)) {
      break
    }
    callback(event)
    if (identical(event$type %||% NULL, "stop")) {
      stop_event <- event
      break
    }
  }
  invisible(stop_event)
}

cli_tool_error <- function(event) {
  error <- event$tool_error %||% NULL
  if (inherits(error, "condition")) {
    return(conditionMessage(error))
  }
  if (is.null(error)) NULL else paste(as.character(error), collapse = " ")
}

cli_render_event <- function(
  event,
  verbose = FALSE,
  mode = c("task", "interactive"),
  debug_log = NULL
) {
  mode <- match.arg(mode)
  event_type <- event$type %||% ""
  tool_name <- event$tool_name %||% "<unknown>"
  tool_error <- cli_tool_error(event)

  switch(
    event_type,
    text = cat(event$text %||% ""),
    tool_start = {
      if (!is.null(debug_log)) {
        debug_log("tool_start: ", tool_name)
      }
      if (verbose) {
        label <- if (identical(mode, "task")) "Tool" else "Calling"
        cli::cli_alert_info("{label}: {.fn {tool_name}}")
      }
    },
    tool_end = {
      if (!is.null(debug_log)) {
        if (is.null(tool_error)) {
          debug_log("tool_end success: ", tool_name)
        } else {
          debug_log("tool_end error: ", tool_name, " -> ", tool_error)
        }
      }
      if (!is.null(tool_error)) {
        cli::cli_alert_danger(
          "Tool {.fn {tool_name}} failed: {tool_error}"
        )
      } else if (verbose) {
        cli::cli_alert_success("Done: {.fn {tool_name}}")
      }
    },
    warning = cli::cli_alert_warning(event$message %||% "Agent warning"),
    stop = {
      total_turns <- event$total_turns %||% NA_integer_
      stop_reason <- event$reason %||% "complete"
      cost <- event$cost %||% NULL
      cost_total <- if (is.null(cost)) NULL else cost$total %||% NULL
      if (!is.null(debug_log)) {
        debug_log("run stop: turns=", as.character(total_turns))
      }
      cat("\n")
      if (identical(mode, "task")) {
        if (!is.null(cost_total) && !is.na(cost_total) && cost_total > 0) {
          cli::cli_alert_info("Cost: {.val {sprintf('$%.4f', cost_total)}}")
        }
        if (identical(stop_reason, "complete")) {
          cli::cli_alert_success(
            "Completed in {.val {total_turns}} turn(s)"
          )
        }
      } else if (!identical(stop_reason, "complete")) {
        cli::cli_alert_warning(
          "Run stopped after {.val {total_turns}} turn(s): {.val {stop_reason}}"
        )
      } else if (
        verbose &&
          !is.null(cost_total) &&
          !is.na(cost_total) &&
          cost_total > 0
      ) {
        cli::cli_text(cli::col_grey(sprintf(
          "[%d turns, $%.4f]",
          total_turns,
          cost_total
        )))
      }
    }
  )
  invisible(event)
}

cli_run_task <- function(agent, task, verbose = FALSE, debug_log = NULL) {
  cli::cli_alert_info("Running task: {.val {task}}")
  cli::cli_text("")
  if (!is.null(debug_log)) {
    debug_log("run_task started")
  }
  stop_event <- cli_walk_agent_events(
    agent,
    task,
    function(event) {
      cli_render_event(
        event,
        verbose = verbose,
        mode = "task",
        debug_log = debug_log
      )
    }
  )
  stop_reason <- if (is.null(stop_event)) {
    "generator_exhausted"
  } else {
    stop_event$reason %||% "complete"
  }
  if (!identical(stop_reason, "complete")) {
    cli::cli_abort(
      c(
        "Task did not complete",
        "x" = "Agent stopped with reason {.val {stop_reason}}"
      ),
      class = "deputy_cli_task_failed"
    )
  }
  invisible(stop_event)
}

cli_read_input <- function(prompt) {
  cat(prompt)
  utils::flush.console()
  value <- readLines(stdin(), n = 1L, warn = FALSE)
  if (length(value) == 0L) NULL else value[[1L]]
}

cli_run_interactive <- function(
  agent,
  verbose = FALSE,
  debug_log = NULL,
  input_reader = cli_read_input
) {
  if (!is.null(debug_log)) {
    debug_log("run_interactive started")
  }

  repeat {
    input <- tryCatch(
      input_reader(cli::col_cyan("> ")),
      error = function(error) {
        if (
          grepl("EOF|end of file|connection", error$message, ignore.case = TRUE)
        ) {
          return(NULL)
        }
        cli::cli_alert_warning("Input error: {error$message}")
        NULL
      }
    )
    if (is.null(input)) {
      cli::cli_text("")
      cli::cli_alert_info("Goodbye!")
      break
    }

    input <- trimws(input)
    if (!nzchar(input)) {
      next
    }

    command <- cli_process_command(input, agent)
    if (command$is_command) {
      if (!is.null(debug_log)) {
        debug_log("command: ", input)
      }
      if (identical(command$action, "quit")) {
        cli::cli_alert_info("Goodbye!")
        break
      }
      next
    }

    cli::cli_text("")
    cli_walk_agent_events(
      agent,
      input,
      function(event) {
        cli_render_event(
          event,
          verbose = verbose,
          mode = "interactive",
          debug_log = debug_log
        )
      }
    )
    cli::cli_text("")
  }
  invisible(NULL)
}

cli_load_mcp <- function(agent, config, debug_log = NULL) {
  if (!isTRUE(config$mcp)) {
    return(invisible(NULL))
  }

  servers <- cli_split_csv_values(config$mcp_server)
  servers <- unique(servers)
  if (length(servers) == 0L) {
    servers <- NULL
  }
  if (!is.null(debug_log)) {
    debug_log(
      "Loading MCP tools with servers=",
      if (is.null(servers)) "<all>" else paste(servers, collapse = ",")
    )
  }
  agent$load_mcp(config = config$mcp_config, servers = servers)
  invisible(NULL)
}

deputy_cli_main <- function(config) {
  config <- cli_normalize_config(config)
  if (isTRUE(config$no_color)) {
    old_colors <- getOption("cli.num_colors")
    options(cli.num_colors = 1)
    on.exit(options(cli.num_colors = old_colors), add = TRUE)
  }

  debug_enabled <- isTRUE(config$debug) || !is.null(config$debug_file)
  debug_log <- cli_create_debug_logger(
    enabled = debug_enabled,
    path = config$debug_file
  )
  on.exit(attr(debug_log, "close")(), add = TRUE)
  if (debug_enabled) {
    debug_log("Debug mode enabled")
  }

  chat <- tryCatch(
    cli_create_chat(config$provider, config$model),
    error = function(error) {
      cli::cli_abort(c(
        "Failed to connect to provider",
        "x" = error$message,
        "i" = "Check your provider credentials and configuration"
      ))
    }
  )
  if (debug_enabled) {
    model <- config$model %||% "<default>"
    debug_log(
      "Chat initialized for provider=",
      config$provider,
      " model=",
      model
    )
  }

  agent <- Agent$new(
    chat = chat,
    tools = cli_get_tools(config$tools, include_ask = !config$no_ask),
    system_prompt = cli_get_system_prompt(
      config$system_prompt,
      config$system_prompt_file
    ),
    permissions = cli_get_permissions(
      config$permissions,
      config$dir
    ),
    usage_limits = cli_get_usage_limits(
      max_requests = config$max_requests,
      max_cost = config$max_cost
    ),
    working_dir = config$dir
  )
  if (debug_enabled) {
    debug_log(
      "Agent created with tool preset=",
      config$tools,
      " and permission mode=",
      config$permissions
    )
  }

  cli_load_mcp(
    agent,
    config,
    debug_log = if (debug_enabled) debug_log else NULL
  )
  if (!is.null(config$session)) {
    if (!file.exists(config$session)) {
      cli::cli_abort("Session file not found: {.path {config$session}}")
    }
    agent$load_session(config$session)
  }

  if (is.null(config$task)) {
    cli_print_welcome(agent, config$tools, config$permissions)
    cli_run_interactive(
      agent,
      verbose = config$verbose,
      debug_log = if (debug_enabled) debug_log else NULL
    )
  } else {
    cli_run_task(
      agent,
      config$task,
      verbose = config$verbose,
      debug_log = if (debug_enabled) debug_log else NULL
    )
  }

  if (!is.null(config$save_session)) {
    agent$save_session(config$save_session)
  }
  invisible(agent)
}
