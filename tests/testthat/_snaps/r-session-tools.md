# bridge transfer rejects runtime attributes and retains portable data

    Code
      r_session_tool_serialize_result(hidden)
    Condition
      Error in `r_session_tool_serialize_result()`:
      ! R session tool results may contain only bounded plain R data; closures, environments and native pointers are not supported.

---

    Code
      r_session_tool_serialize_result(new.env())
    Condition
      Error in `r_session_tool_serialize_result()`:
      ! R session tool results may contain only bounded plain R data; closures, environments and native pointers are not supported.

---

    Code
      r_session_tool_serialize_result(raw(100), max_bytes = 50)
    Condition
      Error in `r_session_tool_serialize_result()`:
      ! R session tool result exceeds its mailbox size limit.

---

    Code
      r_session_tool_read_json(path, 128, "request")
    Condition
      Error in `r_session_tool_read_json()`:
      ! R session mailbox "request" exceeds its size limit.

# request identity and raw JSON never restore worker classes

    Code
      check(request)
    Condition
      Error in `r_session_tool_validate_request()`:
      ! R session tool request generation is stale.

---

    Code
      check(request)
    Condition
      Error in `r_session_tool_validate_request()`:
      ! R session tool request names an unselected tool.

---

    Code
      check(request)
    Condition
      Error in `r_session_tool_validate_request()`:
      ! R session tool arguments must be bounded plain JSON data.

# direct host calls cannot borrow a bridge and selection requires raw tools

    Code
      session$run("tools$fetch()")
    Condition
      Error in `private$enqueue()`:
      ! R code with bridged Agent tools must run inside its active governed tool execution.

---

    Code
      RSession$new(agent, tools = "converted")
    Condition
      Error in `r_session_tool_registered()`:
      ! R session tool "converted" must use `convert = FALSE`.

---

    Code
      RSession$new(durable, tools = "fetch")
    Condition
      Error in `initialize()`:
      ! R sessions with selected tools cannot use an Agent with durable approvals configured.

