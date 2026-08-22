# provider tool call IDs distinguish absence from invalid values

    Code
      request_data <- agent$.__enclos_env__$private$extract_tool_request_data(
        invalid_request)
    Condition
      Warning:
      Ignoring invalid provider tool call ID from request.
      i Expected one non-empty string; got <list>.
    Code
      result_data <- agent$.__enclos_env__$private$extract_tool_result_data(
        invalid_result)
    Condition
      Warning:
      Ignoring invalid provider tool call ID from result.
      i Expected one non-empty string; got <list>.

---

    Code
      unreadable_id <- read_provider_tool_call_id(function() unreadable_request@id,
      source = "request", object = unreadable_request)
    Condition
      Warning:
      Failed to read provider tool call ID from request.
      i Source class: <environment>.
      x no applicable method for `@` applied to an object of class "environment"
