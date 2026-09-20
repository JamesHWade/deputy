job_process_test_package <- function() {
  getNamespaceInfo(asNamespace("deputy"), "path")
}

job_process_test_record_field <- function(record, name) {
  value <- tryCatch(
    S7::prop(record, name),
    error = function(error) NULL
  )
  if (is.null(value) && is.list(record)) {
    value <- record[[name]]
  }
  value
}

job_process_test_status <- function(record) {
  as.character(job_process_test_record_field(record, "status"))
}

job_process_test_runtime <- function(record) {
  job_process_test_record_field(record, "runtime")
}

job_process_test_usage <- function(record) {
  runtime <- job_process_test_runtime(record)
  usage <- job_process_test_record_field(record, "usage")
  if (is.null(usage) && is.list(runtime)) {
    usage <- runtime$usage
  }
  usage
}

job_process_test_requirements <- function() {
  skip_if_not_installed("callr")
  skip_if_not_installed("pkgload")
  skip_if_not_installed("httpuv")
  skip_if_not_installed("jsonlite")
}

job_process_tool_reply <- function(value) {
  response <- runtime_reply(tool = "effect", arguments = list(value = value))
  response$body <- gsub(
    "call_fixture",
    paste0("call_", value),
    response$body,
    fixed = TRUE
  )
  response
}

test_that("a queued job survives its creator process and is consumed once", {
  job_process_test_requirements()
  server <- local_runtime_server(list(runtime_reply("queued result")))
  directory <- withr::local_tempdir(pattern = "deputy-job-process-queued-")
  package_path <- job_process_test_package()

  path <- callr::r(
    function(package_path, directory, url) {
      pkgload::load_all(package_path, quiet = TRUE, helpers = FALSE)
      agent <- deputy::Agent$new(
        chat = ellmer::chat_openai_compatible(
          base_url = url,
          credentials = function() "fixture",
          model = "gpt-4o-mini",
          echo = "none"
        ),
        working_dir = directory,
        agent_id = "queued-agent",
        session_id = "queued-session"
      )
      deputy::job_create(
        directory = directory,
        agent = agent,
        task = "answer from the queued job",
        owner_id = "owner-queued",
        definition_revision = "definition-1",
        context_revision = "context-1",
        usage_limits = deputy::UsageLimits(max_requests = 2L),
        associations = list(owner_id = "owner-queued")
      )
    },
    args = list(
      package_path = package_path,
      directory = directory,
      url = server$url
    ),
    libpath = .libPaths()
  )
  expect_true(is.character(path))
  expect_length(path, 1L)

  first <- callr::r(
    function(package_path, path, directory, url) {
      pkgload::load_all(package_path, quiet = TRUE, helpers = FALSE)
      bind <- function(...) {
        deputy::Agent$new(
          chat = ellmer::chat_openai_compatible(
            base_url = url,
            credentials = function() "fixture",
            model = "gpt-4o-mini",
            echo = "none"
          ),
          working_dir = directory,
          agent_id = "queued-agent",
          session_id = "queued-session"
        )
      }
      deputy::job_run(
        path,
        bind = bind,
        authorize = function(job) {
          list(
            job_id = job$id,
            owner_id = job$owner_id,
            definition_revision = job$definition_revision,
            context_revision = job$context_revision
          )
        }
      )
      deputy::job_read(path)
    },
    args = list(
      package_path = package_path,
      path = path,
      directory = directory,
      url = server$url
    ),
    libpath = .libPaths()
  )
  expect_identical(job_process_test_status(first), "completed")
  expect_length(server$requests(), 1L)

  second <- callr::r(
    function(package_path, path) {
      pkgload::load_all(package_path, quiet = TRUE, helpers = FALSE)
      # A terminal job must be inspectable without recreating a provider,
      # binding an Agent, or dispatching another request.
      deputy::job_run(
        path,
        bind = function(...) stop("terminal job unexpectedly rebound"),
        authorize = function(job) {
          list(
            job_id = job$id,
            owner_id = job$owner_id,
            definition_revision = job$definition_revision,
            context_revision = job$context_revision
          )
        }
      )
      deputy::job_read(path)
    },
    args = list(package_path = package_path, path = path),
    libpath = .libPaths()
  )
  expect_identical(job_process_test_status(second), "completed")
  expect_length(server$requests(), 1L)
})

test_that("a killed worker leaves an indeterminate effect without retry", {
  job_process_test_requirements()
  skip_on_os("windows")
  server <- local_runtime_server(list(
    job_process_tool_reply("once"),
    runtime_reply("unreachable", stream = FALSE)
  ))
  directory <- withr::local_tempdir(pattern = "deputy-job-process-crash-")
  marker <- file.path(directory, "effect.txt")
  package_path <- job_process_test_package()

  path <- callr::r(
    function(package_path, directory, marker, url) {
      pkgload::load_all(package_path, quiet = TRUE, helpers = FALSE)
      kill_after <- FALSE
      tool <- ellmer::tool(
        function(value) {
          cat(value, "\n", file = marker, append = TRUE, sep = "")
          if (isTRUE(kill_after)) {
            tools::pskill(Sys.getpid(), signal = 9L)
          }
          value
        },
        name = "effect",
        description = "Write one effect receipt",
        arguments = list(value = ellmer::type_string()),
        convert = FALSE,
        annotations = ellmer::tool_annotations(
          read_only_hint = FALSE,
          destructive_hint = FALSE,
          open_world_hint = FALSE
        )
      )
      agent <- deputy::Agent$new(
        chat = ellmer::chat_openai_compatible(
          base_url = url,
          credentials = function() "fixture",
          model = "gpt-4o-mini",
          echo = "none"
        ),
        tools = list(tool),
        permissions = deputy::Permissions(can_use_tool = function(...) {
          deputy::PermissionResultAllow()
        }),
        working_dir = directory,
        agent_id = "crash-agent",
        session_id = "crash-session"
      )
      deputy::job_create(
        directory = directory,
        agent = agent,
        task = "write one effect",
        owner_id = "owner-crash",
        definition_revision = "definition-1",
        context_revision = "context-1",
        usage_limits = deputy::UsageLimits(max_requests = 3L),
        associations = list(owner_id = "owner-crash")
      )
    },
    args = list(
      package_path = package_path,
      directory = directory,
      marker = marker,
      url = server$url
    ),
    libpath = .libPaths()
  )

  allocation <- callr::r(
    function(package_path, path) {
      pkgload::load_all(package_path, quiet = TRUE, helpers = FALSE)
      deputy::job_read(path)$allocation
    },
    args = list(package_path = package_path, path = path),
    libpath = .libPaths()
  )

  worker <- callr::r_bg(
    function(package_path, path, directory, marker, url) {
      pkgload::load_all(package_path, quiet = TRUE, helpers = FALSE)
      kill_after <- TRUE
      tool <- ellmer::tool(
        function(value) {
          cat(value, "\n", file = marker, append = TRUE, sep = "")
          if (isTRUE(kill_after)) {
            tools::pskill(Sys.getpid(), signal = 9L)
          }
          value
        },
        name = "effect",
        description = "Write one effect receipt",
        arguments = list(value = ellmer::type_string()),
        convert = FALSE,
        annotations = ellmer::tool_annotations(
          read_only_hint = FALSE,
          destructive_hint = FALSE,
          open_world_hint = FALSE
        )
      )
      bind <- function(...) {
        deputy::Agent$new(
          chat = ellmer::chat_openai_compatible(
            base_url = url,
            credentials = function() "fixture",
            model = "gpt-4o-mini",
            echo = "none"
          ),
          tools = list(tool),
          permissions = deputy::Permissions(can_use_tool = function(...) {
            deputy::PermissionResultAllow()
          }),
          working_dir = directory,
          agent_id = "crash-agent",
          session_id = "crash-session"
        )
      }
      deputy::job_run(
        path,
        bind = bind,
        authorize = function(job) {
          list(
            job_id = job$id,
            owner_id = job$owner_id,
            definition_revision = job$definition_revision,
            context_revision = job$context_revision
          )
        }
      )
    },
    args = list(
      package_path = package_path,
      path = path,
      directory = directory,
      marker = marker,
      url = server$url
    ),
    libpath = .libPaths()
  )
  withr::defer(worker$kill())
  worker$wait(timeout = 10000)
  expect_false(worker$is_alive())
  if (!identical(worker$get_exit_status(), -9L)) {
    worker$get_result()
  }
  expect_identical(worker$get_exit_status(), -9L)
  expect_identical(readLines(marker), "once")

  recovered <- callr::r(
    function(package_path, path) {
      pkgload::load_all(package_path, quiet = TRUE, helpers = FALSE)
      deputy::job_run(
        path,
        bind = function(...) stop("indeterminate job unexpectedly rebound"),
        authorize = function(job) {
          list(
            job_id = job$id,
            owner_id = job$owner_id,
            definition_revision = job$definition_revision,
            context_revision = job$context_revision
          )
        }
      )
      deputy::job_read(path)
    },
    args = list(package_path = package_path, path = path),
    libpath = .libPaths()
  )
  expect_identical(job_process_test_status(recovered), "indeterminate")
  expect_identical(readLines(marker), "once")
  expect_length(server$requests(), 1L)
  expect_true(!is.null(job_process_test_usage(recovered)))
  expect_identical(
    job_process_test_record_field(recovered, "allocation"),
    allocation
  )
  expect_identical(
    job_process_test_record_field(recovered, "reservations")$status,
    "preserved"
  )
})

test_that("a pending approval resumes in a new process without replaying completed effects", {
  job_process_test_requirements()
  server <- local_runtime_server(list(
    job_process_tool_reply("a"),
    job_process_tool_reply("b"),
    runtime_reply("both effects complete")
  ))
  directory <- withr::local_tempdir(pattern = "deputy-job-process-approval-")
  approvals <- file.path(directory, "approvals")
  dir.create(approvals)
  marker <- file.path(directory, "effects.txt")
  package_path <- job_process_test_package()

  path <- callr::r(
    function(package_path, directory, approvals, marker, url) {
      pkgload::load_all(package_path, quiet = TRUE, helpers = FALSE)
      tool <- ellmer::tool(
        function(value) {
          cat(value, "\n", file = marker, append = TRUE, sep = "")
          value
        },
        name = "effect",
        description = "Write an approval effect receipt",
        arguments = list(value = ellmer::type_string()),
        convert = FALSE,
        annotations = ellmer::tool_annotations(
          read_only_hint = FALSE,
          destructive_hint = FALSE,
          open_world_hint = FALSE
        )
      )
      agent <- deputy::Agent$new(
        chat = ellmer::chat_openai_compatible(
          base_url = url,
          credentials = function() "fixture",
          model = "gpt-4o-mini",
          echo = "none"
        ),
        tools = list(tool),
        permissions = deputy::Permissions(can_use_tool = function(
          name,
          input,
          context
        ) {
          if (identical(input$value, "b")) {
            deputy::PermissionResultPending("Review b")
          } else {
            deputy::PermissionResultAllow()
          }
        }),
        approval_dir = approvals,
        working_dir = directory,
        agent_id = "approval-job-agent",
        session_id = "approval-job-session"
      )
      deputy::job_create(
        directory = directory,
        agent = agent,
        task = "perform both effects",
        owner_id = "owner-approval",
        definition_revision = "definition-1",
        context_revision = "context-1",
        usage_limits = deputy::UsageLimits(max_requests = 5L),
        associations = list(owner_id = "owner-approval")
      )
    },
    args = list(
      package_path = package_path,
      directory = directory,
      approvals = approvals,
      marker = marker,
      url = server$url
    ),
    libpath = .libPaths()
  )

  first <- callr::r(
    function(package_path, path, directory, approvals, marker, url) {
      pkgload::load_all(package_path, quiet = TRUE, helpers = FALSE)
      tool <- ellmer::tool(
        function(value) {
          cat(value, "\n", file = marker, append = TRUE, sep = "")
          value
        },
        name = "effect",
        description = "Write an approval effect receipt",
        arguments = list(value = ellmer::type_string()),
        convert = FALSE,
        annotations = ellmer::tool_annotations(
          read_only_hint = FALSE,
          destructive_hint = FALSE,
          open_world_hint = FALSE
        )
      )
      bind <- function(...) {
        deputy::Agent$new(
          chat = ellmer::chat_openai_compatible(
            base_url = url,
            credentials = function() "fixture",
            model = "gpt-4o-mini",
            echo = "none"
          ),
          tools = list(tool),
          permissions = deputy::Permissions(can_use_tool = function(
            name,
            input,
            context
          ) {
            if (identical(input$value, "b")) {
              deputy::PermissionResultPending("Review b")
            } else {
              deputy::PermissionResultAllow()
            }
          }),
          approval_dir = approvals,
          working_dir = directory,
          agent_id = "approval-job-agent",
          session_id = "approval-job-session"
        )
      }
      deputy::job_run(
        path,
        bind = bind,
        authorize = function(job) {
          list(
            job_id = job$id,
            owner_id = job$owner_id,
            definition_revision = job$definition_revision,
            context_revision = job$context_revision
          )
        }
      )
      deputy::job_read(path)
    },
    args = list(
      package_path = package_path,
      path = path,
      directory = directory,
      approvals = approvals,
      marker = marker,
      url = server$url
    ),
    libpath = .libPaths()
  )
  expect_identical(job_process_test_status(first), "approval_pending")
  expect_identical(readLines(marker), "a")
  expect_length(server$requests(), 2L)

  second <- callr::r(
    function(package_path, path, directory, approvals, marker, url) {
      pkgload::load_all(package_path, quiet = TRUE, helpers = FALSE)
      tool <- ellmer::tool(
        function(value) {
          cat(value, "\n", file = marker, append = TRUE, sep = "")
          value
        },
        name = "effect",
        description = "Write an approval effect receipt",
        arguments = list(value = ellmer::type_string()),
        convert = FALSE,
        annotations = ellmer::tool_annotations(
          read_only_hint = FALSE,
          destructive_hint = FALSE,
          open_world_hint = FALSE
        )
      )
      bind <- function(...) {
        deputy::Agent$new(
          chat = ellmer::chat_openai_compatible(
            base_url = url,
            credentials = function() "fixture",
            model = "gpt-4o-mini",
            echo = "none"
          ),
          tools = list(tool),
          permissions = deputy::Permissions(can_use_tool = function(
            name,
            input,
            context
          ) {
            if (identical(input$value, "b")) {
              deputy::PermissionResultPending("Review b")
            } else {
              deputy::PermissionResultAllow()
            }
          }),
          approval_dir = approvals,
          working_dir = directory,
          agent_id = "approval-job-agent",
          session_id = "approval-job-session"
        )
      }
      deputy::job_run(
        path,
        bind = bind,
        authorize = function(job) {
          list(
            job_id = job$id,
            owner_id = job$owner_id,
            definition_revision = job$definition_revision,
            context_revision = job$context_revision
          )
        },
        decision = "approve"
      )
      deputy::job_read(path)
    },
    args = list(
      package_path = package_path,
      path = path,
      directory = directory,
      approvals = approvals,
      marker = marker,
      url = server$url
    ),
    libpath = .libPaths()
  )
  expect_identical(job_process_test_status(second), "completed")
  expect_identical(readLines(marker), c("a", "b"))
  expect_length(server$requests(), 3L)
})

test_that("queued cancellation completes without provider IO during recovery", {
  job_process_test_requirements()
  server <- local_runtime_server(list(runtime_reply(
    "must not run",
    stream = FALSE
  )))
  directory <- withr::local_tempdir(pattern = "deputy-job-process-cancel-")
  package_path <- job_process_test_package()
  path <- callr::r(
    function(package_path, directory, url) {
      pkgload::load_all(package_path, quiet = TRUE, helpers = FALSE)
      agent <- deputy::Agent$new(
        chat = ellmer::chat_openai_compatible(
          base_url = url,
          credentials = function() "fixture",
          model = "gpt-4o-mini",
          echo = "none"
        ),
        working_dir = directory,
        agent_id = "cancel-agent",
        session_id = "cancel-session"
      )
      deputy::job_create(
        directory = directory,
        agent = agent,
        task = "cancel before dispatch",
        owner_id = "owner-cancel",
        definition_revision = "definition-1",
        context_revision = "context-1",
        usage_limits = deputy::UsageLimits(max_requests = 1L),
        associations = list(owner_id = "owner-cancel")
      )
    },
    args = list(
      package_path = package_path,
      directory = directory,
      url = server$url
    ),
    libpath = .libPaths()
  )

  cancelled <- callr::r(
    function(package_path, path) {
      pkgload::load_all(package_path, quiet = TRUE, helpers = FALSE)
      deputy::job_cancel(
        path,
        authorize = function(job) {
          list(
            job_id = job$id,
            owner_id = job$owner_id,
            definition_revision = job$definition_revision,
            context_revision = job$context_revision
          )
        },
        reason = "user_cancelled"
      )
      deputy::job_read(path)
    },
    args = list(package_path = package_path, path = path),
    libpath = .libPaths()
  )
  expect_identical(job_process_test_status(cancelled), "cancelled")

  recovered <- callr::r(
    function(package_path, path) {
      pkgload::load_all(package_path, quiet = TRUE, helpers = FALSE)
      deputy::job_run(
        path,
        bind = function(...) stop("cancelled job unexpectedly rebound"),
        authorize = function(job) {
          list(
            job_id = job$id,
            owner_id = job$owner_id,
            definition_revision = job$definition_revision,
            context_revision = job$context_revision
          )
        }
      )
      deputy::job_read(path)
    },
    args = list(package_path = package_path, path = path),
    libpath = .libPaths()
  )
  expect_identical(job_process_test_status(recovered), "cancelled")
  expect_length(server$requests(), 0L)
})

test_that("host cancellation uses the independent control store while a worker is active", {
  job_process_test_requirements()
  skip_on_os("windows")
  delayed <- runtime_reply("late provider result")
  attr(delayed, "fixture_delay") <- 5
  server <- local_runtime_server(list(delayed))
  directory <- withr::local_tempdir(
    pattern = "deputy-job-process-active-cancel-"
  )
  cleanup_marker <- file.path(directory, "cleanup.txt")
  package_path <- job_process_test_package()

  path <- callr::r(
    function(package_path, directory, url) {
      pkgload::load_all(package_path, quiet = TRUE, helpers = FALSE)
      agent <- deputy::Agent$new(
        chat = ellmer::chat_openai_compatible(
          base_url = url,
          credentials = function() "fixture",
          model = "gpt-4o-mini",
          echo = "none"
        ),
        working_dir = directory,
        agent_id = "active-cancel-agent",
        session_id = "active-cancel-session"
      )
      deputy::job_create(
        directory = directory,
        agent = agent,
        task = "wait for a provider result",
        owner_id = "owner-active-cancel",
        definition_revision = "definition-1",
        context_revision = "context-1",
        usage_limits = deputy::UsageLimits(max_requests = 1L),
        associations = list(owner_id = "owner-active-cancel")
      )
    },
    args = list(
      package_path = package_path,
      directory = directory,
      url = server$url
    ),
    libpath = .libPaths()
  )

  worker <- callr::r_bg(
    function(package_path, path, directory, cleanup_marker, url) {
      pkgload::load_all(package_path, quiet = TRUE, helpers = FALSE)
      bind <- function(...) {
        agent <- deputy::Agent$new(
          chat = ellmer::chat_openai_compatible(
            base_url = url,
            credentials = function() "fixture",
            model = "gpt-4o-mini",
            echo = "none"
          ),
          working_dir = directory,
          agent_id = "active-cancel-agent",
          session_id = "active-cancel-session"
        )
        list(
          agent = agent,
          cleanup = function() {
            cat("cleanup\n", file = cleanup_marker, append = TRUE, sep = "")
          }
        )
      }
      authorize <- function(job) {
        list(
          job_id = job$id,
          owner_id = job$owner_id,
          definition_revision = job$definition_revision,
          context_revision = job$context_revision
        )
      }
      deputy::job_run(path, bind = bind, authorize = authorize)
    },
    args = list(
      package_path = package_path,
      path = path,
      directory = directory,
      cleanup_marker = cleanup_marker,
      url = server$url
    ),
    libpath = .libPaths()
  )
  withr::defer(worker$kill())

  deadline <- Sys.time() + 10
  while (
    length(server$requests()) < 1L &&
      worker$is_alive() &&
      Sys.time() < deadline
  ) {
    Sys.sleep(0.02)
  }
  expect_length(server$requests(), 1L)

  started <- Sys.time()
  requested <- callr::r(
    function(package_path, path) {
      pkgload::load_all(package_path, quiet = TRUE, helpers = FALSE)
      authorize <- function(job) {
        list(
          job_id = job$id,
          owner_id = job$owner_id,
          definition_revision = job$definition_revision,
          context_revision = job$context_revision
        )
      }
      deputy::job_cancel(
        path,
        authorize = authorize,
        reason = "user_cancelled"
      )
    },
    args = list(package_path = package_path, path = path),
    libpath = .libPaths()
  )
  elapsed <- as.numeric(difftime(Sys.time(), started, units = "secs"))
  expect_lt(elapsed, 4)
  expect_true(requested$status %in% c("running", "cancelled", "indeterminate"))

  worker$wait(timeout = 15000)
  expect_false(worker$is_alive())
  if (!identical(worker$get_exit_status(), 0L)) {
    worker$get_result()
  }
  settled <- callr::r(
    function(package_path, path) {
      pkgload::load_all(package_path, quiet = TRUE, helpers = FALSE)
      deputy::job_read(path)
    },
    args = list(package_path = package_path, path = path),
    libpath = .libPaths()
  )
  expect_true(settled$status %in% c("cancelled", "indeterminate"))
  expect_false(identical(settled$status, "completed"))
  expect_identical(readLines(cleanup_marker), "cleanup")
  expect_identical(settled$cleanup$attempts, 1L)
  expect_length(server$requests(), 1L)
})

test_that("a binding failure is terminal and does not dispatch a provider request", {
  job_process_test_requirements()
  server <- local_runtime_server(list(runtime_reply(
    "must not run",
    stream = FALSE
  )))
  directory <- withr::local_tempdir(pattern = "deputy-job-process-failure-")
  package_path <- job_process_test_package()
  path <- callr::r(
    function(package_path, directory, url) {
      pkgload::load_all(package_path, quiet = TRUE, helpers = FALSE)
      agent <- deputy::Agent$new(
        chat = ellmer::chat_openai_compatible(
          base_url = url,
          credentials = function() "fixture",
          model = "gpt-4o-mini",
          echo = "none"
        ),
        working_dir = directory,
        agent_id = "failed-agent",
        session_id = "failed-session"
      )
      deputy::job_create(
        directory = directory,
        agent = agent,
        task = "fail while binding",
        owner_id = "owner-failed",
        definition_revision = "definition-1",
        context_revision = "context-1",
        usage_limits = deputy::UsageLimits(max_requests = 1L),
        associations = list(owner_id = "owner-failed")
      )
    },
    args = list(
      package_path = package_path,
      directory = directory,
      url = server$url
    ),
    libpath = .libPaths()
  )

  failed <- callr::r(
    function(package_path, path) {
      pkgload::load_all(package_path, quiet = TRUE, helpers = FALSE)
      try(
        deputy::job_run(
          path,
          bind = function(...) stop("factory unavailable"),
          authorize = function(job) {
            list(
              job_id = job$id,
              owner_id = job$owner_id,
              definition_revision = job$definition_revision,
              context_revision = job$context_revision
            )
          }
        ),
        silent = TRUE
      )
      deputy::job_read(path)
    },
    args = list(package_path = package_path, path = path),
    libpath = .libPaths()
  )
  expect_identical(job_process_test_status(failed), "failed")
  expect_length(server$requests(), 0L)
})
