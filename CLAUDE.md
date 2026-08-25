# Agent instructions

This repo is a Claude Code skill, so the "code" is prose that gets loaded into agents' context. Every line of SKILL.md costs tokens in every swarm run; every template line costs tokens in every spawned agent. Cut before you add.

## What things are

- `SKILL.md` is the lead's playbook. It is read by the orchestrating session, never by spawned agents.
- `references/templates.md` holds the prompt templates spawned agents actually receive. The constraint lines in them are contracts, not suggestions — instantiators are told to fill the bracketed slots and change nothing else.
- `references/example.md` is illustrative and must stay consistent with the other two when they change.

## Rules that must not be weakened

- **No report rides on final text.** Every template ends with a SendMessage report before finishing. A finished agent's final text may never reach the lead; removing or softening these blocks makes the whole orchestration stall silently. State this without conditions — a justification that names today's spawn substrate invites an agent to decide the rule does not apply to it. If you change how reports work, verify against current documentation, not memory.
- **Reviewers are report-only.** The code reviewer's single licensed write is the contradicted-entry pair; the plan reviewer writes nothing at all. A reviewer that fixes what it finds destroys the record of what it found. The plan reviewer is spawned on `Explore`, so its mandate is enforced by the toolset and not only by its prompt; the code reviewer needs Write for that one pair, so its mandate holds by prompt alone and the wording must stay blunt.
- **The plan is reviewed before any worker spawns.** The gate's cheapest agent prevents the most expensive class of waste: a wave of workers building on a defective plan. Do not make it conditional on the plan looking fine.
- **The conventions entry is written once and binds every worker.** It is the only thing standing between parallel workers and a diff that reads as though four people wrote it. It must carry real code, not rules — "follow existing patterns" is the failure mode it exists to replace.
- **The index is computed, never stored.** Do not add an INDEX.md or any maintained index file; the `rg` one-liner is the index precisely so nothing can contend over it or go stale.
- **Entry IDs stay agent-namespaced** (`<agent>-<n>`). That is what lets concurrent writers skip coordination entirely.
- **Facts and interpretations stay separate kinds.** Collapsing them removes the reviewer's ability to attack one without the other.

## Borrowed practice

Several rules come from skills outside this repo — `adversarial-reviewer` (silence is approval, concrete triggers, severity), `superpowers:test-driven-development` (verify RED, verify GREEN), `superpowers:verification-before-completion` (evidence before claims, never trust an agent's report), `superpowers:writing-plans` (no placeholders, spec coverage, task right-sizing), `superpowers:subagent-driven-development` (the four-status report, no history in a dispatch, workers never spawn reviewers). Where a template can name the skill instead of restating it, name it — that keeps the checklist current and the prompt short. Restate inline only when the cost is paid per worker and the skill is large.

## Style

- Sentence case headers, no emojis (✓ and ✗ are acceptable).
- Templates use `{braced}` placeholders; keep them obvious and few.
- Facts about Claude Code's own behavior are perishable. Prefer a behavioral check the skill already performs over reading a flag or probing a config path; where a fact must be stated, date it inline (*Current as of <month year>*), keep it out of the rule it supports, and write the rule so it holds either way.
- When SKILL.md, a template, and README.md disagree, that is a bug — fix all of them in the same change. README.md summarizes behavior for readers, so it goes stale silently.

## Verification

Run `ruby scripts/check-consistency.rb` on every change. It is not a test suite — it only catches dangling references, unbound template slots, and vocabulary that drifted between files, which is the class of defect that comes from editing one file and not its pair. A new template slot has to be declared in the script deliberately; that is the point.

The real check is still a live run. Before claiming a change works, run the skill on a real multi-file task and confirm: scouts write entries and report by message, the gate verifies the conventions entry and the plan reviewer's verdict arrives, workers respect file scopes and report a status from the four, and the reviewer's verdict arrives as a message.
