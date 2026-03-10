# Internal docs/test support helpers

#' Get the current docs execution mode
#'
#' @return One of `"off"`, `"replay"`, or `"record"`
#' @noRd
deputy_docs_mode <- function() {
  mode <- Sys.getenv("DEPUTY_DOCS_MODE", unset = "off")
  if (!mode %in% c("off", "replay", "record")) {
    mode <- "off"
  }
  mode
}

#' Check whether a docs status should execute
#'
#' @param status Docs status string
#' @return Logical
#' @noRd
deputy_docs_should_eval <- function(status) {
  mode <- deputy_docs_mode()

  switch(
    status,
    "verified-replay" = mode %in% c("replay", "record"),
    "verified-vcr" = mode %in% c("replay", "record") &&
      rlang::is_installed("vcr"),
    "illustrative" = FALSE,
    FALSE
  )
}

#' Format a docs status note for articles
#'
#' @param status Docs status string
#' @param detail Optional extra detail appended after the stock message
#' @return Markdown string
#' @noRd
deputy_docs_status_block <- function(status, detail = NULL) {
  text <- switch(
    status,
    "verified-replay" = paste(
      "Verified in pkgdown CI using deterministic replay fixtures.",
      "Swap in a real `ellmer::chat_*()` object for live runs."
    ),
    "verified-vcr" = paste(
      "Verified in pkgdown CI using recorded `vcr` HTTP cassettes.",
      "The visible code path matches the real provider/web workflow."
    ),
    "illustrative" = paste(
      "Illustrative example only.",
      "This page is not executed during pkgdown builds; see automated tests for coverage of the underlying integration."
    ),
    "Docs status is unknown."
  )

  if (!is.null(detail) && nzchar(detail)) {
    text <- paste(text, detail)
  }

  paste0("> **Status:** ", text, "\n")
}

#' Find the repository root for docs helpers
#'
#' @param start Directory to start the search from
#' @return Absolute repository root path
#' @noRd
deputy_docs_find_repo_root <- function(start = getwd()) {
  explicit <- Sys.getenv("DEPUTY_DOCS_ROOT", unset = "")
  if (nzchar(explicit) && file.exists(file.path(explicit, "DESCRIPTION"))) {
    return(normalizePath(explicit, winslash = "/", mustWork = TRUE))
  }

  path <- normalizePath(start, winslash = "/", mustWork = TRUE)

  repeat {
    if (file.exists(file.path(path, "DESCRIPTION"))) {
      return(path)
    }

    parent <- dirname(path)
    if (identical(parent, path)) {
      cli::cli_abort("Could not locate the deputy repository root from {.path {start}}.")
    }
    path <- parent
  }
}

#' Build an absolute path relative to the repository root
#'
#' @param ... Path components
#' @return Absolute path
#' @noRd
deputy_docs_path <- function(...) {
  file.path(deputy_docs_find_repo_root(), ...)
}

#' Configure a vignette or README to use docs helpers
#'
#' @param article Short article identifier
#' @param status Docs status string
#' @param chunk_options Optional list of global knitr chunk options
#' @param seed Random seed used for deterministic examples
#' @return A helper list used inside vignettes and README
#' @noRd
deputy_docs_init <- function(
  article,
  status,
  chunk_options = list(),
  seed = 1L
) {
  default_options <- list(
    collapse = TRUE,
    comment = "#>"
  )

  do.call(
    knitr::opts_chunk$set,
    c(default_options, chunk_options)
  )

  set.seed(seed)

  list(
    article = article,
    mode = deputy_docs_mode(),
    status = status,
    should_eval = deputy_docs_should_eval(status),
    status_block = function(detail = NULL) {
      knitr::asis_output(deputy_docs_status_block(status, detail))
    },
    make_project = function(name = article) {
      deputy_docs_make_project(name)
    },
    step_text = deputy_docs_step_text,
    step_tool = deputy_docs_step_tool,
    create_chat = deputy_docs_create_chat,
    use_vcr = function(name, code) {
      deputy_docs_use_vcr(article, name, code)
    }
  )
}

#' Create a deterministic temporary project for docs examples
#'
#' @param name Project name
#' @return List containing useful fixture paths
#' @noRd
deputy_docs_make_project <- function(name = "docs") {
  path <- file.path(
    tempdir(),
    paste0("deputy-docs-", gsub("[^A-Za-z0-9_-]+", "-", name))
  )

  if (dir.exists(path)) {
    unlink(path, recursive = TRUE, force = TRUE)
  }

  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(path, "R"), showWarnings = FALSE)
  dir.create(file.path(path, "data"), showWarnings = FALSE)
  dir.create(file.path(path, "notes"), showWarnings = FALSE)

  writeLines(
    c(
      "Package: demoPkg",
      "Title: Demo Package",
      "Version: 0.0.1"
    ),
    file.path(path, "DESCRIPTION")
  )

  writeLines(
    c(
      "say_hello <- function(name = \"world\") {",
      "  paste(\"hello\", name)",
      "}"
    ),
    file.path(path, "R", "hello.R")
  )

  writeLines(
    c(
      "# Demo Notes",
      "",
      "- tools_file() reads and writes project files",
      "- tools_data() can inspect CSV inputs"
    ),
    file.path(path, "notes", "intro.md")
  )

  utils::write.csv(
    data.frame(
      name = c("Ada", "Grace", "Linus"),
      team = c("ml", "platform", "infra"),
      score = c(9, 8, 7)
    ),
    file.path(path, "data", "people.csv"),
    row.names = FALSE
  )

  list(
    root = normalizePath(path, winslash = "/"),
    r_file = normalizePath(file.path(path, "R", "hello.R"), winslash = "/"),
    csv = normalizePath(file.path(path, "data", "people.csv"), winslash = "/"),
    notes = normalizePath(file.path(path, "notes", "intro.md"), winslash = "/")
  )
}

#' Create a replay text step for docs chats
#'
#' @param text Assistant text
#' @param chunks Optional stream chunks
#' @return Step descriptor
#' @noRd
deputy_docs_step_text <- function(text, chunks = NULL) {
  list(
    type = "text",
    text = text,
    chunks = chunks %||% text
  )
}

#' Create a replay tool step for docs chats
#'
#' @param text Assistant text
#' @param tool_name Tool name
#' @param tool_args Tool arguments
#' @param result Optional explicit tool result
#' @param error Optional explicit tool error string
#' @param chunks Optional stream chunks
#' @return Step descriptor
#' @noRd
deputy_docs_step_tool <- function(
  text,
  tool_name,
  tool_args = list(),
  result = NULL,
  error = NULL,
  chunks = NULL
) {
  list(
    type = "tool",
    text = text,
    chunks = chunks %||% text,
    tool_name = tool_name,
    tool_args = tool_args,
    result = result,
    error = error
  )
}

#' Wrap code in a named vcr cassette for docs
#'
#' @param article Article identifier
#' @param name Cassette name suffix
#' @param code Code to evaluate inside the cassette
#' @return Result of `code`
#' @noRd
deputy_docs_use_vcr <- function(article, name, code) {
  if (!rlang::is_installed("vcr")) {
    cli::cli_abort("Package {.pkg vcr} is required for verified-vcr docs.")
  }

  root <- deputy_docs_find_repo_root()
  sensitive_data <- list(
    "<openai_api_key>" = Sys.getenv("OPENAI_API_KEY"),
    "<anthropic_api_key>" = Sys.getenv("ANTHROPIC_API_KEY")
  )
  sensitive_data <- sensitive_data[vapply(sensitive_data, nzchar, logical(1))]
  filtered_response_headers <- stats::setNames(
    as.list(c(
      "<set-cookie>",
      "<openai-organization>",
      "<openai-project>",
      "<x-request-id>",
      "<cf-ray>"
    )),
    c(
      "set-cookie",
      "openai-organization",
      "openai-project",
      "x-request-id",
      "cf-ray"
    )
  )
  old <- options(vcr.dir = file.path(root, "vignettes", "_vcr"))
  on.exit(options(old), add = TRUE)
  vcr::vcr_configure(
    dir = file.path(root, "vignettes", "_vcr"),
    filter_sensitive_data = sensitive_data,
    filter_response_headers = filtered_response_headers
  )

  vcr::turn_on()
  on.exit(suppressMessages(vcr::turn_off()), add = TRUE)

  result <- new.env(parent = emptyenv())
  vcr::use_cassette(
    paste(article, name, sep = "-"),
    serialize_with = "yaml",
    {
      result$value <- force(code)
    }
  )

  result$value
}

#' Create a proper S7 AssistantTurn for replay chats
#'
#' @param text Assistant text
#' @param contents Optional content list
#' @param tokens Token vector
#' @param cost Cost scalar
#' @return Assistant turn
#' @noRd
deputy_test_create_mock_assistant_turn <- function(
  text = "Hello!",
  contents = NULL,
  tokens = c(100, 50, 0),
  cost = 0.001
) {
  if (is.null(contents)) {
    contents <- list(ellmer::ContentText(text))
  }

  ellmer::AssistantTurn(
    contents = contents,
    tokens = tokens,
    cost = cost
  )
}

#' Create a proper S7 UserTurn for replay chats
#'
#' @param text User text
#' @return User turn
#' @noRd
deputy_test_create_mock_user_turn <- function(text = "Hello") {
  ellmer::UserTurn(
    contents = list(ellmer::ContentText(text))
  )
}

#' Create a proper ContentToolRequest
#'
#' @param id Request id
#' @param name Tool name
#' @param arguments Tool arguments
#' @param tool Optional tool definition
#' @return Tool request
#' @noRd
deputy_test_create_mock_tool_request <- function(
  id = "call_123",
  name = "test_tool",
  arguments = list(),
  tool = NULL
) {
  ellmer::ContentToolRequest(
    id = id,
    name = name,
    arguments = arguments,
    tool = tool
  )
}

#' Create an AssistantTurn with a tool request
#'
#' @param tool_name Tool name
#' @param tool_args Tool arguments
#' @param text Optional assistant text
#' @param tool Optional tool definition
#' @return Assistant turn containing a tool request
#' @noRd
deputy_test_create_mock_turn_with_tool_request <- function(
  tool_name = "test_tool",
  tool_args = list(),
  text = "",
  tool = NULL
) {
  tool_request <- deputy_test_create_mock_tool_request(
    id = paste0("call_", sample(1000:9999, 1)),
    name = tool_name,
    arguments = tool_args,
    tool = tool
  )

  contents <- list(tool_request)
  if (nchar(text) > 0) {
    contents <- c(list(ellmer::ContentText(text)), contents)
  }

  deputy_test_create_mock_assistant_turn(
    text = text,
    contents = contents
  )
}

#' Create a replay Chat object for docs and tests
#'
#' @param steps Replay steps
#' @param provider_name Provider label
#' @param model Model label
#' @return A mock Chat-compatible object
#' @noRd
deputy_docs_create_chat <- function(
  steps = list(deputy_docs_step_text("Hello!")),
  provider_name = "docs",
  model = "replay"
) {
  state <- new.env(parent = emptyenv())
  state$steps <- steps
  state$index <- 0L
  state$current_step <- NULL
  state$current_turn <- NULL
  state$turns <- list()
  state$tools <- list()
  state$system_prompt <- NULL
  state$tool_request_callback <- NULL
  state$tool_result_callback <- NULL

  execute_current_step <- function(prompt = NULL) {
    if (!is.null(prompt)) {
      state$turns <- c(
        state$turns,
        list(deputy_test_create_mock_user_turn(prompt))
      )
    }

    state$index <- min(state$index + 1L, length(state$steps))
    state$current_step <- state$steps[[state$index]]
    state$current_turn <- NULL

    state$current_step
  }

  current_chunks <- function(step) {
    chunks <- step$chunks %||% step$text %||% ""
    if (length(chunks) == 0) {
      chunks <- ""
    }
    as.list(chunks)
  }

  create_tool_result <- function(request, step) {
    value <- step$result
    error_text <- step$error

    if (is.null(value) && is.null(error_text)) {
      tool <- state$tools[[step$tool_name]]
      if (is.null(tool)) {
        error_text <- paste0("Unknown tool: ", step$tool_name)
      } else {
        execution <- tryCatch(
          list(
            value = do.call(tool, step$tool_args %||% list()),
            error = NULL
          ),
          error = function(e) {
            list(value = NULL, error = conditionMessage(e))
          }
        )
        value <- execution$value
        error_text <- execution$error
      }
    }

    ellmer::ContentToolResult(
      request = request,
      value = value,
      error = error_text
    )
  }

  create_turn <- function(step) {
    if (!is.null(state$current_turn)) {
      return(state$current_turn)
    }

    contents <- list()
    if (!is.null(step$text) && nzchar(step$text)) {
      contents <- c(contents, list(ellmer::ContentText(step$text)))
    }

    if (identical(step$type, "tool")) {
      request <- deputy_test_create_mock_tool_request(
        id = step$id %||% paste0("call_", state$index),
        name = step$tool_name,
        arguments = step$tool_args %||% list(),
        tool = state$tools[[step$tool_name]]
      )

      if (is.function(state$tool_request_callback)) {
        state$tool_request_callback(request)
      }

      if (is.function(state$tool_result_callback)) {
        state$tool_result_callback(create_tool_result(request, step))
      }

      contents <- c(contents, list(request))
    }

    turn <- deputy_test_create_mock_assistant_turn(
      text = step$text %||% "",
      contents = contents,
      tokens = step$tokens %||% c(100, 50, 0),
      cost = step$cost %||% 0.001
    )

    state$current_turn <- turn
    state$turns <- c(state$turns, list(turn))
    turn
  }

  structure(
    list(
      chat = function(prompt = NULL) {
        step <- execute_current_step(prompt)
        step$text %||% ""
      },
      stream = function(prompt = NULL) {
        step <- execute_current_step(prompt)
        chunks <- current_chunks(step)
        idx <- 0L

        function() {
          idx <<- idx + 1L
          if (idx > length(chunks)) {
            return(coro::exhausted())
          }
          chunks[[idx]]
        }
      },
      get_turns = function() state$turns,
      set_turns = function(new_turns) state$turns <- new_turns,
      get_system_prompt = function() state$system_prompt,
      set_system_prompt = function(prompt) state$system_prompt <- prompt,
      get_tools = function() state$tools,
      register_tool = function(tool) {
        state$tools[[tool@name]] <- tool
      },
      register_tools = function(tool_list) {
        for (tool in tool_list) {
          state$tools[[tool@name]] <- tool
        }
      },
      get_tokens = function() {
        data.frame(
          input = c(100),
          output = c(50),
          cached_input = c(0),
          cost = c(0.001)
        )
      },
      get_provider = function() {
        list(name = provider_name, model = model)
      },
      last_turn = function(role = "assistant") {
        if (is.null(state$current_step)) {
          return(NULL)
        }
        create_turn(state$current_step)
      },
      on_tool_request = function(callback) {
        state$tool_request_callback <- callback
      },
      on_tool_result = function(callback) {
        state$tool_result_callback <- callback
      },
      clone = function() {
        deputy_docs_create_chat(
          steps = steps,
          provider_name = provider_name,
          model = model
        )
      }
    ),
    class = "Chat"
  )
}

#' Create the legacy mock Chat used by tests
#'
#' @param responses Character responses
#' @return Mock Chat
#' @noRd
deputy_test_create_mock_chat <- function(responses = list("Hello!")) {
  steps <- lapply(
    responses,
    function(response) deputy_docs_step_text(response)
  )
  deputy_docs_create_chat(steps = steps, provider_name = "mock", model = "test-model")
}
