# AGENTS.md

## Purpose

This file defines how AI agents should operate in this project. It is the **single source of truth for agent rules**; `CLAUDE.md` defers to it and only adds Claude Code-specific commands and an architecture quick-reference.

Its goal is to ensure:
- correct context usage
- minimal and safe changes
- consistency with the existing codebase
- less hallucination and less unnecessary complexity

---

## Source of Truth Priority

Always follow this order:

1. **Actual code (highest priority)**
2. `WORKING_CONTEXT.md`
3. `docs/DEVELOPMENT_GUIDE.md`
4. `docs/CODE_PATTERNS.md`
5. `docs/UI_DESIGN_SPEC.md` (only for frontend tasks)
6. Other documents (non-authoritative)

If code and documentation conflict, trust the code.

---

## General Rules

- Do NOT assume features that are not implemented
- Do NOT invent behavior based on incomplete docs
- Always verify against real code
- Prefer existing patterns over new abstractions
- Keep solutions simple, minimal, and incremental
- Do not expand scope unless explicitly asked
- Do not treat documentation as truth without checking the code

---

## Required Task Flow

Before doing any meaningful work:

1. Read the relevant project documents
2. Inspect the relevant code
3. Identify similar existing patterns
4. Follow those patterns unless there is a strong reason not to

---

## Role Definitions

### Planner
Responsible for:
- understanding the request
- analyzing current code and context
- asking clarifying questions when needed
- proposing the safest and simplest approach
- identifying files to modify
- identifying risks
- updating `WORKING_CONTEXT.md` after implementation

Planner must NOT:
- jump directly into implementation
- invent architecture
- force refactors by default

### Builder
Responsible for:
- implementing the requested change
- following project rules and code patterns
- keeping scope tight
- touching the minimum number of files necessary

Builder must NOT:
- redesign the system without being asked
- refactor unrelated code
- add abstractions without strong justification

### Reviewer
Responsible for:
- checking correctness
- detecting overengineering
- spotting violations of project rules
- identifying scope creep or duplicated logic

Reviewer must NOT:
- rewrite the feature from scratch unless explicitly asked
- suggest large refactors without clear justification

---

## Backend Rules

Always:
- follow `docs/DEVELOPMENT_GUIDE.md`
- use patterns from `docs/CODE_PATTERNS.md`
- keep controllers thin
- use services only when needed
- return `Result` objects in services when that pattern applies
- validate behavior against actual code before changing flows

Never:
- add unnecessary services
- duplicate business logic
- update stock directly
- move business logic into controllers or views

---

## Frontend Rules

Always:
- follow `docs/UI_DESIGN_SPEC.md`
- use HAML + Tailwind
- keep UI consistent with existing views
- keep business logic out of views

Never:
- introduce a new UI paradigm without reason
- create inconsistent styling
- hide important behavior inside the view layer

---

## Testing Rules

Defines which test layer a change belongs to. The goal is a regression net cheap to maintain for a solo developer: integration (request) specs are the base; browser (system) specs stay a **thin** layer — but where JS touches money, they are **load-bearing, not optional** (see Rule A).

Three named rules govern the layers below: **Rule A** (wire-format contract), **Rule B** (hostile input), **Rule C** (authorization matrix).

### Layers

| Layer | Specs | When |
|-------|-------|------|
| Unit | `spec/models`, `spec/services` | Pure Ruby, no HTTP — isolated business logic, validations, calculations |
| Integration | `spec/requests` | Base regression net — "given these params, the system does X" + **Rule B** (hostile input) + **Rule C** (authorization matrix) |
| E2E | `spec/system` | **Rule A** — Stimulus formats/computes/mirrors a value that gets submitted. Runs only under `FULL=1` (needs Chrome) |

### Decision tree (default + reason — not a blind mandate)

1. Pure model/service logic, no HTTP? → **unit**.
2. Crosses route → controller → service → DB? → **request**. If it touches money/amounts, it must satisfy **Rule B** (hostile input).
3. Does Stimulus format, compute, or mirror backend logic on a value that gets **submitted**? → **system**, per **Rule A** — in addition to the request spec.
4. Does the change add or gate a route by role? → **Rule C** (authorization matrix).
5. When in doubt: **request over system** — cheaper and more robust. Rule A is the one case where that default does not apply.

A change may need more than one layer.

### Rule A — Wire-format contract

**For any screen where Stimulus formats, computes, or mirrors backend logic on a value that gets submitted, one system spec must drive the real form in a real browser and assert the *persisted* value.**

Rationale: a request spec tests what the *author believes* the browser sends. This class of bug lives in the seam between Stimulus and the controller — the JS sends `"1.500.000,50"` while the controller expects `1500000.5`, or the JS rounds one way and the service rounds another. Both sides pass their own tests; the seam is broken and **no other layer can see it**. Unit specs test each side in isolation; request specs test a hand-written payload that never came from the real form.

This promotes system specs from "nice to have" to **load-bearing for money screens**. The assertion must be on the **persisted value** (`order.reload.total_amount`), not on rendered text — rendered text can be right while the DB is wrong.

Applies whenever JS duplicates a backend rule: see `Payments::CashRounding` (Ruby) vs `app/javascript/helpers/cash_rounding.js` (JS) in `docs/TESTING_GUIDE.md`.

### Rule B — Hostile input

**Every money endpoint needs a request spec that POSTs hostile values *bypassing JS*.** A system spec is the wrong place for this: Stimulus would sanitize the value, so the backend's defense would never run.

Required cases:

| Case | Value | Why |
|------|-------|-----|
| AR-thousands | `"1.500.000,50"` | `.to_f` → `1.5` (stops at first dot) |
| **Clean-decimal** | `"1500.50"` | **Required.** Some controllers strip dots unconditionally → `"150050"` → `150050.0`, a **100×** error |
| Non-numeric | `"abc"` | `.to_f` → `0.0`, no error raised |
| Negative | `"-500"` | Must be rejected, not stored |
| Blank | `""` | Must be rejected, not coerced to `0` |

The clean-decimal case is non-negotiable: it is the one that catches a naive `gsub(".", "")` normalizer, and it is the case authors habitually omit because it "looks valid".

### Rule C — Authorization matrix

**Every gated route must be asserted for every role, via a table-driven request spec.**

The app has 3 roles (`vendedor`, `caja`, `admin`) and 12 Pundit policies, but only 5 policy specs — the gap is untested authorization, and a missing `authorize` call fails open (the action just runs). A policy unit spec proves the *policy* is right; it does **not** prove the controller *calls* it. Only a request spec does.

Drive it from a table (role × route → expected outcome), so adding a role or a route forces the matrix to be updated rather than silently under-tested.

### Definition of Done

Every new flow enters at least through a **request spec**. On top of that:

- **money flow** → satisfies **Rule B** (hostile-input case, including clean-decimal). What counts as a "money flow": see `docs/TESTING_GUIDE.md`.
- **Stimulus touches a submitted value** → satisfies **Rule A** (system spec asserting the persisted value).
- **role-gated route** → satisfies **Rule C** (authorization matrix).

### Running the suite

- `bundle exec rspec` — default net. Fast, **no browser**; system specs are excluded. Coverage is reported but not enforced.
- `FULL=1 bundle exec rspec` — everything, **including system specs** (Cuprite/headless Chrome), and enforces the SimpleCov floor. This is the gate a change must pass before it is done.

### Responsibilities

These map to the roles in "Role Definitions" above. The responsibility belongs to whoever performs the role, named agent or not.

- **Builder** (the `rails-builder` agent, or whoever implements the change — including the main session): applies the decision tree; writes tests alongside the feature; when the feature introduces a **new money flow** (a service or action that creates, persists, or computes amounts/discounts/balances/prices), adds it to the catalog in `docs/TESTING_GUIDE.md` under the right list (write-money / read-money); declares the choice in its output as a one-line **Test strategy** (layer + why; trivial changes = "unit, sin riesgo"); **flags** criticality for the user — does not decide it.
- **Reviewer** (the `code-reviewer` agent, or whoever reviews the change): verifies the chosen layer matches the tree; for money flows, confirms **Rule B** (hostile input, incl. clean-decimal) is covered; when Stimulus touches a submitted value, confirms **Rule A** (system spec on the persisted value) exists; for role-gated routes, confirms **Rule C** (authorization matrix) covers every role.

---

## Decision Making

When multiple approaches exist:

1. Choose the simplest valid solution
2. Prefer consistency with existing code
3. Avoid introducing new patterns unless clearly justified

Only propose multiple options when the decision is important.

---

## Scope Control

- Do not refactor unrelated code
- Do not modify files outside the task scope unless necessary
- Do not introduce large structural changes unless explicitly requested
- If a refactor seems useful, separate it from the minimal implementation path

---

## Error Handling

- Handle errors explicitly
- Do not silently fail
- Log unexpected errors when appropriate
- Make uncertainty explicit instead of guessing

---

## Working Context Rules

`WORKING_CONTEXT.md` is operational memory, not full documentation.

When updating it:
- keep it concise
- include only important current behavior, decisions, or constraints
- remove outdated notes when needed
- do not let it become a long narrative document

---

## Commit Conventions

These rules apply to **every** commit message and to who runs the commit. They are mirrored in `CLAUDE.md` §Commits and enforced mechanically by the `commit-msg` hook in `.githooks/` (activate with `git config core.hooksPath .githooks`):

1. **Write commit messages in English.** Never Spanish.
2. **Format `type(scope): title`**, then a blank line, then the body.
   - `type` ∈ `feat | fix | ref | refactor | test | chore | docs | perf | style | build | ci`.
   - `scope` = the numbered work-item from the **branch name**, kept **constant** across every commit on that branch (branch `fix-06_pending-issues` → `fix(fix_06): …`; branch `feat_18-…` → `feat(feat_18): …`). The `type` prefix may vary per commit; the scope does not.
   - When handing the user a message, give **only** the message text — no `Subject:` / `Body:` labels.
3. **Do NOT add `Co-Authored-By` / "Generated with Claude" / any Anthropic attribution lines.**
4. **The agent does NOT run commits.** The user commits. Only run `git commit` when the user explicitly asks for it in that message (see also: never commit without explicit permission).
5. **One logical change per commit** (e.g. one item from `docs/pendientes` per commit).

---

## Final Rule

When in doubt:

> Follow the existing codebase, not assumptions.
