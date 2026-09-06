# S7 run results preserve evidence and independent list values

    Code
      result@response <- "replacement"
    Condition
      Error:
      ! Cannot modify `response`: property is read-only after construction

---

    Code
      result@structured_output <- list(value = 1)
    Condition
      Error:
      ! Cannot modify `structured_output`: property is read-only after construction

# S7 result constructors reject malformed metadata

    Code
      AgentResult(response = c("one", "two"))
    Condition
      Error in `AgentResult()`:
      ! `response` must be NULL or one non-missing string

---

    Code
      AgentResult(stop_reason = NA_character_)
    Condition
      Error in `AgentResult()`:
      ! `stop_reason` must be one non-empty string

---

    Code
      AgentResult(duration = Inf)
    Condition
      Error in `AgentResult()`:
      ! `duration` must be NULL or one finite nonnegative number

---

    Code
      AgentResult(events = list(list(type = "text")))
    Condition
      Error in `AgentResult()`:
      ! `events` must be a list of AgentEvent objects

---

    Code
      AgentResult(session_id = "")
    Condition
      Error in `AgentResult()`:
      ! `session_id` must be NULL or one non-empty string

---

    Code
      AgentResult(turns = "turn")
    Condition
      Error:
      ! <deputy::AgentResult> object properties are invalid:
      - @turns must be <list>, not <character>

---

    Code
      AgentResult(usage = list(requests = 1))
    Condition
      Error:
      ! <deputy::AgentResult> object properties are invalid:
      - @usage must be <NULL> or S3<AgentUsage>, not <list>
