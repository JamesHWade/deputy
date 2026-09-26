# Tools

A tool is an R function the model can ask to call. Deputy ships tools
for files, data, the web and code, and any R function becomes a tool
once you describe it with
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).
Registering a tool only makes it available: the agent’s
[permissions](https://jameshwade.github.io/deputy/articles/permissions.md)
decide whether each call runs.

## Built-in tools

| Tool | What it does | Effects |
|----|----|----|
| `tool_read_file` | Read a text file, or pages of a PDF | read-only |
| `tool_read_markdown` | Convert a PDF, Word, PowerPoint or HTML file to Markdown (needs the Python `markitdown` module) | read-only |
| `tool_list_files` | List a directory | read-only |
| `tool_glob_files` | Find files by glob pattern | read-only |
| `tool_grep_files` | Search file contents | read-only |
| `tool_read_csv` | Read a CSV file and summarise it | read-only |
| `tool_write_file` | Write or append to a file | destructive |
| `tool_edit_file` | Replace text in a file | destructive |
| `tool_multi_edit` | Make several replacements in one file | destructive |
| `tool_run_r_code` | Run R code in a new R process | destructive, open world |
| `tool_run_bash` | Run a shell command | destructive, open world |
| `tool_web_fetch` | Fetch a web page as text | read-only, open world |
| `tool_web_search` | Search the web with DuckDuckGo | read-only, open world |
| `tool_ask_user` | Ask the person running the agent a question | read-only |

`run_r_code` and `run_bash` are trusted-code tools: the code runs with
your user account’s access to files and the network. The default
permissions deny both. [Running R
code](https://jameshwade.github.io/deputy/articles/code-execution.md)
covers when to enable them and how to sandbox model-written code
instead.

## Bundles and presets

Bundles group related tools:

``` r

library(deputy)

tools_file() # read_file, read_markdown, write_file, list_files
tools_data() # read_csv, read_file, read_markdown
tools_code() # run_r_code, run_bash
tools_web() # web_fetch, web_search
tools_all() # every built-in tool except ask_user
```

Combine them with [`c()`](https://rdrr.io/r/base/c.html):

``` r

agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-6-luna"),
  tools = c(tools_file(), tools_web()),
  permissions = Permissions(web = TRUE)
)
```

Presets are named combinations for common jobs:

| Preset | Tools |
|----|----|
| `tools_preset("minimal")` | `read_file`, `read_markdown`, `list_files` |
| `tools_preset("standard")` | `minimal` plus `write_file` |
| `tools_preset("data")` | `minimal` plus `read_csv` and `run_r_code` |
| `tools_preset("dev")` | `standard` plus `run_r_code` and `run_bash` |
| `tools_preset("full")` | [`tools_all()`](https://jameshwade.github.io/deputy/reference/tools_all.md) |

The `data` and `dev` presets include trusted-code tools, so they only do
something useful with permissions that allow code (`r_code = TRUE`,
`bash = TRUE`).

## Turn an R function into a tool

A tool needs a function, a name, a description the model reads, and the
types of its arguments. This one wraps
[`toupper()`](https://rdrr.io/r/base/chartr.html):

``` r

library(deputy)

uppercase <- ellmer::tool(
  base::toupper,
  name = "uppercase",
  description = "Convert text to upper case.",
  arguments = list(x = ellmer::type_string()),
  annotations = ellmer::tool_annotations(
    read_only_hint = TRUE,
    destructive_hint = FALSE,
    open_world_hint = FALSE,
    idempotent_hint = TRUE
  )
)
uppercase("hello")
#> [1] "HELLO"
```

Pass it to the agent like any other tool:

``` r

agent <- Agent$new(
  chat = ellmer::chat("openai/gpt-6-luna"),
  tools = list(uppercase)
)
agent$run_sync("Use the uppercase tool to shout 'hello'.")$response
```

The annotations tell Deputy what the function does. Permissions are
decided from them:

| Annotation | `TRUE` means |
|----|----|
| `read_only_hint` | the tool changes nothing |
| `destructive_hint` | the tool may delete or overwrite data |
| `open_world_hint` | the tool reaches outside the machine, for example the network |
| `idempotent_hint` | calling it twice has the same effect as calling it once |

Deputy takes annotations at their word; it doesn’t inspect the function
to check them. When you leave one out, Deputy assumes the risky answer:
the tool might destroy data, might reach the network, and isn’t safe to
retry. A tool that might reach the network then needs a policy with
`web = TRUE`, and one that might destroy data needs a policy that allows
file writes or shell commands. So declare all four. In `"readonly"` mode
a custom tool must also be listed in the policy’s `tool_allowlist`.

## Add, replace and inspect tools

Add tools to an existing agent with `$register_tool()` or
`$register_tools()`. Registering a name that already exists is an error
unless you pass `replace = TRUE`. `$set_tools()` replaces all tools at
once. Deputy checks the whole batch before changing anything, so one bad
tool leaves the agent’s tools as they were.

``` r

agent$register_tool(tool_list_files)
agent$register_tool(uppercase, replace = TRUE)
```

[`tool_metadata()`](https://jameshwade.github.io/deputy/reference/tool_metadata.md)
shows where a tool came from, which annotations it declares and which
defaults Deputy will assume, without running it:

``` r

tool_metadata(uppercase)
#> $name
#> [1] "uppercase"
#> 
#> $source
#> $source$type
#> [1] "package"
#> 
#> $source$package
#> [1] "base"
#> 
#> 
#> $annotations
#> $annotations$read_only_hint
#> [1] TRUE
#> 
#> $annotations$open_world_hint
#> [1] FALSE
#> 
#> $annotations$idempotent_hint
#> [1] TRUE
#> 
#> $annotations$destructive_hint
#> [1] FALSE
#> 
#> 
#> $missing_annotations
#> character(0)
#> 
#> $effective_annotations
#> $effective_annotations$read_only_hint
#> [1] TRUE
#> 
#> $effective_annotations$destructive_hint
#> [1] FALSE
#> 
#> $effective_annotations$idempotent_hint
#> [1] TRUE
#> 
#> $effective_annotations$open_world_hint
#> [1] FALSE
```

## Web tools

[`tools_web()`](https://jameshwade.github.io/deputy/reference/tools_web.md)
returns Deputy’s own `web_fetch` and `web_search`, which work with any
provider. Pass it your chat to use the provider’s built-in web tools
instead, where there are any (Anthropic, Google, and OpenAI search):

``` r

chat <- ellmer::chat("anthropic/claude-sonnet-5")
agent <- Agent$new(
  chat = chat,
  tools = tools_web(chat),
  permissions = Permissions(
    web = TRUE,
    tool_allowlist = c("web_search", "web_fetch")
  )
)
```

Provider tools run on the provider’s servers, so Deputy can’t check each
call. It checks them once, when they’re registered: the policy must
allow web access and list them in `tool_allowlist`. A policy with a
`can_use_tool` callback can’t use them at all, because the callback
would never see their arguments. Use
`tools_web(chat, use_native = FALSE)` when you need per-call checks.

## Skills

A skill packages instructions, tools and the packages they need, so you
can give the same abilities to several agents. Create one in code:

``` r

concise <- skill_create(
  "concise",
  prompt = "Answer in one short paragraph.",
  requires = list(packages = "base")
)
skill_check_requirements(concise)$ok
#> [1] TRUE
```

`agent$load_skill(concise)` appends the prompt to the agent’s system
prompt and registers the skill’s tools under the agent’s current
permissions. Missing packages produce a warning, and a tool name that
clashes with an existing tool is an error unless you pass
`allow_conflicts = TRUE`. `agent$skills()` lists what’s loaded.

Skills can also live in a directory with a `SKILL.md` prompt and a
`SKILL.yaml` that lists tools and requirements. Deputy ships two:
`data_analysis`, with exploratory analysis tools, and `debate`, a prompt
for weighing opposing arguments.

``` r

agent$load_skill(system.file("skills", "data_analysis", package = "deputy"))
```

Loading a skill directory sources the R files its tools are defined in,
so load only skills you trust.
[`skills_list()`](https://jameshwade.github.io/deputy/reference/skills_list.md)
lists the skills in a directory.

## More tools

- [Running R
  code](https://jameshwade.github.io/deputy/articles/code-execution.md):
  trusted R execution, persistent R sessions, and sandboxed interpreters
  through mcp-repl and MCP Console.
- [MCP servers](https://jameshwade.github.io/deputy/articles/mcp.md):
  tools, resources and prompts from Model Context Protocol servers.
- [Human input and
  approvals](https://jameshwade.github.io/deputy/articles/approvals.md):
  [`tools_interactive()`](https://jameshwade.github.io/deputy/reference/tools_interactive.md)
  lets the model ask a person questions.
