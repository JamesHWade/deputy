# One fixture server scripted per model: each model's replies are indexed by
# how many assistant messages its request already holds, so every agent gets
# its own script however the agents' requests interleave. A reply may be a
# function of the request and of the task IDs seen so far in tool results
# (`ids$analyst` is the analyst's task IDs, oldest first). The request log
# keeps one global arrival order across the agents.
local_scripted_server <- function(script, .local_envir = parent.frame()) {
  helpers <- new.env(parent = baseenv())
  helpers$`%||%` <- function(x, y) if (is.null(x)) y else x
  environment(helpers$`%||%`) <- helpers
  for (name in c("runtime_reply", "runtime_tool_calls_reply")) {
    helper <- get(name)
    environment(helper) <- helpers
    assign(name, helper, envir = helpers)
  }
  # Reply functions run in the server process: they see the helpers above and
  # nothing of the test that wrote them.
  helpers$script <- lapply(script, function(replies) {
    lapply(replies, function(reply) {
      if (is.function(reply)) {
        environment(reply) <- helpers
      }
      reply
    })
  })
  responder <- function(request, count) {
    replies <- script[[request$model]]
    if (is.null(replies)) {
      return(runtime_reply(paste("no script for", request$model)))
    }
    assistant <- 0L
    ids <- list()
    for (message in request$messages) {
      if (identical(message$role, "assistant")) {
        assistant <- assistant + 1L
      }
      if (identical(message$role, "tool") && is.character(message$content)) {
        found <- regmatches(
          message$content,
          regexec(
            '^\\{"task_id":"(task_[^"]+)","agent":"([^"]+)"',
            message$content
          )
        )[[1L]]
        if (length(found) == 3L && !found[[2L]] %in% ids[[found[[3L]]]]) {
          ids[[found[[3L]]]] <- c(ids[[found[[3L]]]], found[[2L]])
        }
      }
    }
    reply <- replies[[min(assistant + 1L, length(replies))]]
    if (is.function(reply)) {
      reply <- reply(request, ids)
    }
    reply
  }
  environment(responder) <- helpers
  server <- local_runtime_server(responder, .local_envir = .local_envir)
  # The models that sent each request, in the order the server received them.
  server$arrivals_by_model <- function() {
    vapply(server$requests(), function(entry) entry$body$model, character(1))
  }
  server
}

# A tool that waits for the test: its call stays pending until `release()`.
background_gate <- function() {
  gate <- new.env(parent = emptyenv())
  gate$calls <- 0L
  gate$released <- FALSE
  gate$pending <- list()
  gate$release <- function() {
    gate$released <- TRUE
    pending <- gate$pending
    gate$pending <- list()
    for (resolve in pending) {
      resolve(TRUE)
    }
    invisible(NULL)
  }
  gate
}

gated_tool <- function(name, gate, value, read_only = TRUE) {
  ellmer::tool(
    function() {
      gate$calls <- gate$calls + 1L
      if (gate$released) {
        return(value)
      }
      promises::then(
        promises::promise(function(resolve, reject) {
          gate$pending <- c(gate$pending, list(resolve))
        }),
        function(ignored) value
      )
    },
    name = name,
    description = paste("Gated fixture tool", name),
    arguments = list(),
    annotations = ellmer::tool_annotations(
      read_only_hint = read_only,
      destructive_hint = FALSE,
      open_world_hint = FALSE,
      idempotent_hint = TRUE
    )
  )
}

tool_call <- function(name, arguments = list(), id = NULL) {
  list(
    id = id %||% paste0("call_", name),
    name = name,
    arguments = arguments
  )
}

# A lead with two retained specialists on one scripted server.
background_setup <- function(
  script,
  analyst_tools = list(),
  reviewer_tools = list(),
  lead_tools = list(),
  lead_limits = UsageLimits(max_requests = 24),
  task_limits = UsageLimits(max_requests = 3),
  permissions = permissions_full(),
  ...,
  .local_envir = parent.frame()
) {
  server <- local_scripted_server(script, .local_envir = .local_envir)
  lead <- Agent$new(
    runtime_chat(server, model = "lead"),
    tools = lead_tools,
    permissions = permissions,
    usage_limits = lead_limits,
    agent_name = "lead",
    delegation_disclosure = DelegationDisclosure(
      authorize = function(requester, scope) identical(requester, "host")
    )
  )
  analyst <- Agent$new(
    runtime_chat(server, model = "analyst"),
    tools = analyst_tools,
    permissions = permissions_full(),
    agent_name = "analyst"
  )
  reviewer <- Agent$new(
    runtime_chat(server, model = "reviewer"),
    tools = reviewer_tools,
    permissions = permissions_full(),
    agent_name = "reviewer"
  )
  handles <- c(
    analyst = lead$retain_agent(analyst, UsageLimits(max_requests = 12)),
    reviewer = lead$retain_agent(reviewer, UsageLimits(max_requests = 12))
  )
  lead$register_tools(background_tools(
    lead,
    handles,
    task_limits,
    descriptions = c(analyst = "Analyzes data", reviewer = "Reviews drafts"),
    ...
  ))
  list(
    server = server,
    lead = lead,
    analyst = analyst,
    reviewer = reviewer,
    handles = handles
  )
}

background_gate_open <- function() {
  gate <- background_gate()
  gate$released <- TRUE
  gate
}

# Releases `gate` from the event loop once `condition()` holds, for a step no
# hook marks, such as a task entering "cancelling" when its lead's pass ends.
release_when <- function(gate, condition, timeout = 60) {
  deadline <- Sys.time() + timeout
  check <- function() {
    if (isTRUE(tryCatch(condition(), error = function(error) FALSE))) {
      gate$release()
    } else if (Sys.time() < deadline) {
      later::later(check, 0.01)
    }
  }
  later::later(check, 0.01)
  invisible(NULL)
}

# Every tool result `model` was sent, by tool call ID: what the model saw.
model_tool_results <- function(server, model = "lead") {
  results <- list()
  for (entry in server$requests()) {
    if (!identical(entry$body$model, model)) {
      next
    }
    for (message in entry$body$messages) {
      if (identical(message$role, "tool")) {
        results[[message$tool_call_id]] <- paste(
          unlist(message$content),
          collapse = ""
        )
      }
    }
  }
  results
}

# No lease, reservation, waiter or active child outlives a run.
expect_background_idle <- function(setup) {
  private <- setup$lead$.__enclos_env__$private
  testthat::expect_false(isTRUE(private$run_active))
  testthat::expect_length(private$delegation_usage_reservations, 0L)
  testthat::expect_length(private$background_reservations, 0L)
  testthat::expect_length(private$active_subagents, 0L)
  testthat::expect_length(private$.background$waiters, 0L)
  testthat::expect_null(
    attr(private$.chat, "deputy_active_conversations", exact = TRUE)
  )
  for (handle in setup$handles) {
    entry <- private$owned_conversations[[handle]]
    testthat::expect_false(entry$busy)
    testthat::expect_length(entry$waiters, 0L)
    testthat::expect_false(
      isTRUE(entry$agent$.__enclos_env__$private$run_active)
    )
  }
  invisible(setup)
}
