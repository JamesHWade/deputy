# authorization precedes lookup and redaction precedes content delivery

    Code
      denied$inspect_subagents("owner")
    Condition
      Error in `delegation_disclosure_abort()`:
      ! Delegation disclosure is not authorized.

# batch outcomes retain failures and repeated specialist identities

    Code
      first$outcomes$a@answer <- "altered"
    Condition
      Error:
      ! Cannot modify `answer`: property is read-only after construction

# large UTF-8 answers are bounded and artifacts remain scoped

    Code
      lead$read_subagent_result("other", ref$delegation_id, ref$reference)
    Condition
      Error in `delegation_disclosure_abort()`:
      ! Delegation disclosure is not authorized.

---

    Code
      unrelated$read_subagent_result("owner", ref$delegation_id, ref$reference)
    Condition
      Error in `delegation_disclosure_abort()`:
      ! Delegation disclosure is not authorized.

# settled history replays without providers or executable tools

    Code
      delegation_history(snapshot, "other", inspection_policy(), snapshot$scope)
    Condition
      Error in `delegation_disclosure_abort()`:
      ! Delegation disclosure is not authorized.

---

    Code
      delegation_history(snapshot, "owner", inspection_policy(), list(owner_id = "different"))
    Condition
      Error in `delegation_disclosure_abort()`:
      ! Delegation disclosure is not authorized.

---

    Code
      delegation_history(snapshot, "owner", inspection_policy(), snapshot$scope)
    Condition
      Error in `validate()`:
      ! Unsupported inspection content class.

# public history omits hidden thinking and raw provider payloads

    Code
      inspection_portable(list(callback = function() NULL))
    Condition
      Error in `FUN()`:
      ! Inspection history must contain portable data only.

# disclosure is bounded and active histories cannot be restored

    Code
      delegation_history(history, "owner", inspection_policy(max_bytes = 64), history$
        scope)
    Condition
      Error in `inspection_bound()`:
      ! Delegation disclosure exceeds max_bytes; narrow the selection.

---

    Code
      delegation_history(history, "owner", inspection_policy(), history$scope)
    Condition
      Error in `FUN()`:
      ! Only settled child history can be replayed.
