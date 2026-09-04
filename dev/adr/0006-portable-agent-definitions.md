# Portable AgentDefinitions use Deputy YAML and explicit registries

Issue #41 adds versioned YAML files under `.deputy/agents/`, with one
AgentDefinition per file. The format mirrors the existing constructor and
uses its validation. It is Deputy's format, consistent with ADR-0001; it does
not restore `.claude/agents/` conventions or serialized runtime objects.

Tools and skills are symbolic references resolved against named registries
supplied by the host. Serializing closures, importing arbitrary package
exports, and sourcing paths from a model-authored document would let that
document choose executable code. Registries instead let the host provide
approved built-ins, custom tools, service tools, Skill objects, or approved
skill paths. Reading a definition only selects those objects. MCP server
names remain inert until the existing LeadAgent lifecycle loads them.

Writers require each selected object to match exactly one registry entry;
unknown or ambiguous references fail rather than guessing by a tool's name.
Round-tripping preserves constructor fields, reference identity, and order,
while normalizing YAML formatting and discarding names on R lists and character
sequences (which the runtime does not use).

Writers finish a temporary file in the destination directory before installing
it. Explicit overwrites use rename; creation without overwrite uses a hard
link, which fails atomically if another writer has already created the path.
Unsupported filesystem operations fail without replacing an existing file.

Discovery reads only the chosen directory, in filename order. It rejects the
whole collection for invalid files or duplicate canonical routing names. It
never searches parent directories or creates Agents implicitly. Nested
subagents and host settings are outside the current AgentDefinition surface;
a host assembles the resulting list into a LeadAgent and retains its
permission ceiling, provider configuration, and run lifecycle.
