# DEVELOPMENT_GUIDE.md

## Purpose

This document defines **how development should be done in this project**.

It is the **source of truth for architecture, rules, and conventions**.
It must remain stable and should not depend on other volatile documents.

---

## Tech Stack

* Ruby on Rails 7+
* PostgreSQL
* Hotwire (Turbo + Stimulus)
* HAML for views
* TailwindCSS

---

## Source of Truth Priority

When making decisions, follow this order:

1. **Actual code (highest priority)**
2. This document (`DEVELOPMENT_GUIDE.md`)
3. `CODE_PATTERNS.md`
4. `UI_DESIGN_SPEC.md` (only for frontend)
5. Other docs (non-authoritative)

---

## Core Principles

* Prefer **simple solutions over abstractions**
* Avoid **premature optimization or generalization**
* Keep changes **small and incremental**
* Do not refactor unrelated code
* Always align with **existing patterns in the codebase**

---

## Architecture

### Models

Responsible for:

* Associations
* Validations
* Simple calculations
* Scopes

Must NOT contain:

* Complex business orchestration
* Multi-step workflows
* Controller logic

---

### Services

Use services only when:

* Multiple models are involved
* A transaction is required
* There is coordination logic

Rules:

* Always use `.call` as entrypoint
* Always return a `Result` object
* Must handle errors explicitly
* Must wrap logic in transactions when needed

---

### Controllers

Must be **thin**.

Responsibilities:

* Receive params
* Call services or models
* Handle responses (redirect/render)

Must NOT:

* Contain business logic
* Create multiple records manually
* Perform complex calculations

---

### Views (HAML)

Responsible only for:

* Presentation
* Rendering data
* UI structure

Must NOT:

* Query database
* Contain business logic

---

## Business Rules (Critical)

These rules must NEVER be violated:

### Stock

* Stock is NEVER updated directly on Product
* Always use `StockMovement`
* No negative stock allowed
* Stock = sum of movements

---

### Sales

* `cash` sales → do NOT generate balance
* `credit` sales → affect customer balance
* Cancelling a sale must:

  * revert stock
  * exclude it from balance

---

### Payments

* `Payment` representa un *tender* — entrega física de dinero con un método único (cash/transfer/check/card)
* Un `Payment` se asigna a una o más `Order`s vía `PaymentAllocation`s (`payment_allocations(payment_id, order_id, amount)`)
* Invariante: `payment.amount == SUM(allocations.amount)` — garantizada por `Payments::AllocatePayment`
* `Order#outstanding_balance` = `total_amount − payment_allocations.sum(:amount)` (solo `credit + confirmed`)
* `Customer#current_balance` = `SUM(credit_orders.total_amount) − SUM(payments.amount)` — los allocations no intervienen en el balance del cliente

---

### Purchases

* Purchases create positive stock movements
* Must recalculate weighted average cost
* Currency handling must be consistent

---

## Conventions

* Follow existing naming conventions
* Do not introduce new patterns without strong reason
* Do not add new dependencies unnecessarily
* Prefer explicit code over magic

---

## Anti-Patterns

Avoid:

* Fat controllers
* God services
* Direct stock manipulation
* Duplicated business logic
* Creating abstractions without clear reuse

---

## Testing

* Add tests when logic is non-trivial
* Do not over-test trivial code
* Focus on:

  * services
  * critical business logic

---

## Decision Guidelines

Before implementing anything, always ask:

* Does this already exist in the codebase?
* Can this be solved simpler?
* Am I introducing unnecessary abstraction?
* Does this follow existing patterns?

If unsure:
→ prefer consistency over “better design”

---

## Final Rule

When in doubt:

> Follow the codebase, not assumptions.
