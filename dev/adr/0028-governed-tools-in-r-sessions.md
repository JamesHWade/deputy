# Governed tool calls from persistent R

An R session can retain data and calculations across model turns. It should
also be able to acquire data through the Agent's approved tools, so a tool
result can become an R value without a model copying it out of a transcript.

## Ownership

The host explicitly selects registered tool names when constructing an
`RSession`. The worker receives callable stubs and data. Executable tool
closures, permissions and the authoritative registry stay in the host; the
bridge does not transfer credential-bearing closures. The stubs are a
convenience, not an authority boundary: the host
validates every request against its captured selection and execution identity.

This first adapter uses the existing trusted callr worker. It does not confine
arbitrary R code or host tool effects. ADR-0005 still assigns OS enforcement to
mcp-repl; #187 tracks the supported producer contract needed to apply this
composition model inside that sandbox. Local tools eligible for confinement
and credentialed remote adapters need distinct execution placement.
The trusted process retains its ordinary account and environment access;
keeping credentials out of bridge messages does not make that process secret
isolated.

## Invocation

Only a registered, active, governed `run_r_code` execution can open a bridge.
The supervisor binds it to the owning Agent, run, enclosing tool call and
worker execution. A direct host `$run()` does not borrow an active Agent's
authority. A reset or cancelled execution cannot supply requests to a later
worker generation.

Nested calls reuse Deputy's request/result governance: current permissions,
hooks, usage limits, registered executable identity, file checkpoints and
events. Every call has its own ID and enclosing tool-call correlation. Tool
selection does not grant permission. Recursive code runners and delegation
are outside this adapter's admission contract.

The released ellmer interface does not expose its argument converter as a
public operation. Therefore selected tools must use `convert = FALSE`, accept
raw JSON-compatible arguments and validate their domain inputs. Deputy does
not copy ellmer's converter or silently change a tool's conversion semantics.
The transport accepts bounded data requests, never worker-supplied executable
closures or serialized R objects for the host to restore.

Results returned to R are bounded ordinary data. Unsupported runtime objects
fail explicitly. Errors remain visible to the R expression, and successful
results can be assigned to variables for subsequent calls. An error after an
external effect does not establish that the effect was rolled back.

## Lifecycle and recovery

Parent polling supports asynchronous host tools while the R worker waits for
its result. Cancellation invalidates that execution's channel; a late result
cannot populate a new R execution. Killing an R worker cannot undo a remote
effect or forcibly interrupt arbitrary synchronous host code.

Durable approval inside a running R expression is unsupported. Sessions with
selected tools reject construction when the Agent has `approval_dir` configured, and
nested permission callbacks that request pending approval also fail. This must fail
before the nested effect rather than create a continuation that pretends to
restore an R stack. Existing standalone approvals retain ADR-0016 semantics.
Saved conversation evidence remains distinct from live R objects.

#188 tracks explicit data checkpoints and supervisor-owned recovery records.
It must reuse existing journal contracts where applicable and preserve an
indeterminate outcome when an external effect may have completed without a
recorded response. This adapter makes no automatic replay or exactly-once
claim.

## Acceptance

Use a real local R worker and deterministic provider fixtures to fetch data
through a selected tool and analyze it across R calls. Check denied and
unselected tools, owner and execution isolation, hook/counter correlation,
errors, asynchronous completion, cancellation, stale responses and bounded
transfer. These checks require no paid model calls.
