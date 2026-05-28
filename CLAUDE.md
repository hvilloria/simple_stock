# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Always read first

1. `AGENTS.md` — **the single source of truth for agent rules**: source-of-truth priority, roles, scope control, backend/frontend rules
2. `WORKING_CONTEXT.md` — current system behavior and active constraints

All operating rules live in `AGENTS.md`. This file only adds what is specific to Claude Code: the commands and an architecture quick-reference.

## Commands

```bash
# Tests
bundle exec rspec                                    # full suite
bundle exec rspec spec/path/to/file_spec.rb          # single file
bundle exec rspec spec/path/to/file_spec.rb:42       # single example

# Lint
bundle exec rubocop                                  # check
bundle exec rubocop -a                               # auto-fix
```

## Architecture quick-reference

**Stack:** Rails 7.2, PostgreSQL, Hotwire, HAML, TailwindCSS, Devise (login only — registrations skipped), Pundit.

**Namespacing:** All web UI controllers live in `app/controllers/web/`; routes are prefixed `/web/`.

**Service layer:** `app/services/[domain]/[action].rb`. Every service exposes `.call(**params)`, returns a `Result` (see `app/services/result.rb`):

```ruby
Result = Struct.new(:success?, :record, :errors, keyword_init: true) do
  def failure? = !success?
end
```

**Controllers are thin:** receive params → call service → render/redirect. Direct ActiveRecord is acceptable for trivial single-model actions (e.g. invoice cancel sets `status` directly).

**Views:** HAML only (no ERB). No DB queries or business logic in views.

**Authorization:** Pundit policies in `app/policies/`. `ApplicationController` handles unauthorized → redirect with flash.

## Critical stock rule

Stock is **never mutated directly**. All changes go through:

```
Inventory::AdjustStock → StockMovement row → product.recalculate_current_stock!
```

`product.update!(current_stock: x)` is forbidden.

## Stable docs

- `docs/DEVELOPMENT_GUIDE.md` — architecture rules and business constraints
- `docs/CODE_PATTERNS.md` — concrete patterns (service template, query objects, anti-patterns)
- `docs/UI_DESIGN_SPEC.md` — frontend only
