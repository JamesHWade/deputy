# ownership denies foreign, duplicate, direct and expired access

    Code
      other$continue_agent(handle, "foreign", UsageLimits())
    Condition
      Error in `conversation_abort()`:
      ! Conversation handle is unavailable for this owner.

---

    Code
      other$retain_agent(child, UsageLimits())
    Condition
      Error in `conversation_abort()`:
      ! The conversation is active or already owned.

---

    Code
      child$run_sync("direct")
    Condition
      Error in `conversation_abort()`:
      ! This conversation must be run through its current owner.

---

    Code
      owner$clone()
    Condition
      Error in `conversation_abort()`:
      ! Release retained conversations before cloning an Agent.

---

    Code
      child$clone()
    Condition
      Error in `conversation_abort()`:
      ! Release retained conversations before cloning an Agent.

---

    Code
      owner$inspect_subagents("stranger", transcript = TRUE)
    Condition
      Error in `delegation_disclosure_abort()`:
      ! Delegation disclosure is not authorized.

---

    Code
      owner$continue_agent(handle, "expired", UsageLimits())
    Condition
      Error in `conversation_abort()`:
      ! Conversation handle is unavailable for this owner.

# busy rejection and cooperative cancellation settle exactly once

    Code
      owner$continue_agent_async(handle, "overlap", UsageLimits())
    Condition
      Error in `conversation_abort()`:
      ! The conversation is busy.

---

    Code
      owner$release_agent(handle)
    Condition
      Error in `conversation_abort()`:
      ! Cancel and wait for settlement before releasing a busy conversation.

# configuration changes and finite retention reject before execution

    Code
      owner$continue_agent(handle, "twice", UsageLimits())
    Condition
      Error in `conversation_abort()`:
      ! The conversation has reached max_runs; release it.

---

    Code
      owner$continue_agent(handle, "changed", UsageLimits())
    Condition
      Error in `conversation_abort()`:
      ! The retained configuration changed; release and explicitly adopt it again.

# provider failures release leases and need an explicit retry

    Code
      owner$continue_agent(handle, "fail", UsageLimits(max_requests = 1))
    Condition
      Error:
      ! fixture provider failure

# delayed streams cannot bypass transferred ownership

    Code
      collect_async_stream(delayed)
    Condition
      Error in `conversation_abort()`:
      ! This conversation must be run through its current owner.

# a retained mutable Chat cannot be adopted through a second wrapper

    Code
      owned_test_owner()$retain_agent(alias, UsageLimits())
    Condition
      Error in `conversation_abort()`:
      ! The conversation is active or already owned.

---

    Code
      Agent$new(chat)
    Condition
      Error in `conversation_abort()`:
      ! This Chat is already owned by a retained conversation.

---

    Code
      alias$run_sync("alias bypass")
    Condition
      Error in `conversation_abort()`:
      ! This conversation must be run through its current owner.

---

    Code
      collect_async_stream(delayed_alias)
    Condition
      Error in `conversation_abort()`:
      ! This conversation must be run through its current owner.
