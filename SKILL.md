---
name: swarm
description: Use for non-trivial engineering tasks spanning multiple files or subsystems where coordinated agents beat one context window — orchestrates plan, scouts, a shared knowledge store, workers, integration, and review so repository exploration happens once and every later agent reuses it. Not for single-file changes or single questions.
---

# Swarm: a token-efficient agent team

One rule governs everything here: **share discoveries, not context.** An agent's transcript dies with it. A written entry outlives it and answers the next agent's question before it re-explores. Every phase below exists to move knowledge out of transcripts and into entries.

The unit of efficiency is useful engineering work per token, not agent count. The best swarm is the smallest one that covers the work.

## When NOT to use this

Do the task directly, with no swarm machinery, when:

- You can already name the files and the change. Scouting what you know is pure waste.
- The task fits comfortably in one agent (single file, a known fix, a clear refactor).
- It is a pure research question — one Explore agent, no store.

The overhead floor is real (plan + store + gate). It pays for itself only when at least two agents would otherwise explore the same ground.

## Substrate: how reports travel

**No report rides on final text.** A finished agent's final text may never reach the lead, so every agent writes its durable output as entries and sends its summary by SendMessage to the lead (`main`; the lead's name if that is rejected) *before* finishing. The lead treats the computed index as the source of truth and the message as the wake-up. An orchestration that waits on return values stalls silently; one that waits on messages works on any substrate. The rule carries no condition on purpose — a condition that goes stale costs the whole run, a message sent needlessly costs nothing.

**Assume the stricter substrate, then learn the truth for free.** Do not branch on `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` or any successor flag, and do not probe `~/.claude/teams/`: it accumulates directories from sessions that have ended, its naming has already changed format once, and neither tells you about the session you are in. The first scout wave tells you what you need — a teammate goes idle with no output delivered, a subagent returns its final text. The SendMessage report arrives either way, which is why the swarm never stalls while you find out. Note the answer in `plan.md` beside the roster so later phases do not re-derive it.

The answer changes exactly one thing: how you gate a worker on a risky or destructive task.

- **Teammates**: require plan approval at spawn ("require plan approval before making any changes"). The worker stays read-only until you approve, and the handshake is native.
- **Subagents**: tell the worker to message its plan and wait for your reply before writing anything. Same gate, same judgment, no native support needed.

Teammates also self-claim tasks with file locking. This skill still assigns owners at the gate regardless, because work is released by a judgment rather than drained from a queue.

## Model selection

Default: omit the model at spawn. An agent then inherits the lead's model, which is the one the user chose for this work. Deviate only with a reason, and the reasons run by role:

- **Scouts**: a mechanical lookup ("where does X mount", "what naming pattern do migrations use") can drop a tier — the answer is checkable against its own evidence paths. A scout whose answer the plan will rest on stays on the lead's model: a wrong entry marked `confidence: high` poisons every agent downstream.
- **Workers**: spawn on `opus` explicitly. Implementation is protected by a stronger reviewer above it, not by its own tier.
- **Plan reviewer, integrator, code reviewers**: inherit the lead's model. A review tier must never sit below the tier of the work it checks — a reviewer weaker than the authors it checks approves what it cannot see. When the change is risky, raise the reviewer's *effort* rather than adding reviewers.
- **Smallest tier** (haiku-class): only for sweeps where the instructions fully determine the output — bulk renames, fixture regeneration — and even then prefer one scripted pass over an agent.

Agent type is a separate axis from model. Default to `claude`, which every role that writes needs — scouts write entries, workers and the integrator write code, the code reviewer writes the contradicted-entry pair. The plan reviewer is the exception and spawns on `Explore`, so it cannot edit what it reviews.

Two mechanics to know: an agent's model is fixed at spawn (`/model` in the lead changes only the lead, and a teammate's model can never be changed after launch), and agents inherit the lead's effort level unless overridden per-spawn.

## The knowledge store

Lives at `.claude/swarm/<slug>/` in the repo, where `<slug>` is a short kebab-case task name.

```
.claude/swarm/<slug>/
  plan.md        # lead-only: base ref, substrate, task breakdown, spec coverage, file partition, roster
  entries/       # append-only knowledge entries; any agent may add
    scout-1-1.md
    worker-2-1.md
```

Entry format and all prompt templates: `references/templates.md`.

- **Kinds**: `fact` (what exists in the repo), `interpretation` (what an agent believes it implies), `decision` (what the team chose to do), `question` (unresolved).
- **Statuses**: `provisional`, `verified`, `contradicted`, `obsolete`.
- **IDs are `<agent-name>-<n>`** (e.g. `scout-2-3`). Each agent numbers its own entries, so concurrent writers can never collide and no coordination is needed.
- Entries are never edited by other agents except to flip `status`, and status flips happen only in single-threaded phases (gate, review).

**The index is computed, never stored.** To see everything known:

```
rg --no-heading '^(kind|status|confidence|summary):' .claude/swarm/<slug>/entries/
```

That is the whole map at ~15 tokens per entry, and every agent runs it before exploring anything. There is no INDEX.md to contend over or let go stale.

The store is scratch, scoped to the task. Suggest adding `.claude/swarm/` to `.gitignore`; delete the slug directory when the work merges, or keep it if the repo wants the record.

## Phases

### 1. Plan (lead, in-session)

Do not spawn anything yet.

**First, justify the swarm in one sentence, out loud:** name the two or more agents that would otherwise explore the same ground. You have already decided to use this skill, which is exactly why the decision needs saying rather than assuming. If you cannot name them, do the task directly — "this is a three-file change to code I have already read" is a complete answer, and ends the swarm here.

**Then find the input.** A spec, design doc, or issue body stating the requirements is the source of truth: do not re-derive it, do not improve it, and copy its exact values into `plan.md` verbatim — a paraphrased threshold is a changed threshold. With a spec, this phase is decomposition, not design. Without one you are also the designer: settle the requirements with the user, then write them into `plan.md`. That section *is* the spec for every later phase, and it is the path you hand the reviewers.

**Record the base ref.** `git rev-parse HEAD` into `plan.md`, before anything spawns. Every later diff is taken against it. `HEAD~1` silently drops all but the last commit of a multi-commit task, and the branch point may have moved since the work began.

Then work out, in your own reasoning:

- **Spec coverage**: every requirement mapped to the task that will implement it, as a list in `plan.md`. A requirement with no task is the cheapest defect you will ever catch, and the reviewer checks this list at the end.
- What must be known before implementation, as a numbered list of questions. Mark each: answerable from what you already know (answer it now, write the entry yourself) or needs a scout.
- The task breakdown with dependencies, created as native tasks (`TaskCreate`, then `TaskUpdate` with `addBlockedBy`). Put each task's intended file scope in its metadata (`{"files": ["lib/foo.rb", "test/foo_test.rb"]}`) — this is what conflict detection reads.
- The file partition: tasks whose file sets overlap are sequential or merged into one task. Prefer one coherent worker over two entangled ones.

Right-size the tasks: a task is the smallest unit that carries its own test cycle and is worth a reviewer's gate. Fold scaffolding into the task whose deliverable needs it; split only where a reviewer could reject one task while approving its neighbour.

Sizing guide — pick the smallest row that fits:

| Shape of task | Team |
|---|---|
| Known files, known change | No swarm. Just do it. |
| One unknown, one change site | 1 scout → 1 worker |
| Multi-file feature, familiar repo | 1-2 scouts → 2-3 workers → reviewer |
| Cross-subsystem, or unfamiliar repo | 3-4 scouts → workers per partition → integrator → reviewer |

Cap concurrent writing workers at 4 regardless of task size. Beyond that, coordination costs exceed parallel gains.

### 2. Scout

**Write the questions before you write the roster.** A vague question is the most common way a swarm wastes tokens. The shape test: *a question is well-formed if its answer fits in one entry with concrete evidence paths.*

- ✗ "Understand the auth system" — produces a wandering scout and four half-entries.
- ✓ "Which module enforces auth on API routes, and where is it mounted?" — one entry, two evidence paths.

If a question fails the test, split it or narrow it. One question per scout; a scout holding two questions will do the easy one well and the other badly.

**One question is always on the list: conventions.** "How does this repo handle errors, name and locate test files, and run its tests — with a real example of each?" If you do not ask it once, every worker derives it separately and they will not agree. Its entry *is* the conventions entry — the gate verifies it, it does not rewrite it.

Spawn scouts in one message so they run in parallel. Each scout gets: a name (`scout-1`, `scout-2`, ...), its question, the store path, and the prompt template from `references/templates.md`. Scouts:

- Run the index command first; do not re-answer an existing entry.
- Investigate only their question. A scout that wanders the repo is a defect.
- **Record absence as a finding.** "No rate limiting exists — checked `middleware/`, `router.ts`, `package.json`" is among the highest-value entries possible, because looking for something that is not there is the most wasteful search to repeat. Agents systematically fail to report it; a negative answer is an answer, not a failed scout.
- Write their own entries — the discoverer records the finding, since transcription through the lead loses evidence and pays twice.
- Report entry IDs plus a summary of three lines or fewer, by SendMessage before finishing.
- Never implement anything.

Use the `claude` agent type (scouts must be able to Write into the store) with the template's constraint that the repo itself is read-only to them.

**Follow-up questions go to the same scout by `SendMessage`**, which resumes it with its context warm. Never spawn a fresh agent to ask a follow-up on territory an existing scout already holds.

### 3. Gate (lead, in-session)

When scouts report, run the index command, read the handful of entries that matter, and do five things in order. This phase decides the quality of everything after it.

**1. Adjudicate.** Settle any conflicting entries, and chase any `low`-confidence finding the plan rests on, before a worker builds on either. Then write the plan's key choices as `decision` entries — workers read decisions; they do not re-litigate them.

**2. Settle the conventions entry.** The conventions scout has already written one: check its claims against the repo, flip it to `verified`, and cite that id everywhere after. Write your own only if no scout answered the question — copying the scout's into a `lead-` entry duplicates the finding and pays the transcription cost this skill forbids. Either way it must hold actual examples rather than rules: the error-handling idiom as real code from this repo, the test-file naming as a real path mapping (`lib/foo.rb → test/foo_test.rb`), the test command, and what its passing output looks like. "Follow existing patterns" is not a convention — it is an instruction to go and find one, which every worker then follows separately and differently. This entry is the main defence against a diff that reads as though four people wrote it.

**3. Run the buildability test, per task.** Could a worker write the exact failing test and the exact implementation from this task plus the entries you will hand it, asking nobody? Where it could not, name what is missing: gaps tracing to the spec are questions for the user, gaps in repo knowledge are one more scout question. Scan for placeholders while you are there — "add validation", "handle errors appropriately", "similar to task 2", or a call to a function no task defines are plan failures, not tasks, and a worker will stop on every one.

**4. Review the plan before anything is built on it.** Spawn one plan reviewer (template in `references/templates.md`) on the `Explore` agent type — it reports and writes nothing, so give it no tool that could — with the spec, `plan.md`, and the store index. A plan defect caught here costs one revision; the same defect caught after three workers have built on it costs the wave, the integration, and a review round trip. Do not skip it because the plan is yours — that is exactly why it needs a reader who did not write it.

**5. Ask everything at once.** Batch what genuinely needs the user's judgment — spec gaps from the buildability test, and any plan-reviewer finding you cannot settle yourself — into a single message, with the digest of what scouting found and anything that changes scope. A reviewer objection is not automatically a question: findings you can fix, fix. A human in the room is this design's advantage over a headless pipeline, and it is squandered by spending it a question at a time.

### 4. Work

Spawn workers wave by wave, respecting task dependencies. Each worker gets: a name (`worker-1`, ...), its task ID (assign `owner` via TaskUpdate at spawn), the entry IDs relevant to its task, its file scope, and the template. Workers:

- Read their task, then their assigned entries, then run the index command. Consult the store before exploring; explore only gaps.
- Follow the conventions entry rather than deriving conventions from neighbouring files. A deviation from it is a finding to report, not a preference to exercise.
- Stay inside their file scope. Needing a file outside it is a finding, not a permission — write a `question` entry and message the lead.
- Write entries for anything durable they discover (`fact` for repo reality, `question` for surprises). A discovery is knowledge the moment it is written, and transcript-only the moment it is not.
- Implement test-first, watching each test fail for the right reason before making it pass. The full cycle is in the worker template; do not restate it at spawn.
- Never spawn subagents — not helpers, and never their own reviewer. That duplicates the review you were going to run anyway, at a full extra seat.
- Report one of four statuses — `DONE`, `DONE_WITH_CONCERNS`, `NEEDS_CONTEXT`, `BLOCKED` — with the test command and its actual output. The status table is in `references/templates.md`.
- On discovering the plan is wrong: write the entry, message the lead, stop. Do not improvise a replacement plan.

**A worker's prompt carries its task, its entries, and its scope — never the session's history.** Pasting what earlier workers did is the most expensive habit available to a lead: the store already holds it, addressed by id.

**Do not trust a report.** A message is a claim; the diff and the test output are the evidence. Check what actually changed before marking a task done or releasing the tasks that depend on it.

**Gate a destructive task before it writes.** For work that drops data, rewrites history, or is otherwise hard to reverse, use the mechanism the substrate note recorded: native plan approval for a teammate, or an instruction to message its plan and wait for your reply for a subagent.

Parallel workers share the working tree only when file scopes are disjoint.

When the last worker reports, capture the diff once: `git diff <base ref from plan.md> > .claude/swarm/<slug>/diff.txt`. Integration and review both read that path, so the diff costs one Read in the agents that need it and never enters your context.

### 5. Integrate (skip when one worker)

One agent, after all workers finish: read the full diff against the original task, check cross-worker consistency (naming, patterns, duplicated helpers introduced independently), and run the full test suite. It reads the store; it does not redo scouting unless it finds concrete evidence an entry is wrong — in which case it writes the contradicting entry and flags the lead.


The integrator may fix seams between workers. It does not add features.

### 6. Review

One reviewer (two for large or risky changes, each with a distinct lens — correctness and regressions; security and edge cases). Point it at the `adversarial-reviewer` skill rather than restating a checklist: the template names the skill and adds only the four lenses that skill does not carry. Hand it `diff.txt`. Spawn it on the `claude` agent type — unlike the plan reviewer it must be able to write the contradicted-entry pair. The reviewer:

- Holds a **report-only mandate: it never edits code.** A reviewer that fixes what it finds silently destroys the record of what it found.
- Reads the diff, the original task, and the store — and is explicitly licensed to challenge entries. The store is evidence, not scripture.
- When it disproves an entry: writes a contradicting entry with evidence, flips the original to `contradicted`, so no later agent builds on it.
- Returns findings with file:line and severity. **Silence is approval** — no compliments, no "this part looks fine". Nothing found means "no findings" and stop; a reviewer manufacturing issues to look thorough costs you twice.
- Checks **spec compliance** as its own axis: requirements missing, requirements misunderstood, and code the spec never asked for. The coverage list in `plan.md` is what it checks against.
- Checks the diff against the **conventions** entry. Code that reads as though its author never opened a neighbouring file is a finding even when it is correct.
- Treats **simplicity** as a first-class lens, not a style note. Parallel workers each add their own abstraction and none is positioned to see that two were unnecessary. Of every new file, helper, and indirection: did this codebase already have a way to do this?
- Checks **test quality** by naming, for each new test, the production change that would make it fail. If there is none, the test proves nothing and that is a finding. An expectation computed by the same code under test is worse than no test at all, because it will pass forever.
- Marks what it **cannot verify from the diff alone** — a requirement living in unchanged code, or spanning tasks — as such rather than as a finding.

The lead decides what goes back to workers. Send findings to the worker that owns the file, by SendMessage — its context is still warm and a fresh spawn pays for the file again. Before declaring the task done, run the tests yourself, in-session, and read the output: a worker's "tests pass" is a claim, not evidence.

**Bounded spend.** Two counters, both the lead's to keep and both surfaced to the user rather than absorbed silently: **two respawns per task**, and **two review round trips**. Without them, a task where the reviewer keeps finding real problems and workers keep half-fixing them consumes the whole budget — and the hardest item is the one least likely to converge. When either runs out the work is paused, not lost: the store and task list hold everything learned.

## Failure handling

The response to every failure mode, in one place. The phases above state the rule; this states what to do when it breaks.

| Event | Response |
|---|---|
| Conflicting entries | Lead adjudicates at the gate; loser marked `contradicted`, decision entry written |
| Low-confidence finding on the critical path | Targeted follow-up to the owning scout, before workers build on it |
| Plan reviewer returns REVISE-PLAN | Revise before spawning any worker; re-review only the parts that changed |
| Worker reports `NEEDS_CONTEXT` | Supply it by SendMessage — the agent is warm. Never respawn for missing context |
| Worker reports `BLOCKED`, or discovers the plan is wrong | Entry + message + stop. Lead re-plans and updates tasks, then asks what the buildability test missed — most of these are phase-3 defects, not routine events |
| Two workers need the same file | Re-partition: merge the tasks or sequence them. `isolation: worktree` only when overlap is unavoidable *and* parallelism actually matters, because the integrator then pays for a real merge |
| Agent timeout / death / null return | Respawn with the same task ID and entry list; the store and tasks carry all state, so the restart costs the task, not the exploration. **Two respawns**, then stop and report — a task failing repeatedly is a partition or plan problem, and a fourth spawn will not find that out |
| Review keeps returning findings | **Two round trips**, then stop and hand the remaining findings to the user as a list |
| Reviewer flags "cannot verify from diff" | Lead resolves it — you hold the cross-task context it lacks. A confirmed gap becomes a finding |
| Session resumed, agents gone | `/resume` does not restore spawned agents; the store and task list persist on disk — respawn from them |
| Tests disprove an architectural assumption | The failing test is evidence; the entry goes `contradicted`, the gate re-runs |
| Merge conflicts (worktree path) | Integrator owns the merge, resolving in favour of the decision entries |

## Scale-out note

For a large *uniform* fan-out (the same operation over 20 files), the Workflow tool with `pipeline()` is more token-efficient than hand-spawning agents — the skill's judgment-driven phases don't apply to mechanical sweeps. Invoking this skill counts as the user's opt-in to orchestration.
