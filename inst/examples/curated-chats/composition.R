# Compose existing configured chats without a LeadAgent definition registry.
curated_conversations <- function(
  caller_chat,
  analyst_chat,
  auditor_chat,
  disclosure
) {
  owner <- deputy::Agent$new(
    caller_chat,
    usage_limits = deputy::UsageLimits(max_requests = 20),
    delegation_disclosure = disclosure
  )
  chats <- list(analyst = analyst_chat, auditor = auditor_chat)
  handles <- lapply(names(chats), function(name) {
    chat <- chats[[name]]
    deputy::adopt_chat(
      chat,
      owner,
      permissions = deputy::Permissions(
        mode = "readonly",
        file_read = TRUE,
        file_write = FALSE,
        tool_allowlist = names(chat$get_tools())
      ),
      usage_limits = deputy::UsageLimits(max_requests = 8),
      history = "retain",
      callbacks = "replace",
      name = name
    )
  })
  names(handles) <- names(chats)
  for (name in names(handles)) {
    owner$register_tool(deputy::delegation_tool(
      owner,
      handles[[name]],
      name = paste0("ask_", name),
      description = paste("Ask the", name),
      usage_limits = deputy::UsageLimits(max_requests = 3)
    ))
  }
  list(owner = owner, handles = handles)
}
