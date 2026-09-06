# usage values freeze stored and initially unset properties

    Code
      usage@requests <- 2L
    Condition
      Error:
      ! Cannot modify `requests`: property is read-only after construction

---

    Code
      usage$total_tokens <- 999
    Condition
      Error:
      ! Can't set S7 properties with `$`. Did you mean `...@total_tokens <- 999`?

---

    Code
      usage@total_tokens <- 999
    Condition
      Error:
      ! Cannot modify `total_tokens`: property is read-only after construction

---

    Code
      usage@cost_usd <- 0
    Condition
      Error:
      ! Cannot modify `cost_usd`: property is read-only after construction

---

    Code
      limits@max_requests <- 2L
    Condition
      Error:
      ! Cannot modify `max_requests`: property is read-only after construction

---

    Code
      limits$on_exceed <- "error"
    Condition
      Error:
      ! Can't set S7 properties with `$`. Did you mean `...@on_exceed <- "error"`?

---

    Code
      S7::props(limits) <- list(max_cost_usd = 1)
    Condition
      Error:
      ! Cannot modify `max_cost_usd`: property is read-only after construction

---

    Code
      S7::props(usage) <- list(input_tokens = 999)
    Condition
      Error:
      ! Cannot modify `input_tokens`: property is read-only after construction

# runtime limits and results require genuine S7 values

    Code
      normalize_usage_limits(fake_limits)
    Condition
      Error in `normalize_usage_limits()`:
      ! `usage_limits` must be created with UsageLimits()

---

    Code
      merge_usage_limits(fake_limits, UsageLimits())
    Condition
      Error in `merge_usage_limits()`:
      ! `usage_limits` must be created with UsageLimits()

---

    Code
      merge_usage_limits(UsageLimits(), fake_limits)
    Condition
      Error in `merge_usage_limits()`:
      ! `defaults` must be created with UsageLimits()

---

    Code
      AgentResult(usage = fake_usage)
    Condition
      Error:
      ! <deputy::AgentResult> object properties are invalid:
      - @usage must be <NULL> or <deputy::AgentUsage>, not S3<AgentUsage/list>
