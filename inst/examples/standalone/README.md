# Standalone Deputy examples

Install deputy and its released ellmer dependency, set
`OPENAI_API_KEY`, and run any script independently with `Rscript`. Install the
optional packages `jsonlite` (structured output) and `yaml` (skills), for example
with `install.packages(c("jsonlite", "yaml"))`. Those scripts check these
dependencies before creating a chat. Live runs
make billable model requests. Set `DEPUTY_EXAMPLE_MODEL` to choose another
OpenAI model supported by your account.

```r
example <- system.file("examples", "standalone", "01-basic.R", package = "deputy")
source(example)
```

| Script | Demonstrates |
| --- | --- |
| 01-basic.R | Bounded run and final text |
| 02-tools.R | Read an actual temporary file and inspect tool calls |
| 03-permissions.R | A registered write tool remains denied in readonly mode |
| 04-hooks.R | Capture an audit record in the caller process |
| 05-delegation.R | LeadAgent and a bounded readonly reviewer |
| 06-structured-output.R | Parse a JSON object with jsonlite |
| 07-session-resume.R | Save, load into a fresh Agent, and continue |
| 08-skills.R | Load YAML skill metadata and prompt with yaml |
| 09-debate.R | Concurrent opposing perspectives, comparison, and bounded synthesis |

Scripts create their own temporary data and do not depend on the current
working directory or on one another. File examples print or retain their
temporary workspace paths in `workspace` for inspection. Session snapshots are
removed after loading. Model wording and tool selection can vary in live runs.

The package tests execute these same files in separate R environments with
scripted provider responses. They exercise Agent runs, tool execution/denial,
hook effects, delegation, structured parsing, session restoration, and skill
loading without network calls. The regular R CMD check CI runs those tests on
Linux, macOS, and Windows. This verifies the examples' runtime contracts, not
live model quality.

The debate example uses two independent stateless responders and then a
tool-free moderator with the bundled `debate` skill. It spends at most two
perspective requests plus one separately budgeted synthesis request. Set
`DEPUTY_DEBATE_TOPIC` to change the question. The `comparison` object is a
Markdown table suitable for a report; `batch` retains both child results and
usage. Failed or stopped perspectives remain visible, and prevent synthesis.
There is no tool-using worker or background scheduler in this example.

To reuse just the moderation prompt, call
`agent$load_skill(system.file("skills", "debate", package = "deputy"))` and
supply your own arguments. Loading the skill does not start responders.

For synchronous human approval and stateful gates, see `../approval-gates.R`
and the Hooks vignette.
