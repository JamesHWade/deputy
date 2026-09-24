# Deliver trusted tool results outside model text

Decision date: 2026-09-23. Issue: [#197](https://github.com/JamesHWade/deputy/issues/197).
Builds on ADR-0007 (tool registration) and ADR-0002 (shinychat as host).

## Context

Will Landau's [trusted mini-agents](https://trustedminiagents.dev/definition.html)
require that (1) trusted tools produce every result, (2) each kind of result
comes from exactly one tool that nothing can bypass, and (3) a human reviews
the model-generated inputs. The recipe in `inst/examples/trusted-mini-agent/`
(#170) enforced all three by hand: host closures held the receipt and a
custom `can_use_tool` callback confined the registry. Deputy had no way to
designate a trusted tool, and `tool_end` events cannot carry a trusted value.
PostToolUse hooks may rewrite them, and large results are offloaded before
the event is built.

## Decision

- **An Agent-level policy, not an annotation.** `TrustedResults(type = "tool")`
  is a read-only S7 value passed to `Agent$new(trusted_results = )` and fixed
  for the Agent's lifetime. ADR-0007 says annotations describe behavior and
  never establish trust, so a result type is not a tool annotation or an
  AgentDefinition field. Each type maps to one tool and each tool to one type.
- **The whole registry is checked when it is published.** The constructor,
  `set_tools()`, `register_tools()` (and through them skills and MCP loading),
  clone rewiring and graph route installation call `check_trusted_registry()`
  on the complete tool list before `Chat$set_tools()`. A failure leaves the
  previous registry intact.
- **The no-bypass rule is explicit.** Trusted tools must be local function
  tools that neither execute code nor delegate. Other tools are rejected if
  they execute model-supplied code or delegate (`run_r_code`, `run_bash`,
  R session tools, composition, delegation and graph route tools), or if
  their effective annotations allow writes (including an explicit
  `destructive_hint = TRUE` beside `read_only_hint = TRUE`) or the open
  world. Unannotated tools get ADR-0007's conservative defaults and so are
  rejected. The host
  may list local function tools in `exempt_tools`. That is an explicit
  assertion, never inferred. MCP, provider-native, code-execution and
  delegation tools cannot be exempted.
- **Capture happens in the runtime wrapper.** `process_tool_result` sees the
  tool's return value before offloading and before any hook. It records a
  `"trusted_result"` AgentEvent carrying the result ID and type, the tool
  call ID, the arguments after conversion, and the verbatim value. It then
  calls `on_result(event)`, and only then does any output reach the model.
  `result_trusted_results()` reads these events from an AgentResult. Tool
  errors produce no trusted result.
- **Delivery fails closed.** If `on_result` signals an error, the event is
  still recorded, a `trusted_result_delivery_failed` notification is emitted,
  and the model receives a generic tool error. The model sees neither the
  value nor the host's error text.
- **Receipts are opt-in.** With `model_receipt = TRUE` the model receives a
  receipt naming the result ID and type instead of the value. The default
  still sends the value, as Landau's examples do.
- **Review gets types.** Permission callbacks and PreToolUse hooks receive
  `context$tool_arguments`, the registered tool's ellmer `TypeObject`.
  `tool_input_review()` turns an input and its declaration into a
  per-field table. The approval-gates recipe uses it instead of `dput()`.

## Consequences

- **Delegation extends the policy to the tree.** `LeadAgent` accepts the
  policy, and every child inherits it. The lead's own `delegate_to_agent`
  tool is admitted only because of that inheritance. Each definition's tools
  are checked when the definition is registered and again when the child is
  built, which covers skills and host resource factories. A designated name
  must refer to the same tool object in the lead and in every definition, so
  each result type keeps one producer. A child's trusted result is recorded
  in the child's run and in the lead's run, and delivered to the lead's
  `on_result` with the child's `delegation_id` and agent identity. Children
  cannot delegate further, and graph routes and other composition tools stay
  rejected everywhere. A separate executor Agent, as in the study recipe,
  remains a valid alternative.
- Durable approval composes with the policy unchanged. The approved tool
  runs through the same wrapper on `resume_approval()`, so edited inputs
  appear in the event's `arguments`.
- The policy constrains registration; it grants no permission. Permissions,
  hooks and approvals still govern every call. It is not an OS sandbox and
  does not protect against a malicious host R process.
- `approval_review_ui()` / `approval_review_server()` present a pending
  durable approval as a typed table with editors for simple fields, and
  approve or deny through `resume_approval()` or a host `decide` function.
  The call stays blocked until the reviewer acts.
- `inst/examples/trusted-results/` is the three-area chat / review / results
  app. Its tests show that the result panel updates only from the trusted
  tool's `on_result`, after review, and never from model text.
