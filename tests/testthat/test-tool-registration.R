registration_chat <- function() {
  ellmer::chat_openai(
    credentials = function() "test",
    model = "gpt-4o-mini",
    echo = "none"
  )
}

registration_tool <- function(name = "lookup", value = "original") {
  ellmer::tool(
    fun = function() value,
    name = name,
    description = "Return a local value.",
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      destructive_hint = FALSE,
      idempotent_hint = TRUE,
      open_world_hint = FALSE
    )
  )
}

test_that("registration requires explicit replacement and uses tool names", {
  agent <- Agent$new(chat = registration_chat())
  original <- registration_tool()
  expect_identical(agent$register_tool(original), agent)
  before <- agent$get_tools()
  replacement <- registration_tool(value = "replacement")
  expect_snapshot(error = TRUE, agent$register_tool(replacement))
  expect_identical(agent$get_tools(), before)
  expect_identical(agent$register_tool(replacement, replace = TRUE), agent)
  expect_identical(agent$get_tools()$lookup(), "replacement")
  agent$register_tools(list(ignored_alias = registration_tool("second")))
  expect_named(agent$get_tools(), c("lookup", "second"))
})

test_that("whole batches are checked before changing a real Chat registry", {
  agent <- Agent$new(
    chat = registration_chat(),
    tools = list(registration_tool())
  )
  before <- agent$get_tools()
  for (replace in c(FALSE, TRUE)) {
    expect_error(
      agent$register_tools(
        list(registration_tool("new"), 42),
        replace = replace
      ),
      class = "deputy_tool_registration"
    )
    expect_error(
      agent$register_tools(
        list(registration_tool("new"), registration_tool("new")),
        replace = replace
      ),
      "Duplicate tool name"
    )
    expect_identical(agent$get_tools(), before)
  }
  expect_error(agent$register_tools(list(), replace = NA), "replace")
  expect_error(agent$register_tools(registration_tool()), "list")
  expect_error(
    agent$set_tools(list(registration_tool("new"), 42)),
    "position 2"
  )
  expect_identical(agent$get_tools(), before)
  agent$set_tools(list(registration_tool("new")))
  expect_named(agent$get_tools(), "new")
  agent$set_tools(list())
  expect_length(agent$get_tools(), 0)
})

test_that("invalid annotations and native adaptation preserve all tools", {
  agent <- Agent$new(
    chat = registration_chat(),
    tools = list(registration_tool())
  )
  before <- agent$get_tools()
  for (value in list(NA, "true", c(TRUE, FALSE), 1)) {
    invalid <- registration_tool("invalid")
    invalid@annotations <- list(read_only_hint = value)
    expect_error(
      agent$register_tools(list(registration_tool("new"), invalid)),
      class = "deputy_tool_registration"
    )
    expect_identical(agent$get_tools(), before)
  }
  expect_error(
    agent$set_tools(list(
      registration_tool("new"),
      ellmer::openai_tool_web_search()
    )),
    "not authorized"
  )
  expect_identical(agent$get_tools(), before)
})

test_that("constructor failures preserve tools on the supplied Chat", {
  chat <- registration_chat()
  chat$register_tool(registration_tool())
  before <- chat$get_tools()
  expect_error(
    Agent$new(chat = chat, tools = list(registration_tool())),
    "already registered"
  )
  expect_identical(chat$get_tools(), before)
  expect_error(Agent$new(chat = chat, tools = list(42)), "position 1")
  expect_identical(chat$get_tools(), before)
  agent <- Agent$new(chat = chat, tools = list(registration_tool("second")))
  expect_named(agent$get_tools(), c("lookup", "second"))
  expect_true(all(vapply(
    agent$get_tools(),
    function(tool) {
      isTRUE(attr(tool, "deputy_runtime_tool"))
    },
    logical(1)
  )))
})

test_that("the internal result reader cannot be replaced by a public tool", {
  agent <- Agent$new(chat = registration_chat())
  spoof <- registration_tool("deputy_read_tool_result")
  expect_error(agent$register_tool(spoof, replace = TRUE), "reserved")
  expect_error(agent$set_tools(list(spoof)), "reserved")
  expect_error(
    Agent$new(chat = registration_chat(), tools = list(spoof)),
    "reserved"
  )
})

test_that("function and package tools share registration and survive cloning", {
  packaged <- ellmer::tool(
    fun = base::toupper,
    name = "uppercase",
    description = "Uppercase text.",
    arguments = list(x = ellmer::type_string()),
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE
    )
  )
  agent <- Agent$new(
    chat = registration_chat(),
    tools = list(packaged, registration_tool())
  )
  clone <- agent$clone()
  clone$set_tools(clone$get_tools())
  expect_identical(clone$get_tools()$uppercase("hello"), "HELLO")
  clone$register_tool(registration_tool(value = "cloned"), replace = TRUE)
  expect_identical(clone$get_tools()$lookup(), "cloned")
  expect_identical(agent$get_tools()$lookup(), "original")
})

test_that("missing annotations stay absent and use conservative permissions", {
  tool <- ellmer::tool(
    function() "unknown",
    name = "unknown",
    description = "Unknown effects."
  )
  agent <- Agent$new(chat = registration_chat(), tools = list(tool))
  expect_identical(agent$get_tools()$unknown@annotations, list())
  for (annotations in list(NULL, list(), list(open_world_hint = NULL))) {
    context <- list(tool_annotations = annotations)
    for (mode in c("standard", "readonly", "plan")) {
      policy <- Permissions$new(mode = mode, web = FALSE, file_write = FALSE)
      expect_s3_class(
        policy$check("unknown", list(), context),
        "PermissionResultDeny"
      )
    }
    expect_s3_class(
      permissions_full()$check("unknown", list(), context),
      "PermissionResultAllow"
    )
  }
  seen <- NULL
  policy <- Permissions$new(can_use_tool = function(
    tool_name,
    tool_input,
    context
  ) {
    seen <<- context$tool_annotations
    PermissionResultAllow()
  })
  expect_s3_class(
    policy$check("unknown", list(), list(tool_annotations = list())),
    "PermissionResultAllow"
  )
  expect_identical(seen, list())
  expect_identical(effective_tool_annotations(list()), tool_annotation_defaults)
})

test_that("permission annotations come from the registered executable", {
  agent <- Agent$new(
    chat = registration_chat(),
    tools = list(registration_tool()),
    permissions = Permissions$new(mode = "readonly", tool_allowlist = "lookup")
  )
  misleading <- registration_tool()
  misleading@annotations <- list(destructive_hint = TRUE)
  for (attached in list(NULL, misleading)) {
    request <- ellmer::ContentToolRequest(
      id = "lookup-1",
      name = "lookup",
      arguments = list(),
      tool = attached
    )
    expect_no_error(agent$.__enclos_env__$private$handle_tool_request(request))
  }
})
