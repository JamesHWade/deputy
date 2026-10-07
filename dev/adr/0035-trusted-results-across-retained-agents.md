# ADR-0035: Trusted results across retained agents and delegation graphs

Status: accepted for implementation in #238. Amends ADR-0030; builds on
ADR-0024, ADR-0025 and ADR-0031.

## Context

ADR-0030 admitted delegation only through a `LeadAgent`, whose children are
built from definitions and inherit its policy. `delegation_tool()`,
`adopt_chat()` and graph routes stayed rejected, because the policy could not
see the tools of an agent reached through them. #238 (following
posit-dev/shinychat#423 and posit-dev/commons#398) needs Commons specialists,
retained across tasks and composed into graphs, to publish trusted results to
the host of the conversation, without weakening the no-bypass rule.

A designated tool was identified by name, and a tree pinned the first object
found under that name. A name alone cannot establish trust across agents the
host composes from separately built chats, and Commons' `commons_tag` is the
producer's own label, not proof.

## Decision

- **Producers can be named explicitly.** `TrustedResults(type = tool)` takes
  the tool object itself; `producers` keeps it and `results` its name. Wrapped
  tools are unwrapped to their source. Any registry in the tree that holds the
  name must hold that object, a designated tool is checked against it again
  when it executes, and every `trusted_result` event carries the producer's
  `tool_fingerprint` (the approval fingerprint of code, schema and metadata).
  Name-only policies keep working for agents and LeadAgents.
- **Admission happens when an agent is retained.** When the owner has a
  policy, `retain_conversation()` (used by `retain_agent()`, `adopt_chat()`,
  `fork_agent()` and graph setup) requires explicit producers for every type
  and checks the retained agent's complete registry against the combined
  policy, as a tree member: every designated name pinned to its producer, code
  execution and delegation rejected, everything else read-only and
  closed-world or exempt. A failure retains nothing and changes nothing.
- **The combined policy weakens neither side.** A retained agent's own policy
  adds its result types (pinned to its registered producers when given by
  name); a type both name must have the same producer, and a tool may produce
  one type. Both rules also hold across everything the root retains (graph
  members included), so two specialists can't give one type different
  producers. Exemptions are the intersection; a receipt applies if either
  asks. The combined policy is installed on the retained agent until release,
  which restores its own policy and removes the owner's `delegation_tool()`
  routes to it (they could only fail, and would fail the owner's next registry
  check); the owner's finalizer restores the policy too.
- **Routes are admitted by provenance, not by name.** `check_trusted_registry()`
  takes an `admit_route` predicate. A tool is an admitted route only when
  Deputy's composition marker names the registering agent as owner, it carries
  the handle of a conversation that agent's policy root retained under its
  policy, and, for graph routes, the tree's root is that policy root. Graph
  members find their policy root through a weak reference. Everything else
  that delegates (another owner's route, a released handle, a tool merely
  named `delegate_to_agent`) is still a bypass.
- **Execution-time binding.** Before each continuation, the installed policy
  and pinned sources must still be the admitted ones and the registry must
  still pass; the retained configuration check already refuses changed tools.
  `execute_tool()` refuses a designated tool that is not the pinned producer.
- **One delivery to the root.** The combined policy's `on_result` records the
  event in the root's run and calls the root's `on_result`, then the retained
  agent's own callback. Each callback runs even when the other fails, and the
  first failure fails the delivery. Delivery still happens in the producing
  agent's
  wrapper, before its model, offloading or hooks see the value, so receipts
  and the fail-closed behavior of ADR-0030 are unchanged. Graph members forward
  straight to the root, never through intermediate agents, so each publication
  is delivered there once with the producer's agent, session, run, delegation
  and tool-call IDs and its parent agent.

## Consequences

- A strict mini-agent can reach Commons specialists, retained or in a graph,
  through Deputy's own routes. Commons must be constrained: `run_sql` and
  `run_r` removed, `open_world_hint = FALSE` set deliberately on the kept
  tools, and `call_measure` given as the explicit producer.
- Permissions, hooks (including input review through `context$tool_arguments`),
  usage limits and the delegation lifecycle are unchanged: they still decide
  whether a producer runs.
- Delegated agents still cannot suspend for durable approval
  (#152/#42); review inputs in a separate executor, as the trusted mini-agent
  recipe does. Graph jobs (ADR-0027) treat interrupted descendant runs as
  indeterminate and do not repeat them, so a trusted result already delivered
  is not delivered again, and one interrupted before delivery is not retried.
- Retained agents that already belong to another trusted tree are refused.
