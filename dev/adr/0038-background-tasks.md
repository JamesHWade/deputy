# ADR-0038: Background tasks on retained agents

Status: implemented. Extends ADR-0024 (retained conversations).

## Problem

Every model-facing delegation blocks. `delegate_to_agent`, `delegation_tool()`
and graph routes resolve their tool call only when the subagent's run has
settled, so a lead cannot work while a specialist works, cannot collect
whichever result is ready first, and cannot drop a task it no longer needs.
Hosts already have what this needs (`continue_agent_async()`, the queue,
leases, cancellation, inspection, observation); models do not.

## Contract

`background_tools(owner, agents, usage_limits)` returns five tools for the
owner's model. `agents` names retained agents by handle; the model sees only
the names.

| Tool | Returns | Blocks |
|------|---------|--------|
| `task_start(agent, task)` | a task ID and state, at once | no |
| `task_status(task_ids)` | state and progress of each task | no |
| `task_wait(task_ids, until)` | outcomes of settled tasks | until one (or all) settles |
| `task_follow_up(task_id, task)` | a new task ID on the same agent | no |
| `task_cancel(task_id, reason)` | the state after the request | no |

A task is one delegation to a retained agent, started through
`continue_conversation_queued()`: the same admission, lease, budget
intersection, guard, hook forwarding, lifecycle record, observation events and
settlement as `delegation_tool()`. The only new behaviour is that the tool
call returns before the delegation settles. There is no second run engine,
scheduler or store.

`owner$background_tasks()` is the host's view: one row per task with its
state, delegation ID, the run and tool call that started it, and the task it
follows. Transcripts, tool activity and outcomes come from the existing
`inspect_subagents()`, `observe_subagents()` and `read_subagent_result()`,
through `DelegationDisclosure`, keyed by that delegation ID. Blocking
delegation and `parallel_delegate()` are unchanged.

## Lifecycle

Tasks belong to the owner run that started them.

- **States.** `queued` (waiting for a busy agent), `running`, `cancelling`,
  then one of `completed`, `failed`, `cancelled`, `stopped` (a limit or a
  hook ended it) or `rejected` (refused when its turn came). A final state is
  what the delegation record says, never what the subagent said.
- **One conversation at a time.** A retained agent has one lease. A start or
  follow-up for a busy agent waits in the existing queue, in order. A
  follow-up continues the same conversation and records the task it follows.
- **Waiting.** `task_wait` is one tool call that resolves on settlement. It
  returns every task that has settled and not been collected, so tasks that
  finish together arrive together, in settlement order. With nothing pending
  it returns at once and says so. It makes no model request while it waits.
- **Cancellation** is the existing cooperative stop. Cancelling a queued task
  removes it before it starts. Cancelling a settled task changes nothing and
  reports the state it settled in.
- **Run end.** When the owner's pass ends for any reason (answer, limit,
  interrupt, error), queued tasks are cancelled, running tasks are asked to
  stop with `parent_completed`, and the run waits for them to settle before
  `Stop` and `SessionEnd`. The run's usage therefore includes every task, no
  lease or reservation outlives the run, and uncollected tasks stay in
  `background_tasks()` with `collected = FALSE`.
- **Handles.** A task ID is a random locator in the owner's private registry
  for the current run. Another agent, a later run or host code outside the
  governed tool call cannot use it, and it carries no permissions or budget.
  Earlier runs' rows stay readable to the host until the next run starts.
- **Capacity.** `max_active` bounds unsettled tasks and `max_tasks` bounds
  tasks per run. At capacity a start is refused, as graph admission is.

## Accounting

Blocking delegation never had a parent spending beside its children. Now it
does, so:

- A task's allocation is `usage_limits` intersected with the agent's lifetime
  remainder, its own limits and the owner run's unreserved remainder, as for
  `delegation_tool()`. It is reserved in full before `task_start` returns.
- The owner's own limit checks subtract the reservations of unsettled
  background tasks. Requests and tool calls are therefore exact: owner plus
  tasks cannot exceed the run's limits.
- A start is refused when its reservation would leave the owner nothing in a
  dimension the run limits. In practice the host gives background tasks a
  finite limit in each dimension the owner's run has one.
- At settlement the reservation is released, the task's actual usage is added
  to the owner's run, and the owner's limits are rechecked.
- Token and cost limits stay observed, not reserved per request: each
  producer running at once (the owner and each task) can overshoot by one
  response, as ADR-0008 and ADR-0025 already state.

## Governance

Unchanged, and checked at each subagent tool call rather than at dispatch:
the retained agent's permissions, the owner's current permissions (so
narrowing after `task_start` applies to the running task), and the owner's
`PreToolUse`/`PostToolUse`/`PostToolUseFailure` hooks. The five tools carry
Deputy's private composition marker: they run only as the owner's governed
tool call, are admitted in read-only and plan modes like other delegation
tools, and cannot be registered on another agent.

## Not included

- Graph members cannot start background tasks; an owner with a delegation
  graph is refused. Graph routes stay blocking.
- An owner with a `TrustedResults` policy cannot register the tools: the
  route check admits single-agent routes only, so registration fails closed.
- `AgentDefinition` subagents stay blocking and fresh. A `LeadAgent` can hold
  retained agents and background tools beside its definitions.
- No detached or durable tasks, no timers and no survival across restart
  (host-scheduled jobs are ADR-0027).
