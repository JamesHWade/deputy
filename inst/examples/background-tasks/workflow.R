# A lead agent with two retained specialists it can run in the background.

# A gate holds a specialist's tool call open until the lead reaches a known
# point, so the example's tasks finish in the same order on every run. Real
# tools take as long as they take; nothing in Deputy needs a gate.
background_example_gate <- function() {
  gate <- new.env(parent = emptyenv())
  gate$calls <- 0L
  gate$open <- FALSE
  gate$held <- list()
  gate$watchers <- list()
  gate$hold <- function(value) {
    gate$calls <- gate$calls + 1L
    watchers <- gate$watchers
    gate$watchers <- list()
    for (watcher in watchers) {
      watcher()
    }
    if (gate$open) {
      return(value)
    }
    promises::promise(function(resolve, reject) {
      gate$held <- c(gate$held, list(function() resolve(value)))
    })
  }
  gate$release <- function() {
    gate$open <- TRUE
    held <- gate$held
    gate$held <- list()
    for (resolve in held) {
      resolve()
    }
    invisible(NULL)
  }
  # A promise for the first call to reach the gate.
  gate$reached <- function() {
    if (gate$calls > 0L) {
      return(promises::promise_resolve(TRUE))
    }
    promises::promise(function(resolve, reject) {
      gate$watchers <- c(gate$watchers, list(function() resolve(TRUE)))
    })
  }
  gate
}

background_example_tool <- function(name, description, fun) {
  ellmer::tool(
    fun,
    name = name,
    description = description,
    arguments = list(),
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      destructive_hint = FALSE,
      open_world_hint = FALSE,
      idempotent_hint = TRUE
    )
  )
}

background_example <- function(fixture) {
  gates <- list(
    analyst = background_example_gate(),
    reviewer = background_example_gate()
  )
  seen <- new.env(parent = emptyenv())
  # Your application decides who may read the specialists' conversations.
  # Here one object stands in for a signed-in user.
  requester <- new.env(parent = emptyenv())

  lead <- Agent$new(
    fixture$chat("lead"),
    system_prompt = paste(
      "You coordinate a batch report. Start the analyst and the reviewer in",
      "the background, look up the specification yourself while they work,",
      "then collect their results."
    ),
    permissions = permissions_standard(),
    usage_limits = UsageLimits(max_requests = 24),
    agent_name = "lead",
    delegation_disclosure = DelegationDisclosure(
      authorize = function(candidate, scope) identical(candidate, requester)
    )
  )
  # The lead's own work. It records what the lead's tasks are doing at that
  # moment, after both specialists have begun their own tool calls.
  lead$register_tool(background_example_tool(
    "lookup_specification",
    "Look up the viscosity specification for a batch.",
    function() {
      promises::then(
        promises::promise_all(
          gates$analyst$reached(),
          gates$reviewer$reached()
        ),
        function(reached) {
          seen$while_working <- lead$background_tasks()[, c("agent", "state")]
          "Specification for batch 12: viscosity 4.0 to 4.5 Pa.s."
        }
      )
    }
  ))

  analyst <- Agent$new(
    fixture$chat("analyst"),
    system_prompt = "You analyze batch measurements.",
    tools = list(background_example_tool(
      "load_measurements",
      "Load the viscosity measurements for the batch.",
      function() gates$analyst$hold("Viscosity (Pa.s): 4.1, 4.2, 4.3")
    )),
    permissions = permissions_standard(),
    agent_name = "analyst"
  )
  reviewer <- Agent$new(
    fixture$chat("reviewer"),
    system_prompt = "You review draft reports.",
    tools = list(background_example_tool(
      "read_draft",
      "Read the draft report.",
      function() gates$reviewer$hold("Draft: batch 12 meets specification.")
    )),
    permissions = permissions_standard(),
    agent_name = "reviewer"
  )

  # Retaining hands each specialist to the lead with a budget for all of its
  # tasks together.
  handles <- c(
    analyst = lead$retain_agent(analyst, UsageLimits(max_requests = 12)),
    reviewer = lead$retain_agent(reviewer, UsageLimits(max_requests = 12))
  )
  lead$register_tools(background_tools(
    lead,
    agents = handles,
    # Each task may make three requests. They are set aside from the lead's 24
    # while the task runs.
    usage_limits = UsageLimits(max_requests = 3),
    descriptions = c(
      analyst = "Analyzes batch measurements",
      reviewer = "Reviews draft reports"
    )
  ))

  # The analyst's measurements arrive once the lead starts waiting, and the
  # reviewer's draft only after the lead has cancelled the review, so the
  # analyst always finishes first and the reviewer is always cancelled
  # partway through.
  lead$add_hook(HookMatcher(
    event = "PreToolUse",
    pattern = "^task_wait$",
    callback = function(tool_name, tool_input, context) {
      gates$analyst$release()
      NULL
    }
  ))
  lead$add_hook(HookMatcher(
    event = "PostToolUse",
    pattern = "^task_cancel$",
    callback = function(tool_name, tool_result, tool_error, context) {
      gates$reviewer$release()
      NULL
    }
  ))

  list(
    lead = lead,
    handles = handles,
    requester = requester,
    gates = gates,
    seen = seen
  )
}

background_example_release <- function(example) {
  for (handle in example$handles) {
    try(example$lead$release_agent(handle), silent = TRUE)
  }
  invisible(NULL)
}
