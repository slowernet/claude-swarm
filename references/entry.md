# Entry format

Path: `.claude/swarm/<slug>/entries/<agent>-<n>.md` — the writing agent numbers its own entries from 1.

```markdown
---
id: scout-2-1
kind: fact            # fact | interpretation | decision | question
status: provisional   # provisional | verified | contradicted | obsolete
confidence: high      # high | medium | low
summary: API auth is enforced once, in AuthMiddleware, before routing
by: scout-2
evidence: src/middleware/auth.ts:41, src/router.ts:12
---

One short paragraph: the conclusion and what it rests on. State what was
checked, not just what was concluded — "grepped all 3 route registrars,
each mounts AuthMiddleware first" beats "auth seems centralized".
If this entry contradicts or supersedes another, name it by id.
```

Rules:

- `summary` must stand alone — it is what the index shows, and most readers never open the body.
- `evidence` is file paths (with line numbers when they matter), never prose.
- `kind: fact` is only for what verifiably exists in the repo. Beliefs about implications are `interpretation`. Keeping these separate is what lets a reviewer attack one without the other.
- One conclusion per entry. Two findings are two files.
- **Absence is a conclusion.** An entry saying a thing does not exist, listing where you looked, is worth as much as one saying it does — and saves the next agent the same fruitless search. Its `evidence` is the places checked.
- Do not paste code blocks longer than ~5 lines; cite the path instead.

## The conventions entry

The one entry every worker cites. Written by the conventions scout and verified at the gate — the lead flips its status rather than copying it into a new entry. `kind: fact`. It is the exception to the code-block rule: it must show real examples, because a worker cannot follow a rule it has to go and reconstruct.

```markdown
---
id: scout-4-1
kind: fact
status: verified
confidence: high
summary: Repo conventions — error idiom, test naming, test command
by: scout-4
evidence: lib/mill/runner.rb:88, test/mill/test_runner.rb:1, Rakefile:12
---

Errors: `rescue StandardError => e; log_error(e); raise` — never a bare rescue,
never swallowed. Tests: mirror the source path, `lib/mill/foo.rb` →
`test/mill/test_foo.rb`, one class per file. Run: `bundle exec rake test`;
passing output ends `N runs, N assertions, 0 failures, 0 errors, 0 skips`.
Hash keys are symbols throughout.
```

Not "follow existing patterns" — that is an instruction to go and find one, which every worker follows separately and differently.
