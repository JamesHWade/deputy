# delegation values preserve text, copy references and round-trip portable input

    Code
      input@task <- "replacement"
    Condition
      Error:
      ! Cannot modify `task`: property is read-only after construction

---

    Code
      DelegationInput("task", evidence = list(list(source_id = "a", revision = "r1",
        image = "unsupported")))
    Condition
      Error in `delegation_record()`:
      ! Invalid delegation record fields or content.

---

    Code
      DelegationInput("task", constraints = list(function() NULL))
    Condition
      Error in `FUN()`:
      ! constraints must be one plain text string.

---

    Code
      DelegationInput(strrep("é", 6e+05))
    Condition
      Error in `delegation_text()`:
      ! task exceeds the 1 MiB text ceiling.

# ordinary and parallel preparation share input without importing parent state

    Code
      first@message <- "replacement"
    Condition
      Error:
      ! Cannot modify `message`: property is read-only after construction

# host scope and AgentDefinition allowlists cannot be overridden by a brief

    Code
      DelegationInput("task", evidence = list(list(source_id = "assay", revision = "r1",
        owner_id = "owner-a")))
    Condition
      Error in `delegation_record()`:
      ! Invalid delegation record fields or content.

