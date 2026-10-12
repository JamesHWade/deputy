# Get the result of a streamed run

`stream_result()` takes the stream that
[Agent](https://jameshwade.github.io/deputy/reference/Agent.md)`$stream_async()`
returned and gives a promise of that run's
[AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md).
The promise resolves when the run has finished, however it ended: a run
that was stopped, hit a limit or failed resolves too, and its `ending`
says which. Draining the stream is still what makes the run go; a stream
that is never read never resolves. The promise is rejected only when
there is no result to give: the run could not start, as when the agent
was already running, or finishing it failed.

## Usage

``` r
stream_result(stream)
```

## Arguments

- stream:

  A stream returned by `Agent$stream_async()`.

## Value

A promise of an
[AgentResult](https://jameshwade.github.io/deputy/reference/AgentResult.md).

## Examples

``` r
if (FALSE) { # \dontrun{
stream <- agent$stream_async(input$message)
promises::then(stream_result(stream), function(result) {
  if (!S7::S7_inherits(result$ending, RunEndingAnswered)) {
    shiny::showNotification(paste("The run ended early:", result$stop_reason))
  }
})
shinychat::chat_append("chat", stream)
} # }
```
