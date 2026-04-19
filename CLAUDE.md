# CLAUDE.md

## Purpose

This file bootstraps Claude Code for this project.

Follow the project system already defined in the repository.
Do not invent a parallel workflow.

## Always read first

1. `AGENTS.md`
2. `WORKING_CONTEXT.md`

## Stable project docs

Read when relevant:
- `docs/DEVELOPMENT_GUIDE.md`
- `docs/CODE_PATTERNS.md`
- `docs/UI_DESIGN_SPEC.md` (frontend only)

## Role definitions

The canonical role definitions live here:
- `.agents/planner.md`
- `.agents/builder.md`
- `.agents/reviewer.md`

When asked to act as planner, builder, or reviewer, follow those files.

## Rules

- Trust code over docs if they conflict
- Do not assume unimplemented behavior
- Keep changes minimal and incremental
- Do not refactor unrelated code
- Use the planner first for non-trivial work
- Update `WORKING_CONTEXT.md` when meaningful behavior or constraints change