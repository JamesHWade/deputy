test_that("run context canonicalizes supported JSON-compatible values", {
  latin1 <- iconv("caf\u00e9", from = "UTF-8", to = "latin1")
  Encoding(latin1) <- "latin1"

  context <- normalize_run_context(list(
    z = list(beta = latin1, alpha = 1L),
    arrays = list(
      c(TRUE, FALSE),
      c(1, 2.5),
      c("alpha", "beta"),
      list(NULL, list(value = "nested"))
    ),
    counts = list(
      token_count = 2L,
      input_tokens = 5L,
      max_input_tokens = 10L
    )
  ))

  expect_named(context, c("arrays", "counts", "z"))
  expect_named(context$z, c("alpha", "beta"))
  expect_identical(context$z$alpha, 1L)
  expect_identical(context$arrays[[4L]][[1L]], NULL)
  expect_identical(Encoding(context$z$beta), "UTF-8")
  expect_identical(normalize_run_context(list()), list())
})

test_that("run context rejects malformed object and array shapes", {
  cases <- list(
    unnamed_top_level = list(1L),
    partial_keys = structure(list(1L, 2L), names = c("first", "")),
    empty_key = structure(list(1L), names = ""),
    duplicate_key = structure(list(1L, 2L), names = c("same", "same")),
    named_primitive = list(value = c(first = 1L)),
    matrix = list(value = matrix(1:4, nrow = 2L)),
    classed = list(value = structure(1L, class = "runtime_value"))
  )

  for (case in cases) {
    expect_error(
      normalize_run_context(case),
      class = "deputy_run_context_error"
    )
  }

  error <- tryCatch(
    normalize_run_context(list(1L), argument = "session$run_context"),
    error = identity
  )
  expect_s3_class(error, "deputy_run_context_error")
  expect_match(conditionMessage(error), "session\\$run_context")
})

test_that("run context rejects missing and non-finite primitives", {
  cases <- list(
    list(value = NA),
    list(value = NA_character_),
    list(value = NA_integer_),
    list(value = NA_real_),
    list(value = NaN),
    list(value = Inf),
    list(value = -Inf)
  )

  for (case in cases) {
    expect_error(
      normalize_run_context(case),
      class = "deputy_run_context_error"
    )
  }
})

test_that("run context rejects runtime and non-JSON values", {
  connection <- textConnection("runtime text")
  withr::defer(close(connection))

  cases <- list(
    function_value = list(value = function() NULL),
    environment = list(value = new.env(parent = emptyenv())),
    connection = list(value = connection),
    call = list(value = quote(run_context_call())),
    symbol = list(value = quote(run_context_symbol)),
    raw = list(value = as.raw(1L)),
    complex = list(value = 1 + 1i),
    expression = list(value = expression(value))
  )

  for (case in cases) {
    expect_error(
      normalize_run_context(case),
      class = "deputy_run_context_error"
    )
  }
})

test_that("credential-like keys are separator insensitive and values stay hidden", {
  credential_keys <- c(
    "api_key",
    "API-KEY",
    "api.key",
    "client secret",
    "apiSecret",
    "APISecret",
    "jwtSecret",
    "webhookSecret",
    "password",
    "access-token",
    "credentials",
    "github_token"
  )
  secret_value <- "do-not-echo-this-secret-value"

  for (key in credential_keys) {
    context <- setNames(list(secret_value), key)
    error <- tryCatch(
      normalize_run_context(context),
      error = identity
    )

    expect_s3_class(error, "deputy_run_context_error")
    expect_s3_class(error, "deputy_error")
    expect_identical(
      grepl(secret_value, conditionMessage(error), fixed = TRUE),
      FALSE
    )
    expect_identical(
      grepl(
        secret_value,
        paste(capture.output(str(error)), collapse = "\n"),
        fixed = TRUE
      ),
      FALSE
    )
  }
})

test_that("scientific context keys are not mistaken for credentials", {
  context <- normalize_run_context(list(
    secretion_id = "observation-1",
    secretion_rate = 2.5,
    secretory_pathway = "constitutive"
  ))

  expect_identical(context$secretion_id, "observation-1")
  expect_identical(context$secretion_rate, 2.5)
  expect_identical(context$secretory_pathway, "constitutive")
})

test_that("run context enforces a finite nesting depth", {
  nested <- "leaf"
  for (index in seq_len(100L)) {
    nested <- list(nested)
  }

  expect_error(
    normalize_run_context(list(value = nested)),
    "maximum nesting depth",
    class = "deputy_run_context_error"
  )
})

test_that("run context normalization and cloning make defensive copies", {
  original <- list(meta = list(role = "reviewer"))
  normalized <- normalize_run_context(original)
  cloned <- clone_run_context(normalized)

  original$meta$role <- "author"
  cloned$meta$role <- "moderator"

  expect_identical(normalized$meta$role, "reviewer")
  expect_identical(original$meta$role, "author")
  expect_identical(cloned$meta$role, "moderator")
})

test_that("run context merge recursively adds and narrows fields", {
  defaults <- list(
    product = "tempest",
    research_run_id = "research-123",
    settings = list(
      limits = list(requests = 10L, tools = 5L),
      roles = c("reader", "writer"),
      note = "default"
    )
  )
  override <- list(
    product = "tempest",
    research_run_id = "research-123",
    child_run_id = "child-456",
    settings = list(
      limits = list(requests = 3L),
      roles = "reader",
      note = NULL
    )
  )

  merged <- merge_run_context(defaults, override)

  expect_identical(merged$product, "tempest")
  expect_identical(merged$research_run_id, "research-123")
  expect_identical(merged$child_run_id, "child-456")
  expect_identical(merged$settings$limits$requests, 3L)
  expect_identical(merged$settings$limits$tools, 5L)
  expect_identical(merged$settings$roles, "reader")
  expect_named(merged$settings, c("limits", "note", "roles"))
  expect_null(merged$settings$note)
})

test_that("run context merge protects identity fields at every depth", {
  protected_keys <- c(
    "product",
    "id",
    "research_run_id",
    "research.run.id",
    "research-run-id",
    "researchRunId",
    "knowledgeSnapshotID"
  )

  for (key in protected_keys) {
    defaults <- setNames(list("original-identity"), key)
    override <- setNames(list("replacement-identity"), key)
    error <- tryCatch(
      merge_run_context(defaults, override),
      error = identity
    )

    expect_s3_class(error, "deputy_run_context_conflict")
    expect_s3_class(error, "deputy_run_context_error")
    expect_s3_class(error, "deputy_error")
    expect_identical(
      grepl("original-identity", conditionMessage(error), fixed = TRUE),
      FALSE
    )
    expect_identical(
      grepl("replacement-identity", conditionMessage(error), fixed = TRUE),
      FALSE
    )
  }

  expect_error(
    merge_run_context(
      list(meta = list(parent_run_id = "parent-1", role = "reviewer")),
      list(meta = "replacement")
    ),
    class = "deputy_run_context_conflict"
  )
})

test_that("run context merge allows identical and new identity fields", {
  merged <- merge_run_context(
    list(
      product = "tempest",
      nested = list(research_run_id = "research-123")
    ),
    list(
      product = "tempest",
      nested = list(
        research_run_id = "research-123",
        deputy_run_id = "deputy-456"
      )
    )
  )

  expect_identical(merged$product, "tempest")
  expect_identical(merged$nested$research_run_id, "research-123")
  expect_identical(merged$nested$deputy_run_id, "deputy-456")

  expect_identical(
    merge_run_context(list(valid = TRUE), list(valid = FALSE))$valid,
    FALSE
  )
  expect_identical(
    merge_run_context(list(LIPID = "a"), list(LIPID = "b"))$LIPID,
    "b"
  )
})

test_that("run context merge does not retain mutable input structure", {
  defaults <- list(meta = list(role = "reviewer"))
  override <- list(meta = list(stage = "verification"))
  merged <- merge_run_context(defaults, override)

  defaults$meta$role <- "author"
  override$meta$stage <- "publication"

  expect_identical(merged$meta$role, "reviewer")
  expect_identical(merged$meta$stage, "verification")
})
