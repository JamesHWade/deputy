# Tool registration validates a complete batch before publication

Issues #49 and #50 share one tool boundary. Hosts use `ellmer::tool()` to
describe a local function, a package export, or a service call; Deputy does
not infer schemas, import packages, or connect services during registration.
Existing tool bundles and MCP loaders supply the same ellmer objects.

`Agent$register_tool()` and `$register_tools()` reject existing names unless
the host explicitly supplies `replace = TRUE`. Duplicate names within a
batch always fail. List element names do not rename tools. Constructor tools,
tools already on a supplied Chat, skills, and `set_tools()` share validation.
Validation and runtime adaptation finish before a single `Chat$set_tools()`
call publishes the registry. This guarantees that validation failures leave
the previous registry intact; arbitrary backend failures are not a database
transaction. Deputy reserves its internal result reader's name.

Supplied annotations retain their original values. Known boolean annotations
must be scalar, non-missing logical values. Missing values remain absent on
the tool, while permission checks for custom tools assume read-only FALSE,
destructive TRUE, idempotent FALSE, and open-world TRUE. These are the
[MCP annotation defaults](https://modelcontextprotocol.io/specification/2025-06-18/schema#toolannotations).
Destructive defaults are irrelevant when read-only is explicitly TRUE; an
explicit contradictory destructive TRUE remains restrictive. Annotations
describe behavior and do not establish trust or grant authority. Native
capability checks, deny/allow lists, callbacks, and parent permission ceilings
still apply. Full mode and explicit standard-mode callbacks remain host
authorization mechanisms.
