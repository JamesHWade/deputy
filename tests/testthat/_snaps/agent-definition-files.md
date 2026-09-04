# discovery is deterministic and rejects duplicate canonical names

    Code
      agent_definitions(root)
    Condition
      Error in `agent_definitions()`:
      ! Invalid AgentDefinition file
      x Duplicate AgentDefinition names: "reviewer"
      i File: '<dir>'

# writing requires explicit unambiguous registries and protects existing files

    Code
      agent_definition_write(definition, path)
    Condition
      Error in `FUN()`:
      ! Invalid AgentDefinition file
      x Each tools object must match exactly one registry entry
      i File: '<file>'

---

    Code
      agent_definition_write(definition, path, tools = list(read = tool_read_file))
    Condition
      Error in `agent_definition_write()`:
      ! Invalid AgentDefinition file
      x File already exists; set `overwrite = TRUE` to replace it
      i File: '<file>'

# a definition file cannot widen its lead's permission ceiling

    Code
      lead$get_tools()[["delegate_to_agent"]]("reviewer", "Review text")
    Condition
      Error in `private$derive_subagent_permissions()`:
      ! Sub-agent permission mode cannot change under the lead policy
      x Lead mode readonly cannot delegate with mode full.
      i Use mode readonly, then tighten the child with disallowed_tools or max_requests.
