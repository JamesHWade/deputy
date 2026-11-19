# Streaming first-byte qualification (#200)

This note records the loopback qualification for the response-body streaming
fix tracked in [#200](https://github.com/JamesHWade/deputy/issues/200).

## Probe

Run from the Deputy checkout:

```sh
Rscript dev/streaming-first-byte-probe.R
```

The probe uses a local `127.0.0.1` HTTP/SSE fixture. It sends one `ok` text
delta followed by the stream terminator, and asserts the exact public replies:

- `Agent$stream_async(..., stream = "text")`: `"ok\n"` after collecting the
  two text chunks (`"ok"` and `"\n"`).
- `Agent$chat_async(...)`: `"ok\n"`.

Each method is exercised against two independent fixture servers:

- `slow_body`: response headers are immediate; the body is delayed by two
  seconds.
- `slow_headers`: headers are delayed by two seconds before any response
  bytes are available.

The probe measures `later` callback progress while the request is pending. A
large `max_event_loop_gap_s` indicates that the R process did not service its
event loop while waiting for the first response bytes. It does not claim that
the underlying transfer is faster; both fixtures deliberately take about two
seconds.

The timeout is 12 seconds per case. No provider endpoint, API key, or network
request outside the loopback fixture is used.

## Current CRAN release qualification

The release run used current CRAN `curl 8.1.0`, `httr2 1.3.0`, and
`ellmer 0.5.2`, installed into isolated libraries. Every case returned the
exact expected reply. Deputy methods use the SSE fixture; the
`ellmer_chat_async` control uses a JSON response and calls ellmer's
nonstreaming `Chat$chat_async()` directly:

| method | fixture | protocol | exact reply | ticks before 1.9 s | max event-loop gap | elapsed |
| --- | --- | --- | --- | ---: | ---: | ---: |
| `stream_async` | delayed body | SSE | `"ok\n"` | 1 | 2.37 s | 3.21 s |
| `chat_async` | delayed body | SSE | `"ok\n"` | 2 | 2.21 s | 2.71 s |
| `ellmer_chat_async` | delayed body | JSON | `"ok"` | 16 | 0.21 s | 2.24 s |
| `stream_async` | delayed headers | SSE | `"ok\n"` | 0 | 2.02 s | 2.04 s |
| `chat_async` | delayed headers | SSE | `"ok\n"` | 1 | 2.01 s | 2.15 s |
| `ellmer_chat_async` | delayed headers | JSON | `"ok"` | 17 | 0.11 s | 2.02 s |

The direct ellmer control stayed responsive. It uses ellmer's nonstreaming
transport outside Deputy's permissions, hooks and usage limits. Both public
Deputy methods use the governed streaming transport.

## Patched dependency qualification

The patched run used the preserved local `httr2 1.3.0.9000` build (commit
`9ad5fda`) with `curl 8.1.0` and released `ellmer 0.5.2`.
Every case returned the exact expected reply, including the `c("ok", "\n")`
stream chunks. The event-loop measurements were:

| method | fixture | protocol | exact reply | ticks before 1.9 s | max event-loop gap | elapsed |
| --- | --- | --- | --- | ---: | ---: | ---: |
| `stream_async` | delayed body | SSE | `"ok\n"` | 16 | 0.29 s | 3.12 s |
| `chat_async` | delayed body | SSE | `"ok\n"` | 14 | 0.23 s | 2.65 s |
| `ellmer_chat_async` | delayed body | JSON | `"ok"` | 16 | 0.20 s | 2.23 s |
| `stream_async` | delayed headers | SSE | `"ok\n"` | 0 | 2.03 s | 2.04 s |
| `chat_async` | delayed headers | SSE | `"ok\n"` | 1 | 2.02 s | 2.14 s |
| `ellmer_chat_async` | delayed headers | JSON | `"ok"` | 17 | 0.11 s | 2.05 s |

With patched httr2, both Deputy methods serviced the event loop while the body
was delayed. Delayed response headers still produced a roughly two-second
stall. Each row is a single loopback run with a two-second fixture delay.

## Release status and host guidance

The released stack uses curl 8.1.0, httr2 1.3.0, and ellmer 0.5.2. The patched
stack uses curl at `f2908e3` and httr2 at `9ad5fda`. Repeat both timing cases
after httr2 releases its change.
[CRAN curl](https://cran.r-project.org/package=curl) ·
[CRAN httr2](https://cran.r-project.org/package=httr2) ·
[CRAN ellmer](https://cran.r-project.org/package=ellmer) ·
[curl fix](https://github.com/jeroen/curl/pull/460) ·
[httr2 fix](https://github.com/r-lib/httr2/pull/919).

Use `Agent$chat_async()` when host code needs one promise. It carries the
same first-response wait and governance as `Agent$stream_async()`. Shared
Shiny processes can stall for the header wait even on the patched transport.
[#200](https://github.com/JamesHWade/deputy/issues/200) tracks that remaining
boundary and qualification of the released dependency set.
