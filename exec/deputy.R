#!/usr/bin/env Rapp
#| name: deputy
#| title: deputy
#| description: "Interactive AI agent CLI for R"

#| description: "LLM provider to use (anthropic, openai, google, ollama)"
#| short: 'p'
provider <- "anthropic"

#| description: "Model to use (provider-specific)"
#| short: 'm'
model <- NA_character_

#| description: "Tool preset (minimal, standard, dev, data, full)"
#| short: 't'
tools <- "standard"

#| description: "Permission mode (standard, plan, readonly, full)"
#| short: 'P'
permissions <- "standard"

#| description: "Maximum model requests before stopping"
#| short: 'n'
max_requests <- 25L

#| description: "Maximum cost in USD before stopping"
#| short: 'c'
max_cost <- NA_real_

#| description: "Path to a session file to load"
#| short: 's'
session <- NA_character_

#| description: "Path to save the session on exit"
#| short: 'S'
save_session <- NA_character_

#| description: "Custom system prompt to use"
#| short: 'y'
system_prompt <- NA_character_

#| description: "Path to a file containing the system prompt"
#| short: 'f'
system_prompt_file <- NA_character_

#| description: "Disable the ask_user tool"
#| short: 'A'
no_ask <- FALSE

#| description: "Enable MCP server tools from configuration"
#| short: 'M'
mcp <- FALSE

#| description: "Path to the MCP configuration file"
#| short: 'C'
mcp_config <- NA_character_

#| description: "MCP server name to load; repeat for multiple servers"
mcp_server <- c()

#| description: "Working directory for file operations"
#| short: 'd'
dir <- "."

#| description: "Show verbose output including tool calls"
#| short: 'v'
verbose <- FALSE

#| description: "Disable colored output"
no_color <- FALSE

#| description: "Enable debug logging for CLI diagnostics"
#| short: 'g'
debug <- FALSE

#| description: "Path to write debug logs"
#| short: 'G'
debug_file <- NA_character_

#| description: "Task to run; omit for interactive mode"
#| required: false
task <- NULL

deputy:::deputy_cli_main(list(
  provider = provider,
  model = model,
  tools = tools,
  permissions = permissions,
  max_requests = max_requests,
  max_cost = max_cost,
  session = session,
  save_session = save_session,
  system_prompt = system_prompt,
  system_prompt_file = system_prompt_file,
  no_ask = no_ask,
  mcp = mcp,
  mcp_config = mcp_config,
  mcp_server = mcp_server,
  dir = dir,
  verbose = verbose,
  no_color = no_color,
  debug = debug,
  debug_file = debug_file,
  task = task
))
