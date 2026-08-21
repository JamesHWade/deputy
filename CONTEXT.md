# deputy

A provider-agnostic framework for building agentic AI workflows in R, built on ellmer. This glossary fixes the vocabulary used in issues, commits, and documentation.

## Language

### Agents

**Agent**:
The runtime object that drives a conversation with an LLM, executes tool calls, and enforces permissions. Always the R6 object, never a spec or a role.
_Avoid_: assistant, bot, LLM

**AgentDefinition**:
A declarative specification of an agent — name, prompt, tools, model, skills — loaded from a markdown file or constructed in code. A definition is not runnable on its own; it describes an Agent that a LeadAgent can instantiate.
_Avoid_: agent config, agent spec, custom agent

**LeadAgent**:
An Agent that can delegate work to subagents. The only kind of Agent that acts on an AgentDefinition.
_Avoid_: orchestrator, supervisor, parent agent

**Subagent**:
An Agent instantiated by a LeadAgent to carry out one delegated task, with its own conversation and its own permissions. Subordinate for the duration of the delegation only.
_Avoid_: child agent, worker, sub-agent (hyphenated)

**Delegation**:
The act of a LeadAgent handing a task to a subagent and receiving its result.
_Avoid_: dispatch, handoff, spawning

### Conversation state

**Run**:
One invocation of an Agent against a task, ending when the model stops, a limit is reached, or it is interrupted. An Agent may perform many runs over its lifetime.
_Avoid_: execution, invocation, call

**Turn**:
A single exchange within a run — one model response and any tool calls it requested.
_Avoid_: step, iteration, round

**Conversation snapshot**:
The serialized contents of an Agent's conversation, written to and read from disk by `save_session()` and `load_session()`. Concerns what was said, not who is saying it.
_Avoid_: session, session file, saved session, conversation state

**Compaction**:
Replacing older turns with a summary to reduce context size, preserving the thread of the conversation while discarding its detail.
_Avoid_: truncation, pruning, summarization

**Checkpoint**:
A recorded state of the files in the workspace, restorable by rewinding. Concerns the filesystem, never the conversation.
_Avoid_: snapshot, save point

### Control

**Tool**:
A function exposed to the model, carrying a description and annotations that declare its effects.
_Avoid_: function, capability, action

**Tool annotation**:
A declaration of a tool's effects — whether it reads only, destroys, reaches outside the workspace, or is safe to retry. Annotations are what permissions reason about; they describe the tool, not the caller.
_Avoid_: tool metadata, hints, flags

**Permission mode**:
The policy governing which tools an Agent may call in a run.
_Avoid_: security level, access mode, sandbox mode

**Hook**:
A callback fired at a named point in an Agent's lifecycle, able to observe a run and, at some points, alter or block it.
_Avoid_: callback, middleware, listener, interceptor

**Hook event**:
The named lifecycle point a hook is registered against.
_Avoid_: trigger, lifecycle stage

**Skill**:
A bundle of prompt text, tools, and metadata that can be loaded into an Agent to specialize it.
_Avoid_: plugin, extension, module, capability pack
