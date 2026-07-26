# Invoice and Credit Note List Filters — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `web/invoices#index` a status filter whose selection also chooses the date axis and ordering, and fix `web/credit_notes#index` — pagination, dead filter options, and page-scoped metrics.

**Architecture:** Filtering and ordering live in model scopes; controllers pick a scope by status and hand the relation to `pagy`; views drop their turbo frames so filters travel in the URL. No migration — `invoices.paid_at` already exists and is stamped by `Invoice#mark_as_paid!`, which both payment paths go through.

**Tech Stack:** Rails 7.2, PostgreSQL, HAML, TailwindCSS, Pundit, pagy, RSpec + FactoryBot.

Spec: `docs/superpowers/specs/2026-07-26-invoice-credit-note-filters-design.md`

## Global Constraints

- **One commit for the whole feature, run by the user.** Never run `git commit`. Do not commit per task. When every task is done, stage the files and hand over the message.
- **English in every file** — code, comments, specs, docs. UI copy stays in Spanish because it is user-facing product text.
- **Comments: as few as possible.** Only where the code cannot explain itself. Never cite `AGENTS.md` or any doctrine document from inside code or specs.
- **HAML only.** No ERB, no DB queries and no business logic in views.
- **Reuse what exists.** The `filter-form` Stimulus controller (`change->filter-form#submit`, `input->filter-form#submitWithDebounce`) already drives every filter card in the app — do not write a new one. The pagination block is copied verbatim from `app/views/web/orders/index.html.haml:101-119`.
- **Every task ends green:** `bundle exec rspec <the files you touched>` passes and `bundle exec rubocop` is clean.
- Page size is 20 (`Pagy::DEFAULT[:items]`, set in `config/initializers/pagy.rb`). Do not override it.
- Both index actions require `user.admin?` to reach (`InvoicePolicy#index?`) or any signed-in user (`CreditNotePolicy#index?`). Request specs sign in an admin for both.

---

## File Structure

| File | Responsibility | Task |
| --- | --- | --- |
| `app/models/invoice.rb` | Status filter scope, payment-date ordering, tiebreaker on `priority_order` | 1 |
| `spec/models/invoice_spec.rb` | Scope behaviour, including the ordering that reverting would break | 1 |
| `app/controllers/web/invoices_controller.rb` | Resolve `@status`, choose the ordering, paginate | 2 |
| `spec/requests/web/invoices_spec.rb` | **New.** Filter sets, axis flip, out-of-domain status, pagination stability | 2 |
| `app/views/web/invoices/index.html.haml` | Status select, axis column, frame removal, empty state, clear button | 3 |
| `app/models/credit_note.rb` | Balance scopes in SQL, availability filter, tiebreaker on `recent` | 4 |
| `spec/models/credit_note_spec.rb` | Balance scopes and the three filter options | 4 |
| `app/controllers/web/credit_notes_controller.rb` | Pagination, eager loading, metrics on an unpaginated scope | 5 |
| `spec/requests/web/credit_notes_spec.rb` | **New.** Filter options return rows, metrics independent of page | 5 |
| `app/views/web/credit_notes/index.html.haml` | Corrected select values, pagination block, frame removal, empty state | 6 |

Tasks 1-3 (invoices) and 4-6 (credit notes) are independent of each other. Within
each group, order matters.

---

## Task 1: Invoice scopes

**Files:**
- Modify: `app/models/invoice.rb:82-94`
- Test: `spec/models/invoice_spec.rb`

**Interfaces:**
- Consumes: nothing.
- Produces — Task 2 calls all three:
  - `Invoice.by_status_filter(status)` → `ActiveRecord::Relation`. `status` is a `String`; anything not a key of `Invoice.statuses` leaves the relation untouched.
  - `Invoice.by_payment_date` → `ActiveRecord::Relation` ordered `paid_at DESC NULLS LAST, id DESC`.
  - `Invoice.priority_order` → existing scope, now with an `id DESC` tiebreaker.

**Background:** `Invoice.statuses` is `{"pending"=>"pending", "paid"=>"paid", "confirmed"=>"confirmed", "cancelled"=>"cancelled"}`. The `:paid` factory trait already sets `status: "paid"` and `paid_at: Date.yesterday`, and includes `:simple_mode`.

- [ ] **Step 1: Write the failing tests**

Add to `spec/models/invoice_spec.rb`, inside the top-level `RSpec.describe Invoice`:

```ruby
describe ".by_status_filter" do
  let!(:pending_invoice) { create(:invoice, :simple_mode) }
  let!(:paid_invoice) { create(:invoice, :paid) }

  it "keeps only invoices in the given status" do
    expect(Invoice.by_status_filter("paid")).to contain_exactly(paid_invoice)
  end

  it "ignores a status outside the enum" do
    expect(Invoice.by_status_filter("bogus")).to contain_exactly(pending_invoice, paid_invoice)
  end
end

describe ".by_payment_date" do
  it "puts the most recently paid invoice first, whatever its due date" do
    paid_today = create(:invoice, :paid, due_date: 6.months.ago.to_date, paid_at: Date.current)
    paid_last_week = create(:invoice, :paid, due_date: 1.month.from_now.to_date, paid_at: 1.week.ago.to_date)

    result = Invoice.where(id: [ paid_today.id, paid_last_week.id ]).by_payment_date

    expect(result).to eq([ paid_today, paid_last_week ])
  end

  it "pushes invoices without a payment date to the end" do
    dated = create(:invoice, :paid, paid_at: 1.month.ago.to_date)
    undated = create(:invoice, :paid, paid_at: nil)

    result = Invoice.where(id: [ dated.id, undated.id ]).by_payment_date

    expect(result).to eq([ dated, undated ])
  end

  it "breaks ties on the payment date by id, newest first" do
    same_day = 3.days.ago.to_date
    older = create(:invoice, :paid, paid_at: same_day)
    newer = create(:invoice, :paid, paid_at: same_day)

    result = Invoice.where(id: [ older.id, newer.id ]).by_payment_date

    expect(result).to eq([ newer, older ])
  end
end
```

And add this example inside the **existing** `describe ".priority_order"` block (it starts at `spec/models/invoice_spec.rb:381`):

```ruby
it "breaks ties on the due date by id, newest first" do
  due = 10.days.from_now.to_date
  older = create(:invoice, :simple_mode, due_date: due)
  newer = create(:invoice, :simple_mode, due_date: due)

  result = Invoice.where(id: [ older.id, newer.id ]).priority_order

  expect(result).to eq([ newer, older ])
end
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `bundle exec rspec spec/models/invoice_spec.rb -e "by_status_filter" -e "by_payment_date" -e "priority_order"`

Expected: the `by_status_filter` and `by_payment_date` examples fail with `NoMethodError: undefined method 'by_status_filter'` / `'by_payment_date'`. The new `priority_order` example fails **only sometimes** — without a tiebreaker Postgres may return either order. If it happens to pass on the first run, that is exactly the instability being fixed; continue anyway.

- [ ] **Step 3: Add the scopes**

In `app/models/invoice.rb`, right after the existing `search_invoice` scope (line 85):

```ruby
  # Filter by status, ignoring values outside the enum
  scope :by_status_filter, ->(status) { where(status: status) if statuses.key?(status.to_s) }

  # Ordered by payment date, most recent first
  scope :by_payment_date, -> { order(Arel.sql("paid_at DESC NULLS LAST"), id: :desc) }
```

- [ ] **Step 4: Add the tiebreaker to `priority_order`**

Replace the existing scope at `app/models/invoice.rb:88-94` with:

```ruby
  # Ordered by priority: 1) pending first, 2) nearest due date
  scope :priority_order, -> {
    order(
      Arel.sql("CASE WHEN status = 'pending' THEN 0 ELSE 1 END"),
      Arel.sql("CASE WHEN due_date IS NULL THEN 1 ELSE 0 END"),
      "due_date ASC",
      "id DESC"
    )
  }
```

- [ ] **Step 5: Run the whole model spec**

Run: `bundle exec rspec spec/models/invoice_spec.rb`
Expected: all green. The pre-existing `priority_order` examples must still pass — the tiebreaker only makes their result deterministic, it never reorders across different due dates.

- [ ] **Step 6: Lint**

Run: `bundle exec rubocop app/models/invoice.rb spec/models/invoice_spec.rb`

---

## Task 2: Invoices controller

**Files:**
- Modify: `app/controllers/web/invoices_controller.rb:10-46`
- Test: `spec/requests/web/invoices_spec.rb` (create)

**Interfaces:**
- Consumes: `Invoice.by_status_filter`, `Invoice.by_payment_date`, `Invoice.priority_order` from Task 1.
- Produces — Task 3 reads both from the view:
  - `@status` → `String`, always one of `"pending"`, `"paid"`, `"cancelled"`. Never blank, never anything else.
  - `@invoices`, `@pagy` → as today.

- [ ] **Step 1: Write the failing request spec**

Create `spec/requests/web/invoices_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::Invoices", type: :request do
  let(:admin) { create(:user, role: "admin") }
  let(:supplier) { create(:supplier, name: "Distribuidora Norte") }

  before { sign_in admin }

  describe "GET /web/invoices" do
    it "shows pending invoices by default and hides the paid ones" do
      create(:invoice, :simple_mode, supplier: supplier, invoice_number: "PEND-1")
      create(:invoice, :paid, supplier: supplier, invoice_number: "PAID-1")

      get "/web/invoices"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("PEND-1")
      expect(response.body).not_to include("PAID-1")
    end

    it "shows only paid invoices when the status is paid" do
      create(:invoice, :simple_mode, supplier: supplier, invoice_number: "PEND-1")
      create(:invoice, :paid, supplier: supplier, invoice_number: "PAID-1")

      get "/web/invoices", params: { status: "paid" }

      expect(response.body).to include("PAID-1")
      expect(response.body).not_to include("PEND-1")
    end

    it "shows only cancelled invoices when the status is cancelled" do
      create(:invoice, :simple_mode, supplier: supplier, invoice_number: "PEND-1")
      create(:invoice, :simple_mode, supplier: supplier, invoice_number: "CANC-1", status: "cancelled")

      get "/web/invoices", params: { status: "cancelled" }

      expect(response.body).to include("CANC-1")
      expect(response.body).not_to include("PEND-1")
    end

    it "falls back to pending when the status is outside the enum" do
      create(:invoice, :simple_mode, supplier: supplier, invoice_number: "PEND-1")
      create(:invoice, :paid, supplier: supplier, invoice_number: "PAID-1")

      get "/web/invoices", params: { status: "'; DROP TABLE invoices; --" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("PEND-1")
      expect(response.body).not_to include("PAID-1")
    end

    it "sorts paid invoices by payment date, not by due date" do
      create(:invoice, :paid, supplier: supplier, invoice_number: "OLD-DUE",
             due_date: 6.months.ago.to_date, paid_at: Date.current)
      create(:invoice, :paid, supplier: supplier, invoice_number: "NEW-DUE",
             due_date: 1.month.from_now.to_date, paid_at: 1.week.ago.to_date)

      get "/web/invoices", params: { status: "paid" }

      expect(response.body.index("OLD-DUE")).to be < response.body.index("NEW-DUE")
    end

    it "keeps the supplier filter while filtering by status" do
      other_supplier = create(:supplier, name: "Mayorista Sur")
      create(:invoice, :paid, supplier: supplier, invoice_number: "MINE-1")
      create(:invoice, :paid, supplier: other_supplier, invoice_number: "THEIRS-1")

      get "/web/invoices", params: { status: "paid", supplier_id: supplier.id }

      expect(response.body).to include("MINE-1")
      expect(response.body).not_to include("THEIRS-1")
    end

    it "does not repeat an invoice across pages when due dates tie" do
      due = 10.days.from_now.to_date
      25.times { |i| create(:invoice, :simple_mode, supplier: supplier, invoice_number: "TIE-#{i}", due_date: due) }

      get "/web/invoices"
      first_page = response.body.scan(/TIE-\d+/).uniq

      get "/web/invoices", params: { page: 2 }
      second_page = response.body.scan(/TIE-\d+/).uniq

      expect(first_page.size).to eq(20)
      expect(second_page.size).to eq(5)
      expect(first_page & second_page).to be_empty
    end
  end
end
```

- [ ] **Step 2: Run the spec and confirm it fails**

Run: `bundle exec rspec spec/requests/web/invoices_spec.rb`
Expected: the status examples fail because the index ignores `params[:status]` and renders every invoice; the ordering example fails because paid invoices still sort by due date.

- [ ] **Step 3: Apply the filter in the controller**

Replace the body of `index` in `app/controllers/web/invoices_controller.rb` (lines 10-46) — keep everything from `@total_pending_amount` onward exactly as it is, only the scope building and pagination change:

```ruby
    def index
      authorize Invoice

      @suppliers = Supplier.alphabetical
      @selected_supplier = Supplier.find_by(id: params[:supplier_id]) if params[:supplier_id].present?
      @status = normalize_status(params[:status])

      invoices_scope = Invoice.simple_mode
                              .includes(:supplier)
                              .for_supplier(@selected_supplier)
                              .search_invoice(params[:invoice_search])
                              .by_status_filter(@status)

      @pagy, @invoices = pagy(ordered_invoices(invoices_scope))

      metrics_scope = Invoice.simple_mode
                              .pending_payment
                              .for_supplier(@selected_supplier)
                              .search_invoice(params[:invoice_search])

      @total_pending_amount = metrics_scope.sum { |i| i.total_amount_ars(include_discount: true) }

      credit_notes_scope = CreditNote.includes(:supplier)
                                      .for_supplier(@selected_supplier)
                                      .available

      @total_credit_amount = credit_notes_scope.sum { |cn| cn.remaining_balance_ars }
      @credit_notes_count = credit_notes_scope.count(&:available?)

      @net_balance = @total_pending_amount - @total_credit_amount
    end
```

Note the metric scopes are unchanged: they deliberately ignore `@status`, so the cards keep reporting global pending debt.

- [ ] **Step 4: Add the two private helpers**

In the `private` section of `app/controllers/web/invoices_controller.rb`, directly after `def load_suppliers ... end`:

```ruby
    STATUS_FILTERS = %w[pending paid cancelled].freeze

    def normalize_status(status)
      STATUS_FILTERS.include?(status) ? status : "pending"
    end

    def ordered_invoices(scope)
      @status == "paid" ? scope.by_payment_date : scope.priority_order
    end
```

`STATUS_FILTERS` is narrower than the enum on purpose: `confirmed` belongs to full-mode purchases, which this index never shows (`simple_mode`).

- [ ] **Step 5: Run the request spec**

Run: `bundle exec rspec spec/requests/web/invoices_spec.rb`
Expected: all green.

- [ ] **Step 6: Prove the axis test would catch a revert**

Temporarily change `ordered_invoices` to `scope.priority_order` unconditionally and run:

`bundle exec rspec spec/requests/web/invoices_spec.rb -e "sorts paid invoices by payment date"`

Expected: FAIL. Restore the method and re-run to confirm it passes again. If it passed while reverted, the example is not testing what it claims — fix it before continuing.

- [ ] **Step 7: Lint**

Run: `bundle exec rubocop app/controllers/web/invoices_controller.rb spec/requests/web/invoices_spec.rb`

---

## Task 3: Invoices view

**Files:**
- Modify: `app/views/web/invoices/index.html.haml`

**Interfaces:**
- Consumes: `@status`, `@invoices`, `@pagy`, `@selected_supplier` from Task 2.
- Produces: nothing.

- [ ] **Step 1: Remove the turbo frame**

Two edits, and they must be made together — removing one without the other breaks the page.

At line 15, drop the frame target from the form's `data:`:

```haml
    = form_with url: web_invoices_path, method: :get, data: { controller: "filter-form" }, class: "flex flex-col md:flex-row items-stretch md:items-center gap-4" do |f|
```

Then delete line 36 (`= turbo_frame_tag "invoices_content" do`) and **dedent its entire body by two spaces** — everything from the metric cards down to the end of the pagination block.

- [ ] **Step 2: Verify the indentation**

HAML is whitespace-sensitive and a misplaced nesting level here renders a silently broken page. Do not eyeball it — print the leading whitespace of the block openers:

Run: `grep -n "^ *\(- if @invoices\|- else\|- if @pagy\|%div.grid\)" app/views/web/invoices/index.html.haml | cat -A | cut -c1-60`

Expected: every one of those lines starts with exactly four spaces — the same level as the `.bg-white...` filter card near the top, i.e. one level inside `.container`. A line at six spaces means the dedent was missed there.

- [ ] **Step 3: Add the status select**

Inside the filter form, between the supplier dropdown (ends line 26) and the clear button:

```haml
      -# Status filter — also selects the date axis of the list
      .flex-1
        = select_tag :status,
                     options_for_select([ [ "Pendientes", "pending" ], [ "Pagadas", "paid" ], [ "Canceladas", "cancelled" ] ], @status),
                     class: "w-full px-4 py-3 border border-slate-300 rounded-xl focus:ring-2 focus:ring-slate-500 focus:border-transparent transition-all",
                     data: { action: "change->filter-form#submit" }
```

- [ ] **Step 4: Update the clear button condition**

Replace the condition at line 29:

```haml
      - if @selected_supplier || params[:invoice_search].present? || @status != "pending"
```

- [ ] **Step 5: Make the date column follow the axis**

At the very top of the file, right under the `content_for`:

```haml
- date_header = @status == "paid" ? "Pagada el" : "Vencimiento"
```

Replace the header cell (currently lines 116-117):

```haml
              %th.px-4.py-3.text-left.text-xs.font-medium.text-slate-500.uppercase.tracking-wider
                = date_header
```

Replace the body cell (currently lines 141-147) in full:

```haml
                %td.px-4.py-3.whitespace-nowrap
                  - if @status == "paid"
                    %p.text-sm.text-slate-900= invoice.paid_at ? invoice.paid_at.strftime("%d/%m/%Y") : "—"
                  - elsif invoice.due_date
                    %p.text-sm.text-slate-900= invoice.due_date.strftime("%d/%m/%Y")
                    - if invoice.overdue?
                      %p.text-xs.text-red-600.font-medium ¡Vencida!
                    - elsif invoice.days_until_due && invoice.days_until_due <= 7 && invoice.days_until_due > 0
                      %p.text-xs.text-orange-600 Vence en #{invoice.days_until_due} días
```

The overdue warnings now render only outside the paid branch. Under Canceladas the due date still shows, and `overdue?` may still flag it — that is correct, a cancelled invoice that was never paid did go past its date.

- [ ] **Step 6: Replace the empty state**

Replace the whole `- else` block (currently lines 188-196) with:

```haml
    - else
      .bg-white.border.border-slate-200.rounded-lg.p-16.text-center
        .inline-flex.w-20.h-20.rounded-full.bg-gray-100.items-center.justify-center.text-4xl.mb-4
          📄
        %h3.text-xl.font-bold.text-gray-900.mb-2 No hay facturas con esos filtros
        %p.text-gray-600.mb-6 Probá con otro estado o quitá los filtros.
        = link_to "✕ Limpiar filtros", web_invoices_path, class: "inline-flex items-center justify-center px-4 py-2 border border-slate-300 rounded-lg text-sm font-medium text-slate-700 bg-white hover:bg-slate-50 transition-colors"
```

- [ ] **Step 7: Run the request spec**

Run: `bundle exec rspec spec/requests/web/invoices_spec.rb`
Expected: still all green — the view renders without raising and the filtered sets are unchanged.

- [ ] **Step 8: Confirm the frame is gone**

Run: `grep -rn "invoices_content" app/`
Expected: no output. A leftover reference means either the form or the wrapper survived.

---

## Task 4: CreditNote scopes

**Files:**
- Modify: `app/models/credit_note.rb:33-37`
- Test: `spec/models/credit_note_spec.rb`

**Interfaces:**
- Consumes: nothing.
- Produces — Task 5 calls `by_availability`; the other two are its building blocks:
  - `CreditNote.with_balance` / `CreditNote.exhausted_credits` → `ActiveRecord::Relation`.
  - `CreditNote.by_availability(filter)` → `ActiveRecord::Relation`. `filter` is a `String`; `"available"`, `"applied"` and `"cancelled"` narrow, anything else (including `""`) leaves the relation untouched.

**Background:** the balance is not a column. `remaining_balance` is `amount - applied_credits.sum(:amount)`, computed in Ruby. It has to move into SQL so that filtering and pagination see the same set. `AppliedCredit` validates that its invoice and credit note share a supplier — build both from the same supplier in the specs or the factory will fail validation.

- [ ] **Step 1: Write the failing tests**

Add to `spec/models/credit_note_spec.rb`, inside the top-level describe:

```ruby
describe "balance scopes" do
  let(:supplier) { create(:supplier) }
  let(:invoice) { create(:invoice, :simple_mode, supplier: supplier) }
  let!(:untouched) { create(:credit_note, supplier: supplier, amount: 1000) }
  let!(:partially_used) { create(:credit_note, supplier: supplier, amount: 1000) }
  let!(:drained) { create(:credit_note, supplier: supplier, amount: 1000) }

  before do
    create(:applied_credit, credit_note: partially_used, invoice: invoice, amount: 400)
    create(:applied_credit, credit_note: drained, invoice: invoice, amount: 1000)
  end

  it "keeps notes that still have balance" do
    expect(CreditNote.with_balance).to contain_exactly(untouched, partially_used)
  end

  it "keeps notes whose balance is fully consumed" do
    expect(CreditNote.exhausted_credits).to contain_exactly(drained)
  end
end

describe ".by_availability" do
  let(:supplier) { create(:supplier) }
  let(:invoice) { create(:invoice, :simple_mode, supplier: supplier) }
  let!(:available_note) { create(:credit_note, supplier: supplier, amount: 1000) }
  let!(:applied_note) { create(:credit_note, supplier: supplier, amount: 1000) }
  let!(:cancelled_note) { create(:credit_note, :cancelled, supplier: supplier, amount: 1000) }

  before { create(:applied_credit, credit_note: applied_note, invoice: invoice, amount: 1000) }

  it "returns active notes with balance for 'available'" do
    expect(CreditNote.by_availability("available")).to contain_exactly(available_note)
  end

  it "returns active notes without balance for 'applied'" do
    expect(CreditNote.by_availability("applied")).to contain_exactly(applied_note)
  end

  it "returns cancelled notes for 'cancelled'" do
    expect(CreditNote.by_availability("cancelled")).to contain_exactly(cancelled_note)
  end

  it "returns everything when no filter is given" do
    expect(CreditNote.by_availability("")).to contain_exactly(available_note, applied_note, cancelled_note)
  end

  it "returns everything for a value outside the filter set" do
    expect(CreditNote.by_availability("bogus")).to contain_exactly(available_note, applied_note, cancelled_note)
  end
end

describe ".recent" do
  it "breaks ties on the issue date by id, newest first" do
    supplier = create(:supplier)
    same_day = Date.current
    older = create(:credit_note, supplier: supplier, issue_date: same_day)
    newer = create(:credit_note, supplier: supplier, issue_date: same_day)

    expect(CreditNote.where(id: [ older.id, newer.id ]).recent).to eq([ newer, older ])
  end
end
```

A cancelled note with full balance is deliberately excluded from `"available"` — cancelled credit cannot be applied, so it is not available regardless of its balance.

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `bundle exec rspec spec/models/credit_note_spec.rb -e "balance scopes" -e "by_availability" -e "recent"`
Expected: `NoMethodError` for `with_balance`, `exhausted_credits` and `by_availability`. The `recent` example may pass by luck — that is the instability being fixed.

- [ ] **Step 3: Add the scopes**

Replace the scope block at `app/models/credit_note.rb:33-37` with:

```ruby
  scope :for_supplier, ->(supplier) { where(supplier_id: supplier.id) if supplier.present? }
  scope :search_number, ->(query) { where("credit_note_number ILIKE ?", "%#{query}%") if query.present? }
  scope :recent, -> { order(issue_date: :desc, created_at: :desc, id: :desc) }
  scope :available, -> { where(status: "active") }

  APPLIED_SUM = "COALESCE((SELECT SUM(ac.amount) FROM applied_credits ac WHERE ac.credit_note_id = credit_notes.id), 0)"

  scope :with_balance, -> { where("credit_notes.amount > #{APPLIED_SUM}") }
  scope :exhausted_credits, -> { where("credit_notes.amount <= #{APPLIED_SUM}") }

  scope :by_availability, ->(filter) {
    case filter
    when "available" then where(status: "active").with_balance
    when "applied"   then where(status: "active").exhausted_credits
    when "cancelled" then where(status: "cancelled")
    end
  }
```

`APPLIED_SUM` is a frozen constant interpolated into the query, never user input — there is no parameter to bind here. Delete the old `by_status` scope entirely; nothing else references it (verify with `grep -rn "by_status" app/ spec/` — matches on `by_status_filter` from Task 1 are a different method and must stay).

- [ ] **Step 4: Run the model spec**

Run: `bundle exec rspec spec/models/credit_note_spec.rb`
Expected: all green.

- [ ] **Step 5: Lint**

Run: `bundle exec rubocop app/models/credit_note.rb spec/models/credit_note_spec.rb`

---

## Task 5: Credit notes controller

**Files:**
- Modify: `app/controllers/web/credit_notes_controller.rb:10-27`
- Test: `spec/requests/web/credit_notes_spec.rb` (create)

**Interfaces:**
- Consumes: `CreditNote.by_availability` from Task 4.
- Produces — Task 6 reads all four:
  - `@credit_notes` → paginated relation, 20 per page.
  - `@pagy` → `Pagy` instance.
  - `@selected_status` → `String`, `""` when no filter.
  - `@total_credit_amount`, `@credit_notes_count` → computed over every matching note, not just the page.

- [ ] **Step 1: Write the failing request spec**

Create `spec/requests/web/credit_notes_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::CreditNotes", type: :request do
  let(:admin) { create(:user, role: "admin") }
  let(:supplier) { create(:supplier, name: "Distribuidora Norte") }
  let(:invoice) { create(:invoice, :simple_mode, supplier: supplier) }

  before { sign_in admin }

  describe "GET /web/credit_notes" do
    it "returns the notes that still have balance for 'available'" do
      create(:credit_note, supplier: supplier, amount: 1000, credit_note_number: "NC-FREE")
      used = create(:credit_note, supplier: supplier, amount: 1000, credit_note_number: "NC-USED")
      create(:applied_credit, credit_note: used, invoice: invoice, amount: 1000)

      get "/web/credit_notes", params: { status: "available" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("NC-FREE")
      expect(response.body).not_to include("NC-USED")
    end

    it "returns the notes with no balance left for 'applied'" do
      create(:credit_note, supplier: supplier, amount: 1000, credit_note_number: "NC-FREE")
      used = create(:credit_note, supplier: supplier, amount: 1000, credit_note_number: "NC-USED")
      create(:applied_credit, credit_note: used, invoice: invoice, amount: 1000)

      get "/web/credit_notes", params: { status: "applied" }

      expect(response.body).to include("NC-USED")
      expect(response.body).not_to include("NC-FREE")
    end

    it "returns cancelled notes for 'cancelled'" do
      create(:credit_note, supplier: supplier, amount: 1000, credit_note_number: "NC-FREE")
      create(:credit_note, :cancelled, supplier: supplier, amount: 1000, credit_note_number: "NC-VOID")

      get "/web/credit_notes", params: { status: "cancelled" }

      expect(response.body).to include("NC-VOID")
      expect(response.body).not_to include("NC-FREE")
    end

    it "paginates instead of truncating at a fixed limit" do
      25.times { |i| create(:credit_note, supplier: supplier, amount: 1000, credit_note_number: "NC-#{i.to_s.rjust(3, '0')}") }

      get "/web/credit_notes"
      first_page = response.body.scan(/NC-\d{3}/).uniq

      get "/web/credit_notes", params: { page: 2 }
      second_page = response.body.scan(/NC-\d{3}/).uniq

      expect(first_page.size).to eq(20)
      expect(second_page.size).to eq(5)
      expect(first_page & second_page).to be_empty
    end

    it "totals every available note, not only the ones on the page" do
      25.times { create(:credit_note, supplier: supplier, amount: 1000) }

      get "/web/credit_notes"

      expect(response.body).to include("ARS 25.000,00")
      expect(response.body).to include("25 notas")
    end

    it "keeps the total independent of the status filter" do
      create(:credit_note, supplier: supplier, amount: 1000)
      create(:credit_note, :cancelled, supplier: supplier, amount: 5000)

      get "/web/credit_notes", params: { status: "cancelled" }

      expect(response.body).to include("ARS 1.000,00")
      expect(response.body).not_to include("ARS 6.000,00")
    end
  end
end
```

These two assert on the rendered card rather than on instance variables: `rails-controller-testing` is not in the `Gemfile`, so `assigns` is unavailable. The expected strings come from the view's existing formatting — `number_to_currency(..., unit: "ARS ", separator: ",", delimiter: ".", precision: 2)` at line 55 and the `"#{@credit_notes_count} notas"` line below it. Do not add the gem.

- [ ] **Step 2: Run the spec and confirm it fails**

Run: `bundle exec rspec spec/requests/web/credit_notes_spec.rb`
Expected: the `available` and `applied` examples fail (the filter is a no-op today, so both sets render), and the pagination examples fail with `NoMethodError` on `@pagy` in the view or a 25-row first page.

- [ ] **Step 3: Rewrite the index action**

Replace lines 10-27 of `app/controllers/web/credit_notes_controller.rb`:

```ruby
    def index
      authorize CreditNote

      @suppliers = Supplier.alphabetical
      @selected_supplier = Supplier.find_by(id: params[:supplier_id]) if params[:supplier_id].present?
      @selected_status = params[:status].to_s

      filtered = CreditNote.includes(:supplier, :invoice, :applied_credits)
                           .for_supplier(@selected_supplier)
                           .search_number(params[:search])
                           .by_availability(@selected_status)
                           .recent

      @pagy, @credit_notes = pagy(filtered)

      available_scope = CreditNote.includes(:applied_credits)
                                  .for_supplier(@selected_supplier)
                                  .search_number(params[:search])
                                  .available

      @total_credit_amount = available_scope.sum { |cn| cn.remaining_balance_ars }
      @credit_notes_count = available_scope.count(&:available?)
    end
```

Three deliberate changes beyond pagination:

1. `includes(:applied_credits)` — without it, rendering each row's balance fires one query per note.
2. The metrics come from their own scope, unpaginated and without the status filter.
3. The total uses `remaining_balance_ars`, not `remaining_balance`. The card is labelled ARS but the old code summed raw amounts, so a USD note was added as if it were pesos. `web/invoices#index` already uses `remaining_balance_ars` for the same figure; this aligns them.

- [ ] **Step 4: Run the request spec**

Run: `bundle exec rspec spec/requests/web/credit_notes_spec.rb`
Expected: green, except any example that depends on the pagination markup — that arrives in Task 6. If `page: 2` returns an empty list, confirm `pagy` is reached (it is a controller concern, already included app-wide) before touching the view.

- [ ] **Step 5: Lint**

Run: `bundle exec rubocop app/controllers/web/credit_notes_controller.rb spec/requests/web/credit_notes_spec.rb`

---

## Task 6: Credit notes view

**Files:**
- Modify: `app/views/web/credit_notes/index.html.haml`

**Interfaces:**
- Consumes: `@credit_notes`, `@pagy`, `@selected_status`, `@selected_supplier` from Task 5.
- Produces: nothing.

- [ ] **Step 1: Fix the status select values**

Replace line 37 in full — these are the values that never matched the data:

```haml
          = select_tag :status,
                       options_for_select([ [ "Todos los estados", "" ], [ "Disponibles", "available" ], [ "Aplicadas", "applied" ], [ "Canceladas", "cancelled" ] ], @selected_status),
                       class: "w-full px-4 py-3 border border-slate-300 rounded-xl focus:ring-2 focus:ring-slate-500 transition-all",
                       data: { action: "change->filter-form#submit" }
```

- [ ] **Step 2: Remove the turbo frame**

At line 24, drop the frame target:

```haml
    = form_with url: web_credit_notes_path, method: :get, data: { controller: "filter-form" } do |f|
```

Delete line 47 (`= turbo_frame_tag "credit_notes_content" do`) and dedent its whole body by two spaces, down to the end of the file.

- [ ] **Step 3: Verify the indentation**

Run: `grep -n "^    - if @credit_notes.any?\|^    - else\|^  .bg-white.border.border-slate-200.rounded-lg.p-6.mb-6" app/views/web/credit_notes/index.html.haml`

Expected: `- if @credit_notes.any?` and `- else` both report at four spaces of indentation. No match means the dedent went wrong.

- [ ] **Step 4: Add the pagination block**

At the end of the file, at the same indentation as `- if @credit_notes.any?`:

```haml
    - if @pagy.pages > 1
      .flex.items-center.justify-center.gap-1.mt-6.pb-2
        - if @pagy.prev
          = link_to "← Anterior", pagy_url_for(@pagy, @pagy.prev), class: "inline-flex items-center px-3 py-2 text-sm font-medium text-slate-600 bg-white border border-slate-300 rounded-lg hover:bg-slate-50 transition-colors"
        - else
          %span.inline-flex.items-center.px-3.py-2.text-sm.font-medium.text-slate-300.bg-white.border.border-slate-200.rounded-lg.cursor-not-allowed ← Anterior

        - @pagy.series.each do |item|
          - if item.is_a?(Integer)
            = link_to item, pagy_url_for(@pagy, item), class: "inline-flex items-center justify-center w-9 h-9 text-sm font-medium text-slate-600 bg-white border border-slate-300 rounded-lg hover:bg-slate-50 transition-colors"
          - elsif item.is_a?(String)
            %span.inline-flex.items-center.justify-center.w-9.h-9.text-sm.font-semibold.text-white.bg-slate-700.border.border-slate-700.rounded-lg= item
          - elsif item == :gap
            %span.inline-flex.items-center.justify-center.w-9.h-9.text-sm.text-slate-400 …

        - if @pagy.next
          = link_to "Siguiente →", pagy_url_for(@pagy, @pagy.next), class: "inline-flex items-center px-3 py-2 text-sm font-medium text-slate-600 bg-white border border-slate-300 rounded-lg hover:bg-slate-50 transition-colors"
        - else
          %span.inline-flex.items-center.px-3.py-2.text-sm.font-medium.text-slate-300.bg-white.border.border-slate-200.rounded-lg.cursor-not-allowed Siguiente →
```

- [ ] **Step 5: Add the status case to the empty state**

Replace the `%p.text-gray-600` block at the end of the file (currently lines 129-135):

```haml
        %p.text-gray-600
          - if @selected_status.present?
            No se encontraron notas de crédito con ese estado
          - elsif @selected_supplier
            No se encontraron notas de crédito para este proveedor
          - elsif params[:search].present?
            No se encontraron notas con ese número
          - else
            Aún no se han registrado notas de crédito
```

- [ ] **Step 6: Run the request spec**

Run: `bundle exec rspec spec/requests/web/credit_notes_spec.rb`
Expected: all green, pagination examples included.

- [ ] **Step 7: Confirm the frame is gone**

Run: `grep -rn "credit_notes_content" app/`
Expected: no output.

---

## Final verification

- [ ] **Full suite**

Run: `bundle exec rspec`
Expected: zero failures. The baseline on this branch before any of these tasks is **1046 examples, 0 failures, 37 pending** (confirm with `bundle exec rspec --dry-run` before you start). The new specs add to that count; the pending count must not move. Any failure is a regression from this work — investigate, do not wave it through.

- [ ] **Lint**

Run: `bundle exec rubocop`
Expected: no offenses.

- [ ] **No orphan references**

Run: `grep -rn "invoices_content\|credit_notes_content\|by_status(" app/ spec/`
Expected: no output. `by_status_filter` and `by_availability` are different names and will not match.

- [ ] **Hand over, do not commit**

Stage the touched files explicitly — never `git add -A`, the working tree carries untracked scratch. Then give the user the commit message and stop.

## What a human still has to check in a browser

No agent can run the app, so these stay manual:

- The three invoice filters submit on change and the URL carries `?status=`.
- Under Pagadas the second date column reads "Pagada el" and the overdue warnings are gone.
- Reloading a filtered page keeps the filters (this is what removing the turbo frame buys).
- The credit note pagination links move between pages and the credit total does not change as you page.
