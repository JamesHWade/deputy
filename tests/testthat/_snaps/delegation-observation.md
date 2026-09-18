# closing observers never cancels work and redaction errors are read-local

    Code
      detached$poll()
    Condition
      Error in `private$authorize()`:
      ! This child observation subscription is closed.

---

    Code
      reader$poll()
    Condition
      Error in `disclosure$redact()`:
      ! observer failed

# authorization is rechecked on reads and foreign cursors disclose nothing

    Code
      reader$poll()
    Condition
      Error in `delegation_disclosure_abort()`:
      ! Delegation disclosure is not authorized.

---

    Code
      reader$snapshot(TRUE)
    Condition
      Error in `delegation_disclosure_abort()`:
      ! Delegation disclosure is not authorized.

---

    Code
      clone$observe_subagents(requester, after = cursor)
    Condition
      Error in `validate_observation_cursor()`:
      ! Invalid or foreign child observation cursor.

---

    Code
      denied$observe_subagents("other", "missing", cursor)
    Condition
      Error in `delegation_disclosure_abort()`:
      ! Delegation disclosure is not authorized.
