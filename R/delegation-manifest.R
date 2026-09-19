#' @include delegation-input.R
NULL

#' Inspect the prepared initial context of a delegation
#'
#' A read-only S7 receipt produced by LeadAgent preparation. It describes the
#' supplied initial context, not later provider framing, hooks, compaction, or
#' runtime state. It never grants access or installs tools or permissions.
#'
#' @param input Plain normalized [DelegationInput] properties.
#' @param definition Declarative definition identity and prompt material.
#' @param sources Ordered resolved text sources and content digests.
#' @param scope Host-bound owner and conversation identifiers.
#' @param system_prompt Prepared system prompt, including static memory/skills.
#' @param message Prepared first user message, including initial prompt and evidence.
#' @param model Selected model name; no provider credentials.
#' @param tools Registered tool names, not unconditional grants of permission.
#' @param policies Policy identifiers and non-executable settings.
#' @param size Byte counts and a public complete-context token estimate when known.
#' @param schema_version Portable record schema. Currently `1L`.
#' @details
#' Hosts normally obtain these values from `LeadAgent$get_subagent_contexts()`.
#' `S7::props()` returns portable plain records suitable for host JSON/RDS storage.
#' Constructing or restoring a receipt does not recreate an Agent. The host owns
#' disclosure authorization and storage; the LeadAgent retains receipts in memory.
#' Evidence hashes identify bytes, not truth or authorization. Size estimates are
#' estimates, not billed token counts. Fresh working context and retained history
#' remain separately inspectable after compaction (ADR-0017).
#' @return A read-only `DelegationManifest` S7 value.
#' @export
DelegationManifest <- S7::new_class(
  "DelegationManifest",
  package = "deputy",
  properties = list(
    schema_version = readonly_property("schema_version", S7::class_integer),
    input = readonly_property("input", S7::class_list),
    definition = readonly_property("definition", S7::class_list),
    sources = readonly_property("sources", S7::class_list),
    scope = readonly_property("scope", S7::class_list),
    system_prompt = readonly_property("system_prompt", S7::class_character),
    message = readonly_property("message", S7::class_character),
    model = readonly_property("model", S7::class_character),
    tools = readonly_property("tools", S7::class_character),
    policies = readonly_property("policies", S7::class_list),
    size = readonly_property("size", S7::class_list)
  ),
  constructor = function(
    input,
    definition,
    sources,
    scope,
    system_prompt,
    message,
    model,
    tools,
    policies,
    size,
    schema_version = 1L
  ) {
    if (
      !is.numeric(schema_version) ||
        length(schema_version) != 1L ||
        is.na(schema_version) ||
        schema_version != 1 ||
        !is.null(attributes(schema_version))
    ) {
      delegation_input_abort(
        "invalid",
        "Unsupported delegation manifest schema."
      )
    }
    value <- S7::new_object(
      S7::S7_object(),
      schema_version = 1L,
      input = S7::props(do.call(DelegationInput, input)),
      definition = normalize_run_context(definition),
      sources = lapply(sources, normalize_run_context),
      scope = normalize_run_context(scope),
      system_prompt = delegation_text(
        system_prompt,
        "system_prompt",
        empty = TRUE
      ),
      message = delegation_text(message, "message"),
      model = delegation_text(model, "model", empty = TRUE),
      tools = delegation_strings(tools, "tools", max_entries = Inf),
      policies = normalize_run_context(policies),
      size = normalize_run_context(size)
    )
    freeze_value(value)
  }
)

prepare_delegation_manifest <- function(lead, definition, prepared, child) {
  private <- lead$.__enclos_env__$private
  context <- child$context_policy
  context_fields <- normalize_run_context(S7::props(context)[c(
    "max_tokens",
    "compact_to",
    "fallback",
    "max_tool_result_bytes",
    "max_tool_result_image_bytes",
    "max_tool_result_images"
  )])
  permissions <- normalize_run_context(S7::props(child$permissions)[c(
    "mode",
    "file_read",
    "file_write",
    "bash",
    "r_code",
    "web",
    "install_packages",
    "tool_allowlist",
    "tool_denylist",
    "permission_prompt_tool_name"
  )])
  callback_present <- !is.null(child$permissions$can_use_tool)
  policy <- list(
    permissions_id = delegation_digest(permissions),
    permission_mode = permissions$mode,
    permission_callback_present = callback_present,
    fingerprint_scope = "declarative settings; excludes callbacks, credentials and offload path",
    context_policy_id = delegation_digest(context_fields),
    context_policy = context_fields,
    binding = child$.__enclos_env__$private$.delegation_binding
  )
  system_prompt <- child$get_system_prompt() %||% ""
  text_bytes <- nchar(system_prompt, type = "bytes") +
    nchar(prepared$message, type = "bytes")
  if (text_bytes > private$delegation_max_bytes) {
    delegation_input_abort(
      "oversized",
      "Initial instructions exceed the host admission ceiling."
    )
  }
  estimated <- tryCatch(
    child$.__enclos_env__$private$context_token_count(list(prepared$message)),
    error = function(error) NULL
  )
  if (
    !is.null(estimated) &&
      !is.null(context$max_tokens) &&
      estimated > context$max_tokens
  ) {
    delegation_input_abort(
      "oversized",
      "Initial context exceeds ContextPolicy$max_tokens."
    )
  }
  fields <- list(
    input = S7::props(prepared$input),
    definition = list(
      name = definition$name,
      prompt = definition$prompt,
      memory = definition$memory,
      initial_prompt = definition$initial_prompt,
      skills = unname(vapply(
        definition$skills,
        function(skill) if (is.character(skill)) skill else skill$name,
        character(1)
      ))
    ),
    sources = prepared$sources,
    scope = private$delegation_scope,
    system_prompt = system_prompt,
    message = prepared$message,
    model = child$get_model() %||% "",
    tools = unname(names(child$get_tools()) %||% character()),
    policies = policy,
    size = list(text_bytes = text_bytes, estimated_tokens = estimated)
  )
  # Hash the declarative source separately from executable tool closures.
  fields$definition$id <- delegation_digest(list(
    definition = fields$definition,
    model = fields$model,
    tools = fields$tools
  ))
  # Canonical constructor output is the export representation. Include the
  # count itself until its decimal width stabilizes.
  fields$size$manifest_bytes <- 0L
  repeat {
    manifest <- do.call(DelegationManifest, fields)
    manifest_bytes <- delegation_bytes(S7::props(manifest))
    if (manifest_bytes == fields$size$manifest_bytes) {
      break
    }
    fields$size$manifest_bytes <- manifest_bytes
  }
  if (manifest_bytes > private$delegation_max_bytes) {
    delegation_input_abort(
      "oversized",
      "Initial manifest exceeds the host admission ceiling."
    )
  }
  manifest
}

redact_delegation_manifest <- function(manifest) {
  if (is.null(manifest)) {
    return(NULL)
  }
  list(
    schema_version = manifest$schema_version,
    content_redacted = TRUE,
    definition_id = manifest$definition$id,
    model = manifest$model,
    tools = manifest$tools,
    size = manifest$size,
    policies = c(
      manifest$policies[c(
        "permissions_id",
        "permission_mode",
        "context_policy_id"
      )],
      list(
        binding = manifest$policies$binding[c(
          "resource_mode",
          "hooks",
          "permissions",
          "approval",
          "human_input",
          "cleanup"
        )]
      )
    ),
    sources = lapply(manifest$sources, function(source) {
      source[c(
        "source_id",
        "revision",
        "owner_id",
        "conversation_id",
        "digest"
      )]
    })
  )
}

lead_subagent_contexts <- function(lead, delegation_id, view, redact) {
  view <- match.arg(view, c("initial", "current"))
  if (!is.logical(redact) || length(redact) != 1L || is.na(redact)) {
    delegation_input_abort("invalid", "redact must be TRUE or FALSE.")
  }
  if (redact && view != "initial") {
    delegation_input_abort(
      "invalid",
      "redact is only supported for initial manifests."
    )
  }
  private <- lead$.__enclos_env__$private
  runs <- unname(private$subagent_runs)
  if (!is.null(delegation_id)) {
    runs <- Filter(
      function(run) identical(run$delegation_id, delegation_id),
      runs
    )
  }
  lapply(runs, function(run) {
    if (view == "initial") {
      if (redact) redact_delegation_manifest(run$manifest) else run$manifest
    } else {
      child <- private$active_subagents[[run$delegation_id]]
      if (!is.null(child)) {
        list(
          system_prompt = child$get_system_prompt(),
          turns = child$get_context_turns()
        )
      } else {
        run$working_context
      }
    }
  })
}

local({
  S7::method(`$`, DelegationManifest) <- function(x, name) S7::prop(x, name)
})
