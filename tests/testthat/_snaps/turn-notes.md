# without a notes function, turns are taken as they are

    Code
      agent$add_note(2, NoteText("Checked"))
    Condition
      Error in `agent$add_note()`:
      ! This agent has no `notes` function.
      i Pass `notes` to `$new()`: a function that recognizes your notes.

# add_note() refuses what it could not keep out of the model context

    Code
      agent$add_note(2, ellmer::ContentText("Plain text"))
    Condition
      Error in `agent$add_note()`:
      ! `content` must be ellmer content that the agent's `notes` function recognizes.
    Code
      agent$add_note(2, "Checked")
    Condition
      Error in `agent$add_note()`:
      ! `content` must be ellmer content that the agent's `notes` function recognizes.
    Code
      agent$add_note(2, list())
    Condition
      Error in `agent$add_note()`:
      ! `content` must be ellmer content that the agent's `notes` function recognizes.
    Code
      agent$add_note(3, NoteText("Checked"))
    Condition
      Error in `agent$add_note()`:
      ! `turn` must be the position of a turn in the conversation, between 1 and 2.
    Code
      agent$add_note(1.5, NoteText("Checked"))
    Condition
      Error in `agent$add_note()`:
      ! `turn` must be the position of a turn in the conversation, between 1 and 2.

---

    Code
      Agent$new(create_mock_chat(), notes = "yes")
    Condition
      Error in `initialize()`:
      ! `notes` must be a function or `NULL`.

# get_turns() can leave out shown activity and notes

    Code
      agent$get_turns(activity = NA)
    Condition
      Error in `agent$get_turns()`:
      ! `activity` must be TRUE or FALSE

