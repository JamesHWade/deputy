# composition tool cannot transfer authority or run outside its caller

    Code
      tool("direct call")
    Condition
      Error in `conversation_abort()`:
      ! Delegation tools require their owner's active governed run.

---

    Code
      owned_test_owner()$register_tool(tool)
    Condition
      Error in `conversation_abort()`:
      ! Delegation tools may only be registered and executed by their owner.

# adoption preserves source callbacks and fresh history is explicit

    Code
      adopt_chat(chat, owner, permissions_standard(), UsageLimits(), history = "fresh",
      callbacks = "preserve")
    Condition
      Error in `conversation_abort()`:
      ! Adoption requires callbacks = 'replace'.
