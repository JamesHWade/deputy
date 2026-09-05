# history rejects text changes and fabricated revision hashes

    Code
      example$history_access(changed, fixture$scope)
    Condition
      Error in `history_scope_records()`:
      ! Authorized history revisions must match the SHA-256 of their text.

---

    Code
      example$history_access(forged, fixture$scope)
    Condition
      Error in `history_scope_records()`:
      ! Authorized history revisions must match the SHA-256 of their text.

# invalid live configuration leaves the requested output path available

    Code
      sys.source(path, envir = new.env())
    Condition
      Error in `match.arg()`:
      ! 'arg' should be one of "original", "changed-constraint"
