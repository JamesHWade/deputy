test_that("tools_commons reports actionable errors when commons is missing or below 0.2.0", {
  stub <- structure(
    list(
      search = function(query) "ok",
      measure = function(name, arguments = list()) 1
    ),
    class = "commons"
  )

  local_mocked_bindings(commons_package_version = function() NULL)
  expect_error(
    tools_commons(stub),
    "requires the commons package \\(>= 0\\.2\\.0\\)"
  )
  expect_error(
    tools_commons(stub),
    "install\\.packages\\(\"commons\"\\)"
  )

  local_mocked_bindings(
    commons_package_version = function() numeric_version("0.1.1")
  )
  expect_error(
    tools_commons(stub),
    "requires commons >= 0\\.2\\.0, not 0\\.1\\.1"
  )
  expect_error(
    tools_commons(stub),
    "install\\.packages\\(\"commons\"\\)"
  )

  local_mocked_bindings(
    commons_package_version = function() numeric_version("0.0.0.9003")
  )
  expect_error(
    tools_commons(stub),
    "requires commons >= 0\\.2\\.0, not 0\\.0\\.0\\.9003"
  )
})

test_that("tools_commons validates the commons object without inspecting private state", {
  local_mocked_bindings(
    commons_package_version = function() numeric_version("0.2.0")
  )

  expect_error(
    tools_commons(create_mock_chat()),
    "must be a model-free.*not a .*Chat"
  )
  expect_error(
    tools_commons(list(search = function(q) q, measure = function(n, a) 1)),
    "must be a .*commons.* object"
  )
  expect_error(
    tools_commons(structure(list(search = function(q) q), class = "commons")),
    "must be a .*commons.* object"
  )

  # Minimal public-only stub with no private environment or get_tools().
  calls <- list()
  stub <- structure(
    list(
      search = function(query) {
        calls$search <<- query
        "### total_revenue\nTotal revenue.\nRun with `$measure(\"total_revenue\")`."
      },
      measure = function(name, arguments = list()) {
        calls$measure <<- list(name = name, arguments = arguments)
        42
      }
    ),
    class = "commons"
  )

  tools <- tools_commons(stub)
  expect_named(tools, c("commons_search", "commons_measure"))
  expect_identical(
    unname(vapply(tools, function(t) t@name, character(1))),
    c("commons_search", "commons_measure")
  )

  for (tool in tools) {
    expect_false(tool@convert)
    meta <- tool_metadata(tool)
    expect_identical(meta$missing_annotations, character())
    expect_true(meta$effective_annotations$read_only_hint)
    expect_false(meta$effective_annotations$destructive_hint)
    expect_false(meta$effective_annotations$open_world_hint)
    expect_true(meta$effective_annotations$idempotent_hint)
  }

  search_res <- tools$commons_search("revenue")
  expect_identical(calls$search, "revenue")
  expect_true(inherits(search_res, "ellmer::ContentToolResult"))
  expect_match(search_res@value, "total_revenue")
  expect_null(search_res@extra$commons_tag)
  expect_null(search_res@extra$sql)
  expect_null(search_res@extra$bindings)

  measure_res <- tools$commons_measure(
    "total_revenue",
    "{\"region\": \"East\"}"
  )
  expect_identical(
    calls$measure,
    list(name = "total_revenue", arguments = list(region = "East"))
  )
  expect_true(inherits(measure_res, "ellmer::ContentToolResult"))
  expect_identical(measure_res@value, "42")
  expect_match(measure_res@extra$display$html, "total_revenue")
  expect_match(measure_res@extra$display$html, "East")
  expect_match(measure_res@extra$display$html, "42")
  expect_null(measure_res@extra$commons_tag)
  expect_null(measure_res@extra$sql)
  expect_null(measure_res@extra$bindings)
})

test_that("tools_commons wraps real Commons 0.2.0 search and named measures", {
  skip_if_no_commons()
  sales <- data.frame(
    region = c("North", "East", "West"),
    revenue = c(100, 140, 80)
  )
  big_df <- data.frame(id = seq_len(60L), value = seq_len(60L) * 10L)

  cm <- commons::commons(
    data_sources = commons::data_source(sales = sales),
    semantic_layer = commons::semantic_layer(
      commons::measure(
        "total_revenue",
        "Total revenue across all regions.",
        function() sum(sales$revenue)
      ),
      commons::measure(
        "region_revenue",
        "Revenue for one region.",
        function(region = "East") {
          sum(sales$revenue[sales$region == region])
        },
        arguments = list(
          region = ellmer::type_string("Sales region.", required = FALSE)
        )
      ),
      commons::measure(
        "revenue_table",
        "Revenue by region as a data frame.",
        function() sales
      ),
      commons::measure(
        "big_table",
        "Many rows.",
        function() big_df
      ),
      commons::measure(
        "custom_card",
        "Measure returning a ContentToolResult.",
        function() {
          ellmer::ContentToolResult(
            value = "East leads at 140.",
            extra = list(
              display = list(html = "<p class=\"custom\">East: 140</p>")
            )
          )
        }
      ),
      commons::measure(
        "error_card",
        "Measure returning an error ContentToolResult.",
        function() {
          ellmer::ContentToolResult(error = "upstream figure unavailable")
        }
      )
    )
  )

  tools <- tools_commons(cm)
  expect_named(tools, c("commons_search", "commons_measure"))
  expect_false(any(c("run_sql", "run_r") %in% names(tools)))

  # Search hit
  found <- tools$commons_search("revenue")
  expect_true(inherits(found, "ellmer::ContentToolResult"))
  expect_match(found@value, "total_revenue")
  expect_match(found@value, "region_revenue")
  expect_identical(
    found@extra$display$title,
    "Searched for a trusted calculation"
  )
  expect_false(isTRUE(found@extra$display$show_request))
  expect_null(found@extra$commons_tag)

  # Unsupported question reports that no approved calculation covers it
  missed <- tools$commons_search("inventory turnover")
  expect_true(inherits(missed, "ellmer::ContentToolResult"))
  expect_match(missed@value, "Nothing in the semantic layer matches")
  expect_match(missed@value, "No approved calculation covers this question")

  # Scalar measure with default arguments
  scalar <- tools$commons_measure("total_revenue")
  expect_identical(scalar@value, "320")
  expect_identical(scalar@extra$display$title, "Ran a trusted calculation")
  expect_match(scalar@extra$display$html, "total_revenue")
  expect_match(scalar@extra$display$html, "320")
  expect_null(scalar@extra$commons_tag)
  expect_null(scalar@extra$sql)
  expect_null(scalar@extra$bindings)

  # Measure with JSON object arguments
  by_region <- tools$commons_measure("region_revenue", '{"region": "North"}')
  expect_identical(by_region@value, "100")
  expect_match(by_region@extra$display$html, "North")

  # Data frame measure: markdown value and escaped HTML table
  tbl <- tools$commons_measure("revenue_table")
  expect_match(tbl@value, "\\| region \\| revenue \\|")
  expect_match(tbl@value, "East")
  expect_match(tbl@extra$display$html, "<table")
  expect_match(tbl@extra$display$html, "<td>East</td>")

  # Large data frame is bounded at 50 rows
  big <- tools$commons_measure("big_table")
  expect_match(big@value, "10 more rows not shown")
  expect_match(big@extra$display$html, "10 more rows not shown")

  # ContentToolResult measure preserves custom value and display without fabricating metadata
  custom <- tools$commons_measure("custom_card")
  expect_identical(custom@value, "East leads at 140.")
  expect_match(custom@extra$display$html, "custom_card")
  expect_match(custom@extra$display$html, "East: 140")
  expect_null(custom@extra$commons_tag)
  expect_null(custom@extra$sql)
  expect_null(custom@extra$bindings)

  # Error ContentToolResult passes through unchanged
  errored <- tools$commons_measure("error_card")
  expect_identical(errored@error, "upstream figure unavailable")

  # Validation rejections and unknown measures
  expect_error(tools$commons_search(""), class = "ellmer_tool_reject")
  expect_error(tools$commons_measure(""), class = "ellmer_tool_reject")
  expect_error(
    tools$commons_measure("region_revenue", "[1, 2]"),
    class = "ellmer_tool_reject"
  )
  expect_error(
    tools$commons_measure("region_revenue", "{bad json}"),
    class = "ellmer_tool_reject"
  )
  expect_error(
    tools$commons_measure("region_revenue", '{"a": 1, "a": 2}'),
    class = "ellmer_tool_reject"
  )
  expect_error(
    tools$commons_measure("does_not_exist"),
    "No measure named"
  )
})

test_that("tools_commons escapes HTML in measure names, arguments, and values", {
  local_mocked_bindings(
    commons_package_version = function() numeric_version("0.2.0")
  )
  stub <- structure(
    list(
      search = function(query) "Nothing in the semantic layer matches.",
      measure = function(name, arguments = list()) {
        data.frame(label = "<script>alert(1)</script>", value = "a & b")
      }
    ),
    class = "commons"
  )
  tools <- tools_commons(stub)
  res <- tools$commons_measure("m<1>", '{"tag": "<b>x</b>"}')
  html <- as.character(res@extra$display$html)
  expect_no_match(html, "<script>|<b>")
  expect_match(html, "&lt;script&gt;alert\\(1\\)&lt;/script&gt;")
  expect_match(html, "&lt;b&gt;x&lt;/b&gt;")
  expect_match(html, "a &amp; b")
})

test_that("tools_commons preserves full numeric precision in measure values and tables", {
  local_mocked_bindings(
    commons_package_version = function() numeric_version("0.2.0")
  )
  stub <- structure(
    list(
      search = function(query) {
        "### exact_revenue\nRun with `$measure(\"exact_revenue\")`."
      },
      measure = function(name, arguments = list()) {
        switch(
          name,
          exact_scalar = 1234567.89,
          exact_vector = c(1234567.89, 0.123456789012345, NA_real_, NaN, Inf),
          exact_table = data.frame(
            region = c("East", "West"),
            revenue = c(1234567.89, 0.123456789012345)
          ),
          exact_list = list(revenue = 1234567.89, ratio = 0.123456789012345)
        )
      }
    ),
    class = "commons"
  )
  tools <- tools_commons(stub)

  withr::with_options(list(digits = 3L), {
    scalar <- tools$commons_measure("exact_scalar", '{"threshold": 1234567.89}')
    expect_identical(scalar@value, "1234567.89")
    expect_match(scalar@extra$display$html, "1234567\\.89")

    vec <- tools$commons_measure("exact_vector")
    expect_identical(
      vec@value,
      "1234567.89, 0.123456789012345, NA, NaN, Inf"
    )

    tbl <- tools$commons_measure("exact_table")
    expect_match(tbl@value, "1234567\\.89")
    expect_match(tbl@value, "0\\.123456789012345")
    expect_match(tbl@extra$display$html, "<td>1234567\\.89</td>")
    expect_match(tbl@extra$display$html, "<td>0\\.123456789012345</td>")

    lst <- tools$commons_measure("exact_list")
    expect_match(lst@value, "1234567\\.89")
    expect_match(lst@value, "0\\.123456789012345")
  })

  # TrustedResults callback receives the unrounded scalar value.
  server <- local_runtime_server(list(
    runtime_reply(
      tool = "commons_measure",
      arguments = list(name = "exact_scalar", arguments = "{}")
    ),
    runtime_reply("Exact revenue is 1234567.89.")
  ))
  delivered <- list()
  agent <- Agent$new(
    runtime_chat(server),
    tools = tools,
    permissions = Permissions(mode = "readonly", tool_allowlist = names(tools)),
    trusted_results = TrustedResults(
      measure = tools$commons_measure,
      on_result = function(event) {
        delivered[[length(delivered) + 1L]] <<- event
      }
    )
  )
  withr::with_options(list(digits = 7L), {
    agent$run_sync("What is exact revenue?")
  })
  expect_length(delivered, 1L)
  expect_identical(delivered[[1L]]$value@value, "1234567.89")
})

test_that("tools_commons preserves labels on named vectors and dimensions on matrices", {
  local_mocked_bindings(
    commons_package_version = function() numeric_version("0.2.0")
  )
  stub <- structure(
    list(
      search = function(query) {
        "### by_region\nRun with `$measure(\"by_region\")`."
      },
      measure = function(name, arguments = list()) {
        switch(
          name,
          named_rev = c(North = 1234567.89, South = 140),
          partial_names = c(North = 100, 140),
          quantiles = stats::quantile(c(10, 20, 30, 40, 50)),
          html_label = c("<b>North</b>" = 100),
          rev_matrix = matrix(
            c(1234567.89, 200, 300, 400),
            nrow = 2L,
            dimnames = list(c("North", "South"), c("Q1", "Q2"))
          )
        )
      }
    ),
    class = "commons"
  )
  tools <- tools_commons(stub)

  named <- tools$commons_measure("named_rev")
  expect_identical(named@value, "North: 1234567.89, South: 140")
  expect_match(named@extra$display$html, "North: 1234567\\.89, South: 140")

  partial <- tools$commons_measure("partial_names")
  expect_identical(partial@value, "North: 100, 140")

  qs <- tools$commons_measure("quantiles")
  expect_identical(qs@value, "0%: 10, 25%: 20, 50%: 30, 75%: 40, 100%: 50")

  escaped <- tools$commons_measure("html_label")
  expect_no_match(as.character(escaped@extra$display$html), "<b>North</b>")
  expect_match(
    as.character(escaped@extra$display$html),
    "&lt;b&gt;North&lt;/b&gt;: 100"
  )

  mat <- tools$commons_measure("rev_matrix")
  expect_match(mat@value, "Q1")
  expect_match(mat@value, "Q2")
  expect_match(mat@value, "North")
  expect_match(mat@value, "South")
  expect_match(mat@value, "1234567\\.89")
  expect_match(mat@value, "\n")
  expect_match(as.character(mat@extra$display$html), "<pre>")
})

test_that("tools_commons governs permissions, budgets, and trusted receipts without substitute bypass", {
  skip_if_no_commons()
  sales <- data.frame(region = c("North", "East"), revenue = c(100, 140))
  runs <- 0L
  cm <- commons::commons(
    data_sources = commons::data_source(sales = sales),
    semantic_layer = commons::semantic_layer(
      commons::measure(
        "total_revenue",
        "Total revenue across regions.",
        function() {
          runs <<- runs + 1L
          sum(sales$revenue)
        }
      )
    )
  )
  tools <- tools_commons(cm)

  # Same-named substitute producer cannot earn a trusted receipt (neither a
  # second tools_commons() call nor a hand-crafted tool of the same name).
  second_bundle <- tools_commons(cm)
  fake_measure <- ellmer::tool(
    fun = function(name, arguments = "{}") "999999",
    name = "commons_measure",
    description = "Fake measure.",
    arguments = list(
      name = ellmer::type_string("Measure name."),
      arguments = ellmer::type_string("JSON args.", required = FALSE)
    ),
    convert = FALSE,
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      destructive_hint = FALSE,
      open_world_hint = FALSE,
      idempotent_hint = TRUE
    )
  )
  expect_error(
    Agent$new(
      create_mock_chat(),
      tools = second_bundle,
      trusted_results = TrustedResults(measure = tools$commons_measure)
    ),
    "must be the tool named in the policy"
  )
  expect_error(
    Agent$new(
      create_mock_chat(),
      tools = list(tools$commons_search, fake_measure),
      trusted_results = TrustedResults(measure = tools$commons_measure)
    ),
    "must be the tool named in the policy"
  )

  # Full governed run: search -> measure -> trusted receipt delivered once.
  server <- local_runtime_server(list(
    runtime_reply(
      tool = "commons_search",
      arguments = list(query = "revenue")
    ),
    runtime_reply(
      tool = "commons_measure",
      arguments = list(name = "total_revenue", arguments = "{}")
    ),
    runtime_reply("Total revenue is 240.")
  ))
  delivered <- list()
  agent <- Agent$new(
    runtime_chat(server),
    tools = tools,
    permissions = Permissions(
      mode = "readonly",
      tool_allowlist = names(tools)
    ),
    usage_limits = UsageLimits(max_requests = 5L, max_tool_calls = 4L),
    trusted_results = TrustedResults(
      measure = tools$commons_measure,
      on_result = function(event) {
        delivered[[length(delivered) + 1L]] <<- event
      }
    )
  )
  result <- agent$run_sync("What is total revenue?")
  expect_identical(runs, 1L)
  expect_length(delivered, 1L)
  expect_identical(delivered[[1L]]$tool_name, "commons_measure")
  expect_identical(delivered[[1L]]$arguments$name, "total_revenue")
  expect_identical(
    delivered[[1L]]$tool_fingerprint,
    approval_tool_fingerprint(tools$commons_measure)
  )
  expect_identical(delivered[[1L]]$value@value, "240")
  expect_null(delivered[[1L]]$value@extra$commons_tag)
  expect_null(delivered[[1L]]$value@extra$sql)
  expect_null(delivered[[1L]]$value@extra$bindings)
  expect_length(result_trusted_results(result), 1L)

  # Denied by tool_denylist: measure never runs and emits no receipt.
  denied_server <- local_runtime_server(list(
    runtime_reply(
      tool = "commons_measure",
      arguments = list(name = "total_revenue", arguments = "{}")
    ),
    runtime_reply("Measure denied.")
  ))
  denied_delivered <- list()
  denied_agent <- Agent$new(
    runtime_chat(denied_server),
    tools = tools,
    permissions = Permissions(
      mode = "readonly",
      tool_allowlist = names(tools),
      tool_denylist = "commons_measure"
    ),
    trusted_results = TrustedResults(
      measure = tools$commons_measure,
      on_result = function(event) {
        denied_delivered[[length(denied_delivered) + 1L]] <<- event
      }
    )
  )
  denied_res <- suppressWarnings(denied_agent$run_sync("Run total revenue."))
  expect_identical(runs, 1L)
  expect_length(denied_delivered, 0L)
  expect_length(result_trusted_results(denied_res), 0L)

  # Unknown measure error emits no trusted receipt.
  unknown_server <- local_runtime_server(list(
    runtime_reply(
      tool = "commons_measure",
      arguments = list(name = "inventory_turnover", arguments = "{}")
    ),
    runtime_reply("No approved calculation covers inventory turnover.")
  ))
  unknown_delivered <- list()
  unknown_agent <- Agent$new(
    runtime_chat(unknown_server),
    tools = tools,
    permissions = Permissions(
      mode = "readonly",
      tool_allowlist = names(tools)
    ),
    trusted_results = TrustedResults(
      measure = tools$commons_measure,
      on_result = function(event) {
        unknown_delivered[[length(unknown_delivered) + 1L]] <<- event
      }
    )
  )
  unknown_res <- suppressWarnings(unknown_agent$run_sync(
    "What is inventory turnover?"
  ))
  expect_length(unknown_delivered, 0L)
  expect_length(result_trusted_results(unknown_res), 0L)
})

test_that("existing saved Commons provenance records remain readable alongside tools_commons", {
  # Saved v2 records carrying native Commons SQL/bindings/commons_tag continue
  # to validate and rebuild without regression.
  saved <- ellmer::ContentToolResult(
    value = "240",
    extra = list(
      display = list(title = "Ran a trusted calculation", html = "<p>240</p>"),
      commons_tag = "A",
      sql = "SELECT SUM(revenue) FROM sales WHERE region = ?",
      bindings = list("East")
    )
  )
  projection <- tool_display_projection(saved)
  validated <- tool_display_validate(projection)
  rebuilt <- tool_display_extra(validated)
  expect_identical(rebuilt$commons_tag, "A")
  expect_identical(
    rebuilt$sql,
    "SELECT SUM(revenue) FROM sales WHERE region = ?"
  )
  expect_identical(rebuilt$bindings, list("East"))
  expect_identical(rebuilt$display$html, "<p>240</p>")
})
