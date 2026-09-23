# Deterministic wire responses for real ellmer producers, including failed
# HTTP requests. A separate event loop serves both sync and async clients.
#
# Each test worker lazily starts one server process and shares it across
# fixtures. Every fixture registers its own responses, counter and request log
# under a unique URL prefix, so fixtures are isolated as if each had its own
# process. Requests to an unknown or released prefix get a 404 error.
local_runtime_server <- function(responses, .local_envir = parent.frame()) {
  skip_if_not_installed("httpuv")
  skip_if_not_installed("jsonlite")
  directory <- withr::local_tempdir(.local_envir = .local_envir)
  fixture <- local_fixture_registration(
    responses = responses,
    directory = directory,
    record = "runtime",
    failure = "Runtime fixture did not start",
    .local_envir = .local_envir
  )
  list(
    url = paste0(fixture$url, "/v1"),
    requests = function() {
      lapply(
        list.files(directory, pattern = "^[0-9]+[.]rds$", full.names = TRUE),
        readRDS
      )
    }
  )
}

# Registers an isolated fixture on the worker's shared server and releases it
# when `.local_envir` exits. The server process itself outlives the fixture.
local_fixture_registration <- function(
  responses,
  directory,
  record,
  failure,
  .local_envir
) {
  for (attempt in 1:2) {
    server <- fixture_server_ensure(failure)
    id <- fixture_server_next_id()
    payload <- serialize(
      list(
        id = id,
        directory = directory,
        responses = responses,
        record = record
      ),
      NULL
    )
    response <- tryCatch(
      fixture_server_control(server, "register", payload),
      error = function(error) error
    )
    if (!inherits(response, "error")) {
      break
    }
    # A transport failure means the shared process is gone or unresponsive:
    # replace it once rather than hanging on a dead server.
    fixture_server_stop(server)
    if (attempt == 2L) {
      cli::cli_abort(failure, parent = response)
    }
  }
  if (httr2::resp_status(response) != 200L) {
    cli::cli_abort(c(
      failure,
      x = httr2::resp_body_string(response)
    ))
  }
  withr::defer(
    fixture_server_release(server, id),
    envir = .local_envir
  )
  list(url = paste0("http://127.0.0.1:", server$port, "/", id))
}

# Worker state lives in an option rather than the helper environment: response
# closures are serialized with their enclosing environments, and the server's
# process handle must not travel with them.
fixture_server_state <- function() {
  state <- getOption("deputy.tests.fixture_server")
  if (is.null(state)) {
    state <- new.env(parent = emptyenv())
    state$next_id <- 0L
    state$server <- NULL
    options(deputy.tests.fixture_server = state)
  }
  state
}

fixture_server_next_id <- function() {
  state <- fixture_server_state()
  state$next_id <- state$next_id + 1L
  sprintf("fixture-%d", state$next_id)
}

fixture_server_ensure <- function(failure) {
  state <- fixture_server_state()
  server <- state$server
  if (!is.null(server) && server$process$is_alive()) {
    return(server)
  }
  directory <- tempfile("deputy-fixture-server-")
  dir.create(directory)
  # Control requests carry serialized R objects, so only this test worker may
  # send them. The token is derived without R's RNG to leave test seeds alone.
  token <- digest::digest(
    list(directory, format(Sys.time(), "%OS6"), Sys.getpid()),
    algo = "sha256"
  )
  process <- callr::r_bg(
    fixture_server_main,
    args = list(directory = directory, token = token),
    supervise = TRUE
  )
  server <- new.env(parent = emptyenv())
  server$process <- process
  server$directory <- directory
  server$token <- token
  state$server <- server
  withr::defer(fixture_server_stop(server), envir = testthat::teardown_env())
  deadline <- Sys.time() + 30
  while (!file.exists(file.path(directory, "ready"))) {
    if (!process$is_alive() || Sys.time() > deadline) {
      fixture_server_stop(server)
      cli::cli_abort(failure)
    }
    Sys.sleep(0.02)
  }
  server$port <- readRDS(file.path(directory, "port.rds"))
  server
}

fixture_server_stop <- function(server) {
  if (!is.null(server$process)) {
    server$process$kill()
  }
  unlink(server$directory, recursive = TRUE)
  state <- fixture_server_state()
  if (identical(state$server, server)) {
    state$server <- NULL
  }
  invisible()
}

fixture_server_release <- function(server, id) {
  if (!server$process$is_alive()) {
    return(invisible())
  }
  tryCatch(
    fixture_server_control(server, "unregister", charToRaw(id)),
    error = function(error) NULL
  )
  invisible()
}

# The control channel shares the server's event loop, so a registration is
# complete before its response returns and before any fixture request is sent.
# Bodies are serialized R objects, preserving response attributes, functions
# and arbitrary JSON text exactly.
fixture_server_control <- function(server, action, payload) {
  withr::with_options(list(httr2_mock = NULL), {
    httr2::request(sprintf(
      "http://127.0.0.1:%d/__control/%s",
      server$port,
      action
    )) |>
      httr2::req_headers(`X-Fixture-Token` = server$token) |>
      httr2::req_body_raw(payload, type = "application/octet-stream") |>
      httr2::req_timeout(30) |>
      httr2::req_error(is_error = function(response) FALSE) |>
      httr2::req_perform()
  })
}

# Runs in the server process. callr resets the function environment, so this
# must be self-contained.
fixture_server_main <- function(directory, token) {
  fixtures <- new.env(parent = emptyenv())
  error_response <- function(status, message) {
    list(
      status = status,
      headers = list("Content-Type" = "application/json"),
      body = as.character(jsonlite::toJSON(
        list(error = list(message = message, type = "fixture_error")),
        auto_unbox = TRUE
      ))
    )
  }
  control <- function(req, action) {
    # Reject before reading or unserializing anything from another process.
    if (!identical(req$HTTP_X_FIXTURE_TOKEN, token)) {
      return(error_response(403L, "Invalid fixture control token"))
    }
    body <- req$rook.input$read()
    if (identical(action, "register")) {
      spec <- tryCatch(unserialize(body), error = function(error) error)
      if (inherits(spec, "error")) {
        return(error_response(400L, conditionMessage(spec)))
      }
      fixture <- new.env(parent = emptyenv())
      fixture$count <- 0L
      fixture$directory <- spec$directory
      fixture$responses <- spec$responses
      fixture$record <- spec$record
      assign(spec$id, fixture, envir = fixtures)
    } else if (identical(action, "unregister")) {
      id <- rawToChar(body)
      if (exists(id, envir = fixtures, inherits = FALSE)) {
        rm(list = id, envir = fixtures)
      }
    } else {
      return(error_response(404L, paste("Unknown fixture control:", action)))
    }
    list(
      status = 200L,
      headers = list("Content-Type" = "text/plain"),
      body = action
    )
  }
  serve <- function(fixture, req, path) {
    fixture$count <- fixture$count + 1L
    count <- fixture$count
    request <- jsonlite::fromJSON(
      rawToChar(req$rook.input$read()),
      simplifyVector = FALSE
    )
    if (identical(fixture$record, "runtime")) {
      entry <- list(body = request, path = path)
      name <- sprintf("%04d.rds", count)
    } else {
      entry <- request
      name <- paste0(count, ".rds")
    }
    # Write then rename so a concurrent reader never sees a partial record.
    partial <- file.path(fixture$directory, paste0(".", name, ".partial"))
    saveRDS(entry, partial)
    file.rename(partial, file.path(fixture$directory, name))
    responses <- fixture$responses
    response <- if (is.function(responses)) {
      responses(request, count)
    } else {
      responses[[min(count, length(responses))]]
    }
    delay <- attr(response, "fixture_delay")
    if (is.null(delay)) {
      response
    } else {
      promises::promise(function(resolve, reject) {
        later::later(function() resolve(response), delay)
      })
    }
  }
  port <- httpuv::randomPort()
  server <- httpuv::startServer(
    "127.0.0.1",
    port,
    list(call = function(req) {
      path <- req$PATH_INFO
      if (startsWith(path, "/__control/")) {
        return(control(req, substring(path, nchar("/__control/") + 1L)))
      }
      parts <- regmatches(path, regexec("^/([^/]+)(/.*)?$", path))[[1L]]
      fixture <- if (length(parts)) {
        get0(parts[[2L]], envir = fixtures, inherits = FALSE)
      }
      if (is.null(fixture)) {
        return(error_response(
          404L,
          paste("No runtime fixture is registered for", path)
        ))
      }
      serve(fixture, req, if (nzchar(parts[[3L]])) parts[[3L]] else "/")
    })
  )
  on.exit(server$stop(), add = TRUE)
  saveRDS(port, file.path(directory, "port.rds"))
  file.create(file.path(directory, "ready"))
  repeat {
    httpuv::service(50)
  }
}

runtime_reply <- function(
  text = "done",
  tool = NULL,
  stream = TRUE,
  finish = "stop",
  arguments = list()
) {
  usage <- list(prompt_tokens = 10, completion_tokens = 5, total_tokens = 15)
  message <- list(role = "assistant", content = text)
  if (!is.null(tool)) {
    message$content <- NULL
    message$tool_calls <- list(list(
      index = 0L,
      id = "call_fixture",
      type = "function",
      `function` = list(
        name = tool,
        arguments = as.character(jsonlite::toJSON(arguments, auto_unbox = TRUE))
      )
    ))
    finish <- "tool_calls"
  }
  if (stream) {
    chunks <- list(
      list(
        id = "fixture",
        model = "gpt-4o-mini",
        choices = list(list(index = 0L, delta = message))
      ),
      list(
        id = "fixture",
        model = "gpt-4o-mini",
        choices = list(list(
          index = 0L,
          delta = list(),
          finish_reason = finish
        )),
        usage = usage
      )
    )
    body <- paste0(
      paste0(
        vapply(
          chunks,
          function(x) {
            paste0(
              "data: ",
              jsonlite::toJSON(x, auto_unbox = TRUE, null = "null"),
              "\n\n"
            )
          },
          character(1)
        ),
        collapse = ""
      ),
      "data: [DONE]\n\n"
    )
  } else {
    body <- jsonlite::toJSON(
      list(
        id = "fixture",
        model = "gpt-4o-mini",
        choices = list(list(
          index = 0L,
          message = message,
          finish_reason = finish
        )),
        usage = usage
      ),
      auto_unbox = TRUE,
      null = "null"
    )
  }
  list(
    status = 200L,
    headers = list(
      "Content-Type" = if (stream) "text/event-stream" else "application/json"
    ),
    body = body
  )
}

runtime_failure <- function(status = 503L) {
  list(
    status = status,
    headers = list("Content-Type" = "application/json", "Retry-After" = "0"),
    body = '{"error":{"message":"fixture unavailable","type":"server_error"}}'
  )
}

runtime_chat <- function(server, model = "gpt-4o-mini", ...) {
  ellmer::chat_openai_compatible(
    base_url = server$url,
    credentials = function() "fixture",
    model = model,
    echo = "none",
    ...
  )
}

runtime_events <- function(agent, type) {
  Filter(function(event) identical(event$type, type), agent$last_run()$events)
}
