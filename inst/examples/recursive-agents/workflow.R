# Host-owned three-level retained graph used by the Shiny app and tests.
recursive_agents <- function(fixture, effects = new.env(parent = emptyenv())) {
  effects$count <- effects$count %||% 0L
  requester <- new.env(parent = emptyenv())
  disclosure <- DelegationDisclosure(
    authorize = function(candidate, scope) identical(candidate, requester)
  )
  evidence <- ellmer::tool(
    function() {
      effects$count <- effects$count + 1L
      "Observed fixture evidence: 4, 7, 6; conditions remain unconfirmed."
    },
    name = "inspect_fixture",
    description = "Read the deterministic fixture evidence.",
    arguments = list(),
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      destructive_hint = FALSE,
      open_world_hint = FALSE,
      idempotent_hint = TRUE
    )
  )
  root <- Agent$new(
    fixture$chat("root"),
    system_prompt = paste(
      "RECURSIVE_ROOT: coordinate a bounded evidence review.",
      "Use analyze once, then synthesize the returned reports."
    ),
    permissions = permissions_full(),
    usage_limits = UsageLimits(max_requests = 8L, max_tool_calls = 4L),
    delegation_disclosure = disclosure
  )
  analyst <- Agent$new(
    fixture$chat("analyst"),
    system_prompt = paste(
      "RECURSIVE_ANALYST: inspect the supplied evidence.",
      "Use inspect_fixture, then ask the reviewer before concluding."
    ),
    permissions = permissions_full(),
    tools = list(inspect_fixture = evidence),
    # This child limit includes its nested reviewer usage. The graph-wide
    # budget remains the lifetime ceiling for the whole retained workflow.
    usage_limits = UsageLimits(max_requests = 8L, max_tool_calls = 4L),
    agent_name = "analyst"
  )
  reviewer <- Agent$new(
    fixture$chat("reviewer"),
    system_prompt = paste(
      "RECURSIVE_REVIEWER: review the analyst's bounded evidence.",
      "Return one concise review."
    ),
    permissions = permissions_full(),
    usage_limits = UsageLimits(max_requests = 1L),
    agent_name = "reviewer"
  )
  handles <- root$retain_agent_graph(
    agents = list(analyst = analyst, reviewer = reviewer),
    routes = list(
      root = list(
        analyze = list(
          target = "analyst",
          description = "Ask the analyst to inspect the evidence.",
          usage_limits = UsageLimits(max_requests = 4L)
        )
      ),
      analyst = list(
        review = list(
          target = "reviewer",
          description = "Ask the reviewer to check the analyst's evidence.",
          usage_limits = UsageLimits(max_requests = 1L)
        )
      )
    ),
    usage_limits = UsageLimits(max_requests = 8L, max_tool_calls = 4L),
    max_depth = 2L,
    max_delegations = 8L,
    max_concurrency = 2L,
    max_runs = 32L
  )
  list(
    root = root,
    agents = list(analyst = analyst, reviewer = reviewer),
    handles = handles,
    requester = requester,
    effects = effects,
    disclosure = disclosure
  )
}
