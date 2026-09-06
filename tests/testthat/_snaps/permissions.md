# S7 permissions reject malformed capability values at construction

    Code
      Permissions(file_read = NA)
    Condition
      Error in `Permissions()`:
      ! `file_read` must be TRUE or FALSE

---

    Code
      Permissions(bash = c(TRUE, FALSE))
    Condition
      Error in `Permissions()`:
      ! `bash` must be TRUE or FALSE

---

    Code
      Permissions(r_code = 1)
    Condition
      Error in `Permissions()`:
      ! `r_code` must be TRUE or FALSE

---

    Code
      Permissions(web = logical())
    Condition
      Error in `Permissions()`:
      ! `web` must be TRUE or FALSE

---

    Code
      Permissions(install_packages = "yes")
    Condition
      Error in `Permissions()`:
      ! `install_packages` must be TRUE or FALSE

---

    Code
      Permissions(can_use_tool = "allow")
    Condition
      Error in `Permissions()`:
      ! `can_use_tool` must be NULL or a function

---

    Code
      Permissions(tool_allowlist = NA_character_)
    Condition
      Error in `Permissions()`:
      ! `tool_allowlist` must be NULL or a character vector

---

    Code
      Permissions(permission_prompt_tool_name = NA_character_)
    Condition
      Error in `Permissions()`:
      ! `permission_prompt_tool_name` must be NULL or a length-1 character string

# nullable S7 permission properties and bulk replacement stay frozen

    Code
      policy@can_use_tool <- (function(...) PermissionResultAllow())
    Condition
      Error:
      ! Cannot modify `can_use_tool`: property is read-only after construction

---

    Code
      policy@tool_allowlist <- "write_file"
    Condition
      Error:
      ! Cannot modify `tool_allowlist`: property is read-only after construction

---

    Code
      policy@tool_denylist <- "read_file"
    Condition
      Error:
      ! Cannot modify `tool_denylist`: property is read-only after construction

---

    Code
      policy@permission_prompt_tool_name <- "ask_user"
    Condition
      Error:
      ! Cannot modify `permission_prompt_tool_name`: property is read-only after construction

---

    Code
      S7::props(policy) <- list(file_write = TRUE)
    Condition
      Error:
      ! Cannot modify `file_write`: property is read-only after construction

