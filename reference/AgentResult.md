# Agent Result R6 Class

Contains the result of an agent task execution, including the final
response, conversation history, cost information, and all events that
occurred during execution.

## Public fields

- `response`:

  The final text response from the agent

- `turns`:

  List of conversation turns

- `cost`:

  Cost information (list with input, output, cached, total)

- `events`:

  List of all AgentEvent objects from execution

- `duration`:

  Execution duration in seconds

- `stop_reason`:

  Reason the agent stopped

- `structured_output`:

  Parsed/validated structured output (if requested)

- `session_id`:

  Stable session identifier for run correlation

- `run_id`:

  Unique identifier shared by events from this run

- `agent_id`:

  Immutable identifier for the Agent instance

- `agent_name`:

  Optional human-readable Agent name

- `parent_agent_id`:

  Parent Agent identifier for delegated runs

- `parent_run_id`:

  Parent run identifier for delegated runs

- `delegation_id`:

  Delegation identifier for delegated runs

- `usage`:

  Run-scoped
  [AgentUsage](https://jameshwade.github.io/deputy/reference/AgentUsage.md)

## Active bindings

- `run_context`:

  Canonical product context for the run. Read-only.

## Methods

### Public methods

- [`AgentResult$new()`](#method-AgentResult-initialize)

- [`AgentResult$n_turns()`](#method-AgentResult-n_turns)

- [`AgentResult$tool_calls()`](#method-AgentResult-tool_calls)

- [`AgentResult$tool_results()`](#method-AgentResult-tool_results)

- [`AgentResult$text_chunks()`](#method-AgentResult-text_chunks)

- [`AgentResult$is_success()`](#method-AgentResult-is_success)

- [`AgentResult$print()`](#method-AgentResult-print)

- [`AgentResult$clone()`](#method-AgentResult-clone)

------------------------------------------------------------------------

### `AgentResult$new()`

Create a new AgentResult object.

#### Usage

    AgentResult$new(
      response = NULL,
      turns = list(),
      cost = list(input = 0, output = 0, cached = 0, total = 0),
      events = list(),
      duration = NULL,
      stop_reason = "complete",
      structured_output = NULL,
      session_id = NULL,
      run_id = NULL,
      usage = AgentUsage(),
      agent_id = NULL,
      agent_name = NULL,
      parent_agent_id = NULL,
      parent_run_id = NULL,
      delegation_id = NULL,
      run_context = list()
    )

#### Arguments

- `response`:

  Final text response

- `turns`:

  List of conversation turns

- `cost`:

  Cost information

- `events`:

  List of AgentEvent objects

- `duration`:

  Execution duration in seconds

- `stop_reason`:

  Reason for stopping

- `structured_output`:

  Parsed structured output (if any)

- `session_id`:

  Stable session identifier (if any)

- `run_id`:

  Unique run identifier (if any)

- `usage`:

  Run-scoped
  [AgentUsage](https://jameshwade.github.io/deputy/reference/AgentUsage.md)

- `agent_id`:

  Agent instance identifier (if any)

- `agent_name`:

  Optional human-readable Agent name

- `parent_agent_id`:

  Parent Agent identifier for delegated runs

- `parent_run_id`:

  Parent run identifier for delegated runs

- `delegation_id`:

  Delegation identifier for delegated runs

- `run_context`:

  Immutable product context for this run

#### Returns

A new `AgentResult` object

------------------------------------------------------------------------

### `AgentResult$n_turns()`

Get the number of turns in the conversation.

#### Usage

    AgentResult$n_turns()

#### Returns

Integer count of turns

------------------------------------------------------------------------

### `AgentResult$tool_calls()`

Get all tool calls made during execution.

#### Usage

    AgentResult$tool_calls()

#### Returns

List of tool_start events

------------------------------------------------------------------------

### `AgentResult$tool_results()`

Get all completed tool events from execution.

#### Usage

    AgentResult$tool_results()

#### Returns

List of `tool_end` events

------------------------------------------------------------------------

### `AgentResult$text_chunks()`

Get all text chunks from the response.

#### Usage

    AgentResult$text_chunks()

#### Returns

Character vector of text chunks

------------------------------------------------------------------------

### `AgentResult$is_success()`

Check if the agent completed successfully.

#### Usage

    AgentResult$is_success()

#### Returns

Logical indicating success

------------------------------------------------------------------------

### `AgentResult$print()`

Print the result summary.

#### Usage

    AgentResult$print()

------------------------------------------------------------------------

### `AgentResult$clone()`

The objects of this class are cloneable with this method.

#### Usage

    AgentResult$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.
