# Inspect the prepared initial context of a delegation

A read-only S7 receipt produced by LeadAgent preparation. It describes
the supplied initial context, not later provider framing, hooks,
compaction, or runtime state. It never grants access or installs tools
or permissions.

## Usage

``` r
DelegationManifest(
  input,
  definition,
  sources,
  scope,
  system_prompt,
  message,
  model,
  tools,
  policies,
  size,
  schema_version = 1L
)
```

## Arguments

- input:

  Plain normalized
  [DelegationInput](https://jameshwade.github.io/deputy/reference/DelegationInput.md)
  properties.

- definition:

  Declarative definition identity and prompt material.

- sources:

  Ordered resolved text sources and content digests.

- scope:

  Host-bound owner and conversation identifiers.

- system_prompt:

  Prepared system prompt, including static memory/skills.

- message:

  Prepared first user message, including initial prompt and evidence.

- model:

  Selected model name; no provider credentials.

- tools:

  Registered tool names, not unconditional grants of permission.

- policies:

  Policy identifiers and non-executable settings.

- size:

  Byte counts and a public complete-context token estimate when known.

- schema_version:

  Portable record schema. Currently `1L`.

## Value

A read-only `DelegationManifest` S7 value.

## Details

Hosts normally obtain these values from
`LeadAgent$get_subagent_contexts()`.
[`S7::props()`](https://rconsortium.github.io/S7/reference/props.html)
returns portable plain records suitable for host JSON/RDS storage.
Constructing or restoring a receipt does not recreate an Agent. The host
owns disclosure authorization and storage; the LeadAgent retains
receipts in memory. Evidence hashes identify bytes, not truth or
authorization. Size estimates are estimates, not billed token counts.
Fresh working context and retained history remain separately inspectable
after compaction (ADR-0017).
