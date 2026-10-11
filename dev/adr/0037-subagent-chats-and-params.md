# ADR-0037: Host-built subagent chats and definition params

Status: Accepted for implementation in #252 (closes #237).

## Context

A definition chose a subagent's model but not its request parameters. `"inherit"`
and bare-id definitions clone the lead's Chat, which keeps the lead's
`ellmer::params()`; ellmer 0.5.0 has no public setter (`Chat$set_model()` changes
only the name and params live on the private `Model`). `"provider/model"`
definitions use `ellmer::chat()` defaults and lose the lead's provider,
endpoint and credentials, which rules them out for gateway clients built outside
ellmer. Hosts also could not inspect what a subagent ran with.

## Decision

`DelegationPolicy(chat = function(definition, context))` builds every subagent's
Chat when set, whatever the definition's model form, `parallel_delegate()`
responders included. `context` mirrors the resource factory's: delegation IDs,
`agent_name`, the child run context, the lead's `delegation_scope` as `scope`
and `working_dir`. Executable client configuration (credentials, gateways,
headers) stays with the host and out of `AgentDefinition` and its YAML, as
ADR-0013 and ADR-0019 require. The returned Chat is treated like a clone: it
must be an ellmer Chat that is not the lead's, not owned by a live Agent
(`chat_owners()`) and not owned by a retained conversation; Deputy clears its
turns, tools and tool callbacks before installing the definition's prompt and
tools. Any failure is a `deputy_delegation_binding` error during preparation,
so the binding is released and nothing is requested.

`AgentDefinition(params = )` carries the standard `ellmer::params()` arguments,
validated by `ellmer::params()`; `extra_args` are refused because they are not
portable. Without a factory, a `"provider/model"` definition passes them to
`ellmer::chat(params = )`. A clone-form definition cannot apply them, so
registering one with params on a lead without a factory fails
(`LeadAgent$new()` and `register_sub_agent()`) rather than dropping them. With
a factory, Deputy hands params to the factory inside the definition and neither
merges nor overrides; the manifest records what the Chat actually carries.

Deputy YAML stays version 1 with an optional `params` mapping (scalars, and a
string sequence for `stop_sequences`). It is written only when non-empty, so
files without params remain readable by earlier versions; earlier versions
reject a file that has it as an unknown field.

`DelegationManifest` moves to schema 2 with `provider` (the provider's name)
and `params` (standard params read through the public `get_model_object()`,
without `extra_args`). Version-1 records still construct, with an empty
provider and params. `policies$binding$chat` records `"host factory"` or
`"default"`; the function itself is never recorded, and credentials never are.
The definition ID digest includes params only when present, so existing IDs are
unchanged.

## Consequences

Retained conversations, graphs, `adopt_chat()` and context forks are unchanged:
the host already builds those Agents. A future public ellmer params setter would
let clone-form definitions apply params without a factory; the registration
check is the place to relax.
