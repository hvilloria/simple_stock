# Invoice Index Pagination — Design Spec

**Date:** 2026-06-15
**Branch:** feat_13-pagination-on-invoices
**Scope:** Add numbered pagination to `app/views/web/invoices/index.html.haml`, 20 records per page, filter-aware.

---

## Problem

`Web::InvoicesController#index` currently caps results with `.limit(50)`. As the invoice count grows, records beyond 50 are invisible. There is no UI to navigate between pages.

---

## Solution

Add `pagy` gem and wire numbered pagination into the existing Turbo Frame flow. Filters (`supplier_id`, `invoice_search`) are preserved on every page link.

---

## Dependencies & Setup

- **Gem:** `gem "pagy"` added to `Gemfile` (v8.x, zero runtime dependencies).
- **Initializer:** `config/initializers/pagy.rb` sets `Pagy::DEFAULT[:items] = 20`. This is the single source of truth for per-page count.
- **`ApplicationController`:** Include `Pagy::Backend` to provide the `pagy()` controller helper.
- **`ApplicationHelper`:** Include `Pagy::Frontend` to provide `pagy_url_for()` for view link generation.

---

## Controller Changes

File: `app/controllers/web/invoices_controller.rb`, `#index` action.

**Replace:**
```ruby
@invoices = invoices_scope.priority_order.limit(50)
```

**With:**
```ruby
@pagy, @invoices = pagy(invoices_scope.priority_order)
```

- `items: 20` is inherited from the initializer default.
- `params[:page]` is read automatically by pagy.
- The `metrics_scope` block is untouched — metric cards always reflect all filtered invoices, not just the current page.

---

## View Changes

File: `app/views/web/invoices/index.html.haml`

Inside `turbo_frame_tag "invoices_content"`, after the invoice table and empty-state block, add a pagination nav:

```
← Anterior    1  2  3  …  8  [9]  10    Siguiente →
```

### Rules

- Render only when `@pagy.pages > 1`.
- Built with `@pagy.series` (sequence of page numbers and `:gap` symbols) and `pagy_url_for(@pagy, n)` (generates URL for page `n`).
- `pagy_url_for` merges into current request params, so `supplier_id` and `invoice_search` are preserved on every page link.
- All page links are plain `<a>` tags. Inside the Turbo Frame they automatically target the frame — clicking page 2 replaces only the frame content, not the full page.

### Styles

| Element | Style |
|---|---|
| Current page | Solid slate button, non-clickable |
| Other pages | Ghost/outline button, hover slate |
| `:gap` | Plain `…` text, no button |
| Prev/Next disabled | Grayed out, `pointer-events-none` |

---

## What Does NOT Change

- Metric cards (Deuda Total Pendiente, Crédito a Favor, Balance Neto) — computed from `metrics_scope`, not `@invoices`.
- Filter form and Turbo Frame setup — untouched.
- All other controller actions — untouched.
- No other controllers get pagination in this task.

---

## Files Touched

| File | Change |
|---|---|
| `Gemfile` | Add `gem "pagy"` |
| `config/initializers/pagy.rb` | New — sets `DEFAULT[:items] = 20` |
| `app/controllers/application_controller.rb` | Include `Pagy::Backend` |
| `app/helpers/application_helper.rb` | Include `Pagy::Frontend` |
| `app/controllers/web/invoices_controller.rb` | Replace `.limit(50)` with `pagy(...)` |
| `app/views/web/invoices/index.html.haml` | Add pagination nav inside Turbo Frame |
