# Multi-agent orchestration for deputy

#' Create an Agent Definition
#'
#' @description
#' AgentDefinition describes a specialized agent that can be used by a lead
#' agent to delegate tasks. It bundles together a system prompt, tools, and
#' metadata about what the agent can do.
#'
#' @param name Unique name for this agent type
#' @param description Brief description of what this agent does (shown to lead agent)
#' @param prompt System prompt for this agent
#' @param tools Optional list of tools for this agent
#' @param model Model to use (default: "inherit" uses parent's model)
#' @param skills Optional list of skills to load
#' @return An `AgentDefinition` object
#'
#' @examples
#' \dontrun{
#' # Define a code review agent
#' code_reviewer <- agent_definition(
#'   name = "code_reviewer",
#'   description = "Reviews code for bugs, style issues, and best practices",
#'   prompt = "You are an expert code reviewer...",
#'   tools = list(tool_read_file, tool_list_files)
#' )
#'
#' # Use with a lead agent
#' lead <- LeadAgent$new(
#'   chat = ellmer::chat("openai/gpt-4o"),
#'   sub_agents = list(code_reviewer)
#' )
#' }
#'
#' @export
agent_definition <- function(
  name,
  description,
  prompt,
  tools = list(),
  model = "inherit",
  skills = list()
) {
  structure(
    list(
      name = name,
      description = description,
      prompt = prompt,
      tools = tools,
      model = model,
      skills = skills
    ),
    class = "AgentDefinition"
  )
}

#' @export
print.AgentDefinition <- function(x, ...) {
  cat("<AgentDefinition:", x$name, ">\n")
  cat("  description:", truncate_string(x$description, 60), "\n")
  cat("  tools:", length(x$tools), "\n")
  cat("  skills:", length(x$skills), "\n")
  cat("  model:", x$model, "\n")
  invisible(x)
}

#' LeadAgent R6 Class
#'
#' @description
#' A LeadAgent is an agent that can delegate tasks to specialized sub-agents.
#' It automatically has a `delegate_to_agent` tool that allows it to spawn
#' sub-agents based on registered AgentDefinitions.
#'
#' @export
LeadAgent <- R6::R6Class(
  "LeadAgent",
  inherit = Agent,

  public = list(
    #' @field sub_agent_defs List of AgentDefinition objects
    sub_agent_defs = NULL,

    #' @description
    #' Create a new LeadAgent.
    #'
    #' @param chat An ellmer Chat object
    #' @param sub_agents List of [agent_definition()] objects
    #' @param tools Additional tools for the lead agent
    #' @param system_prompt System prompt for the lead agent
    #' @param permissions Permissions for the lead agent (also applied to sub-agents)
    #' @param working_dir Working directory
    #' @return A new `LeadAgent` object
    initialize = function(
      chat,
      sub_agents = list(),
      tools = list(),
      system_prompt = NULL,
      permissions = NULL,
      working_dir = getwd()
    ) {
      # Validate sub-agent definitions
      for (def in sub_agents) {
        if (!inherits(def, "AgentDefinition")) {
          cli_abort("All sub_agents must be AgentDefinition objects")
        }
      }

      self$sub_agent_defs <- sub_agents

      # Build enhanced system prompt
      enhanced_prompt <- private$build_lead_prompt(system_prompt, sub_agents)

      # Create the delegate tool
      delegate_tool <- private$create_delegate_tool()

      # Combine tools
      all_tools <- c(list(delegate_tool), tools)

      # Call parent constructor
      super$initialize(
        chat = chat,
        tools = all_tools,
        system_prompt = enhanced_prompt,
        permissions = permissions,
        working_dir = working_dir
      )
    },

    #' @description
    #' Register a new sub-agent definition.
    #'
    #' @param definition An [agent_definition()] object
    #' @return Invisible self
    register_sub_agent = function(definition) {
      if (!inherits(definition, "AgentDefinition")) {
        cli_abort("{.arg definition} must be an AgentDefinition object")
      }

      self$sub_agent_defs <- c(self$sub_agent_defs, list(definition))

      # Rebuild and update system prompt to include new sub-agent
      # Extract base prompt (before sub-agent section) if possible
      current_prompt <- self$chat$get_system_prompt()
      base_prompt <- private$extract_base_prompt(current_prompt)
      new_prompt <- private$build_lead_prompt(base_prompt, self$sub_agent_defs)
      self$chat$set_system_prompt(new_prompt)

      cli_alert_info("Registered sub-agent: {.val {definition$name}}")
      invisible(self)
    },

    #' @description
    #' Get available sub-agent names.
    #'
    #' @return Character vector of sub-agent names
    available_sub_agents = function() {
      sapply(self$sub_agent_defs, function(d) d$name)
    },

    #' @description
    #' Print the lead agent.
    print = function() {
      super$print()
      cat("  sub_agents:", length(self$sub_agent_defs), "\n")
      if (length(self$sub_agent_defs) > 0) {
        names <- self$available_sub_agents()
        cat("    ", paste(names, collapse = ", "), "\n")
      }
      invisible(self)
    }
  ),

  private = list(
    # Build the lead agent's system prompt
    build_lead_prompt = function(base_prompt, sub_agents) {
      lines <- character()

      if (!is.null(base_prompt)) {
        lines <- c(lines, base_prompt, "")
      }

      if (length(sub_agents) > 0) {
        lines <- c(
          lines,
          "# Available Sub-Agents",
          "",
          "You can delegate specialized tasks to these sub-agents using the",
          "`delegate_to_agent` tool:",
          ""
        )

        for (def in sub_agents) {
          lines <- c(lines, paste0("## ", def$name), def$description, "")
        }

        lines <- c(
          lines,
          "When delegating, provide a clear task description. The sub-agent",
          "will complete the task and return results to you.",
          ""
        )
      }

      paste(lines, collapse = "\n")
    },

    # Extract base prompt (before sub-agent section) from full prompt
    extract_base_prompt = function(full_prompt) {
      if (is.null(full_prompt) || nchar(full_prompt) == 0) {
        return(NULL)
      }

      # Look for the sub-agent section marker
      marker <- "# Available Sub-Agents"
      marker_pos <- regexpr(marker, full_prompt, fixed = TRUE)

      if (marker_pos > 0) {
        # Extract everything before the marker
        base <- substr(full_prompt, 1, marker_pos - 1)
        # Trim trailing whitespace
        base <- sub("\\s+$", "", base)
        if (nchar(base) == 0) {
          return(NULL)
        }
        return(base)
      }

      # No marker found, return the full prompt as base
      full_prompt
    },

    # Create the delegate_to_agent tool
    create_delegate_tool = function() {
      # Capture self for the closure
      lead_agent <- self

      ellmer::tool(
        fun = function(agent_name, task) {
          # Find the agent definition
          def <- NULL
          for (d in lead_agent$sub_agent_defs) {
            if (d$name == agent_name) {
              def <- d
              break
            }
          }

          if (is.null(def)) {
            available <- lead_agent$available_sub_agents()
            ellmer::tool_reject(paste0(
              "Unknown agent: ",
              agent_name,
              ". ",
              "Available agents: ",
              paste(available, collapse = ", ")
            ))
          }

          # Create the sub-agent
          sub_agent <- private$create_sub_agent(def)

          # Run the task
          cli::cli_alert_info("Delegating to {.val {agent_name}}: {task}")

          result <- tryCatch(
            {
              sub_result <- sub_agent$run_sync(task)
              sub_result$response
            },
            error = function(e) {
              cli::cli_alert_danger(
                "Sub-agent {.val {agent_name}} failed: {e$message}"
              )
              ellmer::tool_reject(paste0(
                "Sub-agent '",
                agent_name,
                "' failed.\n",
                "Error: ",
                e$message
              ))
            }
          )

          # Fire SubagentStop hook
          lead_agent$hooks$fire(
            "SubagentStop",
            agent_name = agent_name,
            task = task,
            result = result,
            context = list(working_dir = lead_agent$working_dir)
          )

          result
        },
        name = "delegate_to_agent",
        description = "Delegate a task to a specialized sub-agent. The sub-agent will complete the task and return results.",
        arguments = list(
          agent_name = ellmer::type_string(
            "Name of the sub-agent to delegate to"
          ),
          task = ellmer::type_string("The task to delegate to the sub-agent")
        ),
        annotations = ellmer::tool_annotations(
          read_only_hint = FALSE,
          destructive_hint = FALSE
        )
      )
    },

    # Create a sub-agent from a definition
    create_sub_agent = function(def) {
      # Get the model to use
      if (def$model == "inherit") {
        # Get parent's provider info and create similar chat
        parent_provider <- self$provider()

        # Try to create a chat using the same provider type
        sub_chat <- tryCatch(
          {
            # Use ellmer's clone method if available
            if ("clone" %in% names(self$chat)) {
              self$chat$clone()
            } else {
              # Fallback: try to create from provider string
              # provider() returns strings like "openai", "anthropic", etc.
              ellmer::chat(parent_provider)
            }
          },
          error = function(e) {
            cli_abort(c(
              "Could not inherit model from parent for sub-agent {.val {def$name}}",
              "x" = e$message,
              "i" = "Please specify an explicit {.arg model} in {.fn agent_definition}"
            ))
          }
        )
      } else {
        # Use the specified model string (e.g., "openai/gpt-4o", "anthropic/claude-sonnet-4-5-20250929")
        sub_chat <- tryCatch(
          ellmer::chat(def$model),
          error = function(e) {
            cli_abort(c(
              "Failed to create chat for sub-agent {.val {def$name}}",
              "x" = "Invalid model: {.val {def$model}}",
              "i" = e$message
            ))
          }
        )
      }

      # Create the sub-agent
      sub_agent <- Agent$new(
        chat = sub_chat,
        tools = def$tools,
        system_prompt = def$prompt,
        permissions = self$permissions,
        working_dir = self$working_dir
      )

      # Load any skills
      for (skill in def$skills) {
        sub_agent$load_skill(skill)
      }

      sub_agent
    }
  )
)

#' Create a simple delegation agent
#'
#' @description
#' Convenience function to create a LeadAgent with common sub-agents for
#' code-related tasks.
#'
#' @param chat An ellmer Chat object
#' @param permissions Optional permissions
#' @return A [LeadAgent] object
#'
#' @examples
#' \dontrun{
#' agent <- agent_with_delegation(
#'   chat = ellmer::chat("openai/gpt-4o")
#' )
#'
#' result <- agent$run_sync("Review the code in main.R and suggest improvements")
#' }
#'
#' @export
agent_with_delegation <- function(chat, permissions = NULL) {
  # Define common sub-agents
  code_reader <- agent_definition(
    name = "code_reader",
    description = "Reads and explains code files. Good for understanding what code does.",
    prompt = "You are a code reading expert. Read files carefully and explain what the code does clearly and concisely.",
    tools = list(tool_read_file, tool_list_files)
  )

  code_analyzer <- agent_definition(
    name = "code_analyzer",
    description = "Analyzes code for bugs, issues, and improvements. Good for code review.",
    prompt = "You are a code analysis expert. Look for bugs, potential issues, and suggest improvements. Be specific and actionable.",
    tools = list(tool_read_file, tool_list_files)
  )

  LeadAgent$new(
    chat = chat,
    sub_agents = list(code_reader, code_analyzer),
    tools = tools_file(),
    permissions = permissions
  )
}
