# Agent SDK compatibility client

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

- [`ClaudeSDKClient$new()`](#method-ClaudeSDKClient-initialize)

- [`ClaudeSDKClient$query()`](#method-ClaudeSDKClient-query)

- [`ClaudeSDKClient$list_sessions()`](#method-ClaudeSDKClient-list_sessions)

- [`ClaudeSDKClient$list_session_summaries()`](#method-ClaudeSDKClient-list_session_summaries)

- [`ClaudeSDKClient$delete_session()`](#method-ClaudeSDKClient-delete_session)

- [`ClaudeSDKClient$get_mcp_status()`](#method-ClaudeSDKClient-get_mcp_status)

- [`ClaudeSDKClient$checkpoint()`](#method-ClaudeSDKClient-checkpoint)

- [`ClaudeSDKClient$list_checkpoints()`](#method-ClaudeSDKClient-list_checkpoints)

- [`ClaudeSDKClient$rewind_files()`](#method-ClaudeSDKClient-rewind_files)

- [`ClaudeSDKClient$resume()`](#method-ClaudeSDKClient-resume)

- [`ClaudeSDKClient$clone()`](#method-ClaudeSDKClient-clone)

------------------------------------------------------------------------

### `ClaudeSDKClient$new()`

Create a new compatibility client.

#### Usage

    ClaudeSDKClient$new(options = claude_sdk_options())

#### Arguments

- `options`:

  Claude SDK compatibility options

------------------------------------------------------------------------

### `ClaudeSDKClient$query()`

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

### `ClaudeSDKClient$list_sessions()`

List persisted compatibility sessions.

#### Usage

    ClaudeSDKClient$list_sessions()

#### Returns

Data frame describing stored sessions

------------------------------------------------------------------------

### `ClaudeSDKClient$list_session_summaries()`

List summaries from an external session store, when configured.

#### Usage

    ClaudeSDKClient$list_session_summaries()

#### Returns

Data frame or character vector supplied by the store adapter

------------------------------------------------------------------------

### `ClaudeSDKClient$delete_session()`

Delete a stored compatibility session.

#### Usage

    ClaudeSDKClient$delete_session(session_id)

#### Arguments

- `session_id`:

  Session identifier to delete

#### Returns

Invisible self

------------------------------------------------------------------------

### `ClaudeSDKClient$get_mcp_status()`

Get MCP runtime status from the underlying agent.

#### Usage

    ClaudeSDKClient$get_mcp_status()

#### Returns

Data frame describing MCP load attempts

------------------------------------------------------------------------

### `ClaudeSDKClient$checkpoint()`

Create a reversible file checkpoint.

#### Usage

    ClaudeSDKClient$checkpoint(name = NULL, metadata = list())

#### Arguments

- `name`:

  Optional checkpoint label.

- `metadata`:

  Optional serializable metadata list.

#### Returns

The checkpoint ID.

------------------------------------------------------------------------

### `ClaudeSDKClient$list_checkpoints()`

List reversible file checkpoints.

#### Usage

    ClaudeSDKClient$list_checkpoints()

#### Returns

A data frame ordered from oldest to newest.

------------------------------------------------------------------------

### `ClaudeSDKClient$rewind_files()`

Rewind files to a checkpoint without rewinding conversation history.

#### Usage

    ClaudeSDKClient$rewind_files(checkpoint_id)

#### Arguments

- `checkpoint_id`:

  A checkpoint ID.

#### Returns

A list describing the restored changes.

------------------------------------------------------------------------

### `ClaudeSDKClient$resume()`

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

### `ClaudeSDKClient$clone()`

The objects of this class are cloneable with this method.

#### Usage

    ClaudeSDKClient$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.

## Super class

`ClaudeSDKClient` -\> `AgentSDKClient`

## Methods

### Public methods

- [`AgentSDKClient$clone()`](#method-AgentSDKClient-clone)

Inherited methods

- [`ClaudeSDKClient$checkpoint()`](https://jameshwade.github.io/deputy/reference/ClaudeSDKClient.html#method-checkpoint)
- [`ClaudeSDKClient$delete_session()`](https://jameshwade.github.io/deputy/reference/ClaudeSDKClient.html#method-delete_session)
- [`ClaudeSDKClient$get_mcp_status()`](https://jameshwade.github.io/deputy/reference/ClaudeSDKClient.html#method-get_mcp_status)
- [`ClaudeSDKClient$initialize()`](https://jameshwade.github.io/deputy/reference/ClaudeSDKClient.html#method-initialize)
- [`ClaudeSDKClient$list_checkpoints()`](https://jameshwade.github.io/deputy/reference/ClaudeSDKClient.html#method-list_checkpoints)
- [`ClaudeSDKClient$list_session_summaries()`](https://jameshwade.github.io/deputy/reference/ClaudeSDKClient.html#method-list_session_summaries)
- [`ClaudeSDKClient$list_sessions()`](https://jameshwade.github.io/deputy/reference/ClaudeSDKClient.html#method-list_sessions)
- [`ClaudeSDKClient$query()`](https://jameshwade.github.io/deputy/reference/ClaudeSDKClient.html#method-query)
- [`ClaudeSDKClient$resume()`](https://jameshwade.github.io/deputy/reference/ClaudeSDKClient.html#method-resume)
- [`ClaudeSDKClient$rewind_files()`](https://jameshwade.github.io/deputy/reference/ClaudeSDKClient.html#method-rewind_files)

------------------------------------------------------------------------

### `AgentSDKClient$clone()`

The objects of this class are cloneable with this method.

#### Usage

    AgentSDKClient$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.
