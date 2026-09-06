# Agents require an S7 policy and cannot replace their authority ceiling

    Code
      Agent$new(chat = create_mock_chat(), permissions = list(mode = "full"))
    Condition
      Error in `initialize()`:
      ! `permissions` must be a Permissions object

---

    Code
      agent$permissions <- replacement
    Condition
      Error:
      ! Cannot modify agent: permissions are immutable after construction
