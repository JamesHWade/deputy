# The Commons specialists and their root, as the app and its tests use them.

# Base R has `%||%` only from R 4.4.0; Commons runs on R 4.1 and later.
`%||%` <- function(x, y) if (is.null(x)) y else x

commons_example_data <- function() {
  list(
    sales = data.frame(
      region = c("North", "South", "East", "West"),
      revenue = c(120, 95, 140, 80)
    ),
    shipments = data.frame(
      region = c("North", "South", "East", "West"),
      on_time = c(36, 30, 47, 24),
      shipped = c(40, 35, 50, 30)
    )
  )
}

# Counts every measure that runs, across sessions, so a restored conversation
# can be seen to run nothing.
commons_example_effects <- function() {
  effects <- new.env(parent = emptyenv())
  effects$runs <- 0L
  effects$by_measure <- list()
  effects
}

commons_example_table <- function(sales) {
  rows <- paste0(
    "<tr><td>",
    sales$region,
    "</td><td style=\"text-align:right\">",
    sales$revenue,
    "</td></tr>",
    collapse = ""
  )
  paste0(
    "<table class=\"table table-sm\"><thead><tr><th>Region</th>",
    "<th style=\"text-align:right\">Revenue</th></tr></thead><tbody>",
    rows,
    "</tbody></table>"
  )
}

commons_example_chart <- function(sales) {
  path <- tempfile(fileext = ".png")
  on.exit(unlink(path), add = TRUE)
  grDevices::png(path, width = 480, height = 300)
  graphics::par(mar = c(3, 4, 2, 1))
  graphics::barplot(
    sales$revenue,
    names.arg = sales$region,
    col = "#2f6f73",
    border = NA,
    main = "Revenue by region",
    ylab = "Revenue"
  )
  grDevices::dev.off()
  data <- jsonlite::base64_enc(readBin(path, "raw", file.size(path)))
  paste0(
    "<img src=\"data:image/png;base64,",
    gsub("\n", "", data, fixed = TRUE),
    "\" alt=\"Bar chart of revenue by region\" width=\"480\" height=\"300\"/>"
  )
}

commons_example_layer <- function(data, effects) {
  ran <- function(name) {
    effects$runs <- effects$runs + 1L
    effects$by_measure[[name]] <- (effects$by_measure[[name]] %||% 0L) + 1L
  }
  commons::semantic_layer(
    commons::measure(
      "total_revenue",
      "Total revenue across all regions.",
      function() {
        ran("total_revenue")
        sum(data$sales$revenue)
      }
    ),
    commons::measure(
      "revenue_by_region",
      "Revenue for each region, as a table.",
      function() {
        ran("revenue_by_region")
        ellmer::ContentToolResult(
          value = paste(
            data$sales$region,
            data$sales$revenue,
            sep = ": ",
            collapse = "; "
          ),
          extra = list(
            display = list(html = commons_example_table(data$sales))
          )
        )
      }
    ),
    commons::measure(
      "revenue_chart",
      "A bar chart of revenue by region.",
      function() {
        ran("revenue_chart")
        ellmer::ContentToolResult(
          value = "A bar chart of revenue by region; East is highest.",
          extra = list(
            display = list(html = commons_example_chart(data$sales))
          )
        )
      }
    ),
    commons::measure(
      "on_time_rate",
      "Share of shipments delivered on time.",
      function() {
        ran("on_time_rate")
        rate <- sum(data$shipments$on_time) / sum(data$shipments$shipped)
        paste0(round(100 * rate, 1), "%")
      }
    )
  )
}

# Build the model-free Commons 0.2.0 object once for the viewer.
commons_example_object <- function(data, layer) {
  commons::commons(
    data_sources = commons::data_source(
      sales = data$sales,
      shipments = data$shipments
    ),
    semantic_layer = layer
  )
}

# A specialist given the shared Commons tools so every specialist runs the
# same `commons_measure` producer and never sees arbitrary SQL or R tools.
commons_specialist <- function(fixture, role, tools, routes) {
  deputy::Agent$new(
    fixture$chat(role),
    system_prompt = paste(
      "Answer questions using only the approved Commons measures found with",
      "commons_search and run with commons_measure. If no approved calculation",
      "covers the question, report that no approved calculation covers it."
    ),
    tools = tools,
    permissions = deputy::Permissions(
      mode = "readonly",
      tool_allowlist = c(names(tools), routes)
    ),
    usage_limits = deputy::UsageLimits(max_requests = 8L, max_tool_calls = 6L),
    agent_name = role
  )
}

commons_example_workflow <- function(
  fixture,
  effects = commons_example_effects(),
  on_result = function(event) NULL,
  requester = "demo-user"
) {
  data <- commons_example_data()
  layer <- commons_example_layer(data, effects)
  # Build the Commons object and its tool bundle once so every specialist
  # shares the exact `commons_measure` tool named in TrustedResults().
  commons_obj <- commons_example_object(data, layer)
  tools <- deputy::tools_commons(commons_obj)
  disclosure <- deputy::DelegationDisclosure(
    authorize = function(candidate, scope) {
      identical(candidate, requester) &&
        identical(scope$owner_id, requester)
    }
  )
  delivered <- new.env(parent = emptyenv())
  delivered$events <- list()
  root <- deputy::Agent$new(
    fixture$chat("root"),
    system_prompt = paste(
      "COMMONS_ROOT: answer questions about sales and operations by asking",
      "the specialists, then summarize what they report. If no approved",
      "calculation covers a question, say so."
    ),
    # Every call in the graph is also checked against the root's permissions,
    # so the root allows the specialists' tools as well as its own routes.
    permissions = deputy::Permissions(
      mode = "readonly",
      tool_allowlist = c(names(tools), "ask_sales", "ask_ops", "ask_auditor")
    ),
    # One reply's budget covers the specialists it asks, too.
    usage_limits = deputy::UsageLimits(
      max_requests = 30L,
      max_tool_calls = 30L
    ),
    delegation_scope = list(owner_id = requester),
    delegation_disclosure = disclosure,
    trusted_results = deputy::TrustedResults(
      measure = tools$commons_measure,
      on_result = function(event) {
        delivered$events[[length(delivered$events) + 1L]] <- event
        on_result(event)
      }
    )
  )
  agents <- list(
    sales = commons_specialist(fixture, "sales", tools, "ask_auditor"),
    ops = commons_specialist(fixture, "ops", tools, character()),
    auditor = commons_specialist(fixture, "auditor", tools, character())
  )
  route <- function(target, description) {
    list(
      target = target,
      description = description,
      usage_limits = deputy::UsageLimits(max_requests = 8L)
    )
  }
  handles <- root$retain_agent_graph(
    agents = agents,
    routes = list(
      root = list(
        ask_sales = route("sales", "Ask the sales specialist."),
        ask_ops = route("ops", "Ask the operations specialist.")
      ),
      sales = list(
        ask_auditor = route("auditor", "Ask the auditor to check a figure.")
      )
    ),
    usage_limits = deputy::UsageLimits(
      max_requests = 60L,
      max_tool_calls = 40L
    ),
    max_depth = 2L,
    max_delegations = 30L,
    max_concurrency = 3L
  )
  list(
    root = root,
    agents = agents,
    handles = handles,
    commons = commons_obj,
    tools = tools,
    data = data,
    effects = effects,
    delivered = delivered,
    requester = requester
  )
}

# Short summary of what a measure returned, for the trusted-results table.
commons_example_trusted_value <- function(value) {
  if (inherits(value, "ellmer::ContentToolResult")) {
    value <- value@value
  }
  text <- paste(format(value), collapse = "\n")
  first <- trimws(sub("\n.*", "", text))
  substr(first, 1L, 80L)
}

commons_example_receipt_link <- function(event) {
  list(
    result_id = event$result_id %||% "",
    measure = event$arguments$name %||% event$tool_name %||% "",
    agent_name = event$agent_name %||% "root",
    delegation_id = event$delegation_id %||% "",
    tool_fingerprint = event$tool_fingerprint %||% "",
    value = commons_example_trusted_value(event$value)
  )
}

# The app's list of trusted results. The root's `on_result` runs outside any
# reactive context, so it reads the current list with `isolate()`; reading it
# directly would fail, and a failed delivery fails the tool call.
commons_example_results <- function(root = NULL) {
  results <- shiny::reactiveVal(list())
  records <- new.env(parent = emptyenv())
  records$root <- root
  records$by_conversation <- list()
  list(
    results = results,
    bind_root = function(agent) {
      records$root <- agent
      invisible(agent)
    },
    on_result = function(event) {
      results(c(shiny::isolate(results()), list(event)))
      conv_id <- if (!is.null(records$root)) {
        records$root$conversation_id
      } else {
        NULL
      }
      if (is.character(conv_id) && length(conv_id) == 1L && nzchar(conv_id)) {
        existing <- records$by_conversation[[conv_id]] %||% list()
        records$by_conversation[[conv_id]] <- c(
          existing,
          list(commons_example_receipt_link(event))
        )
      }
    },
    for_conversation = function(conv_id) {
      if (!is.character(conv_id) || length(conv_id) != 1L || !nzchar(conv_id)) {
        return(list())
      }
      records$by_conversation[[conv_id]] %||% list()
    }
  )
}

# Save and restore read-only receipt links alongside a shinychat conversation
# so reopening shows the same receipt IDs and producer links without running
# any model, measure, or delivery callback.
commons_example_receipt_history <- function(chat, root, trusted) {
  restored <- shiny::reactiveVal(list())
  state <- new.env(parent = emptyenv())
  state$restored <- list()
  state$conversation_id <- NULL

  merge_receipts <- function(existing, added) {
    combined <- c(existing, added)
    if (!length(combined)) {
      return(list())
    }
    ids <- vapply(
      combined,
      function(item) item$result_id %||% "",
      character(1)
    )
    combined[!duplicated(ids)]
  }

  chat$history$on_save(function(values) {
    conv_id <- root$conversation_id
    prior <- if (identical(state$conversation_id, conv_id)) {
      state$restored
    } else {
      list()
    }
    links <- merge_receipts(prior, trusted$for_conversation(conv_id))
    values$commons_receipt_links <- as.character(jsonlite::toJSON(
      links,
      auto_unbox = TRUE
    ))
    values
  })

  chat$history$on_restore(function(values) {
    raw <- values$commons_receipt_links
    links <- if (is.character(raw) && length(raw) == 1L && nzchar(raw)) {
      tryCatch(
        jsonlite::fromJSON(raw, simplifyVector = FALSE),
        error = function(error) list()
      )
    } else {
      list()
    }
    if (!is.list(links)) {
      links <- list()
    }
    state$conversation_id <- root$conversation_id
    state$restored <- links
    restored(links)
  })

  list(restored = restored)
}

commons_example_release <- function(workflow) {
  root <- workflow$root
  root$interrupt("session_ended")
  deadline <- Sys.time() + 5
  repeat {
    released <- isTRUE(tryCatch(
      {
        root$release_agent_graph()
        TRUE
      },
      error = function(error) FALSE
    ))
    if (released || Sys.time() > deadline) {
      break
    }
    later::run_now(0.05)
  }
  invisible(released)
}
