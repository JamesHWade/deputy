# Agent Configuration

This vignette covers the many ways to configure an agent: system
prompts, settings, skills, sessions, and result inspection.

## System Prompts

Every agent has a system prompt that shapes its behaviour. Pass it
directly at construction:

``` r
library(deputy)

agent <- Agent$new(
  chat = ellmer::chat_anthropic(),
  system_prompt = "You are a helpful data analyst. Always show your
    reasoning step by step. Use R code when calculations are needed."
)
```

The system prompt is prepended to the conversation. If you also load
skills (see below), their prompts are appended after the system prompt.

## Claude-Style Settings

deputy can load settings from `.claude/` directories, following the same
conventions as Claude Code:

``` r
# Load from project and user directories
settings <- claude_settings_load(
  setting_sources = c("project", "user"),
  working_dir = getwd()
)

# Apply to an agent
claude_settings_apply(agent, settings)
```

Settings sources:

- `"project"` – Reads from `.claude/` in the working directory
- `"user"` – Reads from `~/.claude/`
- A file path – Reads a specific `.json` settings file

This is useful when you want an agent that mirrors your Claude Code
setup.

## Skills

Skills are modular extensions that add tools and system prompt segments
to an agent. They live in directories with a `SKILL.yaml` (or
`SKILL.md`) file.

### Loading a Skill

``` r
skill <- skill_load("path/to/skill/directory")
agent$load_skill(skill)
```

### Creating a Skill Programmatically

``` r
skill <- skill_create(
  name = "data_analysis",
  description = "Helps with data analysis tasks",
  prompt = "When analysing data, always check for missing values first.",
  tools = tools_data(),
  version = "1.0.0"
)

agent$load_skill(skill)
```

### Listing Available Skills

``` r
skills_list("path/to/skills/directory")
```

### Skill Directory Format

A skill directory contains:

- `SKILL.yaml` – Metadata (name, version, description, requires)
- `SKILL.md` – System prompt extension (optional YAML frontmatter)
- `tools.R` – Tool definitions referenced in `SKILL.yaml` (optional)

## Session Management

Agents can save and restore their conversation state:

``` r
# Save current state
agent$save_session("my_session.rds")

# Later, restore it
agent2 <- Agent$new(chat = ellmer::chat_anthropic())
agent2$load_session("my_session.rds")

# Continue the conversation
result <- agent2$run_sync("What were we working on?")
```

Sessions persist the conversation turns, so the agent can pick up where
it left off.

## Working with AgentResult

Every call to `run_sync()` returns an `AgentResult` with rich metadata:

``` r
library(deputy)

chat <- ellmer::chat_anthropic(model = "claude-sonnet-4-20250514")
agent <- Agent$new(chat = chat, tools = tools_file())

result <- agent$run_sync("How many files are in the current directory?")
```

### Response Text

``` r
cat(result$response)
```

### Cost Information

``` r
result$cost
#> $input
#> [1] 1250
#> $output
#> [1] 450
#> $total
#> [1] 0.0045
```

### Execution Metadata

``` r
result$duration       # seconds
result$stop_reason    # "complete", "max_turns", "cost_limit", etc.
result$n_turns()      # number of conversation turns
result$is_success()   # TRUE if stop_reason == "complete"
```

### Event Stream

The full event stream is available for detailed analysis:

``` r
result$events         # list of AgentEvent objects
result$tool_calls()   # just the tool_start events
result$text_chunks()  # just the text events
```

## Provider Support

deputy works with any provider that ellmer supports:

| Provider     | Constructor           | Notes             |
|--------------|-----------------------|-------------------|
| Anthropic    | `chat_anthropic()`    | Native web tools  |
| OpenAI       | `chat_openai()`       | Structured output |
| Google       | `chat_google()`       | Native web search |
| Ollama       | `chat_ollama()`       | Local models      |
| Azure OpenAI | `chat_azure_openai()` | Enterprise        |

``` r
# Any ellmer chat works
Agent$new(chat = ellmer::chat_openai())
Agent$new(chat = ellmer::chat_anthropic())
Agent$new(chat = ellmer::chat_google())
Agent$new(chat = ellmer::chat_ollama(model = "llama3.1"))
```
