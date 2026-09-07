test_that("callback results survive RDS and timed hook subprocesses", {
  root <- withr::local_tempdir()
  path <- file.path(root, "results.rds")
  output <- new.env(parent = emptyenv())
  output$count <- 0L
  values <- list(
    HookResultPreToolUse("deny", "blocked", FALSE, "context", "stop"),
    HookResultPostToolUse(FALSE, TRUE, output, "context", "stop"),
    HookResultPreCompact(FALSE, "summary"),
    PermissionResultAllow("approved"),
    PermissionResultDeny("blocked", TRUE)
  )
  saveRDS(list(values = values, output = output), path)
  restored <- callr::r(
    function(path, package_path) {
      if (file.exists(file.path(package_path, "R", "agent.R"))) {
        pkgload::load_all(package_path, quiet = TRUE)
      } else {
        library(deputy, lib.loc = dirname(package_path))
      }
      data <- readRDS(path)
      values <- data$values
      classes <- list(
        HookResultPreToolUse,
        HookResultPostToolUse,
        HookResultPreCompact,
        PermissionResultAllow,
        PermissionResultDeny
      )
      frozen <- vapply(
        values,
        function(value) {
          name <- names(S7::props(value))[[1L]]
          tryCatch(
            {
              S7::prop(value, name) <- S7::prop(value, name)
              FALSE
            },
            error = function(error) grepl("read-only", conditionMessage(error))
          )
        },
        logical(1)
      )
      # Returning an S7 record through the actual timeout path must retain
      # its class and decision in the receiving process.
      registry <- deputy:::HookRegistry$new()
      registry$add(HookMatcher(
        "PreToolUse",
        timeout = 20,
        callback = local({
          package_path <- package_path
          function(...) {
            if (file.exists(file.path(package_path, "R", "agent.R"))) {
              pkgload::load_all(package_path, quiet = TRUE)
            } else {
              library(deputy, lib.loc = dirname(package_path))
            }
            deputy::HookResultPreToolUse("deny", "timed denial")
          }
        })
      ))
      timed <- registry$fire("PreToolUse", tool_name = "effect")
      data$output$count <- 1L
      list(
        classes = mapply(S7::S7_inherits, values, classes),
        hook_family = vapply(
          values[1:3],
          S7::S7_inherits,
          logical(1),
          HookResult
        ),
        permission_family = vapply(
          values[4:5],
          S7::S7_inherits,
          logical(1),
          PermissionResult
        ),
        frozen = frozen,
        records = lapply(values, S7::props),
        output_shared = identical(
          values[[2L]]$updated_tool_output,
          data$output
        ),
        output_count = values[[2L]]$updated_tool_output$count,
        timed_class = S7::S7_inherits(timed, HookResultPreToolUse),
        timed_fields = S7::props(timed),
        errors = registry$last_errors()
      )
    },
    args = list(
      path = path,
      package_path = getNamespaceInfo(asNamespace("deputy"), "path")
    )
  )
  expect_true(all(restored$classes))
  expect_true(all(restored$hook_family))
  expect_true(all(restored$permission_family))
  expect_true(all(restored$frozen))
  for (index in c(1L, 3L, 4L, 5L)) {
    expect_identical(restored$records[[index]], S7::props(values[[index]]))
  }
  expect_true(restored$output_shared)
  expect_identical(restored$output_count, 1L)
  expect_identical(output$count, 0L)
  expect_true(restored$timed_class)
  expect_identical(restored$timed_fields$permission, "deny")
  expect_identical(restored$timed_fields$reason, "timed denial")
  expect_length(restored$errors, 0L)
})
