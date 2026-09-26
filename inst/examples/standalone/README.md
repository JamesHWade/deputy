# Standalone Deputy examples

Short scripts that each show one part of Deputy. Every script runs on its own
with `Rscript`, keeps any files it creates in a temporary directory, and
doesn't depend on the working directory or the other scripts.

You need Deputy and an OpenAI API key in `OPENAI_API_KEY`. `08-skills.R` and
`09-debate.R` also need the yaml package. The scripts make real, billable
requests to `gpt-6-luna`; set `DEPUTY_EXAMPLE_MODEL` to use another OpenAI
model.

```bash
DEPUTY_EXAMPLE_MODEL=gpt-6-luna Rscript inst/examples/standalone/01-basic.R
```

```r
example <- system.file("examples", "standalone", "01-basic.R", package = "deputy")
source(example)
```

| Script | Shows |
| --- | --- |
| 01-basic.R | A run with a request limit |
| 02-tools.R | Reading a temporary file with `read_file` and listing the tool calls |
| 03-permissions.R | Readonly mode blocking a registered `write_file` tool |
| 04-hooks.R | A `PostToolUse` hook keeping an audit record |
| 05-delegation.R | A `LeadAgent` handing a code review to a readonly subagent |
| 06-structured-output.R | A typed result checked with `validate` |
| 07-session-resume.R | Saving a conversation and continuing it in a new `Agent` |
| 08-skills.R | Loading a skill from a `SKILL.md` file |
| 09-debate.R | Two subagents arguing opposite sides, then a moderator |
| 10-evaluation.R | Scoring an agent on fixed cases, with run IDs, usage and cost |

When you `source()` a file example, `workspace` holds its temporary directory
so you can look at it afterwards. Wording and tool choices vary between live
runs. The package tests run these scripts with canned model responses, which
checks the code but not the quality of live answers.

## The debate example

`09-debate.R` asks a `support` and a `challenge` subagent the same question at
once, then has a moderator weigh their answers with the bundled `debate`
skill: at most three model requests in all. Set `DEPUTY_DEBATE_TOPIC` to
change the question. `comparison` holds the side-by-side Markdown table, and
`batch` holds both results and their usage. If either side fails, the table
says so and the script stops before the moderator.

To reuse only the moderator's prompt, load the skill into your own agent and
pass it the question and both arguments:

```r
agent$load_skill(system.file("skills", "debate", package = "deputy"))
```

## The evaluation example

`10-evaluation.R` runs a fresh readonly agent on each of two fixed prompts and
prints one row per case: pass or fail, run ID, stop reason, requests, tokens,
cost and duration. Replace `cases` and the scoring rule with your own. With an
OpenTelemetry tracer configured before ellmer loads, `run_id` matches the
`deputy.run.id` attribute on the run's span.

For a person to approve tool calls before they run, see `../approval-gates.R`
and `vignette("approvals", package = "deputy")`.
