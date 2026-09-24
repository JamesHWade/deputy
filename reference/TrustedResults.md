# Designate trusted tools as the only producers of host results

A read-only S7 policy implementing the trusted mini-agent pattern of
Will Landau and Sam Parmar ([*Trusted
Mini-Agents*](https://trustedminiagents.dev); see their
[definition](https://trustedminiagents.dev/definition.html)). Each named
result type is produced by exactly one registered local tool. When that
tool returns successfully, Deputy delivers its value verbatim to the
host through a `"trusted_result"`
[AgentEvent](https://jameshwade.github.io/deputy/reference/AgentEvent.md),
[`result_trusted_results()`](https://jameshwade.github.io/deputy/reference/result_trusted_results.md),
and the optional `on_result` callback. The value does not have to pass
through model text.

An Agent created with a policy checks its complete tool registry
whenever tools are published: at construction, `$set_tools()`,
`$register_tools()`, skill and MCP loading, cloning, and graph route
installation. Registration fails, leaving the previous registry intact,
when:

- a designated trusted tool is missing from the registry;

- a trusted tool is not a local function tool (it is provider-native or
  MCP), executes code, or delegates to another Agent;

- any other tool executes model-supplied code or delegates to another
  Agent (`run_r_code`, `run_bash`, R session tools, delegation and graph
  route tools). These tools could produce a result of any kind;

- any other tool's effective annotations permit writes (`read_only_hint`
  not `TRUE`, or an explicit `destructive_hint = TRUE`) or the open
  world (`open_world_hint` not `FALSE`), unless the host names it in
  `exempt_tools`. Unannotated tools, including MCP REPL and console
  tools, use the conservative defaults from ADR-0007 and are rejected.

Exemptions are the host's explicit assertion that a local function tool
cannot produce a trusted kind of result. MCP, provider-native,
code-execution, and delegation tools cannot be exempted. The policy is
fixed at construction; it constrains which tools may be registered
alongside trusted ones and does not grant permission to call any tool.
Permissions, hooks, and durable approvals still govern every call.

A
[LeadAgent](https://jameshwade.github.io/deputy/reference/LeadAgent.md)
accepts the policy for its whole delegation tree. Its own
`delegate_to_agent` tool is allowed because every child inherits the
policy: each definition's tools must pass the same check, and a
designated tool may live in the lead or in children but must be the same
tool everywhere. A child's designated tool must be declared in its
definition's `tools` or in
[Skill](https://jameshwade.github.io/deputy/reference/Skill.md) values;
skill directories load when the child is built and cannot supply one.
Child trusted results are recorded in the lead's run and delivered to
its `on_result`, with the child's correlation fields. Graph routes and
other composition tools are still rejected.

A trusted tool runs only as the tool of the Agent's own governed
request, so permissions, hooks, and approvals always precede it. Calls
from host code or from inside another tool fail without publishing a
result.

Tool argument values given to the trusted tool are recorded in the event
after ellmer's argument conversion and Deputy's path resolution.

## Usage

``` r
TrustedResults(
  ...,
  on_result = NULL,
  exempt_tools = character(),
  model_receipt = FALSE
)
```

## Arguments

- ...:

  Named pairs `result_type = "tool_name"`. Result types must be unique
  identifiers (letters, numbers, dots, underscores, hyphens). Each tool
  may produce only one result type.

- on_result:

  Optional function called with the `"trusted_result"`
  [AgentEvent](https://jameshwade.github.io/deputy/reference/AgentEvent.md)
  as soon as the trusted tool returns, before the model sees any output.
  Use it to update a Shiny `reactiveValues()` or a host store. If it
  signals an error, the result event is still recorded, a
  `"trusted_result_delivery_failed"` notification is emitted, and the
  model receives a tool error instead of the value.

- exempt_tools:

  Character vector of local function tool names that the host asserts
  cannot bypass a trusted tool despite write or open-world annotations.

- model_receipt:

  If `TRUE`, the model receives a receipt naming the result ID and type
  instead of the value, so it cannot restate the values. Defaults to
  `FALSE`, which sends the model the same value as the host.

## Value

A read-only `TrustedResults` S7 value.

## See also

[`vignette("trusted-mini-agents")`](https://jameshwade.github.io/deputy/articles/trusted-mini-agents.md),
[`result_trusted_results()`](https://jameshwade.github.io/deputy/reference/result_trusted_results.md),
[`approval_review_ui()`](https://jameshwade.github.io/deputy/reference/approval_review_ui.md),
[Agent](https://jameshwade.github.io/deputy/reference/Agent.md),
[`tool_metadata()`](https://jameshwade.github.io/deputy/reference/tool_metadata.md)

## Additional properties

- `@results`:

  Named character vector mapping result types to tool names.

## Examples

``` r
policy <- TrustedResults(
  forecast = "get_forecast",
  on_result = function(event) print(event$value),
  model_receipt = TRUE
)
policy$results
#>       forecast 
#> "get_forecast" 
```
