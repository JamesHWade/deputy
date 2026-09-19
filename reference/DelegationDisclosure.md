# Authorize and redact child conversation inspection

Hosts authenticate requesters before calling inspection methods.
Identifiers are routing locators, never access grants. Authorization
runs before record lookup; redaction runs before each snapshot leaves
Deputy. These trusted host callbacks never run as model tools. The
default denies all disclosures.

## Usage

``` r
DelegationDisclosure(
  authorize = function(requester, scope) FALSE,
  redact = function(view, requester) view,
  max_bytes = 16 * 1024^2
)
```

## Arguments

- authorize:

  Function of `requester` and fixed host `scope`; only an exact `TRUE`
  permits disclosure. Errors deny access without disclosing details.

- redact:

  Function of `view` and `requester`, returning a redacted list. It may
  remove fields or content. It must not perform agent execution.

- max_bytes:

  Maximum serialized content-payload bytes in one disclosed snapshot or
  saved history, including replayed turn content but excluding shared R
  class/method metadata. Oversized disclosures fail explicitly; select
  fewer children or omit transcripts. Defaults to 16 MiB.

## Value

Read-only `DelegationDisclosure` host configuration.
