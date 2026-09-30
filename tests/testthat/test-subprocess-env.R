test_that("the subprocess environment hides host variables unless allowed", {
  withr::local_envvar(
    DEPUTY_TEST_SENTINEL = "host-secret",
    LC_DEPUTY_TEST = "locale"
  )

  env <- subprocess_env()
  expect_true(is.na(env[["DEPUTY_TEST_SENTINEL"]]))
  expect_false("PATH" %in% names(env))
  expect_false("LC_DEPUTY_TEST" %in% names(env))
  expect_identical(env[["R_TESTS"]], callr::rcmd_safe_env()[["R_TESTS"]])
  # The null device, which no child can leave settings in for the next.
  expect_identical(env[["R_ENVIRON_USER"]], nullfile())

  allowed <- subprocess_env("DEPUTY_TEST_SENTINEL")
  expect_false("DEPUTY_TEST_SENTINEL" %in% names(allowed))

  expect_identical(subprocess_env("inherit"), callr::rcmd_safe_env())

  withr::local_envvar(R_ENVIRON_USER = "/some/environ")
  expect_false("R_ENVIRON_USER" %in% names(subprocess_env("R_ENVIRON_USER")))
})

test_that("programs keep their locations, and proxy settings pass in either case", {
  withr::local_envvar(
    RSTUDIO_PANDOC = "/opt/pandoc",
    RTOOLS44_HOME = "C:/rtools44",
    OMP_NUM_THREADS = "2",
    https_proxy = "http://proxy:3128",
    no_proxy = "localhost",
    DEPUTY_TEST_TOKEN = "x"
  )
  env <- subprocess_env()
  for (name in c("RSTUDIO_PANDOC", "RTOOLS44_HOME", "OMP_NUM_THREADS")) {
    expect_false(name %in% names(env))
  }
  expect_true(is.na(env[["https_proxy"]]))

  behind_proxy <- subprocess_env(c("HTTPS_PROXY", "NO_PROXY"))
  expect_false("https_proxy" %in% names(behind_proxy))
  expect_false("no_proxy" %in% names(behind_proxy))
  # Other names match exactly, except on Windows, where names have no case.
  skip_on_os("windows")
  expect_true(is.na(subprocess_env("deputy_test_token")[["DEPUTY_TEST_TOKEN"]]))
})

test_that("an env argument is inherit or variable names", {
  expect_null(check_subprocess_env(NULL))
  expect_identical(check_subprocess_env("inherit"), "inherit")
  expect_identical(check_subprocess_env(c("A", "B", "A")), c("A", "B"))
  for (bad in list(
    1,
    NA_character_,
    "",
    c(A = "a"),
    "A=1",
    "HAS SPACE",
    c("inherit", "A")
  )) {
    expect_error(check_subprocess_env(bad), class = "deputy_subprocess_env")
  }
  expect_error(tools_code(env = 1), class = "deputy_subprocess_env")
})

test_that("run_r_code can't read host variables or .Renviron by default", {
  skip_on_cran()
  withr::local_envvar(DEPUTY_TEST_SENTINEL = "host-secret")
  project <- withr::local_tempdir()
  writeLines(
    "DEPUTY_TEST_RENVIRON=renviron-secret",
    file.path(project, ".Renviron")
  )
  withr::local_dir(project)
  code <- paste(
    "cat(Sys.getenv('DEPUTY_TEST_SENTINEL', 'unset'),",
    "Sys.getenv('DEPUTY_TEST_RENVIRON', 'unset'), nzchar(Sys.getenv('PATH')))"
  )

  expect_match(tool_run_r_code(code), "unset unset TRUE", fixed = TRUE)

  allowed <- tools_code(env = "DEPUTY_TEST_SENTINEL")[[1]]
  expect_match(allowed(code), "host-secret unset TRUE", fixed = TRUE)
  runner <- attr(allowed, "deputy_workspace_runner", exact = TRUE)
  expect_match(
    runner(list(code = code), project),
    "host-secret unset TRUE",
    fixed = TRUE
  )
  expect_true(is_native_tool(allowed))

  inherited <- tools_code(env = "inherit")[[1]]
  expect_match(
    inherited(code),
    "host-secret renviron-secret TRUE",
    fixed = TRUE
  )

  # Presets pass the same choice to their code tools.
  run_r <- function(tools) {
    Filter(function(tool) identical(tool@name, "run_r_code"), tools)[[1]]
  }
  expect_match(
    run_r(tools_preset("dev"))(code),
    "unset unset TRUE",
    fixed = TRUE
  )
  expect_match(
    run_r(tools_preset("data", env = "DEPUTY_TEST_SENTINEL"))(code),
    "host-secret unset TRUE",
    fixed = TRUE
  )
  expect_match(
    run_r(tools_all(env = "DEPUTY_TEST_SENTINEL"))(code),
    "host-secret unset TRUE",
    fixed = TRUE
  )
})

test_that("the command-line app takes --code-env", {
  expect_null(cli_code_env(NULL))
  expect_null(cli_code_env(NA_character_))
  expect_identical(cli_code_env("inherit"), "inherit")
  expect_identical(
    cli_code_env("HTTPS_PROXY, NO_PROXY"),
    c("HTTPS_PROXY", "NO_PROXY")
  )
  expect_error(cli_code_env("inherit,HOME"), class = "deputy_cli_config_error")
  expect_error(cli_code_env("A=1"), class = "deputy_cli_config_error")
})

test_that("run_bash can't read host variables by default", {
  skip_on_cran()
  skip_on_os("windows")
  withr::local_envvar(DEPUTY_TEST_SENTINEL = "host-secret")
  command <- "echo \"${DEPUTY_TEST_SENTINEL:-unset}\""

  expect_identical(tool_run_bash(command), "unset")
  expect_identical(
    tools_code(env = "DEPUTY_TEST_SENTINEL")[[2]](command),
    "host-secret"
  )
})

test_that("an RSession worker gets only the variables its host allows", {
  skip_on_cran()
  withr::local_envvar(DEPUTY_TEST_SENTINEL = "host-secret")
  agent <- Agent$new(
    chat = create_mock_chat(),
    working_dir = withr::local_tempdir()
  )
  code <- "cat(Sys.getenv('DEPUTY_TEST_SENTINEL', 'unset'))"

  hidden <- RSession$new(agent)
  withr::defer(hidden$close())
  expect_match(r_session_text(r_session_await(hidden$run(code))), "unset")

  allowed <- RSession$new(agent, env = "DEPUTY_TEST_SENTINEL")
  withr::defer(allowed$close())
  expect_match(
    r_session_text(r_session_await(allowed$run(code))),
    "host-secret"
  )

  expect_error(
    RSession$new(agent, env = c(A = "a")),
    class = "deputy_r_session"
  )
})
