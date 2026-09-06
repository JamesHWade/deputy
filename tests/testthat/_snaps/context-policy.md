# S7 context policies freeze configuration and reject list lookalikes

    Code
      policy$max_tokens <- 100L
    Condition
      Error:
      ! Can't set S7 properties with `$`. Did you mean `...@max_tokens <- 100L`?

---

    Code
      S7::prop(policy, "offload_dir") <- "changed"
    Condition
      Error:
      ! Cannot modify `offload_dir`: property is read-only after construction

---

    Code
      S7::props(policy) <- list(fallback = "text")
    Condition
      Error:
      ! Cannot modify `fallback`: property is read-only after construction

---

    Code
      normalize_context_policy(structure(fields, class = c("ContextPolicy", "list")))
    Condition
      Error in `normalize_context_policy()`:
      ! `context_policy` must be a ContextPolicy object

# S7 compactions preserve provider evidence while freezing records

    Code
      outcome$run_id <- "changed"
    Condition
      Error:
      ! Can't set S7 properties with `$`. Did you mean `...@run_id <- "changed"`?

---

    Code
      outcome@attempts[[1L]]$provider <- "changed"
    Condition
      Error:
      ! Cannot modify `attempts`: property is read-only after construction

---

    Code
      outcome@usage@requests <- 3L
    Condition
      Error:
      ! Cannot modify `requests`: property is read-only after construction

---

    Code
      S7::props(outcome) <- list(summary = "changed")
    Condition
      Error:
      ! Cannot modify `summary`: property is read-only after construction

# S7 compaction constructors validate counts and optional evidence

    Code
      DeputyCompaction("invalid", FALSE, 0, 0)
    Condition
      Error in `match.arg()`:
      ! 'arg' should be one of "none", "cancelled", "custom", "hook", "llm", "text"

---

    Code
      DeputyCompaction("none", NA, 0, 0)
    Condition
      Error in `compaction_automatic()`:
      ! `automatic` must be TRUE or FALSE

---

    Code
      DeputyCompaction("none", FALSE, -1, 0)
    Condition
      Error in `context_policy_nonnegative_whole_number()`:
      ! `turns_compacted` must be one non-negative whole number

---

    Code
      DeputyCompaction("none", FALSE, 0, 1.5)
    Condition
      Error in `context_policy_nonnegative_whole_number()`:
      ! `turns_kept` must be one non-negative whole number

---

    Code
      DeputyCompaction("none", FALSE, 0, 0, Inf)
    Condition
      Error in `validate_usage_limit()`:
      ! `estimated_tokens` must be NULL or a non-negative length-1 number

---

    Code
      DeputyCompaction("none", FALSE, 0, 0, summary = NA_character_)
    Condition
      Error in `DeputyCompaction()`:
      ! `summary` must be NULL or one string

---

    Code
      DeputyCompaction("none", FALSE, 0, 0, run_id = c("one", "two"))
    Condition
      Error in `DeputyCompaction()`:
      ! `run_id` must be NULL or one string

---

    Code
      DeputyCompaction("none", FALSE, 0, 0, attempts = "invalid")
    Condition
      Error:
      ! <deputy::DeputyCompaction> object properties are invalid:
      - @attempts must be <list>, not <character>

---

    Code
      DeputyCompaction("none", FALSE, 0, 0, usage = structure(list(), class = c(
        "AgentUsage", "list")))
    Condition
      Error:
      ! <deputy::DeputyCompaction> object properties are invalid:
      - @usage must be <deputy::AgentUsage>, not S3<AgentUsage/list>

# invalid compaction evidence is rejected before hooks or context changes

    Code
      agent$compact(keep_last = 0, estimated_tokens = Inf)
    Condition
      Error in `validate_usage_limit()`:
      ! `estimated_tokens` must be NULL or a non-negative length-1 number

---

    Code
      agent$compact(keep_last = 0, automatic = NA)
    Condition
      Error in `compaction_automatic()`:
      ! `automatic` must be TRUE or FALSE
