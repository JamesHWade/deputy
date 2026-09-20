# Describe a host-selected conversation fork

ContextFork() is a read-only request to seed a fresh standalone Agent
with selected public ellmer turns. The host supplies the owner,
conversation, branch, revision and fork point and remains responsible
for authenticating those identifiers. Turns are projected through the
public ellmer record contract; tool bindings, hidden thinking and
provider-private fields are omitted, and incomplete tool evidence
becomes inert text.

## Usage

``` r
ContextFork(
  owner_id = NULL,
  conversation_id = NULL,
  branch_id = NULL,
  revision = NULL,
  fork_point = NULL,
  view = c("transcript", "context"),
  turns = list(),
  max_bytes = 64 * 1024,
  max_turns = 256L,
  schema_version = 1L
)
```

## Arguments

- owner_id:

  Host owner identifier.

- conversation_id:

  Host conversation identifier.

- branch_id:

  Host-selected branch identifier.

- revision:

  Exact host revision identifier.

- fork_point:

  Host fork point token or non-negative turn number.

- view:

  Either "transcript" for the complete selected transcript or "context"
  for the current model context. The latter never falls back to the
  transcript automatically.

- turns:

  A bounded list of native public ellmer turns, or public records
  produced by
  [`ellmer::contents_record()`](https://ellmer.tidyverse.org/reference/contents_record.html)
  for those turns.

- max_bytes:

  Maximum serialized bytes of the inert public projection.

- max_turns:

  Maximum number of selected turns.

- schema_version:

  Portable value schema version, currently 1L.

## Value

A read-only ContextFork S7 value with no Chat or executable object.
