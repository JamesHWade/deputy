# Host-selected context forks

Deputy accepts an explicitly selected host snapshot and initializes an independent
specialist conversation. A fork carries owner, conversation, branch, revision and
fork-point provenance, plus an explicit choice of retained transcript or current
model context. Fresh delegation remains the default.

## Reuse the conversation contracts

ellmer owns Turns, Content, conversation state and public content record/replay.
Use those objects for copied text, images, documents and settled tool evidence.
Do not flatten a complete native conversation into a second textual transcript
format. Replaying a record reconstructs data; it does not authorize execution.
Executable tool bindings are removed, and incomplete tool evidence cannot become
a pending operation in the new child. Unsupported selections fail explicitly.

shinychat owns its managed history, branch semantics and rich content rendering.
The released R 0.5.0 stores support the managed Shiny flow. The separate headless
branch operations requested in shinychat#391 are still not public. Deputy must
not reproduce the store or mutate private tree fields to work around that gap.
A host can already supply selected native turns without a shinychat dependency.

## Deputy's boundary

The host authenticates the caller and resolves the current source revision.
Deputy validates the returned scope and revision, enforces finite selection
bounds, records provenance and applies existing retained-conversation ownership.
The child is a separately configured Agent and Chat with independent identities.
Its configured prompt, tools and resources come from the host, not the transcript.
Current parent and child governance applies when the child runs.

Selecting an existing branch is a host read. Creating a branch is a host write.
Copying selected context creates a new independent child snapshot. Continuing the
retained child advances that child's conversation and cumulative allocation;
it does not recopy later source messages or create a host branch automatically.

Compaction makes the selection distinction observable: the retained transcript
contains the original history, while current model context contains the reduced
working turns. A host must explicitly include any selected summary material;
the fork does not silently substitute the full transcript for a bounded context.

## Rich results

Native ellmer content and shinychat tool display remain the shared representation
and presentation layers. Portable interactive artifacts from R workers (#144)
are a separate producer/storage contract. Neither a fork nor a saved chat turns
temporary widget dependencies, live render-hook closures or provider upload IDs
into durable, universally accessible artifacts.

Fork snapshots replace provider-specific `ContentUploaded` handles with labelled
inert text and report a `provider_upload` omission. This also applies inside tool
results: a new child can use a different provider or credentials, and the source
upload may expire. Hosts supply portable content when the child needs the file.
