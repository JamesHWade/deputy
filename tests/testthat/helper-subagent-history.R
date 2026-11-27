history_disclosure <- function(state = NULL) {
  DelegationDisclosure(
    authorize = function(requester, scope) {
      identical(requester, "viewer") && !isTRUE(state$denied)
    }
  )
}

history_measure_tool <- function(value, counter) {
  ellmer::tool(
    function() {
      counter$calls <- counter$calls + 1L
      ellmer::ContentToolResult(
        value = value,
        extra = list(
          display = list(
            title = "Ran a trusted calculation",
            html = paste0("<div class=\"measure\">", value, "</div>")
          ),
          commons_tag = "A"
        )
      )
    },
    name = "call_measure",
    description = "Run a registered measure.",
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE
    )
  )
}

# A lead with one retained specialist behind `ask_sales`. Pass `NULL` servers
# for a lead that must never call a model.
history_lead <- function(
  root,
  sales,
  counter,
  scope = list(owner_id = "u1"),
  state = NULL,
  value = 60
) {
  offline <- list(url = "http://127.0.0.1:9/v1")
  lead <- Agent$new(
    runtime_chat(root %||% offline),
    delegation_disclosure = history_disclosure(state),
    delegation_scope = scope
  )
  specialist <- Agent$new(
    runtime_chat(sales %||% offline),
    tools = list(history_measure_tool(value, counter)),
    agent_name = "sales"
  )
  handle <- lead$retain_agent(specialist, UsageLimits(max_requests = 8))
  lead$register_tool(delegation_tool(
    lead,
    handle,
    "ask_sales",
    "Ask the sales specialist.",
    UsageLimits(max_requests = 4)
  ))
  lead
}

history_root_server <- function(.local_envir = parent.frame()) {
  local_runtime_server(
    list(
      runtime_reply(tool = "ask_sales", arguments = list(task = "Revenue?")),
      runtime_reply("Lead: revenue is 60.")
    ),
    .local_envir = .local_envir
  )
}

history_sales_server <- function(.local_envir = parent.frame()) {
  local_runtime_server(
    list(
      runtime_reply(tool = "call_measure"),
      runtime_reply("Total revenue is 60.")
    ),
    .local_envir = .local_envir
  )
}

# shinychat's file store, keeping each record as it reads back from disk.
HistoryTestStore <- if (requireNamespace("shinychat", quietly = TRUE)) {
  R6::R6Class(
    "HistoryTestStore",
    inherit = shinychat::ConversationStore,
    public = list(
      inner = NULL,
      saved = list(),
      initialize = function(dir) {
        self$inner <- shinychat::FileConversationStore$new(dir)
      },
      list = function(partition) self$inner$list(partition),
      get = function(partition, id) self$inner$get(partition, id),
      put = function(partition, record) {
        self$inner$put(partition, record)
        self$saved[[record$id]] <- self$inner$get(partition, record$id)
        invisible(NULL)
      },
      delete = function(partition, id) self$inner$delete(partition, id)
    )
  )
}

history_wait <- function(session, done, timeout = 60) {
  wait_until(
    done,
    timeout = timeout,
    label = "the chat",
    interval = 0.02,
    step = function() session$flushReact()
  )
}

history_submit <- function(session, chat, store, text) {
  before <- shiny::isolate(chat$history$conversation_id())
  count <- if (is.null(before)) 0L else store$saved[[before]]$response_count
  session$setInputs(chat_user_input = text)
  history_wait(session, function() {
    id <- shiny::isolate(chat$history$conversation_id())
    !is.null(id) &&
      (store$saved[[id]]$response_count %||% 0L) > count &&
      identical(shiny::isolate(chat$status()), "idle")
  })
  shiny::isolate(chat$history$conversation_id())
}

# Run `body(session, chat, saver)` in a Shiny session whose chat runs `lead`
# with history kept in `store`.
history_session <- function(lead, store, body, panel = FALSE) {
  skip_if_not_installed("shiny")
  skip_if_not_installed("shinychat", "0.5.0")
  skip_if_not_installed("bslib")
  skip_if_not_installed("commonmark")
  skip_if_not_installed("xml2")
  shiny::testServer(
    function(input, output, session) {
      chat <- shinychat::chat_server(
        "chat",
        lead,
        history = shinychat::history_options(
          restore_mode = "none",
          store = store,
          scope = "test",
          title = NULL
        )
      )
      subagent_chat_activity(chat, lead, function() "viewer")
      saver <- subagent_chat_history(chat, lead, function() "viewer")
      session$userData$chat <- chat
      session$userData$saver <- saver
      if (panel) {
        session$userData$panel <- subagent_chat_server(
          "panel",
          lead,
          function() "viewer",
          conversation = saver,
          poll_interval = 100L
        )
      }
    },
    {
      session$flushReact()
      body(session, session$userData$chat, session$userData$saver)
    }
  )
}

history_results <- function(turns) {
  contents <- unlist(lapply(turns, function(turn) turn@contents))
  Filter(function(x) inherits(x, "ellmer::ContentToolResult"), contents)
}

history_state <- function(lead, conversation_id, requester = "viewer") {
  chat <- new.env()
  chat$client <- lead
  chat$history <- new.env()
  chat$history$conversation_id <- function() conversation_id
  state <- new.env()
  state$chat <- chat
  state$lead <- lead
  state$requester <- function() requester
  state$max_bytes <- 16 * 1024^2
  state$conversation_id <- NULL
  state$record <- NULL
  state$envelope <- NULL
  state$kept <- NULL
  state$error <- NULL
  state
}

# A settled delegation started while `lead` answered in `conversation_id`.
history_settled_lead <- function(
  conversation_id,
  counter,
  .local_envir = parent.frame()
) {
  lead <- history_lead(
    history_root_server(.local_envir),
    history_sales_server(.local_envir),
    counter
  )
  lead$conversation_id <- conversation_id
  lead$run_sync("Revenue?")
  lead
}
