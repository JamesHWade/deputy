# sub-agent tool denylist drops tools with unreadable names

    Code
      filtered <- lead$.__enclos_env__$private$filter_disallowed_tools(tools,
        disallowed_tools = "run_bash")
    Condition
      Warning:
      Dropping tool "unreadable" because its name could not be read.
      i Tool object class: <environment>.
      x no applicable method for `@` applied to an object of class "environment"

# sub-agents inherit remaining lead run budgets

    Code
      child$usage_limits@max_requests <- 100L
    Condition
      Error:
      ! Cannot modify `max_requests`: property is read-only after construction

---

    Code
      child$usage_limits <- UsageLimits()
    Condition
      Error:
      ! Cannot modify agent: usage_limits are immutable after construction

# delegated S7 policies preserve ceilings after serialization

    Code
      child$permissions@tool_denylist <- NULL
    Condition
      Error:
      ! Cannot modify `tool_denylist`: property is read-only after construction

---

    Code
      child$permissions <- permissions_full()
    Condition
      Error:
      ! Cannot modify agent: permissions are immutable after construction

---

    Code
      child$set_permission_mode("full")
    Condition
      Error in `child$set_permission_mode()`:
      ! Permission mode cannot widen or replace the current policy
      x Mode readonly cannot change to full.
      i Create a new Agent with explicitly broader Permissions to make this change.
