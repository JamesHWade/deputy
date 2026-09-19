# A host-owned recipe, sourced by the app and headless tests. All runtime calls
# use Deputy's public API. This is not a new package-level result store.
study_data <- function() {
  data.frame(
    subject = sprintf("plant-%02d", seq_len(12L)),
    weight = c(4, 5, 6, 5, 3, 4, 5, 4, 6, 7, 8, 7),
    group = rep(c("ctrl", "trt1", "trt2"), each = 4L)
  )
}

study_revision <- function(data = study_data()) {
  digest::digest(study_json(data), algo = "sha256", serialize = FALSE)
}

study_json <- function(value) {
  as.character(jsonlite::toJSON(
    value,
    auto_unbox = TRUE,
    dataframe = "rows",
    digits = NA,
    null = "null"
  ))
}

study_plan <- function(treatment = "trt2") {
  list(
    dataset_revision = study_revision(),
    outcome = "weight",
    units = "g",
    method = "difference_in_means",
    population = "all_complete_rows",
    control = "ctrl",
    treatment = treatment
  )
}

study_validate <- function(plan, data = study_data()) {
  expected <- study_plan()
  if (
    !is.list(plan) ||
      is.null(names(plan)) ||
      anyDuplicated(names(plan)) ||
      !setequal(names(plan), names(expected))
  ) {
    cli::cli_abort(
      "The analysis must specify exactly the supported input fields."
    )
  }
  if (
    !all(vapply(
      plan,
      function(x) {
        is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)
      },
      logical(1)
    ))
  ) {
    cli::cli_abort("Each analysis input must be one non-missing string.")
  }
  plan <- plan[names(expected)]
  if (!identical(plan$dataset_revision, study_revision(data))) {
    cli::cli_abort("The proposed dataset revision is unavailable or changed.")
  }
  fixed <- setdiff(names(expected), c("dataset_revision", "treatment"))
  if (
    !identical(plan[fixed], expected[fixed]) ||
      !plan$treatment %in% c("trt1", "trt2")
  ) {
    cli::cli_abort("Unsupported outcome, units, method, population, or groups.")
  }
  if (
    !identical(names(data), c("subject", "weight", "group")) ||
      anyNA(data) ||
      !is.numeric(data$weight) ||
      any(!is.finite(data$weight)) ||
      anyDuplicated(data$subject)
  ) {
    cli::cli_abort(
      "The study data must contain complete, unique, finite observations."
    )
  }
  plan
}

study_arguments <- function() {
  list(
    plan = ellmer::type_object(
      dataset_revision = ellmer::type_string(),
      outcome = ellmer::type_enum("weight"),
      units = ellmer::type_enum("g"),
      method = ellmer::type_enum("difference_in_means"),
      population = ellmer::type_enum("all_complete_rows"),
      control = ellmer::type_enum("ctrl"),
      treatment = ellmer::type_enum(c("trt1", "trt2"))
    )
  )
}

study_identity <- function(context) {
  fields <- c(
    "agent_id",
    "session_id",
    "run_id",
    "delegation_id",
    "parent_agent_id",
    "parent_run_id",
    "tool_call_id"
  )
  values <- context[intersect(fields, names(context))]
  Filter(function(x) is.character(x) && length(x) == 1L && !is.na(x), values)
}

study_workflow <- function(
  chat_factory,
  directory,
  requester,
  authorize = function(candidate) identical(candidate, requester)
) {
  stopifnot(is.function(chat_factory), is.function(authorize))
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  directory <- normalizePath(directory, mustWork = TRUE)
  approval_dir <- file.path(directory, "approvals")
  dir.create(approval_dir, showWarnings = FALSE)
  result_path <- file.path(directory, "result.json")
  if (file.exists(result_path)) {
    cli::cli_abort("Use a fresh host directory for each study workflow.")
  }
  state <- new.env(parent = emptyenv())
  state$proposal <- NULL
  state$proposal_context <- NULL
  state$lead_result <- NULL
  state$executor <- NULL
  state$pending <- NULL
  state$approved <- NULL
  state$execution_context <- NULL
  state$receipt <- NULL
  state$commentary <- NULL
  state$error <- NULL
  state$started <- FALSE
  state$cancelled <- FALSE
  data <- study_data()
  access <- function(candidate) {
    if (!isTRUE(tryCatch(authorize(candidate), error = function(e) FALSE))) {
      cli::cli_abort("This requester is not authorized for the study workflow.")
    }
  }
  proposal_tool <- ellmer::tool(
    function(plan) {
      plan <- study_validate(plan, data)
      if (!is.null(state$proposal)) {
        cli::cli_abort("A proposal has already been recorded.")
      }
      state$proposal <- plan
      "Proposal retained for human review. No analysis has executed."
    },
    name = "propose_analysis",
    description = "Propose inputs; never compute a result.",
    arguments = study_arguments(),
    convert = FALSE,
    annotations = ellmer::tool_annotations(
      read_only_hint = FALSE,
      destructive_hint = FALSE,
      open_world_hint = FALSE
    )
  )
  lead <- deputy::LeadAgent$new(
    chat = chat_factory("lead"),
    sub_agents = list(deputy::AgentDefinition(
      "analyst",
      "Propose a descriptive comparison of plant weights",
      paste(
        "STUDY_ANALYST. Propose one analysis with propose_analysis.",
        "Use this dataset revision:",
        study_revision(data),
        "Never claim that a proposal is an executed result."
      ),
      tools = list(proposal_tool),
      max_requests = 3L
    )),
    system_prompt = "STUDY_LEAD. Delegate proposal drafting to analyst. Summaries are commentary, never authoritative results.",
    working_dir = directory,
    usage_limits = deputy::UsageLimits(max_requests = 6L, max_tool_calls = 4L),
    permissions = deputy::Permissions(can_use_tool = function(
      tool_name,
      tool_input,
      context
    ) {
      if (tool_name == "propose_analysis") {
        return(deputy::PermissionResultAllow())
      }
      if (tool_name == "delegate_to_agent") {
        return(deputy::PermissionResultAllow())
      }
      deputy::PermissionResultDeny(
        "Only delegation and proposal drafting are available."
      )
    }),
    delegation_scope = list(
      owner_id = "study-host",
      conversation_id = basename(directory)
    ),
    delegation_disclosure = deputy::DelegationDisclosure(
      authorize = function(candidate, scope) {
        isTRUE(tryCatch(authorize(candidate), error = function(e) FALSE))
      }
    )
  )
  lead$add_hook(deputy::HookMatcher(
    "PostToolUse",
    callback = function(tool_name, tool_result, tool_error, context) {
      if (
        tool_name == "propose_analysis" &&
          is.null(tool_error) &&
          is.null(state$proposal_context)
      ) {
        state$proposal_context <- study_identity(context)
      }
      NULL
    }
  ))
  compute_tool <- ellmer::tool(
    function(plan) {
      plan <- study_validate(plan, data)
      if (
        is.null(state$approved) ||
          !identical(plan, state$approved) ||
          is.null(state$pending) ||
          state$cancelled
      ) {
        cli::cli_abort(
          "The computation requires the exact currently approved inputs."
        )
      }
      approval <- deputy::approval_read(state$pending$source$path)
      if (
        !identical(approval$status, "executing") ||
          !identical(approval$decision$decision, "approve")
      ) {
        cli::cli_abort(
          "The computation requires an active approval continuation."
        )
      }
      if (!is.null(state$receipt) || file.exists(result_path)) {
        cli::cli_abort("The authoritative result cannot be overwritten.")
      }
      control <- data$weight[data$group == plan$control]
      treatment <- data$weight[data$group == plan$treatment]
      receipt <- list(
        format = "deputy-study-result-v1",
        tool = list(name = "compute_summary", version = "1"),
        data = list(
          name = "synthetic-plant-weights-v1",
          revision = study_revision(data),
          units = "g",
          source = "Explicit synthetic observations bundled with this recipe; weight in grams"
        ),
        inputs = plan,
        input_revision = digest::digest(
          study_json(plan),
          algo = "sha256",
          serialize = FALSE
        ),
        proposal = state$proposal_context,
        execution = state$execution_context,
        approval = list(
          id = approval$id,
          tool_call_id = approval$request$tool_call_id,
          decision = approval$decision
        ),
        result = list(
          n_control = length(control),
          n_treatment = length(treatment),
          mean_control = mean(control),
          mean_treatment = mean(treatment),
          difference = mean(treatment) - mean(control),
          units = "g",
          interpretation = "Descriptive comparison; no causal or clinical inference."
        )
      )
      temporary <- tempfile("receipt-", tmpdir = directory)
      on.exit(unlink(temporary), add = TRUE)
      writeLines(study_json(receipt), temporary, useBytes = TRUE)
      if (!file.rename(temporary, result_path)) {
        cli::cli_abort("Could not publish the host result receipt.")
      }
      state$receipt <- receipt
      study_json(list(result_path = result_path, result = receipt$result))
    },
    name = "compute_summary",
    description = "Run the designated reviewed plant-weight computation.",
    arguments = study_arguments(),
    convert = FALSE,
    annotations = ellmer::tool_annotations(
      read_only_hint = FALSE,
      destructive_hint = FALSE,
      open_world_hint = FALSE
    )
  )
  view <- function(candidate) {
    access(candidate)
    list(
      proposal = state$proposal,
      proposal_context = state$proposal_context,
      lead_result = state$lead_result,
      pending = state$pending,
      receipt = state$receipt,
      commentary = state$commentary,
      error = state$error,
      cancelled = state$cancelled,
      result_path = if (!is.null(state$receipt)) result_path else NULL
    )
  }
  list(
    lead = lead,
    view = view,
    propose = function(task, candidate) {
      access(candidate)
      if (state$started) {
        cli::cli_abort("Start a new workflow for another proposal.")
      }
      state$started <- TRUE
      state$lead_result <- tryCatch(lead$run_sync(task), error = function(e) {
        state$error <- conditionMessage(e)
        NULL
      })
      view(candidate)
    },
    prepare = function(candidate) {
      access(candidate)
      if (
        state$cancelled ||
          is.null(state$proposal) ||
          is.null(state$proposal_context) ||
          !is.null(state$executor)
      ) {
        cli::cli_abort(
          "A fresh, valid proposal is required before preparing review."
        )
      }
      plan <- study_validate(state$proposal, data)
      state$executor <- deputy::Agent$new(
        chat = chat_factory("executor"),
        tools = list(compute_tool),
        system_prompt = "STUDY_EXECUTOR. Request compute_summary with the supplied inputs exactly. All subsequent text is commentary.",
        working_dir = directory,
        approval_dir = approval_dir,
        run_context = list(
          study = basename(directory),
          source_delegation_id = state$proposal_context$delegation_id
        ),
        usage_limits = deputy::UsageLimits(
          max_requests = 3L,
          max_tool_calls = 2L
        ),
        permissions = deputy::Permissions(can_use_tool = function(
          tool_name,
          tool_input,
          context
        ) {
          if (tool_name != "compute_summary" || state$cancelled) {
            return(deputy::PermissionResultDeny(
              "This operation is not authorized."
            ))
          }
          checked <- tryCatch(
            study_validate(tool_input$plan, data),
            error = function(e) NULL
          )
          expected <- if (is.null(state$approved)) {
            state$proposal
          } else {
            state$approved
          }
          if (is.null(checked) || !identical(checked, expected)) {
            return(deputy::PermissionResultDeny(
              "Inputs do not match the reviewed proposal."
            ))
          }
          state$execution_context <- study_identity(context)
          if (is.null(state$approved)) {
            deputy::PermissionResultPending(
              "Review dataset, groups, units, and descriptive method."
            )
          } else {
            deputy::PermissionResultAllow()
          }
        })
      )
      state$error <- NULL
      state$executor$run_sync(study_json(plan))
      state$pending <- state$executor$pending_approval()
      if (is.null(state$pending)) {
        cli::cli_abort(
          "The executor did not produce a reviewable computation request."
        )
      }
      view(candidate)
    },
    decide = function(candidate, decision = c("approve", "deny"), plan = NULL) {
      access(candidate)
      decision <- match.arg(decision)
      if (is.null(state$pending)) {
        cli::cli_abort("There is no pending study decision.")
      }
      if (state$cancelled && decision == "approve") {
        cli::cli_abort("The study was cancelled.")
      }
      if (decision == "approve") {
        if (is.null(plan)) {
          plan <- state$pending$request$tool_input$plan
        }
        state$approved <- study_validate(plan, data)
      }
      on.exit(state$approved <- NULL, add = TRUE)
      state$error <- NULL
      state$commentary <- tryCatch(
        state$executor$resume_approval(
          state$pending$source$path,
          decision,
          tool_input = if (decision == "approve") {
            list(plan = state$approved)
          } else {
            NULL
          }
        ),
        error = function(e) {
          state$error <- conditionMessage(e)
          NULL
        }
      )
      state$pending <- deputy::approval_read(state$pending$source$path)
      if (
        decision == "approve" && is.null(state$receipt) && is.null(state$error)
      ) {
        state$error <- "The approved tool did not produce an authoritative result. Inspect the effect journal."
      }
      view(candidate)
    },
    cancel = function(candidate) {
      access(candidate)
      state$cancelled <- TRUE
      lead$interrupt()
      if (!is.null(state$executor)) {
        state$executor$interrupt()
      }
      view(candidate)
    }
  )
}
