test_that("activity is split from the model's turns and merged back", {
  request <- ellmer::ContentToolRequest("call_1", "delegate", list())
  marker <- list(
    format = "deputy_subagent_activity",
    version = 1L,
    activity_id = "deputy_activity_abc_1",
    label = "sales"
  )
  shown <- ellmer::ContentToolRequest(
    "deputy_activity_abc_1",
    "call_measure",
    list(),
    extra = list(deputy_activity = marker)
  )
  answer <- ellmer::ContentToolResult(
    "60",
    request = shown,
    extra = list(deputy_activity = marker)
  )
  forged <- ellmer::ContentToolRequest(
    "call_2",
    "call_measure",
    list(),
    extra = list(deputy_activity = marker)
  )
  turns <- list(
    ellmer::UserTurn(list(ellmer::ContentText("Go"))),
    ellmer::AssistantTurn(list(request, shown, answer, forged))
  )
  split <- activity_split(turns)
  expect_length(split$turns[[2L]]@contents, 2L)
  expect_identical(split$turns[[2L]]@contents[[2L]], forged)
  expect_identical(
    lapply(split$overlay, function(entry) entry$turn),
    list(2L, 2L)
  )
  merged <- overlay_merge(split$turns, split$overlay)
  expect_identical(
    merged[[2L]]@contents,
    list(request, forged, shown, answer)
  )
  expect_identical(activity_split(merged)$turns, split$turns)
})

test_that("set_turns keeps shown activity out of the model context", {
  chat <- ellmer::chat_openai(credentials = function() "x", echo = "none")
  agent <- Agent$new(chat)
  marker <- list(
    format = "deputy_subagent_activity",
    version = 1L,
    activity_id = "deputy_activity_abc_1",
    label = "sales"
  )
  shown <- ellmer::ContentToolRequest(
    "deputy_activity_abc_1",
    "call_measure",
    list(),
    extra = list(deputy_activity = marker)
  )
  turns <- list(
    ellmer::UserTurn(list(ellmer::ContentText("Go"))),
    ellmer::AssistantTurn(list(ellmer::ContentText("Done."), shown))
  )
  agent$set_turns(turns)
  expect_length(agent$get_context_turns()[[2L]]@contents, 1L)
  expect_identical(agent$get_turns(), turns)
  expect_identical(agent$usage()$tool_calls, 0L)
  agent$set_turns(list())
  expect_identical(agent$get_turns(), list())
})

test_that("add_turn keeps shown activity out of the model context", {
  chat <- ellmer::chat_openai(credentials = function() "x", echo = "none")
  agent <- Agent$new(chat)
  marker <- list(
    format = "deputy_subagent_activity",
    version = 1L,
    activity_id = "deputy_activity_abc_1",
    label = "sales"
  )
  shown <- ellmer::ContentToolRequest(
    "deputy_activity_abc_1",
    "call_measure",
    list(),
    extra = list(deputy_activity = marker)
  )
  first <- list(
    ellmer::UserTurn(list(ellmer::ContentText("Hi"))),
    ellmer::AssistantTurn(list(ellmer::ContentText("Hello.")))
  )
  agent$set_turns(first)
  user <- ellmer::UserTurn(list(ellmer::ContentText("Go")))
  assistant <- ellmer::AssistantTurn(list(ellmer::ContentText("Done."), shown))
  agent$add_turn(user, assistant, log_tokens = FALSE)
  context <- agent$get_context_turns()
  expect_length(context, 4L)
  expect_length(context[[4L]]@contents, 1L)
  expect_identical(agent$get_turns(), c(first, list(user, assistant)))
  expect_identical(agent$last_turn(), assistant)
  # Content that isn't a turn is refused, as ellmer refuses it, and adds
  # nothing for the model to see.
  expect_error(agent$add_turn(user, list(shown), log_tokens = FALSE))
  expect_identical(agent$get_context_turns(), context)
})

test_that("last_turn() includes the activity shown in it", {
  chat <- ellmer::chat_openai(credentials = function() "x", echo = "none")
  agent <- Agent$new(chat)
  marker <- list(
    format = "deputy_subagent_activity",
    version = 1L,
    activity_id = "deputy_activity_abc_1",
    label = "sales"
  )
  shown <- ellmer::ContentToolRequest(
    "deputy_activity_abc_1",
    "call_measure",
    list(),
    extra = list(deputy_activity = marker)
  )
  turns <- list(
    ellmer::UserTurn(list(ellmer::ContentText("Go"))),
    ellmer::AssistantTurn(list(ellmer::ContentText("Done."), shown))
  )
  agent$set_turns(turns)
  expect_identical(agent$last_turn(), turns[[2L]])
  expect_identical(agent$last_turn("user"), turns[[1L]])
  expect_length(agent$get_context_turns()[[2L]]@contents, 1L)
})

test_that("reinitializing with another Chat drops its old activity", {
  marker <- list(
    format = "deputy_subagent_activity",
    version = 1L,
    activity_id = "deputy_activity_abc_1",
    label = "sales"
  )
  shown <- ellmer::ContentToolRequest(
    "deputy_activity_abc_1",
    "call_measure",
    list(),
    extra = list(deputy_activity = marker)
  )
  answer <- ellmer::ContentToolResult(
    "60",
    request = shown,
    extra = list(deputy_activity = marker)
  )
  old_turns <- list(
    ellmer::UserTurn(list(ellmer::ContentText("Old question"))),
    ellmer::AssistantTurn(list(
      ellmer::ContentText("Old answer"),
      shown,
      answer
    ))
  )
  old_chat <- ellmer::chat_openai(
    credentials = function() "unused",
    echo = "none"
  )
  agent <- Agent$new(old_chat)
  agent$set_turns(old_turns)
  presenter <- activity_enable(agent, function() "viewer")
  presenter$queue <- list(shown)
  private <- agent$.__enclos_env__$private
  private$.activity_leftover <- list(
    run_id = private$current_run_id,
    presenter = presenter,
    queue = list(answer)
  )

  new_turns <- list(
    ellmer::UserTurn(list(ellmer::ContentText("New question"))),
    ellmer::AssistantTurn(list(ellmer::ContentText("New answer")))
  )
  new_chat <- ellmer::chat_openai(
    credentials = function() "unused",
    echo = "none"
  )
  new_chat$set_turns(new_turns)
  agent$initialize(new_chat)

  expect_length(activity_take(agent), 0L)
  expect_identical(agent$get_context_turns(), new_turns)
  expect_identical(agent$get_turns(), new_turns)
  expect_identical(agent$last_turn(), new_turns[[2L]])
  expect_identical(agent$last_turn("user"), new_turns[[1L]])

  path <- withr::local_tempfile(fileext = ".rds")
  suppressMessages(agent$save_session(path))
  session <- readRDS(path)
  expect_null(session$activity)

  loaded <- Agent$new(ellmer::chat_openai(
    credentials = function() "unused",
    echo = "none"
  ))
  suppressMessages(loaded$load_session(path))
  expect_identical(loaded$get_context_turns(), new_turns)
  expect_identical(loaded$get_turns(), new_turns)
  expect_identical(loaded$last_turn(), new_turns[[2L]])
})

test_that("reinitializing with the same Chat keeps its shown activity", {
  marker <- list(
    format = "deputy_subagent_activity",
    version = 1L,
    activity_id = "deputy_activity_abc_1",
    label = "sales"
  )
  shown <- ellmer::ContentToolRequest(
    "deputy_activity_abc_1",
    "call_measure",
    list(),
    extra = list(deputy_activity = marker)
  )
  answer <- ellmer::ContentToolResult(
    "60",
    request = shown,
    extra = list(deputy_activity = marker)
  )
  turns <- list(
    ellmer::UserTurn(list(ellmer::ContentText("Question"))),
    ellmer::AssistantTurn(list(
      ellmer::ContentText("Answer"),
      shown,
      answer
    ))
  )
  chat <- ellmer::chat_openai(
    credentials = function() "unused",
    echo = "none"
  )
  agent <- Agent$new(chat)
  agent$set_turns(turns)
  presenter <- activity_enable(agent, function() "viewer")
  presenter$queue <- list(shown)
  private <- agent$.__enclos_env__$private
  private$.activity_leftover <- list(
    run_id = private$current_run_id,
    presenter = presenter,
    queue = list(answer)
  )
  agent$initialize(chat)

  expect_identical(activity_take(agent), list(answer, shown))
  expect_identical(agent$get_turns(), turns)
  expect_identical(agent$last_turn(), turns[[2L]])
  expect_identical(
    agent$get_context_turns(),
    list(
      ellmer::UserTurn(list(ellmer::ContentText("Question"))),
      ellmer::AssistantTurn(list(ellmer::ContentText("Answer")))
    )
  )
})

test_that("moving to another Chat keeps shown activity on its own turn", {
  marker <- list(
    format = "deputy_subagent_activity",
    version = 1L,
    activity_id = "deputy_activity_abc_1",
    label = "sales"
  )
  shown <- ellmer::ContentToolRequest(
    "deputy_activity_abc_1",
    "call_measure",
    list(),
    extra = list(deputy_activity = marker)
  )
  delegation <- ellmer::ContentToolRequest("call_1", "delegate", list())
  turns <- list(
    ellmer::UserTurn(list(ellmer::ContentText("First"))),
    # A reply stopped while thinking, which another provider can't take.
    ellmer::AssistantTurn(list(ellmer::ContentThinking("stopped thinking"))),
    ellmer::UserTurn(list(ellmer::ContentText("Second"))),
    ellmer::AssistantTurn(list(delegation, shown)),
    ellmer::UserTurn(list(ellmer::ContentToolResult(
      "60",
      request = delegation
    ))),
    ellmer::AssistantTurn(list(ellmer::ContentText("Done.")))
  )
  agent <- Agent$new(ellmer::chat_openai(
    model = "gpt-4o-mini",
    credentials = function() "unused",
    echo = "none"
  ))
  agent$set_turns(turns)
  agent$set_chat(ellmer::chat_anthropic(
    model = "claude-sonnet-4-5",
    credentials = function() "unused",
    echo = "none"
  ))
  moved <- agent$get_turns()
  expect_length(moved, 5L)
  expect_identical(moved[[3L]]@contents, list(delegation, shown))
  expect_identical(moved[[4L]], turns[[5L]])
  expect_identical(agent$get_context_turns()[[3L]]@contents, list(delegation))
})

test_that("concurrent specialists stream attributed activity with unique IDs", {
  skip_if_not_installed("xml2")
  fixture <- activity_concurrent_root()
  root <- fixture$root
  counter <- new.env(parent = emptyenv())
  counter$calls <- 0L
  sales <- activity_specialist("sales", "60", counter = counter)
  ops <- activity_specialist("ops", "7", counter = counter)
  activity_retain(root, sales$agent, "ask_sales")
  activity_retain(root, ops$agent, "ask_ops")
  activity_enable(root, function() "viewer", 0.05)

  seen <- activity_collect(root, "How are sales and ops?")
  expect_identical(counter$calls, 2L)
  items <- activity_items(seen)
  expect_length(items, 4L)
  ids <- unique(activity_ids(items))
  expect_length(ids, 2L)
  rows <- root$list_subagents()
  expect_setequal(
    unique(vapply(
      items,
      function(content) content@extra$deputy_activity$delegation_id,
      character(1)
    )),
    rows$delegation_id
  )
  # Both children reused the provider ID "call_fixture"; none of it shows, and
  # IDs are opaque rather than built from delegation IDs.
  expect_false(any(grepl("call_fixture|delegation", ids)))
  labels <- vapply(
    items,
    function(content) content@extra$deputy_activity$label,
    character(1)
  )
  expect_setequal(unique(labels), c("sales", "ops"))

  # Every card arrives before the lead's own delegation results.
  positions <- which(vapply(seen, is_activity_content, logical(1)))
  lead_results <- which(vapply(
    seen,
    function(content) {
      inherits(content, "ellmer::ContentToolResult") &&
        !is_activity_content(content)
    },
    logical(1)
  ))
  expect_lt(max(positions), min(lead_results))

  result <- Filter(function(x) inherits(x, "ellmer::ContentToolResult"), items)
  marker <- result[[1L]]@extra$deputy_activity
  record <- rows[rows$delegation_id == marker$delegation_id, ]
  expect_identical(marker$agent_id, record$agent_id)
  expect_identical(marker$run_id, record$run_id)
  expect_identical(marker$conversation_id, record$session_id)
  expect_identical(marker$root_tool_call_id, record$tool_call_id)
  expect_identical(result[[1L]]@extra$commons_tag, "A")
  expect_identical(
    result[[1L]]@extra$display$title,
    subagent_display_contain("Ran a trusted calculation", "title")
  )
  expect_match(
    result[[1L]]@extra$display$html,
    "<div class=\"measure\"><strong>",
    fixed = TRUE
  )
  expect_null(result[[1L]]@extra$provider_private)
  expect_identical(result[[1L]]@extra$display$label, marker$label)

  turns <- root$get_turns()
  context <- root$get_context_turns()
  expect_length(turns, length(context))
  expect_length(turns[[2L]]@contents, 6L)
  expect_length(context[[2L]]@contents, 2L)
  sent <- paste(
    vapply(
      fixture$server$requests(),
      function(request) paste(deparse(request), collapse = ""),
      character(1)
    ),
    collapse = ""
  )
  expect_no_match(sent, "deputy_activity", fixed = TRUE)
  expect_identical(root$usage()$tool_calls, 2L)
})

test_that("repeated names are numbered and restored turns keep their activity", {
  root_server <- local_runtime_server(list(
    runtime_reply(tool = "ask_sales", arguments = list(task = "First")),
    runtime_reply("First answer."),
    runtime_reply(tool = "ask_sales", arguments = list(task = "Second")),
    runtime_reply("Second answer.")
  ))
  root <- Agent$new(
    runtime_chat(root_server),
    delegation_disclosure = activity_disclosure()
  )
  sales <- activity_specialist(
    "sales",
    "60",
    responses = list(
      runtime_reply(tool = "call_measure"),
      runtime_reply("first"),
      runtime_reply(tool = "call_measure"),
      runtime_reply("second")
    )
  )
  activity_retain(root, sales$agent, "ask_sales")
  activity_enable(root, function() "viewer", 0.05)
  first <- activity_items(activity_collect(root, "One"))
  second <- activity_items(activity_collect(root, "Two"))
  label <- function(items) {
    unique(vapply(
      items,
      function(content) content@extra$deputy_activity$label,
      character(1)
    ))
  }
  expect_identical(label(first), "sales")
  expect_identical(label(second), "sales #2")
  expect_length(intersect(activity_ids(first), activity_ids(second)), 0L)

  turns <- root$get_turns()
  shown <- vapply(
    turns,
    function(turn) sum(vapply(turn@contents, is_activity_content, logical(1))),
    integer(1)
  )
  expect_identical(shown, c(0L, 2L, 0L, 0L, 0L, 2L, 0L, 0L))

  # shinychat records turns with ellmer and replays them into the client.
  recorded <- lapply(turns, ellmer::contents_record)
  restored <- lapply(recorded, ellmer::contents_replay, tools = list())
  root$set_turns(restored)
  expect_length(root$get_context_turns()[[2L]]@contents, 1L)
  expect_identical(
    activity_ids(activity_items(unlist(
      lapply(root$get_turns(), function(turn) turn@contents),
      recursive = FALSE
    ))),
    activity_ids(c(first, second))
  )
})

test_that("a failed subagent's completed calls stay settled", {
  fixture <- activity_concurrent_root()
  root <- fixture$root
  sales <- activity_specialist("sales", "60")
  ops <- activity_specialist(
    "ops",
    "7",
    responses = list(runtime_reply(tool = "call_measure"), runtime_failure())
  )
  activity_retain(root, sales$agent, "ask_sales")
  activity_retain(root, ops$agent, "ask_ops")
  activity_enable(root, function() "viewer", 0.05)
  withr::local_options(ellmer_max_tries = 1)
  seen <- suppressWarnings(activity_collect(root, "Report."))
  items <- activity_items(seen)
  results <- Filter(function(x) inherits(x, "ellmer::ContentToolResult"), items)
  expect_length(results, 2L)
  expect_true(all(vapply(results, function(x) is.null(x@error), logical(1))))
  expect_setequal(root$list_subagents()$status, c("completed", "failed"))
})

test_that("calls without results are closed when their delegation settles", {
  fixture <- activity_concurrent_root()
  root <- fixture$root
  sales <- activity_specialist("sales", "60")
  ops <- activity_specialist("ops", "7")
  activity_retain(root, sales$agent, "ask_sales")
  activity_retain(root, ops$agent, "ask_ops")
  root$run_sync("Report.")
  private <- root$.__enclos_env__$private
  id <- names(private$subagent_runs)[[1L]]
  # Drop the tool result turn, as when a child stops before a tool returns.
  turns <- private$subagent_runs[[id]]$turns
  private$subagent_runs[[id]]$turns <- turns[-3L]
  private$subagent_runs[[id]]$stop_reason <- "interrupted"
  private$subagent_runs[[id]]$status <- "stopped"
  activity_enable(root, function() "viewer")
  activity_poll(root, final = TRUE)
  items <- activity_take(root)
  results <- Filter(function(x) inherits(x, "ellmer::ContentToolResult"), items)
  open <- Filter(function(x) !is.null(x@error), results)
  expect_length(open, 1L)
  expect_match(open[[1L]]@error, "Not completed: the subagent stopped")
  expect_match(open[[1L]]@error, "interrupted")
  activity_poll(root, final = TRUE)
  expect_length(activity_take(root), 0L)
})

test_that("a grandchild's calls are attributed through its parent", {
  fixture <- recursive_activity_fixture()
  seen <- activity_collect(fixture$root, "compose")
  items <- activity_items(seen)
  labels <- unique(vapply(
    items,
    function(content) content@extra$deputy_activity$label,
    character(1)
  ))
  expect_identical(labels, c("analyst", "reviewer (via analyst)"))
  markers <- lapply(items, function(content) content@extra$deputy_activity)
  depths <- unique(vapply(markers, function(marker) marker$depth, integer(1)))
  expect_identical(depths, c(1L, 2L))
  rows <- fixture$root$list_subagents()
  expect_identical(
    unique(vapply(markers, function(marker) marker$root_tool_call_id, "")),
    rows$tool_call_id[[1L]]
  )
  reviewer <- Filter(function(marker) identical(marker$depth, 2L), markers)
  expect_identical(
    reviewer[[1L]]$parent_delegation_id,
    rows$delegation_id[[1L]]
  )
  turns <- fixture$root$get_turns()
  expect_identical(
    vapply(turns[[2L]]@contents, is_activity_content, logical(1)),
    c(FALSE, rep(TRUE, length(items)))
  )
  fixture$root$release_agent_graph()
})

test_that("a grandchild names its parent only when its view reports one", {
  fixture <- recursive_activity_fixture(
    redact = function(view, requester) {
      view$outcome$runtime$parent_delegation_id <- NULL
      view$outcome$runtime$depth <- NULL
      view
    }
  )
  items <- activity_items(activity_collect(fixture$root, "compose"))
  markers <- lapply(items, function(content) content@extra$deputy_activity)
  expect_identical(
    unique(vapply(markers, function(marker) marker$label, character(1))),
    c("analyst", "reviewer")
  )
  for (marker in markers) {
    expect_null(marker$parent_delegation_id)
    expect_null(marker$depth)
  }
  # The lead's call is named only along parents the views report: the
  # analyst's own call, and not for the reviewer, whose parent is hidden.
  rows <- fixture$root$list_subagents()
  by_name <- function(name) {
    Filter(function(marker) identical(marker$agent_name, name), markers)
  }
  expect_identical(
    unique(vapply(by_name("analyst"), function(m) m$root_tool_call_id, "")),
    rows$tool_call_id[[1L]]
  )
  reviewer <- by_name("reviewer")
  expect_gt(length(reviewer), 0L)
  for (marker in reviewer) {
    expect_null(marker$root_tool_call_id)
  }
  fixture$root$release_agent_graph()
})

test_that("a subagent's transcript leaves out activity its own chat showed", {
  root_server <- local_runtime_server(list(
    runtime_reply(tool = "ask_sales", arguments = list(task = "Sales?")),
    runtime_reply("Lead done.")
  ))
  root <- Agent$new(
    runtime_chat(root_server),
    delegation_disclosure = activity_disclosure()
  )
  sales <- activity_specialist("sales", "60")
  # Before it is retained, the specialist's own chat showed a card for a
  # subagent of its own.
  marker <- list(
    format = "deputy_subagent_activity",
    version = 1L,
    activity_id = "deputy_activity_abc_1",
    label = "helper"
  )
  shown <- ellmer::ContentToolRequest(
    "deputy_activity_abc_1",
    "call_measure",
    list(),
    extra = list(deputy_activity = marker)
  )
  sales$agent$set_turns(list(
    ellmer::UserTurn(list(ellmer::ContentText("Earlier?"))),
    ellmer::AssistantTurn(list(ellmer::ContentText("Earlier answer."), shown))
  ))
  activity_retain(root, sales$agent, "ask_sales")
  root$run_sync("Sales?")
  views <- root$inspect_subagents("viewer", transcript = TRUE)
  expect_length(views, 1L)
  # The transcript has the calls the specialist's model saw, and no card.
  turns <- lapply(views[[1L]]$transcript, inspection_replay)
  expect_identical(
    activity_test_call_ids(turns),
    activity_test_call_ids(sales$agent$get_context_turns())
  )
})

test_that("a card's tool name is bounded like the rest of it", {
  long <- strrep("n", 100000)
  rename <- function(x) {
    if (!is.list(x)) {
      return(x)
    }
    if (identical(x[["class"]], "ellmer::ContentToolRequest")) {
      x$props$name <- long
    }
    lapply(x, rename)
  }
  fixture <- recursive_activity_fixture(
    redact = function(view, requester) {
      view$transcript <- rename(view$transcript)
      view
    }
  )
  items <- activity_items(activity_collect(fixture$root, "compose"))
  requests <- Filter(
    function(item) inherits(item, "ellmer::ContentToolRequest"),
    items
  )
  expect_gt(length(requests), 0L)
  for (request in requests) {
    expect_lte(nchar(request@name, type = "bytes"), 256L)
  }
  fixture$root$release_agent_graph()
})

test_that("a descendant's new cards read its ancestors' views again", {
  hidden <- new.env(parent = emptyenv())
  hidden$analyst <- FALSE
  fixture <- recursive_activity_fixture(
    redact = function(view, requester) {
      runtime <- view$outcome$runtime
      if (isTRUE(hidden$analyst) && identical(runtime$agent_name, "analyst")) {
        view$outcome$runtime$agent_name <- NULL
        view$outcome$runtime$tool_call_id <- NULL
      }
      view
    }
  )
  root <- fixture$root
  activity_disable(root)
  root$run_sync("compose")
  private <- root$.__enclos_env__$private
  child <- Filter(
    function(id) !is.null(private$subagent_runs[[id]]$parent_delegation_id),
    names(private$subagent_runs)
  )
  record <- private$subagent_runs[[child]]
  # The grandchild has asked for its measure and not yet had the result.
  private$subagent_runs[[child]]$turns <- record$turns[1:2]
  private$subagent_runs[[child]]$completed_at <- as.POSIXct(
    NA_real_,
    tz = "UTC"
  )
  marker <- function(item) item@extra$deputy_activity
  activity_enable(root, function() "viewer")
  activity_poll(root)
  first <- Filter(
    function(item) identical(marker(item)$agent_name, "reviewer"),
    activity_take(root)
  )
  expect_length(first, 1L)
  expect_identical(marker(first[[1L]])$label, "reviewer (via analyst)")
  expect_true(is_nonempty_string(marker(first[[1L]])$root_tool_call_id))
  # The host stops showing the parent's name and the lead's call to the
  # viewer. The parent's record hasn't changed since, but the grandchild's
  # next card shows neither.
  hidden$analyst <- TRUE
  private$subagent_runs[[child]] <- record
  activity_poll(root)
  later <- activity_take(root)
  expect_length(later, 1L)
  expect_identical(marker(later[[1L]])$label, "reviewer (via subagent)")
  expect_null(marker(later[[1L]])$root_tool_call_id)
  expect_no_match(later[[1L]]@extra$display$label %||% "", "analyst")
  activity_disable(root)
  root$release_agent_graph()
})

test_that("each refresh labels its cards from its own redacted view", {
  root_server <- local_runtime_server(list(
    runtime_reply(tool = "ask_sales", arguments = list(task = "Sales?")),
    runtime_reply("Lead done.")
  ))
  hidden <- new.env(parent = emptyenv())
  hidden$name <- FALSE
  root <- Agent$new(
    runtime_chat(root_server),
    delegation_disclosure = activity_disclosure(
      redact = function(view, requester) {
        if (isTRUE(hidden$name)) {
          view$outcome$runtime$agent_name <- NULL
        }
        view
      }
    )
  )
  sales <- activity_specialist(
    "sales",
    "60",
    responses = list(
      runtime_reply(tool = "call_measure"),
      runtime_reply(tool = "call_measure"),
      runtime_reply("sales done")
    )
  )
  activity_retain(root, sales$agent, "ask_sales")
  root$run_sync("Sales?")
  private <- root$.__enclos_env__$private
  id <- names(private$subagent_runs)[[1L]]
  record <- private$subagent_runs[[id]]
  private$subagent_runs[[id]]$turns <- record$turns[1:3]
  private$subagent_runs[[id]]$completed_at <- as.POSIXct(NA_real_, tz = "UTC")
  labels <- function(items) {
    unique(vapply(
      items,
      function(item) item@extra$deputy_activity$label,
      character(1)
    ))
  }
  activity_enable(root, function() "viewer")
  activity_poll(root)
  expect_identical(labels(activity_take(root)), "sales")
  # The host stops showing the subagent's name: its later cards don't
  # show it either.
  hidden$name <- TRUE
  private$subagent_runs[[id]] <- record
  activity_poll(root, final = TRUE)
  later <- activity_take(root)
  expect_length(later, 2L)
  expect_identical(labels(later), "subagent")
  for (item in later) {
    expect_null(item@extra$deputy_activity$agent_name)
    expect_no_match(item@extra$display$label %||% "", "sales")
  }
  activity_disable(root)
})

test_that("viewers who may not see subagents get no activity", {
  state <- new.env(parent = emptyenv())
  state$denied <- TRUE
  root_server <- local_runtime_server(list(
    runtime_reply(tool = "ask_sales", arguments = list(task = "Sales?")),
    runtime_reply("Lead done.")
  ))
  root <- Agent$new(
    runtime_chat(root_server),
    delegation_disclosure = activity_disclosure(state)
  )
  sales <- activity_specialist("sales", "60")
  activity_retain(root, sales$agent, "ask_sales")
  activity_enable(root, function() "viewer", 0.05)
  seen <- activity_collect(root, "Sales?")
  expect_length(activity_items(seen), 0L)
  expect_match(
    root$.__enclos_env__$private$.activity$error,
    "not authorized"
  )
  expect_identical(root$last_run()$stop_reason, "complete")

  root_server <- local_runtime_server(list(
    runtime_reply(tool = "ask_sales", arguments = list(task = "Sales?")),
    runtime_reply("Lead done.")
  ))
  root <- Agent$new(
    runtime_chat(root_server),
    delegation_disclosure = activity_disclosure(
      redact = function(view, requester) {
        view$transcript <- NULL
        view
      }
    )
  )
  sales <- activity_specialist("sales", "60")
  activity_retain(root, sales$agent, "ask_sales")
  activity_enable(root, function() "viewer", 0.05)
  expect_length(activity_items(activity_collect(root, "Sales?")), 0L)
})

test_that("activity renders as native shinychat tool cards", {
  skip_if_not_installed("shinychat", "0.5.0")
  skip_if_not_installed("xml2")
  root_server <- local_runtime_server(list(
    runtime_reply(tool = "ask_sales", arguments = list(task = "Sales?")),
    runtime_reply("Lead done.")
  ))
  root <- Agent$new(
    runtime_chat(root_server),
    delegation_disclosure = activity_disclosure()
  )
  sales <- activity_specialist("sales", "60")
  activity_retain(root, sales$agent, "ask_sales")
  activity_enable(root, function() "viewer", 0.05)
  items <- activity_items(activity_collect(root, "Sales?"))
  request <- shinychat::contents_shinychat(items[[1L]])
  result <- shinychat::contents_shinychat(items[[2L]])
  expect_s3_class(request, "shinychat_tool_request")
  expect_s3_class(result, "shinychat_tool_result")
  expect_identical(request$request_id, items[[1L]]@id)
  expect_identical(result$request_id, items[[1L]]@id)
  expect_identical(request$tool_name, "call_measure")
  expect_identical(
    result$title,
    subagent_display_contain("Ran a trusted calculation", "title")
  )
  expect_identical(result$label, "sales")
  expect_identical(result$status, "success")
  expect_identical(result$value_type, "html")
  expect_identical(
    result$value,
    subagent_display_contain(
      "<div class=\"measure\"><strong>60</strong></div>",
      "html"
    )
  )
})

test_that("activity shows only what the host's redaction leaves", {
  root_server <- local_runtime_server(list(
    runtime_tool_calls_reply(list(
      list(id = "call_a", name = "ask_sales", arguments = list(task = "S?")),
      list(id = "call_b", name = "ask_ops", arguments = list(task = "O?"))
    )),
    runtime_reply("Lead done.")
  ))
  root <- Agent$new(
    runtime_chat(root_server),
    delegation_disclosure = activity_disclosure(
      redact = function(view, requester) {
        view$outcome$runtime$agent_name <- "specialist"
        view$outcome$runtime$agent_id <- NULL
        view$outcome$runtime$run_id <- NULL
        view$outcome$runtime$session_id <- NULL
        view$outcome$runtime$tool_call_id <- NULL
        view
      }
    )
  )
  sales <- activity_specialist("sales", "60")
  ops <- activity_specialist("ops", "7")
  activity_retain(root, sales$agent, "ask_sales")
  activity_retain(root, ops$agent, "ask_ops")
  activity_enable(root, function() "viewer", 0.05)
  items <- activity_items(activity_collect(root, "Both?"))
  expect_length(items, 4L)
  markers <- lapply(items, function(content) content@extra$deputy_activity)
  expect_setequal(
    unique(vapply(markers, function(marker) marker$label, "")),
    c("specialist", "specialist #2")
  )
  expect_identical(
    unique(vapply(markers, function(marker) marker$agent_name, "")),
    "specialist"
  )
  for (marker in markers) {
    expect_null(marker$agent_id)
    expect_null(marker$run_id)
    expect_null(marker$conversation_id)
    expect_null(marker$root_tool_call_id)
  }
  shown <- paste(deparse(items), collapse = "")
  for (name in c("sales", "ops", sales$agent$agent_id, ops$agent$agent_id)) {
    expect_false(grepl(name, shown, fixed = TRUE))
  }
})

test_that("a view over the disclosure bound shows one note instead", {
  root_server <- local_runtime_server(list(
    runtime_reply(tool = "ask_sales", arguments = list(task = "Sales?")),
    runtime_reply("Lead done.")
  ))
  root <- Agent$new(
    runtime_chat(root_server),
    delegation_disclosure = DelegationDisclosure(
      authorize = function(requester, scope) identical(requester, "viewer"),
      max_bytes = 2048
    )
  )
  sales <- activity_specialist("sales", "60")
  activity_retain(root, sales$agent, "ask_sales")
  activity_enable(root, function() "viewer", 0.05)
  items <- activity_items(activity_collect(root, "Sales?"))
  expect_length(items, 2L)
  expect_identical(items[[1L]]@name, "more_subagent_tool_calls")
  expect_match(items[[1L]]@id, "_oversized$")
  expect_match(items[[2L]]@value, "over the size the viewer may see")
})

test_that("notes for oversized views count toward the reply's limit", {
  local_mocked_bindings(activity_max_calls = 1L)
  root <- activity_concurrent_root()$root
  root$.__enclos_env__$private$.delegation_disclosure <- DelegationDisclosure(
    authorize = function(requester, scope) identical(requester, "viewer"),
    max_bytes = 2048
  )
  activity_retain(root, activity_specialist("sales", "60")$agent, "ask_sales")
  activity_retain(root, activity_specialist("ops", "7")$agent, "ask_ops")
  activity_enable(root, function() "viewer", 0.05)
  items <- activity_items(activity_collect(root, "Report."))
  ids <- vapply(
    Filter(function(item) inherits(item, "ellmer::ContentToolRequest"), items),
    function(item) item@id,
    character(1)
  )
  expect_length(ids, 2L)
  expect_identical(sum(endsWith(ids, "_oversized")), 1L)
  expect_identical(sum(endsWith(ids, "_limit")), 1L)
})

test_that("calls shown before a view grows too large still get a result", {
  root_server <- local_runtime_server(list(
    runtime_reply(tool = "ask_sales", arguments = list(task = "Sales?")),
    runtime_reply("Lead done.")
  ))
  root <- Agent$new(
    runtime_chat(root_server),
    delegation_disclosure = activity_disclosure()
  )
  sales <- activity_specialist("sales", "60")
  activity_retain(root, sales$agent, "ask_sales")
  root$run_sync("Sales?")
  private <- root$.__enclos_env__$private
  id <- names(private$subagent_runs)[[1L]]
  record <- private$subagent_runs[[id]]
  # The first poll sees the call running.
  private$subagent_runs[[id]]$turns <- record$turns[-3L]
  private$subagent_runs[[id]]$completed_at <- as.POSIXct(NA_real_, tz = "UTC")
  activity_enable(root, function() "viewer")
  activity_poll(root)
  shown <- activity_take(root)
  expect_length(shown, 1L)
  expect_s3_class(shown[[1L]], "ellmer::ContentToolRequest")
  # Then the record grows past what the viewer may see.
  private$subagent_runs[[id]] <- record
  private$.delegation_disclosure <- DelegationDisclosure(
    authorize = function(requester, scope) identical(requester, "viewer"),
    max_bytes = 2048
  )
  activity_poll(root, final = TRUE)
  items <- activity_take(root)
  results <- Filter(function(x) inherits(x, "ellmer::ContentToolResult"), items)
  expect_length(results, 2L)
  expect_identical(results[[1L]]@request@id, shown[[1L]]@id)
  expect_match(results[[1L]]@value, "grew past the size the viewer may see")
  expect_match(results[[2L]]@request@id, "_oversized$")
  activity_poll(root, closing = TRUE)
  expect_length(activity_take(root), 0L)
})

test_that("a call keeps its card when redaction later hides an earlier one", {
  root_server <- local_runtime_server(list(
    runtime_reply(tool = "ask_sales", arguments = list(task = "Sales?")),
    runtime_reply("Lead done.")
  ))
  hidden <- new.env(parent = emptyenv())
  root <- Agent$new(
    runtime_chat(root_server),
    delegation_disclosure = activity_disclosure(
      redact = function(view, requester) {
        if (is.null(hidden$id)) {
          return(view)
        }
        shows_hidden <- function(record) {
          any(vapply(
            inspection_replay(record)@contents,
            function(content) {
              id <- if (inherits(content, "ellmer::ContentToolResult")) {
                content@request@id
              } else if (inherits(content, "ellmer::ContentToolRequest")) {
                content@id
              }
              identical(id, hidden$id)
            },
            logical(1)
          ))
        }
        view$transcript <- Filter(Negate(shows_hidden), view$transcript)
        view
      }
    )
  )
  sales <- activity_specialist(
    "sales",
    "60",
    responses = list(
      runtime_tool_calls_reply(list(list(
        id = "call_a",
        name = "call_measure"
      ))),
      runtime_tool_calls_reply(list(list(
        id = "call_b",
        name = "call_measure"
      ))),
      runtime_reply("sales result 60")
    )
  )
  activity_retain(root, sales$agent, "ask_sales")
  root$run_sync("Sales?")
  private <- root$.__enclos_env__$private
  id <- names(private$subagent_runs)[[1L]]
  record <- private$subagent_runs[[id]]
  running <- function(turns) {
    private$subagent_runs[[id]]$turns <- turns
    private$subagent_runs[[id]]$completed_at <- as.POSIXct(NA_real_, tz = "UTC")
  }
  activity_enable(root, function() "viewer")
  # The first call runs.
  running(record$turns[1:2])
  activity_poll(root)
  first <- activity_take(root)
  expect_length(first, 1L)
  # The second runs, and the host's redaction now hides the first.
  hidden$id <- "call_a"
  running(record$turns[1:4])
  activity_poll(root)
  second <- activity_take(root)
  expect_length(second, 1L)
  expect_s3_class(second[[1L]], "ellmer::ContentToolRequest")
  expect_false(identical(second[[1L]]@id, first[[1L]]@id))
  # The second call's result goes to its own card, and the first card is
  # closed rather than left running.
  private$subagent_runs[[id]] <- record
  activity_poll(root, final = TRUE)
  results <- activity_take(root)
  expect_length(results, 2L)
  names(results) <- vapply(results, function(result) result@request@id, "")
  expect_setequal(names(results), c(first[[1L]]@id, second[[1L]]@id))
  expect_identical(results[[second[[1L]]@id]]@value, "60")
  expect_match(
    results[[first[[1L]]@id]]@value,
    "no longer shows this call",
    fixed = TRUE
  )
  activity_poll(root, closing = TRUE)
  expect_length(activity_take(root), 0L)
})

test_that("identical reused calls keep their own cards under redaction", {
  # Two calls with the same provider ID, tool and arguments, returning
  # different values or the same one, with or without a redaction that hides
  # the first once it has finished: the second call's result goes to its own
  # card.
  cases <- list(
    list(values = c("60", "61"), hide = TRUE),
    list(values = c("60", "60"), hide = TRUE),
    list(values = c("60", "61"), hide = FALSE),
    list(values = c("60", "60"), hide = FALSE)
  )
  for (case in cases) {
    root_server <- local_runtime_server(list(
      runtime_reply(tool = "ask_sales", arguments = list(task = "Sales?")),
      runtime_reply("Lead done.")
    ))
    hidden <- new.env(parent = emptyenv())
    hidden$first <- FALSE
    root <- Agent$new(
      runtime_chat(root_server),
      delegation_disclosure = activity_disclosure(
        redact = function(view, requester) {
          if (isTRUE(hidden$first)) {
            view$transcript <- view$transcript[-(2:3)]
          }
          view
        }
      )
    )
    values <- case$values
    counter <- new.env()
    counter$calls <- 0L
    measure <- ellmer::tool(
      function() {
        counter$calls <- counter$calls + 1L
        values[[counter$calls]]
      },
      name = "call_measure",
      description = "Run a registered measure.",
      annotations = ellmer::tool_annotations(
        read_only_hint = TRUE,
        open_world_hint = FALSE
      )
    )
    server <- local_runtime_server(list(
      runtime_tool_calls_reply(list(list(
        id = "call_same",
        name = "call_measure"
      ))),
      runtime_tool_calls_reply(list(list(
        id = "call_same",
        name = "call_measure"
      ))),
      runtime_reply("sales done")
    ))
    sales <- Agent$new(
      runtime_chat(server),
      tools = list(measure),
      agent_name = "sales"
    )
    activity_retain(root, sales, "ask_sales")
    root$run_sync("Sales?")
    private <- root$.__enclos_env__$private
    id <- names(private$subagent_runs)[[1L]]
    record <- private$subagent_runs[[id]]
    running <- function(turns) {
      private$subagent_runs[[id]]$turns <- turns
      private$subagent_runs[[id]]$completed_at <- as.POSIXct(
        NA_real_,
        tz = "UTC"
      )
    }
    activity_enable(root, function() "viewer")
    running(record$turns[1:2])
    activity_poll(root)
    first <- activity_take(root)
    running(record$turns[1:3])
    activity_poll(root)
    expect_identical(activity_take(root)[[1L]]@value, "60")
    # The second, identical call runs: it gets a card of its own.
    hidden$first <- case$hide
    running(record$turns[1:4])
    activity_poll(root)
    second <- activity_take(root)
    expect_length(second, 1L)
    expect_s3_class(second[[1L]], "ellmer::ContentToolRequest")
    expect_false(identical(second[[1L]]@id, first[[1L]]@id))
    private$subagent_runs[[id]] <- record
    activity_poll(root, final = TRUE)
    results <- activity_take(root)
    expect_length(results, 1L)
    expect_identical(results[[1L]]@request@id, second[[1L]]@id)
    expect_identical(results[[1L]]@value, values[[2L]])
    activity_disable(root)
  }
})

test_that("a call the redactor shows differently keeps its card", {
  root_server <- local_runtime_server(list(
    runtime_reply(tool = "ask_sales", arguments = list(task = "Sales?")),
    runtime_reply("Lead done.")
  ))
  # Masks requests' arguments, then results too, from a given view on.
  masked <- new.env(parent = emptyenv())
  masked$level <- 0L
  mask <- function(x) {
    if (!is.list(x)) {
      return(x)
    }
    if (identical(x$class, "ellmer::ContentToolRequest")) {
      x$props$arguments <- list(region = "[masked]")
    }
    if (identical(x$class, "ellmer::ContentToolResult") && masked$level > 1L) {
      x$props$value <- "[masked]"
    }
    for (i in seq_along(x)) {
      x[i] <- list(mask(x[[i]]))
    }
    x
  }
  root <- Agent$new(
    runtime_chat(root_server),
    delegation_disclosure = activity_disclosure(
      redact = function(view, requester) {
        if (masked$level > 0L) {
          view$transcript <- mask(view$transcript)
        }
        view
      }
    )
  )
  measure <- ellmer::tool(
    function(region) "60",
    name = "call_measure",
    description = "Run a registered measure.",
    arguments = list(region = ellmer::type_string()),
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE
    )
  )
  server <- local_runtime_server(list(
    runtime_reply(tool = "call_measure", arguments = list(region = "north")),
    runtime_reply("sales done")
  ))
  sales <- Agent$new(
    runtime_chat(server),
    tools = list(measure),
    agent_name = "sales"
  )
  activity_retain(root, sales, "ask_sales")
  root$run_sync("Sales?")
  private <- root$.__enclos_env__$private
  id <- names(private$subagent_runs)[[1L]]
  record <- private$subagent_runs[[id]]
  running <- function(turns) {
    private$subagent_runs[[id]]$turns <- turns
    private$subagent_runs[[id]]$completed_at <- as.POSIXct(NA_real_, tz = "UTC")
  }
  activity_enable(root, function() "viewer")
  running(record$turns[1:2])
  activity_poll(root)
  shown <- activity_take(root)
  expect_length(shown, 1L)
  expect_identical(shown[[1L]]@arguments, list(region = "north"))
  # Finished, with its arguments masked: the result goes to the same card.
  masked$level <- 1L
  running(record$turns[1:3])
  activity_poll(root)
  results <- activity_take(root)
  expect_length(results, 1L)
  expect_s3_class(results[[1L]], "ellmer::ContentToolResult")
  expect_identical(results[[1L]]@request@id, shown[[1L]]@id)
  expect_identical(results[[1L]]@value, "60")
  # Its result masked too, as the subagent settles: nothing new is shown.
  masked$level <- 2L
  private$subagent_runs[[id]] <- record
  activity_poll(root, final = TRUE)
  expect_length(activity_take(root), 0L)
  activity_disable(root)
})
