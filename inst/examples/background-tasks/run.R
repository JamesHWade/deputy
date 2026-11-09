# Background tasks: a lead starts two specialists, keeps working while they
# run, collects the first result, follows up with that specialist, cancels the
# other, and answers. A local server stands in for the models, so this needs
# no API key.
#
#   Rscript -e 'source(system.file("examples/background-tasks/run.R", package = "deputy"))'
library(deputy)

directory <- system.file("examples", "background-tasks", package = "deputy")
for (file in c("fixture.R", "workflow.R", "report.R")) {
  source(file.path(directory, file), local = TRUE)
}

fixture <- background_local_fixture()
tryCatch(
  {
    example <- background_example(fixture)
    # Open the subscription before the run to receive its events.
    activity <- example$lead$observe_subagents(example$requester)
    result <- example$lead$run_sync("Report on batch 12.")
    tasks <- background_example_report(example, result, activity)
    background_example_release(example)
  },
  finally = fixture$close()
)
