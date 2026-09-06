# both definition constructors expose the same S7 contract

    Code
      definition@name <- "changed"
    Condition
      Error:
      ! Cannot modify `name`: property is read-only after construction

---

    Code
      definition@max_requests <- 2L
    Condition
      Error:
      ! Cannot modify `max_requests`: property is read-only after construction

---

    Code
      definition@permission_mode <- "full"
    Condition
      Error:
      ! Cannot modify `permission_mode`: property is read-only after construction

---

    Code
      S7::props(definition) <- list(prompt = "changed")
    Condition
      Error:
      ! Cannot modify `prompt`: property is read-only after construction

# definition values compose original tools and caller-owned skill state

    Code
      definition@tools <- list()
    Condition
      Error:
      ! Cannot modify `tools`: property is read-only after construction

---

    Code
      definition@skills <- list()
    Condition
      Error:
      ! Cannot modify `skills`: property is read-only after construction

# definition consumers reject old S3 lookalikes

    Code
      copy_agent_definition(old)
    Condition
      Error in `copy_agent_definition()`:
      ! `definition` must be an AgentDefinition object

---

    Code
      LeadAgent$new(create_mock_chat(), sub_agents = list(old))
    Condition
      Error in `copy_agent_definition()`:
      ! `sub_agents[[1]]` must be an AgentDefinition object

---

    Code
      lead$register_sub_agent(old)
    Condition
      Error in `lead$register_sub_agent()`:
      ! `definition` must be an AgentDefinition object
