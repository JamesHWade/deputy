# Which subagent call a shown tool card is

[`subagent_chat_activity()`](https://jameshwade.github.io/deputy/reference/subagent_chat_activity.md)
shows each tool call a subagent makes as a pair of cards in the lead's
conversation: a request and its result. Use this function on the
contents of `lead$get_turns()` to tell those cards apart from the lead's
own tool calls, for example to check an answer against what the
subagent's tools returned. Use `lead$get_turns(activity = FALSE)` to
leave the cards out instead.

## Usage

``` r
subagent_activity_info(content)
```

## Arguments

- content:

  An ellmer content object.

## Value

`NULL` unless `content` is a card shown by
[`subagent_chat_activity()`](https://jameshwade.github.io/deputy/reference/subagent_chat_activity.md).
For a card, a list with:

- `activity_id`: the card's ID, which its request and result share.

- `root_tool_call_id`: the ID of the lead's tool call that delegated the
  work, so you can find the delegation the card belongs to.

- `label`, `agent_name`, `agent_id`: which subagent made the call.

- `depth`: 1 for the lead's own subagents, 2 for theirs, and so on.

- `sequence`, `delegation_id`, `parent_delegation_id`, `run_id`: the
  call's position among the cards and the delegation it ran in.

Fields with no value are left out.

## See also

[`subagent_chat_activity()`](https://jameshwade.github.io/deputy/reference/subagent_chat_activity.md)

## Examples

``` r
subagent_activity_info(ellmer::ContentText("Not a card"))
#> NULL
```
