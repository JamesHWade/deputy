# Agent SDK compatibility client

Agent SDK compatibility client

Agent SDK compatibility client

## Details

`AgentSDKClient` is an additive alias for ClaudeSDKClient.

## Public fields

- `options`:

  Stored
  [`claude_sdk_options()`](https://jameshwade.github.io/deputy/reference/claude_sdk_options.md)
  used to configure the client

- `agent`:

  The underlying Deputy agent instance

## Methods

### Public methods

- [`ClaudeSDKClient$new()`](#method-ClaudeSDKClient-new)

- [`ClaudeSDKClient$query()`](#method-ClaudeSDKClient-query)

- [`ClaudeSDKClient$list_sessions()`](#method-ClaudeSDKClient-list_sessions)

- [`ClaudeSDKClient$resume()`](#method-ClaudeSDKClient-resume)

- [`ClaudeSDKClient$clone()`](#method-ClaudeSDKClient-clone)

------------------------------------------------------------------------

### Method `new()`

Create a new compatibility client.

#### Usage

    ClaudeSDKClient$new(options = claude_sdk_options())

#### Arguments

- `options`:

  Claude SDK compatibility options

------------------------------------------------------------------------

### Method `query()`

Run a prompt through the compatibility client.

#### Usage

    ClaudeSDKClient$query(prompt, output_format = NULL)

#### Arguments

- `prompt`:

  User prompt to send

- `output_format`:

  Optional structured output format passed to deputy

#### Returns

An
[AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md)

------------------------------------------------------------------------

### Method `list_sessions()`

List persisted compatibility sessions.

#### Usage

    ClaudeSDKClient$list_sessions()

#### Returns

Data frame describing stored sessions

------------------------------------------------------------------------

### Method `resume()`

Resume or fork a persisted compatibility session.

#### Usage

    ClaudeSDKClient$resume(session_id, at = NULL, fork = FALSE)

#### Arguments

- `session_id`:

  Session identifier to restore

- `at`:

  Optional timestamp to restore at or before

- `fork`:

  If TRUE, restore into a new session id

#### Returns

Invisible self

------------------------------------------------------------------------

### Method `clone()`

The objects of this class are cloneable with this method.

#### Usage

    ClaudeSDKClient$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.

## Super class

`deputy::ClaudeSDKClient` -\> `AgentSDKClient`

## Methods

### Public methods

- [`AgentSDKClient$clone()`](#method-AgentSDKClient-clone)

Inherited methods

- [`deputy::ClaudeSDKClient$initialize()`](https://jameshwade.github.io/deputy/reference/ClaudeSDKClient.html#method-initialize)
- [`deputy::ClaudeSDKClient$list_sessions()`](https://jameshwade.github.io/deputy/reference/ClaudeSDKClient.html#method-list_sessions)
- [`deputy::ClaudeSDKClient$query()`](https://jameshwade.github.io/deputy/reference/ClaudeSDKClient.html#method-query)
- [`deputy::ClaudeSDKClient$resume()`](https://jameshwade.github.io/deputy/reference/ClaudeSDKClient.html#method-resume)

------------------------------------------------------------------------

### Method `clone()`

The objects of this class are cloneable with this method.

#### Usage

    AgentSDKClient$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.
