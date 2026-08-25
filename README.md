# claude-swarm

A Claude Code skill that orchestrates a token-efficient, non-duplicative agent team for non-trivial software engineering tasks.

The point is not launching agents in parallel — Claude Code already does that. The point is that expensive repository exploration and reasoning happen once, get written down in a shared knowledge store, and every later agent reuses them instead of repeating them. The design optimizes useful engineering work per token, not agent count.

## How it works

```
Plan -> Scouts -> Gate -> Workers -> Integrate -> Review
  ^                 |        ^                       |
  +-- REVISE-PLAN --+        +-- RETURN-TO-WORKERS --+
```

The store is not a stage in the line — every phase reads it before exploring anything, and every phase can write to it. That is what makes this a swarm rather than a pipeline: work done once in any phase is available to all the others, including the ones that have not started yet.

- **Plan** (lead, no agents yet): read the spec as the source of truth, map every requirement to the task that implements it, build a task DAG with dependencies, partition files so workers never collide.
- **Scouts** (parallel): each answers one narrow question and writes findings to the store. A scout that wanders the repo is a defect.
- **Gate** (lead): adjudicate conflicting findings, write the conventions entry every worker will follow, test each task for buildability, spawn one reviewer against the plan itself, then put every open question to the human in a single batch. The cheapest agent in the swarm sits here: a plan defect caught now costs one revision, and the same defect caught after three workers built on it costs the wave.
- **Workers** (waves, ≤4 concurrent): implement inside a fixed file scope, consulting the store before exploring anything. Test-first, watching each test fail before making it pass. They never spawn subagents, and they report one of four statuses with the test output pasted, not summarized. A worker that discovers the plan is wrong stops and reports instead of improvising.
- **Integrate**: one agent reads the whole diff, fixes cross-worker seams, runs the full suite.
- **Review**: report-only — a reviewer that fixes what it finds destroys the record of what it found. Beyond correctness, it checks spec compliance against the coverage list, adherence to the conventions entry, simplicity, and whether each new test could actually fail. Reviewers may disprove store entries, with evidence.

Three channels carry everything, and they are deliberately different:

| Channel | Carries | Survives |
|---|---|---|
| Knowledge store (`.claude/swarm/<slug>/entries/`) | facts, interpretations, decisions, open questions | agent death, session resume |
| Task list (native Claude Code tasks) | state: who owns what, what blocks what | agent death, session resume |
| Messages (SendMessage) | wake-ups and escalations only | nothing — by design |

Entries are one file per finding with frontmatter (kind, status, confidence, evidence, author). IDs are namespaced by agent (`scout-2-1`) so concurrent writers never collide. There is no stored index — one `rg` over the frontmatter is the index, so it can never go stale and nothing contends over it.

## Install

```sh
git clone https://github.com/slowernet/claude-swarm ~/code/claude-swarm
ln -s ~/code/claude-swarm ~/.claude/skills/swarm
```

Claude Code picks it up as a personal skill named `swarm`.

## Use

Invoke with `/swarm <task>`, or describe a multi-file task and ask for the swarm. The skill's first section is a refusal rule: if the files and the change are already known, it tells the lead to skip the machinery and just do the work.

## Model policy

Judgment runs at the top tier, execution one down, retrieval below that:

- Lead (plan, gate, adjudication), the plan reviewer, the integrator, and code reviewers: the session's model
- Workers: `opus`, explicitly — protected by the stronger reviewer above them
- Mechanical-lookup scouts: may drop a tier; critical-path scouts stay at the lead's model
- The review tier must never sit below the workers' tier

## Agent teams

The skill runs on either of Claude Code's spawn substrates: plain subagents, or teammates ([agent teams](https://code.claude.com/docs/en/agent-teams)). The rule that makes it substrate-proof: no report rides on an agent's final text, because a finished agent's final text may never reach the lead. Durable output goes in the store; summaries go by SendMessage before the agent finishes — correct under both substrates.

The lead never reads a feature flag to find out which substrate it has. It assumes the stricter one, and the first wave of scouts reveals the answer at no cost: a teammate goes idle with no output delivered, a subagent returns its final text. The only thing that changes is the mechanism for gating a risky worker — native plan approval with teammates, message-your-plan-and-wait with subagents.

## Files

- `SKILL.md` — the lead's playbook: phases, sizing, failure handling, model policy
- `references/templates.md` — entry format, the four-status report contract, and verbatim prompt templates for scout, plan reviewer, worker, integrator, code reviewer
- `references/example.md` — a worked example, a rate-limiting feature through all phases
- `scripts/check-consistency.rb` — mechanical cross-file checks; run it on every change

## Limitations

- Teams mode changes delivery semantics; the skill is written to survive both, but spawned agents are not restored by `/resume` (the store and task list are — respawn from them).
- The store is per-task scratch, not a persistent repo map. Promoting verified facts into a durable per-repo map is the intended v2.
- Untested claims are marked as such in the skill; the honest status is that the workflow has not yet been burned in against a large real task.
