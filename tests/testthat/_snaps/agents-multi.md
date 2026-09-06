# LeadAgent registry is a read-only snapshot

    Code
      snapshot[[1]]@name <- "changed"
    Condition
      Error:
      ! Cannot modify `name`: property is read-only after construction

---

    Code
      definition@name <- "also-changed"
    Condition
      Error:
      ! Cannot modify `name`: property is read-only after construction
