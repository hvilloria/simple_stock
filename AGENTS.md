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

Defines which test layer a change belongs to. The goal is a regression net cheap to maintain for a solo developer: integration (request) specs are the base; browser (system) specs are a thin layer reserved for JS behavior.

### Layers

| Layer | Specs | When |
|-------|-------|------|
| Unit | `spec/models`, `spec/services` | Pure Ruby, no HTTP — isolated business logic, validations, calculations |
| Integration | `spec/requests` | Base regression net — "given these params, the system does X" + rejection of hostile input |
| E2E | `spec/system` | Only when correctness depends on Stimulus JS behavior |

### Decision tree (default + reason — not a blind mandate)

1. Pure model/service logic, no HTTP? → **unit**.
2. Crosses route → controller → service → DB? → **request**. If it touches money/amounts, include at least one **hostile-input** case (AR format `1.500.000,50`, negative, non-numeric, blank).
3. Correctness depends on Stimulus JS (disabled submit, live recalculation, cash-only rule, modals)? → **system** (minimal), in addition to the request spec.
4. When in doubt: **request over system** — cheaper and more robust.

A change may need more than one layer.

### Definition of Done

Every new flow enters at least through a request spec; it rises to a system spec only if its correctness depends on Stimulus JS; money flows include a hostile-input case. What counts as a "money flow": see `docs/TESTING_GUIDE.md`.

### Responsibilities

These map to the roles in "Role Definitions" above. The responsibility belongs to whoever performs the role, named agent or not.

- **Builder** (the `rails-builder` agent, or whoever implements the change — including the main session): applies the decision tree; writes tests alongside the feature; when the feature introduces a **new money flow** (a service or action that creates, persists, or computes amounts/discounts/balances/prices), adds it to the catalog in `docs/TESTING_GUIDE.md` under the right list (write-money / read-money); declares the choice in its output as a one-line **Test strategy** (layer + why; trivial changes = "unit, sin riesgo"); **flags** criticality for the user — does not decide it.
- **Reviewer** (the `code-reviewer` agent, or whoever reviews the change): verifies the chosen layer matches the tree; for money flows, confirms a request spec with a hostile-input case exists.

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

These rules apply to **every** commit message and to who runs the commit:

1. **Write commit messages in English.**
2. **Use Conventional Commit prefixes:** `feat`, `fix`, `ref`, `test`, `chore`, etc. (e.g. `feat: ...`, `fix: ...`, `ref: ...`).
3. **Do NOT add `Co-Authored-By` / "Generated with Claude" / any Anthropic attribution lines.**
4. **The agent does NOT run commits.** The user commits. Only run `git commit` when the user explicitly asks for it in that message (see also: never commit without explicit permission).

---

## Final Rule

When in doubt:

> Follow the existing codebase, not assumptions.
