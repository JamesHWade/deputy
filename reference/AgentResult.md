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

## Methods

### Public methods

- [`AgentResult$new()`](#method-AgentResult-new)

- [`AgentResult$n_turns()`](#method-AgentResult-n_turns)

- [`AgentResult$tool_calls()`](#method-AgentResult-tool_calls)

- [`AgentResult$text_chunks()`](#method-AgentResult-text_chunks)

- [`AgentResult$is_success()`](#method-AgentResult-is_success)

- [`AgentResult$print()`](#method-AgentResult-print)

- [`AgentResult$clone()`](#method-AgentResult-clone)

------------------------------------------------------------------------

### Method `new()`

Create a new AgentResult object.

#### Usage

    AgentResult$new(
      response = NULL,
      turns = list(),
      cost = list(input = 0, output = 0, cached = 0, total = 0),
      events = list(),
      duration = NULL,
      stop_reason = "complete"
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

#### Returns

A new `AgentResult` object

------------------------------------------------------------------------

### Method `n_turns()`

Get the number of turns in the conversation.

#### Usage

    AgentResult$n_turns()

#### Returns

Integer count of turns

------------------------------------------------------------------------

### Method `tool_calls()`

Get all tool calls made during execution.

#### Usage

    AgentResult$tool_calls()

#### Returns

List of tool_start events

------------------------------------------------------------------------

### Method `text_chunks()`

Get all text chunks from the response.

#### Usage

    AgentResult$text_chunks()

#### Returns

Character vector of text chunks

------------------------------------------------------------------------

### Method `is_success()`

Check if the agent completed successfully.

#### Usage

    AgentResult$is_success()

#### Returns

Logical indicating success

------------------------------------------------------------------------

### Method [`print()`](https://rdrr.io/r/base/print.html)

Print the result summary.

#### Usage

    AgentResult$print()

------------------------------------------------------------------------

### Method `clone()`

The objects of this class are cloneable with this method.

#### Usage

    AgentResult$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.
