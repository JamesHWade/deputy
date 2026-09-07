# mcp-repl producer qualification

Run the real sandboxed R journey against an explicitly installed mcp-repl 0.3.0
binary and mcptools 1.0.2. The script uses mock Chats and a local deterministic
MCP server as well as the real REPL. It makes no model API requests.

From a clean committed Deputy checkout:

```sh
DEPUTY_MCP_REPL_BIN=/path/to/mcp-repl \
DEPUTY_MCP_QUALIFICATION_OUTPUT=/new/qualification/directory \
Rscript dev/evaluations/mcp-repl/qualify.R
```

The script records the source commit, binary SHA-256, package versions, platform,
individual test outcomes and assertion counts. It rejects any failed, skipped
or warning-bearing qualification and preserves partial evidence. The executable
name alone does not establish its version; install the intended release before
running the script.

The journey checks persistent state and isolation across two Agents using the
same server name, plots as ellmer image content, bounded output with an accessible
full transcript artifact, a busy interpreter, state-preserving interrupt, reset,
interpreter exit/state loss, closure, and stale handles. The deterministic client
producer also checks catalogue pages, exact allowances, denied requests without
dispatch, Agent permissions/hooks, event-loop progress, cancellation, timeout
and server crash. See `dev/mcp-client-contract.md` for ownership and limitations.

Qualification demonstrates the named producer combination on the recorded host.
It does not establish behavior for other platforms or binaries, production
Shiny load, a large external catalogue, or a public mcptools client API.
