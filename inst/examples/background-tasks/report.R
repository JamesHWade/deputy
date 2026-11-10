# What a host can see once the lead's run has ended. Everything here is read
# through the lead; reading never starts or resumes work.
background_example_report <- function(example, result, activity) {
  lead <- example$lead
  requester <- example$requester
  heading <- function(text) cat("\n== ", text, " ==\n", sep = "")

  heading("The lead's answer")
  cat(trimws(result$response), "\n", sep = "")

  heading("Tasks while the lead looked up the specification")
  print(example$seen$while_working, row.names = FALSE)

  # One row per task. Task and delegation IDs are random, so the example
  # prints the columns that are the same on every run.
  heading("lead$background_tasks()")
  tasks <- lead$background_tasks()
  shown <- tasks[, c("agent", "state", "collected")]
  shown$follows_row <- match(tasks$previous_task_id, tasks$task_id)
  print(shown)

  heading("lead$list_subagents()")
  print(lead$list_subagents()[, c("agent_name", "task", "status")])

  # The subscription was opened before the run, so it holds every event.
  heading("Tool activity from lead$observe_subagents()")
  for (event in activity$poll()$events) {
    if (event$type %in% c("tool_start", "tool_end")) {
      cat(
        event$agent_name,
        ": ",
        event$data$tool_name,
        if (identical(event$type, "tool_start")) " started" else " finished",
        "\n",
        sep = ""
      )
    }
  }

  # Both of the analyst's tasks are in one conversation. The view of its
  # latest task carries the whole of it.
  heading("The analyst's conversation, from lead$inspect_subagents()")
  latest <- tasks$delegation_id[max(which(tasks$agent == "analyst"))]
  view <- lead$inspect_subagents(requester, latest, transcript = TRUE)[[1L]]
  for (turn in view$turns) {
    for (content in turn@contents) {
      line <- if (S7::S7_inherits(content, ellmer::ContentToolRequest)) {
        paste0("[calls ", content@name, "]")
      } else if (S7::S7_inherits(content, ellmer::ContentToolResult)) {
        paste0("[", content@request@name, " returned] ", content@value)
      } else {
        content@text
      }
      cat(turn@role, ": ", trimws(line), "\n", sep = "")
    }
  }

  heading("Outcomes")
  for (row in seq_len(nrow(tasks))) {
    view <- lead$inspect_subagents(requester, tasks$delegation_id[[row]])[[1L]]
    answer <- trimws(view$outcome$answer)
    cat(
      row,
      " ",
      tasks$agent[[row]],
      " (",
      tasks$state[[row]],
      ", ",
      view$usage$requests,
      " request",
      if (view$usage$requests != 1L) "s",
      "): ",
      if (nzchar(answer)) answer else "no answer",
      "\n",
      sep = ""
    )
  }

  # The run's usage includes every task's.
  heading("Usage of the lead's run")
  cat(
    result$usage$requests,
    " requests, ",
    result$usage$tool_calls,
    " tool calls\n",
    sep = ""
  )
  invisible(tasks)
}
