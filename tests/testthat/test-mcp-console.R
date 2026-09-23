# MCP Console producer tests. The fixture serves the released 0.0.4 `send`
# schema and description over stdio; no network or MCP Console install needed.

console_agent <- function(fixture, ...) {
  Agent$new(chat = create_mock_chat(), working_dir = fixture$workspace, ...)
}

console_bare <- c(DEPUTY_CONSOLE_FIXTURE_BARE = "1")

# expect_match() evaluates its object twice; a Console call must run once.
expect_console <- function(object, ...) {
  force(object)
  expect_match(object, ...)
}

console_pid <- function(fixture) {
  start <- mcp_console_log(fixture, "start ")
  as.integer(sub("^start pid=([0-9]+) .*$", "\\1", start[[length(start)]]))
}

console_pid_alive <- function(pid, wait = 5) {
  until <- Sys.time() + wait
  repeat {
    alive <- isTRUE(tools::pskill(pid, 0L))
    if (!alive || Sys.time() >= until) {
      return(alive)
    }
    Sys.sleep(0.05)
  }
}

console_context <- function(tool) {
  list(tool_annotations = tool@annotations, tool_metadata = tool_metadata(tool))
}

test_that("MCP Console requires an explicit, qualified executable", {
  fixture <- mcp_console_fixture()
  agent <- console_agent(fixture)
  withr::local_envvar(DEPUTY_MCP_CONSOLE_BIN = NA)
  expect_error(
    mcp_console_connection(agent),
    "explicit MCP Console executable",
    class = "deputy_mcp_console"
  )
  expect_error(
    mcp_console_connection(agent, file.path(fixture$workspace, "missing")),
    "not an executable",
    class = "deputy_mcp_console"
  )
  for (version in c("0.0.3", "0.0.5", "unknown")) {
    expect_error(
      mcp_console_connection(
        agent,
        fixture$command,
        env = c(console_bare, DEPUTY_CONSOLE_FIXTURE_VERSION = version)
      ),
      "0.0.4",
      class = "deputy_mcp_console"
    )
  }
  expect_length(mcp_console_log(fixture, "start "), 0L)

  withr::local_envvar(DEPUTY_MCP_CONSOLE_BIN = fixture$command)
  connection <- mcp_console_connection(agent, env = console_bare)
  withr::defer(connection$close())
  execution <- connection$status()$execution
  expect_identical(execution$backend, "mcp-console")
  expect_identical(execution$version, "0.0.4")
  expect_identical(execution$sandbox, "default")
  expect_identical(execution$dependencies, "unavailable")
  expect_identical(execution$workspace, agent$working_dir)
  expect_identical(
    execution$recordings,
    file.path(agent$working_dir, ".agents", "console", "sessions")
  )
  expect_true(endsWith(
    mcp_console_log(fixture, "start "),
    paste0("wd=", normalizePath(fixture$workspace), " args=serve")
  ))
  expect_identical(
    tool_metadata(connection$tools()$send)$source$execution,
    execution
  )
})

test_that("launch arguments cannot widen the Console sandbox", {
  refused <- list(
    "--no-sandbox" = "--no-sandbox",
    "unrestricted" = c("-c", "sandbox.filesystem.kind=unrestricted"),
    "external" = "--config=sandbox.filesystem={kind: external-sandbox}",
    "whole sandbox" = c(
      "--config",
      "sandbox={filesystem: {kind: unrestricted}}"
    ),
    "proxy" = c("-c", "sandbox.proxy.enabled=true"),
    "proxy object" = "-csandbox={proxy: {enabled: true}}",
    "network" = c("-c", "sandbox.network=enabled"),
    "target" = c("-c", "target.transport.kind=ssh"),
    "profile" = c("-c", "extends=:danger"),
    "worker" = c("--worker", "/tmp/worker"),
    "subcommand" = "serve",
    "missing value" = "-c"
  )
  for (args in refused) {
    expect_error(
      validate_mcp_console_args(args),
      class = "deputy_mcp_console"
    )
  }
  expect_error(validate_mcp_console_args("--no-sandbox"), "no-sandbox")
  expect_error(
    validate_mcp_console_args(c("-c", "sandbox.filesystem.kind=unrestricted")),
    "filesystem overrides"
  )
  expect_error(
    validate_mcp_console_args(c("-c", "sandbox.proxy.enabled=true")),
    "proxy"
  )
  allowed <- c(
    "-c",
    "extends=:workspace",
    "--config=extends=':read-only'",
    "-csandbox.network=restricted",
    "--writable-root",
    "/tmp/output",
    "--writable-root=/tmp/cache"
  )
  expect_identical(validate_mcp_console_args(allowed), allowed)

  fixture <- mcp_console_fixture()
  agent <- console_agent(fixture)
  expect_error(
    mcp_console_connection(agent, fixture$command, args = "--no-sandbox"),
    class = "deputy_mcp_console"
  )
  expect_length(mcp_console_log(fixture, "start "), 0L)
  connection <- mcp_console_connection(
    agent,
    fixture$command,
    args = c("-c", "extends=:workspace"),
    env = c(console_bare, DEPUTY_CONSOLE_FIXTURE_BOUNDARY = "workspace")
  )
  withr::defer(connection$close())
  expect_console(
    mcp_console_log(fixture, "start "),
    "args=serve -c extends=:workspace$"
  )
  expect_identical(connection$status()$execution$sandbox, "workspace")
})

test_that("a workspace project configuration needs explicit host opt-in", {
  fixture <- mcp_console_fixture()
  agent <- console_agent(fixture)
  dir.create(
    file.path(fixture$workspace, ".agents", "console"),
    recursive = TRUE
  )
  writeLines(
    "sandbox: {filesystem: {kind: unrestricted}}",
    file.path(fixture$workspace, ".agents", "console", "config.yaml")
  )
  expect_error(
    mcp_console_connection(agent, fixture$command, env = console_bare),
    "project configuration",
    class = "deputy_mcp_console"
  )
  expect_error(
    mcp_console_connection(agent, fixture$command, project_config = NA),
    class = "deputy_mcp_console"
  )
  expect_length(mcp_console_log(fixture, "start "), 0L)
  # Opting in still requires the server to report a restricted boundary.
  expect_error(
    mcp_console_connection(
      agent,
      fixture$command,
      env = c(console_bare, DEPUTY_CONSOLE_FIXTURE_BOUNDARY = "unsandboxed"),
      project_config = TRUE
    ),
    "native sandbox",
    class = "deputy_mcp_console"
  )
  connection <- mcp_console_connection(
    agent,
    fixture$command,
    env = console_bare,
    project_config = TRUE
  )
  withr::defer(connection$close())
  expect_identical(connection$status()$state, "idle")
})

test_that("only an advertised native sandbox with restricted networking is used", {
  for (boundary in c("unsandboxed", "proxy")) {
    fixture <- mcp_console_fixture()
    agent <- console_agent(fixture)
    expect_error(
      mcp_console_connection(
        agent,
        fixture$command,
        env = c(console_bare, DEPUTY_CONSOLE_FIXTURE_BOUNDARY = boundary)
      ),
      "native sandbox with restricted networking",
      class = "deputy_mcp_console"
    )
    expect_false(console_pid_alive(console_pid(fixture)))
    expect_length(mcp_console_log(fixture, "call "), 0L)
  }
  expect_identical(
    mcp_console_sandbox_profile(paste(
      "Workbench.\n\nEvaluated code can read host files, cannot directly",
      "access the network, and can write in the worker's private temporary",
      "directory and to paths explicitly allowed by the launcher."
    )),
    "default"
  )
  expect_error(mcp_console_sandbox_profile("A new security sentence."))
  expect_error(mcp_console_sandbox_profile(paste(
    "Evaluated code has unrestricted filesystem access and cannot directly",
    "access the network."
  )))
})

test_that("dependency preparation needs both host and Agent permission", {
  fixture <- mcp_console_fixture()
  agent <- console_agent(fixture)
  expect_error(
    mcp_console_connection(agent, fixture$command),
    "prepares dependencies outside its sandbox",
    class = "deputy_mcp_console"
  )
  bare <- mcp_console_connection(agent, fixture$command, env = console_bare)
  withr::defer(bare$close())
  expect_false("requirements" %in% names(formals(bare$tools()$send)))
  bare$close()

  calls <- function() length(mcp_console_log(fixture, "call "))
  for (grant in c(FALSE, TRUE)) {
    runner <- NULL
    fixture_chat <- create_shiny_tool_chat(
      "send",
      list(r = "1", requirements = list(r = list("praise"))),
      execute = function(request) {
        mcp_test_await(do.call(runner$get_tools()$send, request@arguments))
      }
    )
    runner <- Agent$new(
      chat = fixture_chat$chat,
      working_dir = fixture$workspace,
      permissions = Permissions(
        bash = TRUE,
        web = TRUE,
        install_packages = grant
      )
    )
    connection <- mcp_console_connection(
      runner,
      fixture$command,
      dependencies = "allow"
    )
    withr::defer(connection$close())
    expect_identical(connection$status()$execution$dependencies, "allow")
    runner$register_tools(connection$tools())
    before <- calls()
    runner$run_sync("Prepare a package.")
    expect_identical(fixture_chat$state$executed, grant)
    expect_equal(calls() - before, as.integer(grant))
    if (!grant) {
      expect_console(
        conditionMessage(fixture_chat$state$rejection),
        "package installation is not allowed"
      )
    } else {
      expect_console(
        tail(mcp_console_log(fixture, "call "), 1L),
        "\"requirements\":{\"r\":[\"praise\"]}",
        fixed = TRUE
      )
    }
    connection$close()
  }

  # A connection that did not allow dependencies refuses them itself, even in
  # full permission mode.
  closed <- mcp_console_connection(agent, fixture$command, env = console_bare)
  withr::defer(closed$close())
  send <- closed$tools()$send
  before <- calls()
  expect_error(
    attr(closed, "deputy_mcp_adapter")$arguments(list(
      r = "1",
      requirements = list(python = list("polars"))
    )),
    "not enabled for this connection",
    class = "deputy_permission_denied"
  )
  expect_identical(calls(), before)

  context <- console_context(send)
  input <- list(r = "1")
  expect_s7_class(
    permissions_check(permissions_readonly(), "send", input, context),
    PermissionResultDeny
  )
  expect_console(
    permissions_check(
      Permissions(mode = "plan", bash = TRUE, web = TRUE),
      "send",
      input,
      context
    )@reason,
    "plan mode"
  )
  expect_console(
    permissions_check(Permissions(web = TRUE), "send", input, context)@reason,
    "shell-class"
  )
  expect_s7_class(
    permissions_check(
      Permissions(bash = TRUE, web = TRUE),
      "send",
      input,
      context
    ),
    PermissionResultAllow
  )
  expect_s7_class(
    permissions_check(
      Permissions(bash = TRUE, web = TRUE),
      "send",
      list(requirements = list(duckdb = list("fts"))),
      context
    ),
    PermissionResultDeny
  )
})

test_that("timeout_ms is capped and long work is polled, not resubmitted", {
  fixture <- mcp_console_fixture()
  agent <- console_agent(fixture)
  connection <- mcp_console_connection(
    agent,
    fixture$command,
    env = console_bare
  )
  withr::defer(connection$close())
  send <- connection$tools()$send
  expect_console(send@description, "caps `timeout_ms` at 2500 ms", fixed = TRUE)
  mcp_test_await(send(r = "1"))
  mcp_test_await(send(r = "1", timeout_ms = 60000))
  mcp_test_await(send(r = "1", timeout_ms = 100))
  timeouts <- sub(
    ".*\"timeout_ms\":([0-9]+).*",
    "\\1",
    mcp_console_log(fixture, "call ")
  )
  expect_identical(timeouts, c("2500", "2500", "100"))

  started <- Sys.time()
  expect_console(
    mcp_test_await(send(r = "work 4"), timeout = 30),
    "[running; poll with an empty send]",
    fixed = TRUE
  )
  expect_lt(as.numeric(difftime(Sys.time(), started, units = "secs")), 3.5)
  expect_console(
    mcp_test_await(send(), timeout = 30),
    "work finished\n[done]",
    fixed = TRUE
  )
  expect_identical(connection$status()$state, "idle")
  expect_console(
    tail(mcp_console_log(fixture, "call "), 1L),
    "\\{\"timeout_ms\":2500\\}$"
  )
})

test_that("interrupt and restart map onto send control", {
  fixture <- mcp_console_fixture()
  agent <- console_agent(fixture)
  connection <- mcp_console_connection(
    agent,
    fixture$command,
    env = console_bare
  )
  withr::defer(connection$close())
  send <- connection$tools()$send
  expect_error(
    send(control = "restart"),
    "restart is a host control",
    class = "deputy_mcp_console"
  )
  expect_length(mcp_console_log(fixture, "call "), 0L)
  expect_error(mcp_console_control(NULL), class = "deputy_mcp_console")

  mcp_test_await(send(r = "deputy_value <- 42"))
  expect_console(
    mcp_test_await(send(r = "work 30"), timeout = 30),
    "running",
    fixed = TRUE
  )
  interrupted <- mcp_test_await(mcp_console_control(connection, "interrupt"))
  expect_console(interrupted, "[idle]", fixed = TRUE)
  expect_console(
    tail(mcp_console_log(fixture, "call "), 1L),
    "\"control\":\"interrupt\"",
    fixed = TRUE
  )
  expect_console(
    mcp_test_await(send(r = "deputy_value")),
    "[1] 42",
    fixed = TRUE
  )

  restarted <- mcp_test_await(mcp_console_control(connection, "restart"))
  expect_console(restarted, "in-memory state lost", fixed = TRUE)
  expect_console(
    mcp_test_await(send(r = "exists('deputy_value')")),
    "[1] FALSE",
    fixed = TRUE
  )
  # The host flag does not leak into later model-facing calls.
  expect_error(send(control = "restart"), class = "deputy_mcp_console")
})

test_that("a restart that outlasts the response window is reported, not hidden", {
  fixture <- mcp_console_fixture()
  agent <- console_agent(fixture)
  connection <- mcp_console_connection(
    agent,
    fixture$command,
    env = c(console_bare, DEPUTY_CONSOLE_FIXTURE_RESTART = "6")
  )
  withr::defer(connection$close())
  send <- connection$tools()$send
  pid <- console_pid(fixture)
  expect_error(
    mcp_test_await(mcp_console_control(connection, "restart"), timeout = 60),
    "did not finish within the client's response window",
    class = "deputy_mcp_console_restart"
  )
  expect_identical(connection$status()$reason, "desynchronized")
  expect_false(console_pid_alive(pid))
  expect_error(send(r = "1"), "closed", class = "deputy_mcp_connection")
})

test_that("two Agents own isolated Console servers", {
  fixture <- mcp_console_fixture()
  agent_a <- console_agent(fixture)
  agent_b <- console_agent(fixture)
  a <- mcp_console_connection(agent_a, fixture$command, env = console_bare)
  withr::defer(a$close())
  b <- mcp_console_connection(agent_b, fixture$command, env = console_bare)
  withr::defer(b$close())
  send_a <- a$tools()$send
  send_b <- b$tools()$send
  mcp_test_await(send_a(r = "deputy_value <- 'alpha'"))
  expect_console(
    mcp_test_await(send_b(r = "exists('deputy_value')")),
    "[1] FALSE",
    fixed = TRUE
  )
  expect_error(
    agent_b$register_tools(a$tools()),
    "different Agent",
    class = "deputy_tool_registration"
  )
  a$close()
  expect_error(send_a(r = "1"), "closed", class = "deputy_mcp_connection")
  expect_console(mcp_test_await(send_b(r = "1 + 1")), "[1] 2", fixed = TRUE)
})

test_that("close asks the server to shut down; cancel stops it", {
  fixture <- mcp_console_fixture()
  agent <- console_agent(fixture)
  connection <- mcp_console_connection(
    agent,
    fixture$command,
    env = console_bare
  )
  send <- connection$tools()$send
  pid <- console_pid(fixture)
  mcp_test_await(send(r = "1"))
  connection$close()
  expect_identical(connection$status()$reason, "closed")
  expect_identical(tail(readLines(fixture$log), 1L), "stdin closed")
  expect_false(console_pid_alive(pid))
  expect_error(send(r = "1"), "closed", class = "deputy_mcp_connection")

  cancelled <- mcp_console_connection(
    agent,
    fixture$command,
    env = console_bare
  )
  pid <- console_pid(fixture)
  cancelled$cancel()
  expect_identical(cancelled$status()$reason, "cancelled")
  expect_false(console_pid_alive(pid))
})

test_that("plot output is native ellmer content within rich-result bounds", {
  fixture <- mcp_console_fixture()
  agent <- console_agent(fixture)
  connection <- mcp_console_connection(
    agent,
    fixture$command,
    env = console_bare
  )
  withr::defer(connection$close())
  result <- mcp_test_await(connection$tools()$send(r = "plot"))
  expect_s3_class(result[[1L]], "ellmer::ContentText")
  expect_s3_class(result[[2L]], "ellmer::ContentImageInline")
  expect_identical(result[[2L]]@type, "image/png")
  policy <- ContextPolicy(
    max_tool_result_images = 0L,
    offload_dir = withr::local_tempdir()
  )
  bounded <- bound_rich_tool_result(
    ellmer::ContentToolResult(value = result),
    "send",
    policy,
    "session",
    "agent"
  )
  expect_false(any(vapply(
    bounded$result@value,
    inherits,
    logical(1),
    "ellmer::ContentImage"
  )))
  expect_console(
    r_session_text(bounded$result),
    "deputy://tool-result/",
    fixed = TRUE
  )
})

test_that("released MCP Console keeps governed state across R, SQL and Python", {
  command <- Sys.getenv("DEPUTY_MCP_CONSOLE_BIN")
  skip_if(
    !nzchar(command),
    "Set DEPUTY_MCP_CONSOLE_BIN to a qualified MCP Console 0.0.4 executable"
  )
  skip_if_mcptools_unqualified()
  skip_on_os("windows")
  running <- "[running; poll with an empty send]"
  # The first cell can prepare the managed environment for minutes; poll it.
  cell <- function(send, ..., patience = 900) {
    output <- character()
    value <- mcp_test_await(send(...), timeout = 60)
    until <- Sys.time() + patience
    repeat {
      text <- if (is.character(value)) {
        paste(value, collapse = "\n")
      } else if (inherits(value, "ellmer::ContentToolResult")) {
        paste("Error:", paste(value@error, collapse = "\n"))
      } else {
        paste(
          vapply(
            Filter(function(x) inherits(x, "ellmer::ContentText"), value),
            function(x) x@text,
            character(1)
          ),
          collapse = "\n"
        )
      }
      output <- c(output, text)
      if (
        !grepl(running, text, fixed = TRUE) &&
          !grepl("[worker starting]", text, fixed = TRUE)
      ) {
        return(paste(output, collapse = "\n"))
      }
      if (Sys.time() > until) {
        stop("MCP Console did not finish the cell in time.")
      }
      value <- mcp_test_await(send(), timeout = 60)
    }
  }
  workspace_a <- withr::local_tempdir("deputy-console-a-")
  workspace_b <- withr::local_tempdir("deputy-console-b-")
  agent_a <- Agent$new(chat = create_mock_chat(), working_dir = workspace_a)
  agent_b <- Agent$new(chat = create_mock_chat(), working_dir = workspace_b)
  a <- mcp_console_connection(agent_a, command, dependencies = "allow")
  withr::defer(a$close())
  b <- mcp_console_connection(agent_b, command, dependencies = "allow")
  withr::defer(b$close())
  expect_identical(a$status()$execution$sandbox, "default")
  send_a <- a$tools()$send
  send_b <- b$tools()$send

  expect_console(
    cell(
      send_a,
      r = "deputy_df <- data.frame(g = c('a', 'b', 'a'), v = c(1, 2, 3)); nrow(deputy_df)"
    ),
    "[1] 3",
    fixed = TRUE
  )
  sql <- cell(
    send_a,
    sql = "SELECT g, SUM(v) AS total FROM deputy_df GROUP BY g ORDER BY g"
  )
  expect_console(sql, "a")
  expect_console(sql, "4")
  expect_console(
    cell(send_a, python = "int(r.deputy_df['v'].sum() * 2)"),
    "12",
    fixed = TRUE
  )
  expect_console(
    cell(send_b, r = "exists('deputy_df')"),
    "[1] FALSE",
    fixed = TRUE
  )

  # Agent permissions deny code without shell capability, and dependency
  # preparation without the package-installation grant.
  for (case in list(
    list(
      input = list(r = "deputy_df$v <- 0"),
      permissions = Permissions(web = TRUE)
    ),
    list(
      input = list(r = "1", requirements = list(r = list("praise"))),
      permissions = Permissions(bash = TRUE, web = TRUE)
    )
  )) {
    governed <- NULL
    chat <- create_shiny_tool_chat(
      "send",
      case$input,
      execute = function(request) {
        mcp_test_await(do.call(governed$get_tools()$send, request@arguments))
      }
    )
    governed <- Agent$new(
      chat = chat$chat,
      working_dir = workspace_a,
      permissions = case$permissions
    )
    connection <- mcp_console_connection(
      governed,
      command,
      dependencies = "allow"
    )
    governed$register_tools(connection$tools())
    governed$run_sync("Run the cell.")
    connection$close()
    expect_true(chat$state$rejected)
    expect_false(chat$state$executed)
  }
  expect_console(cell(send_a, r = "sum(deputy_df$v)"), "[1] 6", fixed = TRUE)

  busy <- mcp_test_await(send_a(r = "Sys.sleep(30); 'late'"), timeout = 60)
  expect_console(paste(busy), running, fixed = TRUE)
  interrupted <- mcp_test_await(
    mcp_console_control(a, "interrupt"),
    timeout = 60
  )
  expect_false(grepl("late", paste(interrupted), fixed = TRUE))
  expect_console(cell(send_a, r = "nrow(deputy_df)"), "[1] 3", fixed = TRUE)

  restarted <- tryCatch(
    mcp_test_await(mcp_console_control(a, "restart"), timeout = 60),
    deputy_mcp_console_restart = identity
  )
  if (inherits(restarted, "deputy_mcp_console_restart")) {
    expect_identical(a$status()$state, "closed")
    expect_error(send_a(r = "1"), "closed", class = "deputy_mcp_connection")
  } else {
    expect_console(
      paste(restarted),
      "[worker stopped: in-memory state lost]",
      fixed = TRUE
    )
    expect_console(
      cell(send_a, r = "exists('deputy_df')"),
      "[1] FALSE",
      fixed = TRUE
    )
  }
  a$close()
  expect_identical(a$status()$state, "closed")
  expect_error(send_a(r = "1"), "closed", class = "deputy_mcp_connection")
  expect_true(dir.exists(a$status()$execution$recordings))
  expect_console(cell(send_b, r = "1 + 1"), "[1] 2", fixed = TRUE)
  b$close()
})
