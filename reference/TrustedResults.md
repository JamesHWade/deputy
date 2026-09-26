# Designate trusted tools

`TrustedResults()` names, for each kind of result, the one tool allowed
to produce it. When that tool returns, Deputy passes its value unchanged
to your app: as a `"trusted_result"`
[AgentEvent](https://jameshwade.github.io/deputy/reference/AgentEvent.md),
through
[`result_trusted_results()`](https://jameshwade.github.io/deputy/reference/result_trusted_results.md),
and to the optional `on_result` callback. The value never has to pass
through model text. This implements the trusted mini-agent pattern of
Will Landau and Sam Parmar ([*Trusted
Mini-Agents*](https://trustedminiagents.dev); see their
[definition](https://trustedminiagents.dev/definition.html)).

To keep each trusted tool the only source of its results, an agent with
a policy checks all its tools whenever they change, including at
construction, in `$set_tools()` and `$register_tools()`, and when
loading skills or MCP tools. The change errors, and the previous tools
stay in place, if:

- a trusted tool is missing;

- a trusted tool is not a local function tool (for example, it is an MCP
  or provider tool), runs code, or delegates to another agent;

- another tool runs model-supplied code or delegates (`run_r_code`,
  `run_bash`, `install_package`, R session tools, delegation and graph
  route tools), since it could produce any result;

- another tool isn't annotated with both `read_only_hint = TRUE` and
  `open_world_hint = FALSE`, or is annotated `destructive_hint = TRUE`,
  and isn't listed in `exempt_tools`. Tools without annotations,
  including MCP REPL and console tools, fail this check.

The policy can't be changed after construction. It only limits which
tools may sit alongside trusted ones and doesn't allow any call:
permissions, hooks and approvals still apply to every call.

A trusted tool runs only when the model calls it through the agent.
Calling it from your own code or from inside another tool errors, and no
result is published. The event's `arguments` are the values the tool
received, after ellmer's type conversion and Deputy's path resolution.

A
[LeadAgent](https://jameshwade.github.io/deputy/reference/LeadAgent.md)
applies the policy to its subagents too. Its `delegate_to_agent` tool is
allowed because every subagent inherits the policy: each definition's
tools must pass the same checks, and a trusted tool may live in the lead
or in subagents but must be the same tool everywhere. A subagent's
trusted tool must be listed in its definition's `tools` or in
[Skill](https://jameshwade.github.io/deputy/reference/Skill.md) values,
not loaded from a skill directory. Subagent trusted results are recorded
in the lead's run and passed to its `on_result`, with the subagent's
IDs. Graph routes and other tools that compose agents are still
rejected.

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

  Named pairs `result_type = "tool_name"`. Result types must be unique,
  start with a letter or number, and contain only letters, numbers,
  dots, underscores and hyphens. Each tool may produce only one result
  type.

- on_result:

  Optional function called with the `"trusted_result"`
  [AgentEvent](https://jameshwade.github.io/deputy/reference/AgentEvent.md)
  as soon as the trusted tool returns, before the model sees any output.
  Use it to update a Shiny `reactiveValues()` or your own store. If it
  signals an error, the result event is still recorded, a
  `"trusted_result_delivery_failed"` notification is emitted, and the
  model receives a tool error instead of the value.

- exempt_tools:

  Names of local function tools that may write or reach external systems
  but can't produce a trusted result. Listing a tool here is your
  promise; Deputy can't check it. MCP, provider, code-running and
  delegation tools can't be exempted.

- model_receipt:

  If `TRUE`, the model receives a receipt naming the result ID and type
  instead of the value, so it cannot restate the values. Defaults to
  `FALSE`, which sends the model the same value your app gets.

## Value

A `TrustedResults` object. It is read-only; read fields with `$`.

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
