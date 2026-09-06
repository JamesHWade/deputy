# S7 hook properties remain frozen when initialized with NULL

    Code
      hook@pattern <- "^write"
    Condition
      Error:
      ! Cannot modify `pattern`: property is read-only after construction

# S7 event records freeze their envelope and payload

    Code
      event@data$text <- "replacement"
    Condition
      Error:
      ! Cannot modify `data`: property is read-only after construction

# S7 events validate their type and payload names

    Code
      AgentEvent(NA_character_)
    Condition
      Error in `AgentEvent()`:
      ! `type` must be one non-empty string

---

    Code
      AgentEvent("")
    Condition
      Error in `AgentEvent()`:
      ! `type` must be one non-empty string

---

    Code
      AgentEvent(c("start", "stop"))
    Condition
      Error in `AgentEvent()`:
      ! `type` must be one non-empty string

---

    Code
      AgentEvent("text", "unnamed")
    Condition
      Error in `AgentEvent()`:
      ! Event data must have unique, non-empty names

---

    Code
      AgentEvent("text", text = "a", text = "b")
    Condition
      Error in `AgentEvent()`:
      ! Event data must have unique, non-empty names

---

    Code
      AgentEvent("text", timestamp = Sys.time())
    Condition
      Error in `AgentEvent()`:
      ! Event data cannot replace `type`, `timestamp`, or `data`

---

    Code
      AgentEvent("text", data = list())
    Condition
      Error in `AgentEvent()`:
      ! Event data cannot replace `type`, `timestamp`, or `data`
