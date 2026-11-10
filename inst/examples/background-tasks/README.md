# Background tasks

A script in which a lead agent runs two specialists in the background: it
starts an analyst and a reviewer, looks something up itself while they work,
collects the analyst's result, asks the analyst a follow-up question, cancels
the reviewer, and writes its answer. The script then prints what your code
can see of all that.

```r
source(system.file("examples/background-tasks/run.R", package = "deputy"))
```

It needs callr, httpuv and jsonlite. A local test server in a separate R
process stands in for the three models and answers from a fixed script, so
there are no API keys or paid requests, and the output is the same every run.

## What happens

`workflow.R` builds the three agents. The lead retains the analyst and the
reviewer with `retain_agent()` and gets the five task tools from
`background_tools()`. The lead's model then makes these calls:

1. `task_start` twice, in one response: the analyst summarizes measurements
   and the reviewer checks a draft. Both calls return a task ID at once.
2. `lookup_specification`, a tool of the lead's own, while both tasks run.
3. `task_wait`, which returns when the analyst finishes.
4. `task_follow_up` on the analyst's task. The analyst answers from the
   measurements it loaded for the first task, without loading them again.
5. `task_cancel` on the reviewer's task, then `task_wait` with
   `until = "all"`, which returns the follow-up's answer and the cancelled
   review together.
6. Its answer.

## What the script prints

- `lead$background_tasks()`: one row per task. The reviewer's task is
  `cancelled`, and the follow-up records the task it follows.
- `lead$list_subagents()`: the same three tasks as delegations, with the brief
  each was given.
- Tool activity from `lead$observe_subagents()`. The reviewer's `read_draft`
  finishes even though its task was cancelled: a task that is asked to stop
  completes the tool call it is in first.
- The analyst's conversation from `lead$inspect_subagents(transcript = TRUE)`,
  with both tasks in it.
- Each task's outcome, and the usage of the lead's run, which includes the
  specialists' requests and tool calls.

Reading the specialists' conversations goes through the lead's
`DelegationDisclosure()`. In the script a single `requester` object stands in
for a signed-in user; it is not authentication.

## How the order is fixed

Real tasks finish whenever they finish. To print the same thing every run,
each specialist's tool waits at a gate (`background_example_gate()` in
`workflow.R`) that a hook on the lead opens: the analyst's when the lead first
calls `task_wait`, the reviewer's after the lead has called `task_cancel`. The
lead's `lookup_specification` also waits until both specialists have begun
their tool calls. Your own tools need none of this.

`fixture.R` is the test server and `report.R` prints the host's view. From a
source checkout, `devtools::test(filter = "background-tasks-example")` runs
the script and checks its output.
