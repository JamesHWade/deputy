# The Commons specialists and their root, as the app and its tests use them.

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
  grDevices::png(path, width = 480, height = 300, type = "cairo")
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

commons_example_chat <- function(fixture, role, data, layer) {
  commons::commons(
    fixture$chat(role),
    data_sources = commons::data_source(
      sales = data$sales,
      shipments = data$shipments
    ),
    semantic_layer = layer
  )
}

# Commons as it ships also has `run_sql` and `run_r`, which compute anything
# the model asks for and so could stand in for a trusted measure. Keep only
# the pool search and the measures, and mark them closed-world: they read the
# data frames given to Commons and nothing else.
commons_strict_tools <- function(pool) {
  tools <- pool$get_tools()[c("search_pool", "call_measure")]
  lapply(tools, function(tool) {
    tool@annotations$open_world_hint <- FALSE
    tool
  })
}

# A Commons specialist: an actual Commons chat, given the shared strict tools
# so that every specialist runs the same `call_measure`.
commons_specialist <- function(fixture, role, data, layer, tools, routes) {
  chat <- commons_example_chat(fixture, role, data, layer)
  chat$set_tools(tools)
  deputy::Agent$new(
    chat,
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
  # The pool defines the one `call_measure` every specialist uses; it never
  # answers a question itself.
  pool <- commons_example_chat(fixture, "pool", data, layer)
  tools <- commons_strict_tools(pool)
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
      "the specialists, then summarize what they report."
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
      measure = tools$call_measure,
      on_result = function(event) {
        delivered$events[[length(delivered$events) + 1L]] <- event
        on_result(event)
      }
    )
  )
  agents <- list(
    sales = commons_specialist(
      fixture,
      "sales",
      data,
      layer,
      tools,
      "ask_auditor"
    ),
    ops = commons_specialist(fixture, "ops", data, layer, tools, character()),
    auditor = commons_specialist(
      fixture,
      "auditor",
      data,
      layer,
      tools,
      character()
    )
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
    pool = pool,
    tools = tools,
    data = data,
    effects = effects,
    delivered = delivered,
    requester = requester
  )
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
