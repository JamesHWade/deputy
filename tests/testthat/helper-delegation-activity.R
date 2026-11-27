activity_disclosure <- function(state = NULL, redact = NULL) {
  DelegationDisclosure(
    authorize = function(requester, scope) {
      identical(requester, "viewer") && !isTRUE(state$denied)
    },
    redact = redact %||% function(view, requester) view
  )
}

activity_measure_tool <- function(value, counter = NULL) {
  ellmer::tool(
    function() {
      if (!is.null(counter)) {
        counter$calls <- counter$calls + 1L
      }
      ellmer::ContentToolResult(
        value = value,
        extra = list(
          display = list(
            title = "Ran a trusted calculation",
            html = paste0(
              "<div class=\"measure\" onclick=\"steal()\"><strong>",
              value,
              "</strong></div>"
            ),
            show_request = FALSE
          ),
          commons_tag = "A",
          provider_private = "secret"
        )
      )
    },
    name = "call_measure",
    description = "Run a registered measure.",
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE
    )
  )
}

activity_specialist <- function(name, value, responses = NULL, counter = NULL) {
  server <- local_runtime_server(
    responses %||%
      list(
        runtime_reply(tool = "call_measure"),
        runtime_reply(paste(name, "result", value))
      ),
    .local_envir = parent.frame()
  )
  list(
    server = server,
    agent = Agent$new(
      runtime_chat(server),
      tools = list(activity_measure_tool(value, counter)),
      agent_name = name
    )
  )
}

activity_retain <- function(root, specialist, tool_name) {
  handle <- root$retain_agent(specialist, UsageLimits(max_requests = 8))
  root$register_tool(delegation_tool(
    root,
    handle,
    tool_name,
    paste("Ask", tool_name),
    UsageLimits(max_requests = 4)
  ))
  handle
}

# The tool-call IDs of the requests and results in `turns`.
activity_test_call_ids <- function(turns) {
  contents <- unlist(lapply(turns, function(turn) turn@contents))
  calls <- Filter(
    function(content) {
      inherits(content, "ellmer::ContentToolRequest") ||
        inherits(content, "ellmer::ContentToolResult")
    },
    contents
  )
  vapply(
    calls,
    function(content) {
      if (inherits(content, "ellmer::ContentToolRequest")) {
        content@id
      } else {
        content@request@id
      }
    },
    character(1)
  )
}

activity_collect <- function(agent, task) {
  stream <- agent$stream_async(task, stream = "content")
  seen <- list()
  done <- FALSE
  failure <- NULL
  coro::async(function() {
    tryCatch(
      for (chunk in coro::await_each(stream)) {
        seen[[length(seen) + 1L]] <<- chunk
      },
      error = function(error) failure <<- error
    )
    done <<- TRUE
  })()
  while (!done) {
    later::run_now(0.05)
  }
  if (!is.null(failure)) {
    rlang::cnd_signal(failure)
  }
  seen
}

activity_items <- function(contents) {
  Filter(is_activity_content, contents)
}

activity_ids <- function(contents) {
  vapply(
    contents,
    function(content) {
      if (inherits(content, "ellmer::ContentToolRequest")) {
        content@id
      } else {
        content@request@id
      }
    },
    character(1)
  )
}

activity_concurrent_root <- function(.local_envir = parent.frame()) {
  root_server <- local_runtime_server(
    list(
      runtime_tool_calls_reply(list(
        list(
          id = "call_a",
          name = "ask_sales",
          arguments = list(task = "Sales?")
        ),
        list(id = "call_b", name = "ask_ops", arguments = list(task = "Ops?"))
      )),
      runtime_reply("Lead: sales and ops reported.")
    ),
    .local_envir = .local_envir
  )
  root <- Agent$new(
    runtime_chat(root_server),
    delegation_disclosure = activity_disclosure()
  )
  list(root = root, server = root_server)
}

recursive_activity_fixture <- function(
  redact = NULL,
  .local_envir = parent.frame()
) {
  root_server <- local_runtime_server(
    list(
      runtime_reply(tool = "analyze", arguments = list(task = "Analyze.")),
      runtime_reply("Root synthesis.")
    ),
    .local_envir = .local_envir
  )
  analyst_server <- local_runtime_server(
    list(
      runtime_reply(tool = "call_measure"),
      runtime_reply(tool = "review", arguments = list(task = "Review.")),
      runtime_reply("Analyst synthesis.")
    ),
    .local_envir = .local_envir
  )
  reviewer_server <- local_runtime_server(
    list(runtime_reply(tool = "call_measure"), runtime_reply("Reviewed.")),
    .local_envir = .local_envir
  )
  root <- Agent$new(
    runtime_chat(root_server),
    permissions = permissions_full(),
    delegation_disclosure = activity_disclosure(redact = redact)
  )
  analyst <- Agent$new(
    runtime_chat(analyst_server),
    tools = list(activity_measure_tool("60")),
    permissions = permissions_full(),
    agent_name = "analyst"
  )
  reviewer <- Agent$new(
    runtime_chat(reviewer_server),
    tools = list(activity_measure_tool("61")),
    permissions = permissions_full(),
    agent_name = "reviewer"
  )
  route <- function(target) {
    list(
      target = target,
      description = paste("Ask", target),
      usage_limits = UsageLimits(max_requests = 4)
    )
  }
  root$retain_agent_graph(
    agents = list(analyst = analyst, reviewer = reviewer),
    routes = list(
      root = list(analyze = route("analyst")),
      analyst = list(review = route("reviewer"))
    ),
    usage_limits = UsageLimits(max_requests = 12),
    max_depth = 2L,
    max_delegations = 8L,
    max_concurrency = 2L
  )
  activity_enable(root, function() "viewer", 0.05)
  list(root = root)
}
