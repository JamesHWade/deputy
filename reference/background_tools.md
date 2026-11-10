# Create tools for running retained agents in the background

Lets `owner`'s model start tasks on retained agents and keep working
while they run. The model gets five tools:

## Usage

``` r
background_tools(
  owner,
  agents,
  usage_limits,
  descriptions = NULL,
  max_active = 4L,
  max_tasks = 16L
)
```

## Arguments

- owner:

  The [Agent](https://jameshwade.github.io/deputy/reference/Agent.md)
  whose model gets the tools. Register them on this agent only. It can't
  be a member of, or the owner of, a delegation graph, and can't have a
  [TrustedResults](https://jameshwade.github.io/deputy/reference/TrustedResults.md)
  policy.

- agents:

  A named character vector or list of handles from
  [`adopt_chat()`](https://jameshwade.github.io/deputy/reference/adopt_chat.md)
  or `owner$retain_agent()`. The names are what the model calls the
  agents.

- usage_limits:

  [UsageLimits](https://jameshwade.github.io/deputy/reference/UsageLimits.md)
  for each task. A task also can't exceed the agent's remaining budget
  or the owner run's.

- descriptions:

  Optional named character vector telling the model what each agent is
  for.

- max_active:

  Maximum number of tasks waiting or running at once. Further starts are
  refused until one finishes.

- max_tasks:

  Maximum number of tasks in one run of `owner`.

## Value

A named list of ellmer tools for `owner$register_tools()`.

## Details

- `task_start(agent, task)` starts a task and returns a task ID at once.

- `task_status(task_ids)` reports each task's state and progress.

- `task_wait(task_ids, until)` waits until a task finishes and returns
  the finished tasks' outcomes. It makes no model request while it
  waits.

- `task_follow_up(task_id, task)` sends another task to the same agent,
  which keeps its conversation.

- `task_cancel(task_id, reason)` asks a task to stop.

Each task is a call to a retained agent, like `owner$continue_agent()`:
the agent keeps its own permissions, each of its tool calls is also
checked against the owner's current permissions and tool hooks, and its
work can be followed with `owner$observe_subagents()` and
`owner$inspect_subagents()`. An agent runs one task at a time, so a task
for a busy agent waits its turn.

Tasks belong to the run that started them. When the owner's model stops,
tasks that are still waiting or running are cancelled and the run waits
for them to stop, so its usage includes theirs. Use
`owner$background_tasks()` to see every task of the latest run,
including ones the model never collected.

Use
[`delegation_tool()`](https://jameshwade.github.io/deputy/reference/delegation_tool.md)
instead when the model should simply wait for the agent's answer, and a
[LeadAgent](https://jameshwade.github.io/deputy/reference/LeadAgent.md)'s
`$parallel_delegate()` for one reply each from several subagents with no
tools. See
[`vignette("background-tasks")`](https://jameshwade.github.io/deputy/articles/background-tasks.md).

## Budgets

Each task's `usage_limits` are set aside from the owner's run when the
task starts and returned, less what the task used, when it finishes. The
owner's own requests and tool calls can't use what is set aside, so
together they stay within the run's request and tool-call limits. A task
that would leave the owner nothing under one of its run's limits is
refused, so give `usage_limits` a value for each limit the owner's run
has. Token and cost limits are checked after each response, so the owner
and each running task can each overshoot them by one response.

## Examples

``` r
if (FALSE) { # \dontrun{
lead <- Agent$new(ellmer::chat("anthropic/claude-sonnet-5"))
analyst <- adopt_chat(
  ellmer::chat("openai/gpt-6-luna"),
  owner = lead,
  permissions = permissions_readonly(),
  usage_limits = UsageLimits(max_requests = 20),
  history = "fresh",
  callbacks = "replace",
  name = "analyst"
)
lead$register_tools(background_tools(
  lead,
  agents = c(analyst = analyst),
  usage_limits = UsageLimits(max_requests = 5)
))
} # }
```
