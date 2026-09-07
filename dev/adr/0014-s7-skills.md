# Use S7 values for declarative Skill configuration

Decision date: 2026-09-06. Baseline: `b0064cb`.
Issue: [#127](https://github.com/JamesHWade/deputy/issues/127), a bounded slice of
[#119](https://github.com/JamesHWade/deputy/issues/119).
Builds on [ADR-0009](0009-s7-value-contracts.md) and
[ADR-0013](0013-s7-agent-definitions.md).

## Decision and interface

Skill is a Deputy-owned S7 value with seven read-only stored properties: name,
version, description, prompt, tools, requires, and path. `Skill(...)` is the
explicit class constructor. The R6 `$new()` constructor and instance methods
are removed without a facade. `skill_check_requirements(skill, current_provider)`
is a standalone public function, and ordinary `print(skill)` preserves stdout
and invisible return.

`Skill()` retains the former constructor's `"0.0.0"` version default.
`skill_create()` deliberately retains its `"1.0.0"` default and delegates to the
same S7 constructor. `skill_load()` constructs the same class from directory or
Markdown metadata. There is no parallel legacy value API.

Names and version strings are non-empty scalar strings and remain as supplied;
Skill names do not adopt AgentDefinition routing normalization. Optional text
properties permit NULL and empty strings. Tools remain a list of executable
objects. Requirements are a uniquely named list of declarative data; known
package/provider entries contain strings, NULL, or empty sequences. Additional
declarative metadata remains intact and is not evaluated. Construction rejects
executable and reference objects in requirements.

Read properties with `$`, `@`, or `S7::prop()`. `S7::props()` gives an ordinary
property record for constructing a revised value. A caller cannot rename or
change a loaded Skill through an Agent getter or an AgentDefinition snapshot.
The common frozen-property mechanism also covers initially NULL fields and
bulk property replacement. Agent and LeadAgent retain their mutable registries
and runtime identity.

## Executable composition and loading

The value contract and requirements checker live in `R/skill.R`. Explicit
Skill file discovery, metadata parsing, and tool loading stay in `R/skills.R`.
Neither the constructor nor the requirements checker sources files, installs
packages, connects services, or executes tools.

Skill composes original ellmer ToolDef objects. Constructing or revising a
Skill does not clone closures, clients, services, or caller-owned environments.
Freezing configuration does not freeze executable tool state. Agent loading
still applies its existing tool-registration checks, conflicts policy, prompt
composition, and provider/package warnings. The Agent's permissions remain the
authority ceiling for actual execution.

The requirements checker preserves known provider aliases and case-insensitive
exact matching for other ellmer providers. NULL current provider skips provider
validation. Empty and NULL required-provider sequences allow any provider.
Missing package and mismatch reports retain the existing fields and semantics.

`skill_load()` preserves YAML/Markdown precedence, defaults, direct Markdown
loading, and tool sourcing. The source-loading boundary remains explicit and
separate from AgentDefinition YAML, whose symbolic registries never execute or
load a Skill implicitly.

## Serialization and verification

RDS preserves Skill class dispatch, frozen properties, and serializable object
graphs when Deputy is loaded in the receiving process. This is not a transport
contract for live services, connections, or credentials. AgentDefinition YAML
version 1 resolves Skill values through the receiving host's explicit registry;
replacement implementations are selected by symbolic registry keys. Legacy R6
or S3 lookalikes are rejected by Agent and registry boundaries rather than being
silently migrated.

Tests cover constructor validation and defaults, frozen nested configuration,
revised values, original executable identity, Agent getters and clones,
requirements aliases and mismatch reports, sourced tool state, and metadata
precedence. Fresh-process tests verify RDS dispatch/frozen fields and YAML
reattachment to a different host-supplied Skill. R CMD check runs these against
the installed package. Runnable reference and vignette examples, full package
gates, and final-head CI results are recorded in the PR. ADR-0015 completes the remaining hook and permission-result value families
tracked in #119.
