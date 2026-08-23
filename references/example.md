# Worked example

Task: "Add rate limiting to our public API. Per-key limits, 429 with Retry-After, existing keys grandfathered at a higher tier." Express/TypeScript repo, ~400 files, unfamiliar to the lead.

## Plan

Lead restates the problem in `plan.md`, lists what must be known:

1. Where do API requests enter, and where does auth resolve the key? (scout)
2. Is there existing middleware/infra a limiter should follow as a pattern? Any redis/store already in the stack? (scout)
3. How are API keys modeled, and where would a "tier" live? (scout)
4. What do existing 4xx responses look like — error shape, tests? (answerable during scouting 1, folded in)

Tasks created with dependencies:

- T1 limiter middleware + unit tests — blockedBy: scouting
- T2 key-tier model change + migration — blockedBy: scouting
- T3 wire middleware into request path, integration tests — blockedBy: T1, T2
- T4 docs — blockedBy: T3

File partition: T1 `src/middleware/ratelimit.ts` + its test; T2 `src/models/apikey.ts` + migration dir; T3 `src/app.ts` + integration tests. Disjoint → T1 and T2 parallel, T3 sequential after both. Sizing row: multi-file feature, unfamiliar repo → 3 scouts, 3 workers (T4 folded into T3's worker), 1 integrator, 1 reviewer.

## Scouts

Three spawned in one message, one question each. They index-check (store empty), investigate, write entries:

- `scout-1-1` (fact, high): all API routes mount through `src/api/router.ts`; auth resolves key in `AuthMiddleware` (`src/middleware/auth.ts:41`) and sets `req.apiKey`
- `scout-1-2` (fact, high): error responses use `ApiError` helper, shape `{error, code}`; tests assert on `code`
- `scout-2-1` (fact, high): redis client already exists at `src/lib/redis.ts`, used by session cache
- `scout-2-2` (interpretation, medium): middleware ordering matters — body-parser assumes auth ran; limiter should mount after auth, before routing
- `scout-3-1` (fact, high): `ApiKey` model in `src/models/apikey.ts`, migrations in `db/migrations/`, pattern is timestamped files
- `scout-3-2` (question): no existing concept of "tier" — name and default value need a decision

Each returns 3 lines + IDs. Lead's cost: one index command (~90 tokens for 6 entries) plus two entry bodies it chose to open.

## Gate

Lead reads the index, opens `scout-2-2` and `scout-3-2`. Decisions written:

- `lead-1` (decision): limiter mounts after auth in `app.ts`, keyed on `req.apiKey.id`, backed by existing redis client — cites scout-1-1, scout-2-1, scout-2-2
- `lead-2` (decision): tier is an enum column `tier` on api_keys, default `standard`; migration backfills existing keys to `legacy` (the grandfather tier) — resolves scout-3-2

Digest surfaced to the user; scope confirmed. `scout-2-2` is medium-confidence but load-bearing → lead sends one follow-up message to scout-2 (warm context): "verify ordering claim against how session cache middleware mounts." Scout-2 replies with evidence, flips its entry to `verified`.

## Work

worker-1 (T1) and worker-2 (T2) spawn in parallel, each with: task ID, the 3-4 entry IDs that matter to them, file scope, binding decisions (`lead-1`, `lead-2`). Neither re-explores the router or the redis client — the entries answer it.

worker-2 discovers mid-task that the migration runner requires a model version bump (`worker-2-1`, fact) — written to the store, not just mentioned in its report. worker-3 (T3), spawning later, reads it from the index and avoids the same trap.

worker-3 wires the middleware, writes integration tests asserting the 429 shape against `scout-1-2`'s error contract, updates docs, completes T3 and T4.

## Integrate

Integrator reads the diff and the index. Finds one seam: worker-1 named the redis keyspace `rl:` while worker-3's test asserted `ratelimit:` — fixes the test to match the implementation, cites `lead-1`. Runs the full suite; green; reports actual output.

## Review

Reviewer (correctness lens, report-only) checks the diff against the task. Two findings:

- high: limiter counts requests before auth *failures* are rejected, so invalid keys consume a valid key's budget when key IDs collide on prefix — file:line, repro described
- medium: no test covers the Retry-After header value, only its presence

It cannot disprove any entry; store stands. Verdict: RETURN-TO-WORKERS with the high finding. Lead messages worker-1 (warm context, has the middleware loaded), which fixes and adds the missing test. Lead re-runs the suite in-session, confirms green, done.

## The token ledger

What was paid once instead of N times: the router/auth topology (explored by scout-1, reused by workers 1 and 3 and the integrator), the redis discovery, the migration-runner trap (worker-2's find, worker-3's savings), the error-shape contract. Follow-ups went to warm contexts twice instead of fresh spawns. The reviewer read a diff plus a 90-token index, not three worker transcripts.
