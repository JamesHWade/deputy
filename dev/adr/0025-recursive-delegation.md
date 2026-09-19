# ADR-0025: Root-owned bounded recursive delegation

Status: implemented for #169, extending ADR-0024.

The host configures a graph with `root$retain_agent_graph(agents, routes, ...)`.
Every node is an independently configured Agent and Chat. The root atomically
retains all member conversations, installs declared route tools, and owns their
lifecycle records. A route fixes its target and allocation; the model supplies
only a task brief. Members do not own nested registries. This permits a host to
configure cyclic routes while one lease per Chat rejects reentry into a busy
ancestor. Fresh AgentDefinition delegation remains unchanged.

Depth starts at zero for the root. Admission checks the maximum depth, lifetime
invocation count, and simultaneous queued/running child count before dispatch.
A caller awaiting its child occupies a slot: root → analyst → reviewer needs two
child slots. At capacity the call rejects; there is no background scheduler or
unbounded queue. Each retained conversation also keeps its finite `max_runs`.

One graph ledger accumulates requests, attempted tool calls, reported tokens and
estimated cost until explicit graph release. It samples active runs and stores
each node's own usage, avoiding double charging inclusive child results. The
existing per-route, caller and retained-handle allocations still intersect.
Requests reserve their count before provider dispatch. Tool attempts count even
when denied. Tokens and cost are observed from responses: requests already in
flight can overshoot those ceilings, up to the bounded concurrent producers.
Missing completed cost fails closed under a finite cost ceiling. A host follow-up
or a new root run does not replenish the graph budget.

Every descendant tool is governed by its own policy and every ancestor's current
policy. Ancestor PreToolUse, PostToolUse and PostToolUseFailure hooks run once per
registry; a nearer allow cannot override an ancestor denial or stop. Graph tools
require the exact caller's governed ellmer tool invocation. Ordinary host aliases
cannot run or mutate a retained member. Shared executable closures remain trusted
host resources, not a sandbox or a credential boundary.

All records and ordered event envelopes belong to the root. They carry exact
parent Agent/run/tool-call identity plus `parent_delegation_id`, `depth` and
`root_agent_id`. Authorized root inspection selects any descendant independently
of the root's model context. The bounded event ring reports gaps and supports
snapshot recovery; observers never consume or execute a child stream. Separate
child panels display ancestry and retained transcripts. Native nested shinychat
tool-card streams are not required by this contract.

Cancellation marks the requested subtree, stops active producers cooperatively,
and prevents queued descendants from dispatching. Unrelated siblings keep their
own records and execution. Completion asks any outstanding descendants to stop;
callers must await settlement before release. Partial transcript and terminal
records remain inspectable. There is no force-kill, refund, retry or exactly-once
external-effect guarantee.

`release_agent_graph()` releases the whole idle graph and its snapshots, removes
its route tools, and returns borrowed members to standalone host use. It does not
close their external resources. The graph references its root weakly, allowing
idle owner collection to release members. A newly retained graph represents a
new host authorization. Models cannot reset or recreate the graph.

Deterministic transport tests use real local HTTP producers without paid model
calls. The companion Shiny app and user guide are tracked in PR #176. Durable
restart/recovery remains #42; saved transcripts do not restore execution ownership.
