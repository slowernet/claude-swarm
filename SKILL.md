---
name: swarm
description: Use for non-trivial engineering tasks spanning multiple files or subsystems where coordinated agents beat one context window — orchestrates plan, scouts, a shared knowledge store, workers, and review so repository exploration happens once and every later agent reuses it. Not for single-file changes or single questions.
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

Do not detect the substrate by feature flag, config path, or probing; the rule above holds on any of them. To gate a worker on a risky or destructive task, fill the worker template's gate slot: the worker messages its plan and stops, and your reply resumes it. That works on every substrate. The lead assigns task owners at the gate whether or not the substrate lets an agent self-claim, because work is released by a judgment rather than drained from a queue.

## Model selection

Default: omit the model at spawn. An agent then inherits the lead's model, which is the one the user chose for this work. Deviate only with a reason, and the reasons run by role:

- **Scouts**: a mechanical lookup ("where does X mount", "what naming pattern do migrations use") can drop a tier — the answer is checkable against its own evidence paths. A scout whose answer the plan will rest on stays on the lead's model: a wrong entry marked `confidence: high` poisons every agent downstream.
- **Workers**: may sit one tier below the lead's model. What protects implementation is the reviewer above it, which inherits the lead's tier; review must never sit below the work it checks, so a worker never rises above the lead.
- **Plan reviewer, integrator, code reviewers**: inherit the lead's model. A review tier must never sit below the tier of the work it checks — a reviewer weaker than the authors it checks approves what it cannot see. When the change is risky, raise the reviewer's *effort* rather than adding reviewers.
- **Smallest tier available**: only for sweeps where the instructions fully determine the output — bulk renames, fixture regeneration — and even then prefer one scripted pass over an agent.

Agent type is a separate axis from model. Default to `claude`, which every role that writes needs — scouts write entries, workers and the integrator write code, the code reviewer writes the contradicted-entry pair. The plan reviewer is the exception and spawns on `Explore`, so it cannot edit what it reviews.

Two mechanics to know: an agent's model is fixed when it spawns, so changing the lead's model afterwards does not reach an agent already running, and agents inherit the lead's effort level unless the spawn overrides it. *Current as of September 2026.*

## The knowledge store

Lives at `.claude/swarm/<slug>/` in the repo, where `<slug>` is a short kebab-case task name.

```
.claude/swarm/<slug>/
  plan.md        # lead-only: base ref, task breakdown, spec coverage, file partition, roster
  entries/       # append-only knowledge entries; any agent may add
    scout-1-1.md
    worker-2-1.md
```

Entry format: `references/entry.md`. All prompt templates: `references/templates.md`.

- **Kinds**: `fact` (what exists in the repo), `interpretation` (what an agent believes it implies), `decision` (what the team chose to do), `question` (unresolved).
- **Statuses**: `provisional`, `verified`, `contradicted`, `obsolete`.
- **IDs are `<agent-name>-<n>`** (e.g. `scout-2-3`). Each agent numbers its own entries, so concurrent writers can never collide and no coordination is needed.
- Entries are never edited by other agents except to flip `status`, and status flips happen only in single-threaded phases (gate, review).

**The index is computed, never stored.** To see everything known:

```
rg --no-heading '^(kind|status|confidence|summary):' .claude/swarm/<slug>/entries/
```

That is the whole map at ~15 tokens per entry, and every agent runs it before exploring anything. There is no INDEX.md to contend over or let go stale.

The store is scratch, scoped to the task. Add `.claude/swarm/` to `.gitignore` before anything spawns; the diff capture in phase 4 stages untracked files, and an unignored store would land in its own diff. Delete the slug directory when the work merges, or keep it if the repo wants the record.

## Phases

### 1. Plan (lead, in-session)

Do not spawn anything yet.

**First, justify the swarm in one sentence, out loud:** name the two or more agents that would otherwise explore the same ground. You have already decided to use this skill, which is exactly why the decision needs saying rather than assuming. If you cannot name them, do the task directly — "this is a three-file change to code I have already read" is a complete answer, and ends the swarm here.

**Then find the input.** A spec, design doc, or issue body stating the requirements is the source of truth: do not re-derive it, do not improve it, and copy its exact values into `plan.md` verbatim — a paraphrased threshold is a changed threshold. With a spec, this phase is decomposition, not design. Without one you are also the designer: settle the requirements with the user, then write them into `plan.md`. That section *is* the spec for every later phase, and it is the path you hand the reviewers.

**Record the base ref.** `git rev-parse HEAD` into `plan.md`, before anything spawns. Every later diff is taken against it. `HEAD~1` silently drops all but the last commit of a multi-commit task, and the branch point may have moved since the work began.

Then work out, in your own reasoning:

- **Spec coverage**: every requirement mapped to the task that will implement it, as a list in `plan.md`. A requirement with no task is the cheapest defect you will ever catch, and the reviewer checks this list at the end.
- What must be known before implementation, as a numbered list of questions. Mark each: answerable from what you already know (answer it now, write the entry yourself) or needs a scout.
- The task breakdown with dependencies, created as native tasks (`TaskCreate`, then `TaskUpdate` with `addBlockedBy`). Put each task's intended file scope in its metadata (`{"files": ["lib/foo.rb", "test/foo_test.rb"]}`), so the partition is recorded beside the task and any agent holding TaskGet can read it.
- The file partition: tasks whose file sets overlap are sequential or merged into one task. Prefer one coherent worker over two entangled ones.

Right-size the tasks: a task is the smallest unit that carries its own test cycle and is worth a reviewer's gate. Fold scaffolding into the task whose deliverable needs it; split only where a reviewer could reject one task while approving its neighbour.

Sizing guide — pick the smallest row that fits:

| Shape of task | Roster |
|---|---|
| Known files, known change | No swarm. Just do it. |
| One unknown, one change site | 1 scout → plan reviewer → 1 worker → code reviewer (four agents; the gate holds at this size too) |
| Multi-file feature, familiar repo | 1-2 scouts → plan reviewer → 2-3 workers → code reviewer |
| Cross-subsystem, or unfamiliar repo | 3-4 scouts → plan reviewer → workers per partition → code reviewer |

Cap concurrent writing workers at 4 regardless of task size. Beyond that, coordination costs exceed parallel gains.

### 2. Scout

**Write the questions before you write the roster.** A vague question is the most common way a swarm wastes tokens. The shape test: *a question is well-formed if its answer fits in one entry with concrete evidence paths.*

- ✗ "Understand the auth system" — produces a wandering scout and four half-entries.
- ✓ "Which module enforces auth on API routes, and where is it mounted?" — one entry, two evidence paths.

If a question fails the test, split it or narrow it. One question per scout; a scout holding two questions will do the easy one well and the other badly.

**One question is always on the list: conventions.** "How does this repo handle errors, name and locate test files, and run its tests — with a real example of each?" If you do not ask it once, every worker derives it separately and they will not agree. Its entry *is* the conventions entry — the gate verifies it, it does not rewrite it.

Spawn scouts in one message so they run in parallel. Each scout gets: a name (`scout-1`, `scout-2`, ...), its one question, a scope hint, the store path, and the scout prompt from `references/templates.md`, which carries the constraints (index first, that one question only, the repo read-only, absence recorded as a finding, entries written by the discoverer). Use the `claude` agent type; a scout must be able to Write into the store.

Back comes a SendMessage with entry IDs and a summary of three lines or fewer. Open only the entries the plan turns on.

**Follow-up questions go to the same scout by `SendMessage`**, which resumes it with its context warm. Never spawn a fresh agent to ask a follow-up on territory an existing scout already holds.

### 3. Gate (lead, in-session)

When scouts report, run the index command, read the handful of entries that matter, and do five things in order. This phase decides the quality of everything after it.

**1. Adjudicate.** Settle any conflicting entries, and chase any `low`-confidence finding the plan rests on, before a worker builds on either. Then write the plan's key choices as `decision` entries — workers read decisions; they do not re-litigate them.

**2. Settle the conventions entry.** The conventions scout has already written one: check its claims against the repo, flip it to `verified`, and cite that id everywhere after. Write your own only if no scout answered the question — copying the scout's into a `lead-` entry duplicates the finding and pays the transcription cost this skill forbids. Either way it must hold actual examples rather than rules: the error-handling idiom as real code from this repo, the test-file naming as a real path mapping (`lib/foo.rb → test/foo_test.rb`), the test command, and what its passing output looks like. "Follow existing patterns" is not a convention — it is an instruction to go and find one, which every worker then follows separately and differently. This entry is the main defence against a diff that reads as though four people wrote it.

**3. Run the buildability test, per task.** Could a worker write the exact failing test and the exact implementation from this task plus the entries you will hand it, asking nobody? Where it could not, name what is missing: gaps tracing to the spec are questions for the user, gaps in repo knowledge are one more scout question. Scan for placeholders while you are there — "add validation", "handle errors appropriately", "similar to task 2", or a call to a function no task defines are plan failures, not tasks, and a worker will stop on every one.

**4. Review the plan before anything is built on it.** Spawn one plan reviewer (template in `references/templates.md`) on the `Explore` agent type — it reports and writes nothing, so give it no tool that could — with the spec, `plan.md`, and the store index. A plan defect caught here costs one revision; the same defect caught after three workers have built on it costs the wave and a review round trip. Do not skip it because the plan is yours — that is exactly why it needs a reader who did not write it.

**5. Ask everything at once.** Batch what genuinely needs the user's judgment — spec gaps from the buildability test, and any plan-reviewer finding you cannot settle yourself — into a single message, with the digest of what scouting found and anything that changes scope. A reviewer objection is not automatically a question: findings you can fix, fix. A human in the room is this design's advantage over a headless pipeline, and it is squandered by spending it a question at a time.

### 4. Work

Spawn workers wave by wave, respecting task dependencies. Each worker gets: a name (`worker-1`, ...), its task ID (assign `owner` via TaskUpdate at spawn), the entry IDs relevant to its task, the conventions entry id, the binding decision ids, its file scope, and the worker prompt from `references/templates.md`, which carries the rest (store before exploring, the test-first cycle, no subagents, stop rather than improvise when the plan turns out wrong).

Back comes a SendMessage report: one of four statuses (`DONE`, `DONE_WITH_CONCERNS`, `NEEDS_CONTEXT`, `BLOCKED`), the files changed, the test command and its actual output, entry ids added, and notes. The status table in `references/templates.md` says what each one obliges you to do. A worker never widens its own file scope, so a request for a file outside it is a re-partition decision of yours rather than a permission to grant.

**A worker's prompt carries its task, its entries, and its scope — never the session's history.** Pasting what earlier workers did is the most expensive habit available to a lead: the store already holds it, addressed by id.

**Do not trust a report.** A message is a claim; the diff and the test output are the evidence. Check what actually changed before marking a task done or releasing the tasks that depend on it.

**Gate a destructive task before it writes.** For work that drops data, rewrites history, or is otherwise hard to reverse, fill the worker template's gate slot. The worker sends its plan by SendMessage and stops; that message carries no STATUS line and is not a report. Your reply resumes it, and only then does it write.

Parallel workers share the working tree only when file scopes are disjoint.

When the last worker reports, run the full test suite in-session and read the output. Workers ran only their own tests, so a breakage across two scopes is invisible to both; a failure goes back to the owning worker by SendMessage before any reviewer spawns. Then capture the diff once: `git add -N . && git diff <base ref from plan.md> > .claude/swarm/<slug>/diff.txt`. Nothing commits during a swarm, so the intent-to-add is what puts files workers created into the diff. Review reads that path, and so does the integrator when there is one, so the diff costs one Read in the agents that need it and never enters your context.

### 5. Merge (only when a worktree was used)

When no worker ran in a worktree there is nothing to integrate: the diff already sits in the shared tree, and cross-worker seams belong to the reviewer's conventions and simplicity lenses, routed back to the worker that owns the file. When a worktree was used, spawn one integrator with the integrator prompt from `references/templates.md`. It applies the worktree's uncommitted changes onto the shared tree from the path recorded in `plan.md`, resolves conflicts in favour of the decision entries, fixes the seams the merge introduces, recaptures `diff.txt` after those fixes so review reads the tree as it stands, and runs the full test suite. It does not add features. It reads the store and does not redo scouting unless it finds concrete evidence an entry is wrong, in which case it writes the contradicting entry and flags the lead.

### 6. Review

One reviewer (two for large or risky changes, each with a distinct lens — correctness and regressions; security and edge cases). Point it at the `adversarial-reviewer` skill rather than restating a checklist: the template names the skill and adds only the four lenses that skill does not carry. Each reviewer gets: its lens, the path to `diff.txt`, the spec path, the conventions entry id, the store path, and the reviewer prompt from `references/templates.md`. Spawn it on the `claude` agent type — unlike the plan reviewer it must be able to write the contradicted-entry pair, which is the one write its report-only mandate licenses.

Back comes a SendMessage: findings ranked by severity with file:line, entries it challenged, a CANNOT VERIFY list, and a verdict of APPROVE or RETURN-TO-WORKERS with the blocking finding ids. Silence is approval, so an empty findings list is itself a verdict. Because the reviewer fixes nothing, every finding is yours to route.

The lead decides what goes back to workers. Send findings to the worker that owns the file, by SendMessage — its context is still warm and a fresh spawn pays for the file again. Before declaring the task done, run the tests yourself, in-session, and read the output: a worker's "tests pass" is a claim, not evidence.

**Bounded spend.** Two counters are yours to keep and to surface to the user rather than absorb silently, **two respawns per task** and **two review round trips**; the failure table below says what each one does when it runs out.

## Failure handling

The response to every failure mode, in one place. The phases above state the rule; this states what to do when it breaks.

| Event | Response |
|---|---|
| Conflicting entries | Lead adjudicates at the gate; loser marked `contradicted`, decision entry written |
| Low-confidence finding on the critical path | Targeted follow-up to the owning scout, before workers build on it |
| Plan reviewer returns REVISE-PLAN | Revise before spawning any worker; re-review only the parts that changed |
| Worker reports `NEEDS_CONTEXT` | Supply it by SendMessage — the agent is warm. Never respawn for missing context |
| Worker reports `BLOCKED`, or discovers the plan is wrong | Entry + message + stop. Lead re-plans and updates tasks, then asks what the buildability test missed — most of these are phase-3 defects, not routine events |
| Two workers need the same file | Re-partition: merge the tasks or sequence them. `isolation: worktree` only when overlap is unavoidable *and* parallelism actually matters, because the integrator then pays for a real merge. Record the worktree's path in `plan.md` beside the roster at spawn; the integrator has no other way to find it |
| Agent timeout / death / null return | Respawn with the same task ID and entry list; the store and tasks carry all state, so the restart costs the task, not the exploration. **Two respawns**, then stop and report — a task failing repeatedly is a partition or plan problem, and a fourth spawn will not find that out |
| Review keeps returning findings | **Two round trips**, then stop and hand the remaining findings to the user as a list |
| Reviewer flags "cannot verify from diff" | Lead resolves it — you hold the cross-task context it lacks. A confirmed gap becomes a finding |
| Session resumed, agents gone | A resumed session does not bring spawned agents back; the store and task list persist on disk, so respawn from them |
| Tests disprove an architectural assumption | The failing test is evidence; the entry goes `contradicted`, the gate re-runs |
| Merge conflicts (worktree path) | Integrator owns the merge, resolving in favour of the decision entries |

## Scale-out note

For a large *uniform* fan-out (the same operation over 20 files), one scripted pass is more token-efficient than hand-spawning agents, because the skill's judgment-driven phases don't apply to mechanical sweeps. The Workflow tool's `pipeline()` is the vehicle for that pass (*current as of September 2026*). Invoking this skill counts as the user's opt-in to orchestration.
