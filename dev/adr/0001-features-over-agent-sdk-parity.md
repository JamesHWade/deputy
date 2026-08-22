# Track Agent SDK features, not literal Agent SDK parity

deputy began by mirroring Anthropic's Claude Agent SDK closely, shipping a compatibility facade — `ClaudeSDKClient`, `claude_sdk_query()`, Claude-style settings adapters, automatic session stores, and aliases — alongside the native `Agent` and `LeadAgent` APIs. That facade was removed in PR #23, reducing the exported API from 82 to 51 symbols. deputy takes its *ideas* from the Agent SDK — permissions, hooks, delegation, skills, human-in-the-loop — but expresses them in whatever shape is idiomatic for R, and does not commit to matching the SDK's names, options, or file formats.

## Why

Literal parity is a maintenance treadmill with no finish line: the SDK moves, and every move becomes deputy work that delivers nothing to an R user. It also imported foreign conventions — `.claude/` directory layouts, `settings.json` field names, camelCase options — into a package whose users expect tidyverse idiom. Two surfaces for the same capability meant every feature was built and tested twice, and the compatibility one was always the less-loved.

The features are the valuable part. The wire format is not.

## Consequences

- **`.claude/` conventions are not a target.** A future declarative agent format should be deputy's own. Re-adding a `.claude/` loader would reintroduce what #23 removed. See issue #41.
- **Issues framed as "parity gaps" are not automatically valid.** Several were closed as not-planned on these grounds: they asked to extend a surface that had been deliberately deleted.
- **Downstream callers on the facade must migrate** to the native constructors. See issue #56.
- **This is not a rejection of the SDK's design.** Ideas from it remain welcome; what is rejected is the obligation to match its interface.
