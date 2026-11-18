# Deputy runtime priorities · 2026-11-17

I reviewed the nine issues open on Deputy main at `d669871` and compared its
runtime with the OpenAI Agents SDK, LangGraph and PydanticAI. The first
implementation is **portable recovery of selected R data**. A Shiny host can
get an analysis table back after a worker or supervisor exits, with a receipt
that names the restored bindings. This work is [#263](https://github.com/JamesHWade/deputy/issues/263),
a child of [#188](https://github.com/JamesHWade/deputy/issues/188).

## What the other runtimes shipped

| Runtime | Relevant capability | Implication for Deputy |
| --- | --- | --- |
| OpenAI Agents SDK | Stable v0.25.0 exposes helpers for session adapters and advances RunState for nested approvals. Run-context snapshots can use a custom serializer for process-local resources. A separate native-runtime preview added application-owned durable root sessions and reconciliation of uncertain effects. [Stable release](https://github.com/openai/openai-agents-python/releases/tag/v0.25.0) · [Native preview](https://github.com/openai/openai-agents-python/releases/tag/v0.24.0-alpha.7) | Persist data and operational evidence with explicit boundaries. The native preview is an upstream design reference. |
| LangGraph | Thread-scoped checkpoints preserve graph state. The Functional API can recover previous results and may rerun work that was in flight. Task boundaries and idempotency matter when a workflow writes to an external service. [Checkpointers](https://docs.langchain.com/oss/python/langgraph/checkpointers) · [Functional API](https://docs.langchain.com/oss/python/langgraph/functional-api) | Copy the discipline of explicit checkpoints. Deputy’s R restore imports completed data, with zero replay of R expressions or tool calls. |
| PydanticAI | Durable workflow integration delegates journaling and recovery to engines such as Temporal, DBOS and Restate. Step persistence for resuming and forking is a separate interface. [Durable execution](https://pydantic.dev/docs/ai/capabilities/durable_execution/overview/) | Keep a portable R artifact independent of the workflow runner and its effect journal. |

## What Deputy should work on

1. **Recover selected trusted R data.** Deputy already saves conversation
   evidence and journals effects for jobs and approvals. A killed job worker
   can leave an indeterminate effect, which the host inspects before continuing.
   Losing an R worker still loses its data on main. #263 adds owner-scoped
   checkpoints for named ordinary data, with integrity verification before
   fresh-worker import. The scope is trusted callr-backed R. [Job lifecycle](adr/0027-host-scheduled-agent-jobs.md)
   · [Approval continuations](adr/0016-durable-approval-continuations.md)
   · [#263](https://github.com/JamesHWade/deputy/issues/263)
2. **Build durable displays next.** Preserve interactive R tables and plots as
   host-owned HTML artifacts, with a verified fallback for the model and
   enough renderer/dependency evidence to reopen in a fresh process. Reuse
   the ownership and integrity principles from #263. Display artifacts need
   their own serving and browser contract. [#144](https://github.com/JamesHWade/deputy/issues/144)
3. **Qualify the streaming fix alongside feature work.** The upstream issue
   identifying the wait for the first SSE body byte is closed. The curl and
   httr2 fixes are merged upstream. Test the exact versions through Deputy’s
   public stream path and measure both delayed headers and delayed body.
   Adopt through the released dependency set and retain the upstream issue
   until that end-to-end qualification is complete. [#200](https://github.com/JamesHWade/deputy/issues/200)
   · [curl fix](https://github.com/jeroen/curl/pull/460)
   · [httr2 fix](https://github.com/r-lib/httr2/pull/919)
4. **Keep sandbox and integration work tied to public contracts.** #188’s
   sandbox path still depends on a supported worker-to-host channel. A later
   recovery path can associate artifacts with existing effect records and
   explicitly reconcile uncertain outcomes using service evidence.
   Qualify upstream APIs before replacing the temporary MCP adapters or
   adding headless shinychat history. [#187](https://github.com/JamesHWade/deputy/issues/187)
   · [#188](https://github.com/JamesHWade/deputy/issues/188)
   · [#48](https://github.com/JamesHWade/deputy/issues/48)
   · [#99](https://github.com/JamesHWade/deputy/issues/99)
   · [#66](https://github.com/JamesHWade/deputy/issues/66)
5. **Treat model refresh and release as their own work.** #228 is a bounded
   documentation and pricing qualification item. #86 tracks testing the
   exact release source and returning to released CRAN dependencies.
   [#228](https://github.com/JamesHWade/deputy/issues/228)
   · [#86](https://github.com/JamesHWade/deputy/issues/86)
