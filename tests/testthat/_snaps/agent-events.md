# malformed tool identity is rejected before permission checks

    Code
      agent$.__enclos_env__$private$on_tool_request(request)
    Condition
      Error in `ellmer::tool_reject()`:
      ! Tool call rejected. Cannot execute tool request because its name could not be read. Request class: <ellmer::ContentToolRequest/ellmer::Content/S7_object>. Expected one non-empty string; got <list>.
