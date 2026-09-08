# R sessions reuse variables, queue dependencies and isolate owners

    Code
      other_agent$register_tools(session$tools())
    Condition
      Error in `validate_r_session_tool_owner()`:
      ! The R session belongs to a different Agent, session, workspace or run context.

---

    Code
      session$run("1")
    Condition
      Error in `private$check_current()`:
      ! The R session is closed.

# worker crashes settle and finite output and queue limits are enforced

    Code
      session$run("2")
    Condition
      Error in `session$run()`:
      ! The R session waiting queue is full.
