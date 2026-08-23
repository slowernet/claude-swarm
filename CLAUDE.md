# Agent instructions

This repo is a Claude Code skill, so the "code" is prose that gets loaded into agents' context. Every line of SKILL.md costs tokens in every swarm run; every template line costs tokens in every spawned agent. Cut before you add.

## What things are

- `SKILL.md` is the lead's playbook. It is read by the orchestrating session, never by spawned agents.
- `references/templates.md` holds the prompt templates spawned agents actually receive. The constraint lines in them are contracts, not suggestions — instantiators are told to fill the bracketed slots and change nothing else.
- `references/example.md` is illustrative and must stay consistent with the other two when they change.

## Rules that must not be weakened

- **No report rides on final text.** Every template ends with a SendMessage report before finishing. Under agent-teams mode a finished agent's final text is never delivered; removing or softening these blocks makes the whole orchestration stall silently. If you change how reports work, verify against the current agent-teams documentation, not memory.
- **The reviewer is report-only.** Its single licensed write is the contradicted-entry pair. A reviewer that fixes what it finds destroys the record of what it found.
- **The index is computed, never stored.** Do not add an INDEX.md or any maintained index file; the `rg` one-liner is the index precisely so nothing can contend over it or go stale.
- **Entry IDs stay agent-namespaced** (`<agent>-<n>`). That is what lets concurrent writers skip coordination entirely.
- **Facts and interpretations stay separate kinds.** Collapsing them removes the reviewer's ability to attack one without the other.

## Style

- Sentence case headers, no emojis (✓ and ✗ are acceptable).
- Templates use `{braced}` placeholders; keep them obvious and few.
- When SKILL.md and a template disagree, that is a bug — fix both in the same change.

## Verification

There is no test suite; the check is a live run. Before claiming a change works, run the skill on a real multi-file task and confirm: scouts write entries and report by message, the gate reads only the computed index, workers respect file scopes, and the reviewer's verdict arrives as a message.
