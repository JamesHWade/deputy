# sub-agent tool denylist drops tools with unreadable names

    Code
      filtered <- lead$.__enclos_env__$private$filter_disallowed_tools(tools,
        disallowed_tools = "run_bash")
    Condition
      Warning:
      Dropping tool "unreadable" because its name could not be read.
      i Tool object class: <environment>.
      x no applicable method for `@` applied to an object of class "environment"

