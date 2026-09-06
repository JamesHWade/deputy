# parallel budget allocation constructs independent S7 limits

    Code
      first@max_requests <- 2L
    Condition
      Error:
      ! Cannot modify `max_requests`: property is read-only after construction
