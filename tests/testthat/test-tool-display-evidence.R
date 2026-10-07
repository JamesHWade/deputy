display_policy <- function() {
  DelegationDisclosure(
    authorize = function(requester, scope) identical(requester, "owner")
  )
}

display_tool_result <- function(...) {
  ellmer::ContentToolResult(
    value = "60",
    extra = list(
      display = list(
        title = "Ran a trusted calculation",
        html = "<div class=\"measure\"><strong>60</strong></div>",
        show_request = FALSE,
        ...
      ),
      commons_tag = "A",
      private_provider = list(signature = "secret")
    )
  )
}

display_tool <- function() {
  ellmer::tool(
    function() display_tool_result(),
    name = "call_measure",
    description = "Run a registered measure.",
    annotations = ellmer::tool_annotations(
      read_only_hint = TRUE,
      open_world_hint = FALSE
    )
  )
}

display_lead <- function(server) {
  LeadAgent$new(
    runtime_chat(server),
    sub_agents = list(agent_definition(
      "analyst",
      "Runs measures",
      "ANALYST",
      tools = list(display_tool())
    )),
    delegation_disclosure = display_policy()
  )
}

display_results <- function(turns) {
  Filter(
    function(content) inherits(content, "ellmer::ContentToolResult"),
    unlist(lapply(turns, function(turn) turn@contents), recursive = FALSE)
  )
}

test_that("approved display and provenance fields survive projection", {
  projection <- tool_display_projection(display_tool_result(
    footer = htmltools::tags$small("From the ", htmltools::tags$em("registry")),
    label = "Revenue",
    unknown_field = "x"
  ))
  expect_identical(projection$format, "deputy_tool_display")
  expect_identical(projection$version, 1L)
  expect_identical(projection$display$title, "Ran a trusted calculation")
  expect_identical(
    projection$display$html,
    "<div class=\"measure\"><strong>60</strong></div>"
  )
  expect_match(projection$display$footer, "<em>registry</em>", fixed = TRUE)
  expect_false(projection$display$show_request)
  expect_identical(projection$display$label, "Revenue")
  expect_identical(projection$provenance, list(commons_tag = "A"))
  expect_identical(projection$omitted$extra, "private_provider")
  expect_identical(projection$omitted$display_fields, "unknown_field")
  expect_no_match(
    paste(deparse(projection), collapse = ""),
    "secret",
    fixed = TRUE
  )
  expect_identical(tool_display_validate(projection), projection)
  expect_identical(
    tool_display_extra(projection),
    list(
      display = projection$display,
      commons_tag = "A"
    )
  )
  expect_null(tool_display_projection(ellmer::ContentToolResult("plain")))
})

test_that("display projection bounds sizes and refuses executable objects", {
  dependency <- htmltools::htmlDependency(
    "measure-css",
    "1.2.0",
    src = c(href = "https://example.invalid")
  )
  result <- ellmer::ContentToolResult(
    value = "x",
    extra = list(
      display = list(
        html = strrep("x", 2 * 1024^2 + 1),
        icon = htmltools::tagList(htmltools::tags$span("i"), dependency),
        footer = function() "footer",
        label = c("too", "many"),
        open = "yes",
        open_style = "popup"
      ),
      commons_tag = "not a tag!"
    )
  )
  projection <- tool_display_projection(result)
  expect_identical(projection$display$icon, "<span>i</span>")
  expect_identical(projection$omitted$dependencies, "measure-css 1.2.0")
  expect_identical(
    projection$omitted$fields,
    c(
      html = "oversized",
      footer = "unsupported_object",
      label = "invalid",
      open = "invalid",
      open_style = "invalid"
    )
  )
  expect_identical(projection$omitted$provenance, "commons_tag")
  expect_identical(projection$provenance, list())
  expect_identical(tool_display_validate(projection), projection)

  widget <- structure(list(), class = c("htmlwidget", "list"))
  projection <- tool_display_projection(ellmer::ContentToolResult(
    "x",
    extra = list(display = list(html = widget))
  ))
  expect_identical(projection$omitted$fields, c(html = "unsupported_object"))
  projection <- tool_display_projection(ellmer::ContentToolResult(
    "x",
    extra = list(display = htmltools::tags$div("not a display list"))
  ))
  expect_identical(projection$omitted$display, "invalid")
  # shinychat's class on something other than a list, or beside another
  # class, isn't a display either.
  for (display in list(
    structure(new.env(), class = "shinychat_tool_result_display"),
    structure(
      methods::new("externalptr"),
      class = "shinychat_tool_result_display"
    ),
    structure(
      list(title = "x"),
      class = c("other", "shinychat_tool_result_display")
    )
  )) {
    projection <- tool_display_projection(ellmer::ContentToolResult(
      "x",
      extra = list(display = display)
    ))
    expect_identical(projection$omitted$display, "invalid")
  }
  projection <- tool_display_projection(ellmer::ContentToolResult(
    "x",
    extra = list(
      display = structure(
        list(title = "Ran"),
        class = "shinychat_tool_result_display"
      )
    )
  ))
  expect_identical(projection$display$title, "Ran")
})

test_that("saved display records are validated before replay", {
  projection <- tool_display_projection(display_tool_result())
  future <- projection
  future$version <- 2L
  expect_null(tool_display_validate(future))
  tampered <- list(
    function(x) {
      x$display$html <- list("<b>")
      x
    },
    function(x) {
      x$display$onclick <- "alert(1)"
      x
    },
    function(x) {
      x$provenance$commons_tag <- "<script>"
      x
    },
    function(x) {
      x$provenance$signature <- "A"
      x
    },
    function(x) {
      x$display$label <- strrep("x", 2000)
      x
    },
    function(x) {
      x$omitted$fields <- c("oversized")
      x
    },
    function(x) {
      x$format <- "other"
      x
    },
    function(x) {
      x$extra <- list()
      x
    }
  )
  for (change in tampered) {
    expect_error(
      tool_display_validate(change(projection)),
      "Invalid tool display"
    )
  }
})

test_that("child tool displays survive inspection, export and replay", {
  server <- local_runtime_server(list(
    runtime_reply(
      tool = "delegate_to_agent",
      arguments = list(agent_name = "analyst", task = "Revenue?")
    ),
    runtime_reply(tool = "call_measure"),
    runtime_reply("Revenue is 60."),
    runtime_reply("Lead: 60.")
  ))
  lead <- display_lead(server)
  lead$run_sync("Revenue?")

  view <- lead$inspect_subagents("owner", transcript = TRUE)[[1L]]
  result <- display_results(view$turns)[[1L]]
  expect_identical(result@extra$commons_tag, "A")
  expect_identical(result@extra$display$title, "Ran a trusted calculation")
  expect_named(result@extra, c("display", "commons_tag"))
  record <- Filter(
    function(content) identical(content$class, "ellmer::ContentToolResult"),
    unlist(
      lapply(view$transcript, function(turn) turn$props$contents),
      recursive = FALSE
    )
  )[[1L]]
  expect_identical(record$props$extra, list())
  expect_identical(record$deputy_display$omitted$extra, "private_provider")

  snapshot <- lead$observe_subagents("owner")$snapshot(transcript = TRUE)
  observed <- snapshot$children[[1L]]$transcript
  expect_match(
    paste(deparse(observed), collapse = ""),
    "Ran a trusted calculation",
    fixed = TRUE
  )

  history <- unserialize(serialize(lead$export_subagents("owner"), NULL))
  expect_no_match(
    paste(deparse(history), collapse = ""),
    "secret",
    fixed = TRUE
  )
  replayed <- delegation_history(
    history,
    "owner",
    display_policy(),
    history$scope
  )
  restored <- display_results(replayed[[1L]]$turns)[[1L]]
  expect_identical(restored@extra, result@extra)
  expect_identical(restored@request@name, "call_measure")
  expect_null(restored@request@tool)

  tamper <- function(history, change) {
    for (turn in seq_along(history$children[[1L]]$transcript)) {
      contents <- history$children[[1L]]$transcript[[turn]]$props$contents
      for (index in seq_along(contents)) {
        if (!is.null(contents[[index]]$deputy_display)) {
          contents[[index]]$deputy_display <- change(
            contents[[index]]$deputy_display
          )
        }
      }
      history$children[[1L]]$transcript[[turn]]$props$contents <- contents
    }
    history
  }
  broken <- tamper(history, function(display) {
    display$display$html <- 1
    display
  })
  expect_error(
    delegation_history(broken, "owner", display_policy(), history$scope),
    "Invalid tool display"
  )
  newer <- tamper(history, function(display) {
    display$version <- 9L
    display
  })
  replayed <- delegation_history(
    newer,
    "owner",
    display_policy(),
    history$scope
  )
  expect_identical(display_results(replayed[[1L]]$turns)[[1L]]@extra, list())
})

test_that("observed content keeps its display within the event bound", {
  small <- observation_payload(AgentEvent(
    "content",
    content = display_tool_result(),
    content_type = "ellmer::ContentToolResult"
  ))
  expect_identical(
    small$content$deputy_display$display$title,
    "Ran a trusted calculation"
  )
  expect_identical(small$content$props$extra, list())
  # A display larger than one event is left to the snapshot, as other large
  # content is: the buffer checks the projected payload against its bound.
  large <- display_tool_result()
  large@extra$display$html <- strrep("x", 70000)
  payload <- observation_payload(AgentEvent(
    "content",
    content = large,
    content_type = "ellmer::ContentToolResult"
  ))
  expect_identical(nchar(payload$content$deputy_display$display$html), 70000L)
  expect_false(observation_payload_fits(payload, 65536))
})

test_that("tags with render hooks are never rendered", {
  ran <- FALSE
  hooked <- htmltools::tagAddRenderHook(
    htmltools::div("60"),
    function(tag) {
      ran <<- TRUE
      tag
    }
  )
  result <- ellmer::ContentToolResult(
    value = "60",
    extra = list(display = list(title = "Measure", html = hooked))
  )
  projection <- tool_display_projection(result)
  expect_false(ran)
  expect_null(projection$display$html)
  expect_identical(projection$display$title, "Measure")
  expect_identical(
    projection$omitted$fields,
    c(html = "unsupported_object")
  )
  nested <- htmltools::tags$section(hooked)
  result@extra$display$html <- nested
  projection <- tool_display_projection(result)
  expect_false(ran)
  expect_null(projection$display$html)
})

test_that("a tag tree whose text is over its field's limit isn't rendered", {
  rendered <- 0L
  local_mocked_bindings(tool_display_render_tags = function(value) {
    rendered <<- rendered + 1L
    htmltools::renderTags(value)
  })
  over <- 2 * 1024^2 + 1
  result <- ellmer::ContentToolResult(
    value = "60",
    extra = list(
      display = list(
        title = "Measure",
        html = htmltools::div(htmltools::span(strrep("&", over)))
      )
    )
  )
  projection <- tool_display_projection(result)
  expect_null(projection$display$html)
  expect_identical(projection$omitted$fields, c(html = "oversized"))
  # The title rendered; the oversized body never was.
  expect_identical(rendered, 0L)
  # Text in attributes counts too.
  result@extra$display$html <- htmltools::div(title = strrep("x", over))
  expect_identical(
    tool_display_projection(result)$omitted$fields,
    c(html = "oversized")
  )
  expect_identical(rendered, 0L)
  result@extra$display$html <- htmltools::div("60")
  projection <- tool_display_projection(result)
  expect_identical(projection$display$html, "<div>60</div>")
  expect_identical(rendered, 1L)
})

test_that("classed objects in a display never run their methods", {
  ran <- new.env()
  ran$calls <- character()
  method <- function(generic, value) {
    force(value)
    function(x, ...) {
      ran$calls <- c(ran$calls, generic)
      value
    }
  }
  local_mocked_s3_method("$", "deputy_test_object", method("$", "div"))
  local_mocked_s3_method(
    "names",
    "deputy_test_object",
    method("names", c("name", "attribs", "children"))
  )
  local_mocked_s3_method("length", "deputy_test_object", method("length", 1L))
  local_mocked_s3_method("is.na", "deputy_test_object", method("is.na", FALSE))
  classed <- function(x) {
    class(x) <- c("deputy_test_object", class(x))
    x
  }
  dependency <- htmltools::htmlDependency(
    "measure",
    "1.0",
    src = c(file = tempdir())
  )
  result <- ellmer::ContentToolResult(
    value = "60",
    extra = list(
      display = list(
        title = classed("Measure"),
        html = classed(htmltools::div("60")),
        footer = htmltools::tagList(htmltools::span("ok"), classed(dependency)),
        show_request = classed(TRUE),
        markdown = "Plain text stays."
      ),
      commons_tag = classed("A")
    )
  )
  projection <- tool_display_projection(result)
  expect_identical(ran$calls, character())
  expect_identical(projection$display, list(markdown = "Plain text stays."))
  expect_identical(
    projection$omitted$fields,
    c(
      title = "invalid",
      html = "unsupported_object",
      footer = "unsupported_object",
      show_request = "invalid"
    )
  )
  expect_identical(projection$omitted$provenance, "commons_tag")
  # Plain tags, html strings and dependencies are still rendered.
  result@extra <- list(
    display = list(
      title = htmltools::HTML("<b>Measure</b>"),
      footer = htmltools::tagList(htmltools::span("ok"), dependency)
    )
  )
  projection <- tool_display_projection(result)
  expect_identical(projection$display$title, "<b>Measure</b>")
  expect_match(projection$display$footer, "<span>ok</span>", fixed = TRUE)
})

test_that("a Commons display and tag survive retained inspection", {
  skip_if_not_installed("commons")
  skip_if_not_installed("shinychat")
  root_server <- local_runtime_server(list(
    runtime_reply(tool = "ask_sales", arguments = list(task = "Revenue?")),
    runtime_reply("Lead: revenue is 60.")
  ))
  sales_server <- local_runtime_server(list(
    runtime_reply(
      tool = "call_measure",
      arguments = list(name = "total_revenue", arguments = "{}")
    ),
    runtime_reply("Total revenue is 60.")
  ))
  sales <- data.frame(region = c("north", "south"), revenue = c(25, 35))
  analyst <- commons::commons(
    runtime_chat(sales_server),
    data_sources = commons::data_source(sales = sales),
    semantic_layer = commons::semantic_layer(commons::measure(
      "total_revenue",
      "Total revenue across regions.",
      function() sum(sales$revenue),
      arguments = list()
    ))
  )
  kept <- analyst$get_tools()[c("search_pool", "call_measure")]
  kept <- lapply(kept, function(tool) {
    tool@annotations$open_world_hint <- FALSE
    tool
  })
  analyst$set_tools(kept)
  root <- Agent$new(
    runtime_chat(root_server),
    delegation_disclosure = display_policy()
  )
  handle <- adopt_chat(
    analyst,
    root,
    permissions = Permissions(
      mode = "readonly",
      tool_allowlist = c("search_pool", "call_measure")
    ),
    usage_limits = UsageLimits(max_requests = 4),
    history = "fresh",
    callbacks = "replace",
    name = "sales"
  )
  root$register_tool(delegation_tool(
    root,
    handle,
    "ask_sales",
    "Ask the sales specialist.",
    UsageLimits(max_requests = 4)
  ))
  root$run_sync("Revenue?")
  history <- root$export_subagents("owner")
  replayed <- delegation_history(
    history,
    "owner",
    display_policy(),
    history$scope
  )
  result <- display_results(replayed[[1L]]$turns)[[1L]]
  expect_identical(result@extra$commons_tag, "A")
  expect_identical(result@extra$display$title, "Ran a trusted calculation")
  expect_match(
    result@extra$display$html,
    "commons-measure-result-value",
    fixed = TRUE
  )
  # Commons draws icons only when bsicons is installed.
  if (rlang::is_installed("bsicons")) {
    expect_match(result@extra$display$icon, "<svg", fixed = TRUE)
  } else {
    expect_null(result@extra$display$icon)
  }
})
