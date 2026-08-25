# Worked example

Spec (on the issue's linked branch): "Add rate limiting to our public API. Per-key limits of 100 req/min, 429 with `Retry-After` in seconds, existing keys grandfathered at 1000 req/min." Express/TypeScript repo, ~400 files, unfamiliar to the lead.

## Plan

The spec is the source of truth, so the lead decomposes rather than designs. Exact values go into `plan.md` verbatim — `100`, `1000`, `Retry-After` in seconds — not "a per-key limit". `git rev-parse HEAD` goes in too, before anything spawns: every diff later in the run is taken against it.

Spec coverage, written as a list:

| Requirement | Task |
|---|---|
| Per-key limit, 100 req/min | T1 |
| 429 response with `Retry-After` in seconds | T1, asserted in T3 |
| Existing keys grandfathered at 1000 | T2 (migration), T3 (integration test) |

What must be known first:

1. Where do API requests enter, and where does auth resolve the key? (scout)
2. Is there existing middleware/infra a limiter should follow as a pattern? Any redis/store already in the stack? (scout)
3. How are API keys modeled, and where would a "tier" live? (scout)
4. Repo conventions: error idiom, test file naming, test command? (scout — always on the list)

Tasks with dependencies:

- T1 limiter middleware + unit tests — blockedBy: scouting
- T2 key-tier model change + migration — blockedBy: scouting
- T3 wire middleware into request path, integration tests — blockedBy: T1, T2
- T4 docs — folded into T3, since a reviewer would never approve one and reject the other

File partition: T1 `src/middleware/ratelimit.ts` + its test; T2 `src/models/apikey.ts` + migration dir; T3 `src/app.ts` + integration tests. Disjoint → T1 and T2 parallel, T3 sequential after both. Sizing row: multi-file feature, unfamiliar repo → 4 scouts, 3 workers, 1 integrator, 1 reviewer.

## Scouts

Four spawned in one message, one question each. They index-check (store empty), investigate, write entries:

- `scout-1-1` (fact, high): all API routes mount through `src/api/router.ts`; auth resolves key in `AuthMiddleware` (`src/middleware/auth.ts:41`) and sets `req.apiKey`
- `scout-1-2` (fact, high): error responses use `ApiError` helper, shape `{error, code}`; tests assert on `code`
- `scout-2-1` (fact, high): redis client already exists at `src/lib/redis.ts`, used by session cache
- `scout-2-2` (interpretation, medium): middleware ordering matters — body-parser assumes auth ran; limiter should mount after auth, before routing
- `scout-3-1` (fact, high): `ApiKey` model in `src/models/apikey.ts`, migrations in `db/migrations/`, pattern is timestamped files
- `scout-3-2` (question): no existing concept of "tier" — name and default value need a decision
- `scout-4-1` (fact, high): conventions — `throw new ApiError('...', 'CODE')`, never a bare `throw`; tests mirror source as `src/x/y.ts` → `src/x/y.test.ts`; `npm test` ends `Tests: N passed, N total`

Each returns 3 lines + IDs. Lead's cost: one index command (~105 tokens for 7 entries) plus two entry bodies it chose to open.

## Gate

**Adjudicate.** No conflicts. `scout-2-2` is medium-confidence and the plan rests on it → one follow-up message to scout-2 (warm context): "verify the ordering claim against how session cache middleware mounts." Scout-2 replies with evidence and flips its entry to `verified`.

**Conventions entry.** `scout-4-1` already holds it. The lead checks the quoted `ApiError` call, the path mapping, and the test command against the repo, flips the entry to `verified`, and cites that id from here on. No copy is made: restating it under the lead's own id would be the same transcription cost the skill forbids.

**Decisions.**

- `lead-1` (decision): limiter mounts after auth in `app.ts`, keyed on `req.apiKey.id`, backed by the existing redis client — cites scout-1-1, scout-2-1, scout-2-2
- `lead-2` (decision): tier is an enum column `tier` on api_keys, default `standard` (100/min); migration backfills existing keys to `legacy` (1000/min) — resolves scout-3-2

**Buildability test.** T1 and T2 pass. T3 fails: "assert the 429 body" does not say what the body is. The spec fixes `Retry-After` but says nothing about the JSON shape — a spec gap, batched for the user.

**Plan review.** One plan reviewer on `Explore`, given the spec, `plan.md`, and the index. Two findings:

- high, buildability: T3's assertion is unspecified — the same gap the lead found, independently confirmed
- medium, simplicity: T1 proposed a `RateLimitStore` interface with one implementation. The codebase wraps redis directly everywhere else. Drop the interface

Verdict: REVISE-PLAN on the first. The lead drops the interface from T1 itself — a finding it can settle is not a question for the user.

**One question round.** The digest, the scope, and the single open question — what shape is the 429 body — go to the user in one message. Answer: `{error, code}` like everything else, `code: 'RATE_LIMITED'`. It lands in `lead-1`.

Total cost of the gate: one extra agent and one message. It prevented a worker stopping mid-task on T3 and an abstraction nobody would have questioned once three files used it.

## Work

worker-1 (T1) and worker-2 (T2) spawn in parallel, each with: task ID, the 3-4 entry IDs that matter, file scope, conventions (`scout-4-1`), and binding decisions (`lead-1`, `lead-2`). Neither re-explores the router, the redis client, or how to run tests — the entries answer all three. Neither prompt mentions the other's work.

worker-2 discovers mid-task that the migration runner requires a model version bump (`worker-2-1`, fact) — written to the store, not just mentioned in its report. worker-3 (T3), spawning later, reads it from the index and avoids the same trap.

Reports come back as `DONE` with pasted test output. The lead checks `git diff --stat` against each worker's claimed file list before releasing T3 — a claim is not evidence.

worker-3 wires the middleware, writes integration tests asserting the 429 shape against `lead-1` and `scout-1-2`, updates the docs, and reports `DONE_WITH_CONCERNS`: the `Retry-After` value rounds up, which the spec does not address. The lead reads it, judges it correct, and lets it stand.

With the last worker in, the lead captures the diff once — `git diff <base ref> > .claude/swarm/rate-limit/diff.txt` — and hands that path onward. It never reads the diff itself.

## Integrate

The integrator gets the diff path, the index, and the coverage list. It finds one seam: worker-1 named the redis keyspace `rl:` while worker-3's test asserted `ratelimit:` — fixes the test to match the implementation, cites `lead-1`. Runs the full suite; green; reports `DONE` with actual output.

## Review

One reviewer, correctness lens, report-only, given the diff file, the spec, the coverage list, and the index. Three findings:

- high: the limiter counts requests before auth *failures* are rejected, so invalid keys consume a valid key's budget when key IDs collide on prefix — file:line, repro described
- medium, test quality: the `Retry-After` test asserts the header is present but never its value. No production change to the value would fail it
- CANNOT VERIFY: whether existing keys are actually backfilled to `legacy` — the migration runs against a database the diff does not show

It cannot disprove any entry; the store stands. Verdict: RETURN-TO-WORKERS with the high finding.

The lead messages worker-1 (warm, has the middleware loaded) with both findings; it fixes the ordering and strengthens the test. The CANNOT VERIFY item is the lead's: it runs the migration against a scratch database, confirms the backfill, and records it. Then it runs the full suite in-session, reads the output, and only then says the work is done.

## The token ledger

Paid once instead of N times: the router/auth topology (scout-1, reused by workers 1 and 3 and the integrator), the redis discovery, the migration-runner trap (worker-2's find, worker-3's savings), the error-shape contract, and the conventions — written once by scout-4, verified rather than recopied, and used by three workers and the reviewer without any of them deriving it. Follow-ups went to warm contexts twice instead of fresh spawns. The diff was read from a file by two agents and never by the lead. The reviewer read a diff path plus a 105-token index, not three worker transcripts.

Paid once and saved more: the plan reviewer, one agent at the gate, which removed an abstraction before three files depended on it and caught a gap that would have stopped a worker mid-task.
