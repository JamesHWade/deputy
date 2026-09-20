# Host-scheduled durable Agent jobs

A host can persist an admitted task, run it in a separate R worker and inspect
its state after that worker exits. Deputy supplies the durable execution record
and binds it to the existing governed Agent kernel. The host owns scheduling,
worker processes, authentication, resource factories and conversation storage.

## Reuse the existing runtime and journal

Job records use the same locked, checksummed, atomic revision store as durable
approvals (ADR-0016). Execution uses ordinary Agent runs, existing tool adapters,
current permission callbacks, cancellation and graph admission. Pending standalone
approvals resume through the existing approval protocol. A second tool executor,
conversation database or provider request pool is unnecessary.

The durable record contains the task, authenticated ownership associations,
definition/context revisions, source digests, stable Agent/session identities,
ordered state transitions, observed usage, allocations, effect evidence and
cleanup disposition. It never serializes provider clients, callbacks, tools,
promises, live leases or cleanup closures. The host reconstructs those resources.
Tool fingerprints describe public definitions, not captured closure state; the
host's definition revision must also identify the configuration of those resources.

Runtime event history is best-effort evidence. In addition to per-event and count
limits, checkpoints evict older events when the complete record exceeds the
shared store's atomic replacement budget. The committed drop count survives
subsequent checkpoints. Event eviction never removes authority, usage, effect
state, or the terminal outcome; if those fields alone cannot fit, persistence
fails explicitly.

For a configured graph, retain the route declarations, limits, cumulative usage,
consumed admissions and continuation counts. Admission and reservation changes
are checkpointed before a descendant can dispatch. Reconstructing the graph must
not reset its budgets, increase its depth/concurrency/count bounds or change a
route. The host rebinds the same selected conversation context; job storage does
not replace the host's conversation archive.

## Recovery boundaries

Queued work has not dispatched and can be claimed by a new authorized worker.
That includes a queued graph root: the worker rebinds the saved graph ledger,
reservations and limits before it can dispatch any node. A pending standalone
approval is an existing resumable boundary with saved authority, usage and
effect history. Completed, failed or cancelled jobs are inspected without
calling the provider or binding another tool execution. Only the standalone
approval boundary is resumable; a pending approval inside a retained graph is
not a supported recovery path.

Once a provider request or tool effect may have begun, losing the worker creates
an indeterminate job. The persisted allocation remains reserved and the terminal
record cannot be rerun or rebound through `job_run()`. An external effect may
have completed even if its result was never committed. The host must reconcile
it before creating new work; Deputy does not promise exactly-once execution
across arbitrary external systems.

A separately persisted cancellation request is visible while the execution record
is locked. Recovery checks it before dispatch, and an active worker uses the
existing cooperative interrupt path. Cleanup is recorded separately from task
success: when a task result was produced but binder cleanup fails, the bounded
result remains inspectable alongside the cleanup failure. A lost worker cannot
certify that an owned external resource was closed.
Successful cleanup clears its required flag; failed runtime detachment remains
uncertain and still requires reconciliation. Cleanup failure also prevents an
approval-pending job from becoming a resumable continuation.

Durable approval inside a retained graph remains unsupported by the existing
graph contract. A job must reject incompatible bindings rather than weaken that
restriction. A saved transcript or provider batch identifier is not a recoverable
job: neither carries these execution, authority, allocation and effect boundaries.
