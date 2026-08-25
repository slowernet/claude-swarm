---
name: swarm
description: Use for non-trivial engineering tasks spanning multiple files or subsystems where coordinated agents beat one context window — orchestrates plan, scouts, a shared knowledge store, workers, integration, and review so repository exploration happens once and every later agent reuses it. Not for single-file changes or single questions.
---

# Swarm: a token-efficient agent team

One rule governs everything here: **share discoveries, not context.** An agent's transcript dies with it. A written entry outlives it, survives agent failure, and answers the next agent's question before it re-explores. Every phase below exists to move knowledge out of transcripts and into entries.

The unit of efficiency is useful engineering work per token, not agent count. The best swarm is the smallest one that covers the work.

## When NOT to use this

Do the task directly, with no swarm machinery, when:

- You can already name the files and the change. Scouting what you know is pure waste.
- The task fits comfortably in one agent (single file, a known fix, a clear refactor).
- It is a pure research question — one Explore agent, no store.

The overhead floor of a swarm is real (plan + store + gate). It pays for itself only when at least two agents would otherwise explore the same ground.

## Substrate: subagents or teammates

Claude Code spawns named agents on one of two substrates, and this skill must work on both. With `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` set (and an interactive session), a named agent launches as a *teammate*: fully independent, able to self-claim tasks — and its final text is **not delivered to the lead**; the lead gets only an idle notification with no output. Without the variable, a named agent is a plain subagent whose final text returns to the caller.

The rule that makes the skill substrate-proof: **no report rides on final text.** Every agent writes its durable output as entries and sends its summary by SendMessage to the lead (`main`; the lead's name if that is rejected) *before* finishing. The lead treats the computed index as the source of truth and the message as the wake-up. An orchestration that waits on return values stalls the moment teams mode is on.

Teams mode adds two native mechanisms to use when present: **plan approval** (spawn a worker with plan approval required; it works read-only until the lead approves its plan — right for risky or destructive tasks) and task self-claim with file locking. This skill still assigns owners at the gate — that is policy (work is released by a judgment, not drained from a queue), not race-avoidance; the locking already handles races.

## Model selection

Default: omit the model at spawn. An agent then inherits the lead's model, which is the one the user chose for this work. Deviate only with a reason, and the reasons run by role:

- **Scouts**: a mechanical lookup ("where does X mount", "what naming pattern do migrations use") can drop a tier — the answer is checkable and the store's evidence paths keep it honest. A scout whose answer the plan will be built on stays on the lead's model: a wrong entry marked `confidence: high` poisons every agent downstream, and that costs more than the tier saves.
- **Workers**: spawn on `opus` explicitly. The lead's model is reserved for judgment — plan, gate, adjudication, review; implementation runs on opus and is protected by a stronger reviewer above it, not by its own tier.
- **Integrator and reviewers**: inherit the lead's model. The review tier must never sit below the workers' tier — a reviewer weaker than the authors it checks approves what it cannot see. When the change is risky, raise the reviewer's *effort* rather than adding reviewers.
- **Smallest tier** (haiku-class): only for sweeps where the instructions fully determine the output — bulk renames, fixture regeneration — and even then prefer one scripted pass over an agent.

Two mechanics to know: an agent's model is fixed at spawn (`/model` in the lead changes only the lead, and under teams mode a teammate's model can never be changed after launch), and agents inherit the lead's effort level unless overridden per-spawn.

## The knowledge store

Lives at `.claude/swarm/<slug>/` in the repo, where `<slug>` is a short kebab-case task name.

```
.claude/swarm/<slug>/
  plan.md        # lead-only: task breakdown, file partition, roster
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

That is the whole map at ~15 tokens per entry. Every agent runs it before exploring anything — the question "has this already been investigated?" costs one tool call. There is no INDEX.md to maintain, contend over, or let go stale.

The store is scratch, scoped to the task. Suggest adding `.claude/swarm/` to `.gitignore`; delete the slug directory when the work merges, or keep it if the repo wants the record.

## Phases

### 1. Plan (lead, in-session)

Do not spawn anything yet.

**First, justify the swarm in one sentence, out loud, before anything else:** name the two or more agents that would otherwise explore the same ground. If you cannot name them, say so and do the task directly — you have already decided to use this skill, which is exactly why the decision needs saying rather than assuming. "This is a three-file change to code I have already read" is a complete and correct answer, and ends the swarm here.

Then work out, in your own reasoning:

- What the actual problem is, restated in one paragraph in `plan.md`.
- What must be known before implementation, as a numbered list of questions. Mark each: answerable from what you already know (answer it now, write the entry yourself) or needs a scout.
- The task breakdown with dependencies, created as native tasks (`TaskCreate`, then `TaskUpdate` with `addBlockedBy`). Put each task's intended file scope in its metadata (`{"files": ["lib/foo.rb", "test/foo_test.rb"]}`) — this is what conflict detection reads.
- The file partition: tasks whose file sets overlap are sequential or merged into one task. Prefer one coherent worker over two entangled ones.

Sizing guide — pick the smallest row that fits:

| Shape of task | Team |
|---|---|
| Known files, known change | No swarm. Just do it. |
| One unknown, one change site | 1 scout → 1 worker |
| Multi-file feature, familiar repo | 1-2 scouts → 2-3 workers → reviewer |
| Cross-subsystem, or unfamiliar repo | 3-4 scouts → workers per partition → integrator → reviewer |

Cap concurrent writing workers at 4 regardless of task size. Beyond that, coordination costs exceed parallel gains.

### 2. Scout

**Write the questions before you write the roster.** Scout quality decides everything downstream, and a vague question is the most common way a swarm wastes tokens. The shape test: *a question is well-formed if its answer fits in one entry with concrete evidence paths.*

- ✗ "Understand the auth system" — produces a wandering scout and four half-entries.
- ✓ "Which module enforces auth on API routes, and where is it mounted?" — one entry, two evidence paths.

If a question fails the test, split it or narrow it. One question per scout; a scout holding two questions will do the easy one well and the other badly.

Spawn scouts in one message so they run in parallel. Each scout gets: a name (`scout-1`, `scout-2`, ...), its question, the store path, and the prompt template from `references/templates.md`. Scouts:

- Run the index command first; do not re-answer an existing entry.
- Investigate only their question. A scout that wanders the repo is a defect.
- **Record absence as a finding.** "No rate limiting exists — checked `middleware/`, `router.ts`, `package.json`" is one of the highest-value entries possible: looking for something that is not there is the most wasteful search to repeat, and agents systematically fail to report it. A negative answer is an answer, not a failed scout.
- Write their own entries (the discoverer records the finding — transcription through the lead loses evidence and pays twice).
- Report entry IDs plus a summary of three lines or fewer — by SendMessage, before finishing, per the substrate rule above.
- Never implement anything.

Use the `claude` agent type (scouts must be able to Write into the store) with the template's constraint that the repo itself is read-only to them.

**Follow-up questions go to the same scout by `SendMessage`**, which resumes it with its context warm. Never spawn a fresh agent to ask a follow-up on territory an existing scout already holds.

### 3. Gate (lead, in-session)

When scouts report: run the index command, read the handful of entries that matter, and decide:

- Are the critical-path findings high-confidence? A `low` confidence entry that the plan depends on gets a targeted follow-up (SendMessage to its scout) before any worker builds on it.
- Do any entries conflict? Adjudicate now: mark the loser `contradicted`, write a `decision` entry saying which stands and why.
- Does the task breakdown survive contact with the findings? Update tasks and file scopes if not.
- Write the key choices as `decision` entries. Workers read decisions; they do not re-litigate them.

This is also the natural point to surface a digest to the user — the plan, what scouting found, and anything that changes scope — before implementation spends real tokens.

### 4. Work

Spawn workers wave by wave, respecting task dependencies. Each worker gets: a name (`worker-1`, ...), its task ID (assign `owner` via TaskUpdate at spawn), the entry IDs relevant to its task, its file scope, and the template. Workers:

- Read their task, then their assigned entries, then run the index command. Consult the store before exploring; explore only gaps.
- Stay inside their file scope. Needing a file outside it is a finding, not a permission — write a `question` entry and message the lead.
- Write entries for anything durable they discover (`fact` for repo reality, `question` for surprises). A worker discovery is knowledge the moment it is written, and transcript-only the moment it is not.
- Implement test-first, run the tests they touched, update their task status honestly — a task with failing tests stays `in_progress`.
- On discovering the plan is wrong: write the entry, message the lead, stop. Do not improvise a new plan mid-task.

Parallel workers share the working tree only when file scopes are disjoint. If two tasks genuinely must touch the same files and cannot merge into one worker, run them sequentially; use `isolation: worktree` only when overlap is unavoidable *and* parallelism actually matters, because the integrator then pays for a real merge.

If a worker dies or returns null: the knowledge store and task state survive it. Respawn with the same task ID and entry list — the restart costs the task, not the exploration.

### 5. Integrate (skip when one worker)

One agent, after all workers finish: read the full diff against the original task, check cross-worker consistency (naming, patterns, duplicated helpers introduced independently), resolve any worktree merges, and run the full test suite. It reads the store; it does not redo scouting unless it finds concrete evidence an entry is wrong — in which case it writes the contradicting entry and flags the lead.

The integrator may fix seams between workers. It does not add features.

### 6. Review

One reviewer (two for large or risky changes, each with a distinct lens — correctness and regressions; security and edge cases). The reviewer:

- Holds a **report-only mandate: it never edits code.** A reviewer that fixes what it finds silently destroys the record of what it found.
- Reads the diff, the original task, and the store — and is explicitly licensed to challenge entries. The store is evidence, not scripture.
- When it disproves an entry: writes a contradicting entry with evidence, flips the original to `contradicted`, so no later agent builds on it.
- Returns findings with file:line and severity.

The lead decides what goes back to workers. Before declaring the task done, verify with a fresh test run in-session — evidence before claims, always.

**Bounded spend.** Two counters, both the lead's to keep, both surfaced to the user rather than absorbed silently:

- **Two respawns per task.** A worker that dies or returns nothing gets respawned twice. On the third failure, stop and report the task with what the store holds — a task failing repeatedly is usually a partition or plan problem, and a fourth identical spawn will not find that out.
- **Two review round trips.** Findings go back to workers at most twice. On a third round, stop and hand the remaining findings to the user as a list.

The reason is not tidiness. Without a cap, a task where the reviewer keeps finding real problems and workers keep half-fixing them consumes the whole budget on one item, and the hardest item is exactly the one least likely to converge. When either counter runs out, the store and the task list hold everything learned — the work is paused, not lost.

## Failure handling summary

| Event | Response |
|---|---|
| Conflicting entries | Lead adjudicates at the gate; loser marked `contradicted`, decision entry written |
| Low-confidence finding on the critical path | Targeted follow-up to the owning scout before workers build on it |
| Worker discovers the plan is wrong | Entry + message to lead + stop; lead re-plans, updates tasks |
| Two workers need the same file | Re-partition: merge tasks or sequence them; worktree only as last resort |
| Agent timeout / death / null return | Respawn with same task ID; store and tasks carry all state. **Two respawns per task**, then stop and report |
| Review keeps returning findings | **Two round trips**, then stop and hand the remaining findings to the user |
| Session resumed, agents gone | `/resume` does not restore teammates; the store and task list persist on disk — respawn from them |
| Tests disprove an architectural assumption | The failing test is evidence; entry goes `contradicted`, gate re-runs |
| Merge conflicts (worktree path) | Integrator owns the merge |

## Scale-out note

For a large *uniform* fan-out (the same operation over 20 files), the Workflow tool with `pipeline()` is more token-efficient than hand-spawning agents — the skill's judgment-driven phases don't apply to mechanical sweeps. Invoking this skill counts as the user's opt-in to orchestration.
