# Record what a subagent started with

Holds what a subagent was given when a delegation started: the task,
evidence, system prompt, first message, provider, model and request
parameters, tool names, and its permission and context settings. A
[LeadAgent](https://jameshwade.github.io/deputy/reference/LeadAgent.md)
keeps one in memory for each delegation; read them with
`$get_subagent_contexts()`. A manifest covers the starting point only,
not what happened during the run.

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
  provider = "",
  params = list(),
  schema_version = 2L
)
```

## Arguments

- input:

  The task, as a list of
  [DelegationInput](https://jameshwade.github.io/deputy/reference/DelegationInput.md)
  fields.

- definition:

  The definition's name, prompt, memory, initial prompt and skill names,
  plus an `id` hash.

- sources:

  The evidence given to the subagent, each with a SHA-256 `digest` of
  its text.

- scope:

  The lead's `delegation_scope`.

- system_prompt:

  The subagent's system prompt, including memory and skills.

- message:

  The first message sent to the subagent, including the definition's
  `initial_prompt` and the evidence.

- model:

  The model name. Credentials are never recorded.

- tools:

  Names of the subagent's tools.

- policies:

  A summary of the permission, context and
  [DelegationPolicy](https://jameshwade.github.io/deputy/reference/DelegationPolicy.md)
  settings, with hashes that identify them. Callbacks are not recorded.

- size:

  `text_bytes`, `manifest_bytes` and `estimated_tokens` (`NULL` when
  unknown). The token count is an estimate, not a billed count.

- provider:

  The name of the subagent's provider, such as `"OpenAI"`.

- params:

  The request parameters set with
  [`ellmer::params()`](https://ellmer.tidyverse.org/reference/params.html)
  on the subagent's chat, such as `reasoning_effort`; `extra_args` are
  left out.

- schema_version:

  Format version; must be `2L`.

## Value

A `DelegationManifest` object.

## Details

To store a manifest, save `S7::props(x)` (plain lists) and rebuild it
with `do.call(DelegationManifest, record)`. A manifest includes the task
and evidence text, so check who may see it before showing it to users;
`$get_subagent_contexts(redact = TRUE)` leaves that text out.
