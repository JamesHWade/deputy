create_parallel_chat <- function(state = new.env(parent = emptyenv())) {
  if (is.null(state$started)) {
    state$started <- character()
    state$completed <- character()
    state$active <- 0L
    state$peak <- 0L
    state$inputs <- list()
    state$fail <- character()
  }
  chat <- create_mock_chat()
  chat$get_tokens <- function() {
    count <- sum(vapply(
      chat$get_turns(),
      inherits,
      logical(1),
      what = "ellmer::AssistantTurn"
    ))
    data.frame(
      input = rep(10, count),
      output = rep(5, count),
      cached_input = rep(0, count),
      cost = rep(0.001, count)
    )
  }
  chat$last_turn <- function(role = "assistant") {
    turns <- chat$get_turns()
    if (length(turns) == 0L) {
      return(NULL)
    }
    tail(turns, 1L)[[1L]]
  }
  chat$clone <- function(deep = FALSE) {
    cloned <- create_parallel_chat(state)
    cloned$set_turns(chat$get_turns())
    cloned$set_system_prompt(chat$get_system_prompt())
    cloned$set_tools(chat$get_tools())
    cloned
  }
  chat$stream_async <- function(prompt, stream = "content", controller = NULL) {
    coro::async_generator(function() {
      key <- chat$get_system_prompt()
      state$started <- c(state$started, key)
      state$active <- state$active + 1L
      state$peak <- max(state$peak, state$active)
      state$inputs[[key]] <- list(
        prompt = prompt,
        turns = chat$get_turns(),
        tools = chat$get_tools()
      )
      released <- FALSE
      on.exit(
        {
          if (!released) state$active <- state$active - 1L
        },
        add = TRUE
      )
      coro::await(promises::promise(function(resolve, reject) {
        if (isTRUE(state$hold_a_until_b) && key == "a") {
          state$release_a <- resolve
        } else {
          later::later(function() resolve(NULL))
        }
      }))
      state$active <- state$active - 1L
      released <- TRUE
      if (key == "b" && is.function(state$release_a)) {
        state$release_a(NULL)
        state$release_a <- NULL
      }
      if (key %in% state$fail) {
        stop("deterministic responder failure")
      }
      text <- paste(key, prompt)
      chat$set_turns(list(
        ellmer::UserTurn(list(ellmer::ContentText(prompt))),
        ellmer::AssistantTurn(
          list(ellmer::ContentText(text)),
          tokens = c(10, 5, 0),
          cost = 0.001
        )
      ))
      state$completed <- c(state$completed, key)
      coro::yield(ellmer::ContentText(text))
    })()
  }
  chat
}

parallel_test_lead <- function(state, ...) {
  LeadAgent$new(
    create_parallel_chat(state),
    sub_agents = lapply(c("a", "b", "c"), function(name) {
      agent_definition(name, paste("Responder", name), name)
    }),
    ...
  )
}
