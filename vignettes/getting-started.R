## ----include = FALSE----------------------------------------------------------
knitr::opts_chunk$set(
  collapse = TRUE,
  comment = "#>",
  eval = FALSE
)

## -----------------------------------------------------------------------------
# # Install from GitHub
# # install.packages("pak")
# pak::pak("JamesHWade/deputy")

## -----------------------------------------------------------------------------
# pak::pak("tidyverse/ellmer")

## -----------------------------------------------------------------------------
# library(deputy)
#
# # Create an agent with file tools
# agent <- Agent$new(
#   chat = ellmer::chat("openai/gpt-4o"),
#   tools = tools_file()
# )
#
# # Run a task
# result <- agent$run_sync("What R files are in the current directory?")
# cat(result$response)

## -----------------------------------------------------------------------------
# for (event in agent$run("Analyze the structure of this project")) {
#   switch(event$type,
#     "text" = cat(event$text),
#     "tool_start" = cli::cli_alert_info("Calling {event$tool_name}..."),
#     "tool_end" = cli::cli_alert_success("Done"),
#     "stop" = cli::cli_alert("Finished! Cost: ${event$cost$total}")
#   )
# }

## -----------------------------------------------------------------------------
# # Combine multiple tool bundles
# agent <- Agent$new(
#   chat = ellmer::chat("openai/gpt-4o"),
#   tools = c(tools_file(), tools_code())
# )

## -----------------------------------------------------------------------------
# # Create a custom tool
# tool_weather <- ellmer::tool(
#   name = "get_weather",
#   description = "Get the current weather for a location",
#   arguments = list(
#     location = ellmer::tool_arg(
#       type = "string",
#       description = "City name"
#     )
#   ),
#   .fun = function(location) {
#     # Your implementation here
#     paste("Weather in", location, "is sunny, 72F")
#   }
# )
#
# agent <- Agent$new(
#   chat = ellmer::chat("openai/gpt-4o"),
#   tools = list(tool_weather)
# )

## -----------------------------------------------------------------------------
# # Allows: file read/write (in working dir), R code execution
# # Denies: bash commands, web access, package installation
# agent <- Agent$new(
#   chat = ellmer::chat("openai/gpt-4o"),
#   tools = tools_file(),
#   permissions = permissions_standard()
# )

## -----------------------------------------------------------------------------
# # Only allows reading files - no writes, no code execution
# agent <- Agent$new(
#   chat = ellmer::chat("openai/gpt-4o"),
#   tools = tools_file(),
#   permissions = permissions_readonly()
# )

## -----------------------------------------------------------------------------
# # Allows everything - use with caution!
# agent <- Agent$new(
#   chat = ellmer::chat("openai/gpt-4o"),
#   tools = tools_all(),
#   permissions = permissions_full()
# )

## -----------------------------------------------------------------------------
# perms <- Permissions$new(
#   file_read = TRUE,
#   file_write = "/path/to/allowed/dir",  # Restrict to specific directory
#
#   bash = FALSE,
#   r_code = TRUE,
#   web = FALSE,
#   max_turns = 10,
#   max_cost_usd = 0.50
# )
#
# agent <- Agent$new(
#   chat = ellmer::chat("openai/gpt-4o"),
#   permissions = perms
# )

## -----------------------------------------------------------------------------
# perms <- Permissions$new(
#   can_use_tool = function(tool_name, tool_input, context) {
#     # Block any file writes to sensitive directories
#     if (tool_name == "write_file") {
#       if (grepl("^\\.env|secrets|credentials", tool_input$path)) {
#         return(PermissionResultDeny(
#           reason = "Cannot write to sensitive files"
#         ))
#       }
#     }
#     PermissionResultAllow()
#   }
# )

## -----------------------------------------------------------------------------
# agent$add_hook(HookMatcher$new(
#   event = "PostToolUse",
#   callback = function(tool_name, tool_result, context) {
#     cli::cli_alert_info("Tool {tool_name} completed")
#     HookResultPostToolUse()
#   }
# ))

## -----------------------------------------------------------------------------
# agent$add_hook(HookMatcher$new(
#   event = "PreToolUse",
#   pattern = "^run_bash$",  # Only match bash tool
#   callback = function(tool_name, tool_input, context) {
#     if (grepl("rm -rf|sudo|chmod 777", tool_input$command)) {
#       HookResultPreToolUse(
#         permission = "deny",
#         reason = "Dangerous command pattern detected"
#       )
#     } else {
#       HookResultPreToolUse(permission = "allow")
#     }
#   }
# ))

## -----------------------------------------------------------------------------
# # Save the current session
# agent$save_session("my_session.rds")
#
# # Later, restore it
# agent2 <- Agent$new(chat = ellmer::chat("openai/gpt-4o"))
# agent2$load_session("my_session.rds")
#
# # Continue the conversation
# result <- agent2$run_sync("Continue where we left off...")

## -----------------------------------------------------------------------------
# # Define specialized sub-agents
# code_agent <- agent_definition(
#   name = "code_analyst",
#   description = "Analyzes R code and suggests improvements",
#   prompt = "You are an expert R programmer. Analyze code for best practices.",
#   tools = tools_file()
# )
#
# data_agent <- agent_definition(
#   name = "data_analyst",
#   description = "Analyzes data files and provides statistical summaries",
#   prompt = "You are a data analyst. Provide clear statistical insights.",
#   tools = tools_data()
# )
#
# # Create a lead agent that can delegate
# lead <- LeadAgent$new(
#   chat = ellmer::chat("openai/gpt-4o"),
#   sub_agents = list(code_agent, data_agent),
#   system_prompt = "You coordinate between specialized agents to complete tasks."
# )
#
# # The lead agent will automatically delegate to sub-agents as needed
# result <- lead$run_sync("Review the R code in src/ and analyze the data in data/")

## -----------------------------------------------------------------------------
# result <- agent$run_sync("Analyze this project")
#
# # The final response
# cat(result$response)
#
# # Cost information
# result$cost
# #> $input
# #> [1] 1250
# #> $output
# #> [1] 450
# #> $total
# #> [1] 0.0045
#
# # Execution duration
# result$duration
# #> [1] 3.45  # seconds
#
# # Stop reason
# result$stop_reason
# #> [1] "complete"
#
# # All events (for detailed analysis)
# length(result$events)
# #> [1] 12

## -----------------------------------------------------------------------------
# # OpenAI
# agent <- Agent$new(chat = ellmer::chat("openai/gpt-4o"))
#
# # Anthropic
# agent <- Agent$new(chat = ellmer::chat("anthropic/claude-sonnet-4-5-20250929"))
#
# # Google
# agent <- Agent$new(chat = ellmer::chat("google/gemini-1.5-pro"))
#
# # Local models via Ollama
# agent <- Agent$new(chat = ellmer::chat("ollama/llama3.1"))

## -----------------------------------------------------------------------------
# # Example combining best practices
# agent <- Agent$new(
#   chat = ellmer::chat("openai/gpt-4o"),
#   tools = tools_file(),
#   permissions = Permissions$new(
#     file_write = getwd(),
#     max_turns = 20,
#     max_cost_usd = 1.00
#   )
# )
#
# agent$add_hook(HookMatcher$new(
#   event = "PostToolUse",
#   callback = function(tool_name, tool_result, context) {
#     message(sprintf("[%s] %s", Sys.time(), tool_name))
#     HookResultPostToolUse()
#   }
# ))
#
# for (event in agent$run("Organize the files in this directory")) {
#   if (event$type == "text") cat(event$text)
# }
