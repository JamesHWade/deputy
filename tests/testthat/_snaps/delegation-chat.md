# a failing or invalid chat function stops the delegation first

    Code
      DelegationPolicy(chat = "gateway")
    Condition
      Error in `delegation_binding_abort()`:
      ! chat must be a function or NULL.

# params for a copy of the lead's chat need a chat function

    Code
      LeadAgent$new(create_mock_chat(), sub_agents = list(inherit))
    Condition
      Error in `private$check_definition_params()`:
      ! AgentDefinition "a" has `params`, but its model copies the lead's chat, which keeps the lead's params.
      i Give the lead a `DelegationPolicy(chat = )` function that builds the subagent's chat, or use a "provider/model" model.

# definition params are validated, printed and kept by copies

    Code
      print(definition)
    Output
      <AgentDefinition: a >
        description: A
        tools: 0
        skills: 0
        model: openai/gpt-test
        params: stop_sequences = x, y; reasoning_effort = low

---

    Code
      agent_definition("a", "A", "a", params = "low")
    Condition
      Error in `validate_agent_definition_params()`:
      ! `params` must be a list made by `ellmer::params()`

---

    Code
      agent_definition("a", "A", "a", params = list(temperature = -1))
    Condition
      Error in `validate_agent_definition_params()`:
      ! `params` is invalid: `temperature` must be a number larger than or equal to 0 or `NULL`, not the number -1.

---

    Code
      agent_definition("a", "A", "a", params = ellmer::params(foo = 1))
    Condition
      Error in `validate_agent_definition_params()`:
      ! `params` can only hold the parameters of `ellmer::params()`
      x Not supported: "foo"
      i For other request settings, build the subagent's chat yourself with `DelegationPolicy(chat = )`.

