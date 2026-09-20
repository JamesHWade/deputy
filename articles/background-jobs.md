# Host-scheduled background jobs

A host can queue a task in one R process, execute it in another, and
inspect its outcome after both processes exit. Deputy stores execution
state and uses the ordinary governed Agent runtime. Your application
owns the scheduler, worker processes, authentication, resource factories
and conversation archive.

## Queue and run a job

Build the same configured Agent at admission and in the worker. Stable
identities and explicit definition and context revisions let Deputy
reject an incompatible binding before a model request or tool execution.

``` r

library(deputy)

make_worker <- function() {
  Agent$new(
    ellmer::chat_openai(model = "gpt-5.6-luna"),
    system_prompt = "Summarize the supplied report evidence.",
    agent_id = "report-agent",
    session_id = "report-session",
    permissions = permissions_readonly(),
    usage_limits = UsageLimits(max_requests = 4)
  )
}

path <- job_create(
  directory = "jobs",
  agent = make_worker(),
  task = "Explain the supplied report evidence.",
  owner_id = "report-owner",
  definition_revision = "report-definition-1",
  context_revision = "report-context-1",
  usage_limits = UsageLimits(max_requests = 4),
  associations = list(conversation_id = "report-conversation")
)
job_read(path)
```

The host stores `path` and dispatches a worker through its chosen
scheduler.
[`job_run()`](https://jameshwade.github.io/deputy/reference/job_run.md)
runs synchronously in that worker; it does not start a process or
register a recurring task itself.

[`job_read()`](https://jameshwade.github.io/deputy/reference/job_read.md)
only inspects the committed record. It does not bind an Agent, call a
provider or execute a tool, so hosts can use it for status displays and
recovery decisions.

``` r

authorize_job <- function(job) {
  # Application code authenticates the requester and checks current access.
  current <- lookup_authorized_job(job$id)
  list(
    job_id = current$id,
    owner_id = current$owner_id,
    definition_revision = current$definition_revision,
    context_revision = current$context_revision
  )
}

outcome <- job_run(path,
  bind = function(job) make_worker(),
  authorize = authorize_job
)
outcome$status
outcome$result
outcome$usage
```

`lookup_authorized_job()` belongs to your application. It must consult
current authorization and revisions, rather than simply echoing the
stored job. Reading a job also requires whatever access controls the
host applies to its storage. An `AgentJob` is a read-only inspection
value; it contains no live Agent, tools, callbacks, provider clients or
credentials.

The binder reconstructs the admitted configuration and selected
conversation context, including stable Agent and session identities and
the working directory. Definition revisions must cover external resource
configuration and tool closure state that a public tool fingerprint
cannot inspect. A factory can return
`list(agent = agent, cleanup = function() ...)` to transfer resource
cleanup to the worker. Returning an Agent alone leaves external
resources host-owned.

## Restart, decisions and cancellation

Queued work can be claimed after its creating process exits. This
includes a queued graph root: the worker restores the saved graph
ledger, reservations and limits before dispatching any node. A terminal
job is returned without binding resources or dispatching another
request. Losing a worker after execution may have begun leaves an
**indeterminate** job. Its allocation remains reserved;
[`job_run()`](https://jameshwade.github.io/deputy/reference/job_run.md)
will return that terminal inspection rather than rebinding or rerunning
it. An external effect may have completed without its result being
committed, so the host must reconcile that uncertainty before creating
new work.

A standalone Agent configured for durable approval can stop at an
`approval_pending` boundary. Resume that boundary using the existing
approval protocol through the job API. Approval recovery is supported
for a standalone Agent only; a pending approval inside a retained graph
is rejected rather than being replayed:

``` r

outcome <- job_run(path,
  bind = host_reconstruct_approved_agent,
  authorize = authorize_job,
  decision = "approve"
)
# Or, from a host control while the worker is running:
job_cancel(path, authorize = authorize_job, reason = "user_cancelled")
```

The host’s `host_reconstruct_approved_agent()` supplies the configured
resources and current permission callback. Approval recovery keeps prior
usage and completed effect evidence. It does not replay completed tool
calls. Cancellation is cooperative and has a separate control record, so
requesting it does not wait for the execution record’s lock. A process
that disappears cannot certify cleanup; the persisted cleanup
disposition reports that separately from the task outcome. If a task
result was produced before binder cleanup failed, its bounded result
summary remains available alongside the cleanup failure.

## Graphs and conversation storage

An explicitly configured graph root can own a job. Reconstruct the same
nodes, routes and source contexts in the binder. Deputy preserves
cumulative usage, consumed admissions, continuation counts and graph
limits; a new worker does not receive a fresh budget. Historical
delegation correlations remain in the job record. They do not recreate
live child handles or grant transcript access.

Jobs currently accept ordinary Agents and explicit graph roots with one
provider per node. A retained child cannot be detached into an
independent job, and durable approvals inside a retained graph remain
unsupported. Provider-native tools cannot supply the per-effect
callbacks required by the durable journal.

Saved conversation text, a shinychat branch and a provider batch
identifier serve different purposes. None replaces the job’s authority,
allocation, lifecycle and effect records. ellmer continues to own native
turns and content; shinychat or another host store continues to own
conversation persistence and branch selection.
