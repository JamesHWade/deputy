# Use S7 values for AgentDefinitions and explicit serialization boundaries

Decision date: 2026-09-06. Baseline: `8fbdc18`.
Issue: [#125](https://github.com/JamesHWade/deputy/issues/125), a bounded slice of
[#119](https://github.com/JamesHWade/deputy/issues/119).
Builds on [ADR-0009](0009-s7-value-contracts.md) and
[ADR-0006](0006-portable-agent-definitions.md).

## Decision and interface

AgentDefinition is a Deputy-owned S7 value with read-only stored properties.
The existing `agent_definition(...)` constructor is an alias of the exported
`AgentDefinition(...)` class: both names refer to the same S7 constructor,
with the same explicit arguments, validation, and defaults. There is no
parallel S3 value constructor or R6 facade. The class is available for typed
properties, `S7::S7_inherits()`, and method dispatch.

The value contract and routing normalization live in `R/agent-definition.R`.
`R/agents-multi.R` retains the mutable LeadAgent registry and delegation
lifecycle. Definition fields are read with `$`, `@`, or `S7::prop()`.
`S7::props()` returns a plain property record; editing it and calling
`do.call(agent_definition, fields)` constructs a revised, validated value.
The shared frozen-property mechanism rejects individual and bulk replacement,
including initially NULL fields. Printing preserves stdout and invisible return.

## Routing and authority

Construction still trims and lowercases routing names, validates the routing-key
syntax, normalizes denylists and character sequences, and distinguishes NULL
request limits from zero. Permission modes remain canonical Deputy modes.
A LeadAgent validates and reconstructs definitions when accepting them, rejects
duplicate canonical names, and updates routing prompts through registration.
Its public registry getter returns an ordinary list of immutable definition
values. Replacing an element in that list cannot change the private registry;
renaming a registered definition through property assignment now fails.

Definition properties describe requested configuration. They do not replace the
lead's authority ceiling. Child construction still derives tools, intersects
capabilities and request allowances, applies denylists, and rejects mode
widening. Stateless fan-out restrictions and reservation accounting are unchanged.

Tools and Skill objects are composed as supplied. Definition reconstruction
copies the record but does not clone tool closures, Skill reference objects,
services, or caller-owned environments. Those objects retain their original
semantics and remain the host's responsibility. The record's read-only fields
do not promise deep immutability for executable dependencies.

Skill configuration subsequently became read-only under
[ADR-0014](0014-s7-skills.md). Executable dependencies nested in those Skill
values retain the ownership semantics described above.

## YAML and RDS

Deputy YAML remains version 1. The writer projects S7 properties explicitly,
then replaces tools and skills with unique symbolic registry keys. The reader
resolves those keys through the receiving host's explicit registries and
constructs the same S7 value. Matching by tool name, automatic package loading,
source evaluation, and service connection remain outside this format.

All constructor fields, optional NULLs, empty sequences, zero limits, canonical
routing, registry identity, and object order retain their current representation.
Unknown fields, duplicate names, ambiguous references, expression tags, oversized
files, and unsafe overwrite races retain their existing failure behavior.
The S7 class identity and frozen marker are not written into YAML. Session
schema 2 remains separate; loading a conversation does not restore a lead's
registry or delegated authority.

RDS can preserve S7 definitions and ordinary R object graphs after Deputy loads
in the receiving process. This includes shared closures and Skill references
when those objects are themselves serializable. It is not a transport contract
for live clients, credentials, connections, or external services. Portable
definitions use YAML and host-side reattachment. Legacy S3 definition objects
are rejected at registry and writer boundaries; there is no silent RDS migration.

## Verification

Focused tests cover the constructor alias and API inventory, read-only fields,
property-record edits, S3 lookalike rejection, template identity, canonical
registration, child permission/request narrowing, and YAML validation and atomic
writes. Existing delegation and parallel fixtures retain the runtime behavior.
A fresh-process test checks RDS dispatch and frozen fields, shared executable
identity, and YAML rebinding to a different host-supplied implementation. R CMD
check runs that test against the installed package. Runnable constructor and
vignette examples, pkgdown, full package tests, and current-head CI complete the
verification recorded in the PR. Remaining value families stay in #119.
