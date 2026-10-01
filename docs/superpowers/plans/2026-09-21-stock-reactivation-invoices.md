# Stock reactivation, part 1: invoices with products — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A supplier invoice can carry product lines; when it does, registering it adds their quantities to stock and takes its amount from the lines, and cancelling it takes that stock back as far as there is stock to take.

**Architecture:** `Invoices::CreateInvoice` absorbs today's `CreateSimpleInvoice` and, when complete lines arrive, builds the `invoice_items` before saving, computes `amount` server-side and writes one `purchase` movement per line through `Inventory::AdjustStock` — all in one transaction, with the invoice still `has_items: false` so accounts payable never notices. A new `Invoices::CancelInvoice` reverses the invoice's actual purchase movements floored at zero. The form gains a Productos card driven by a new `invoice-lines` Stimulus controller that reuses `product-search`, and the existing `invoice-form` controller freezes the amount, updates the summary and opens the zero-cost confirmation modal.

**Tech Stack:** Rails 7.2, HAML, Stimulus (importmap, controllers auto-registered from `app/javascript/controllers`), TailwindCSS, RSpec + FactoryBot, Capybara + Selenium (system specs), Docker-only development.

**Spec:** `docs/superpowers/specs/2026-09-21-stock-reactivation-invoices-design.md` (decisions D1–D14) — and its parent `docs/superpowers/specs/2026-07-09-invoice-items-stock-reactivation-design.md` (decisions A–H). Executors read both.

**Branch:** `feat-34_stock-reactivation`. Commit scope `feat_34`, one commit per task; the owner squashes at the end.

## Global Constraints

- **No host Ruby.** Every command runs in Docker, in the FOREGROUND: `docker compose exec -T web bundle exec rspec …`, `docker compose exec -T web bundle exec rubocop`. Never launch a background job and idle. Full suite ONCE per task, at the end of the task.
- **Stock is never written directly.** Every stock change is `Inventory::AdjustStock` → `StockMovement` row → `Product#recalculate_current_stock!`. `product.update!(current_stock: x)` is forbidden. Every spec that moves stock creates a `StockLocation` first (`create(:stock_location)`), because every caller uses `StockLocation.first!`.
- **Services return `Result`** (`app/services/result.rb`); **controllers stay thin**; **Pundit** on every action; **HAML only**; **no queries or logic in views** — put it in a helper or the controller.
- **`docs/UI_DESIGN_SPEC.md` governs every view change:** slate base, white cards, the red danger button only for the destructive action, empty states without decoration, labels always visible, errors near fields, reuse existing partials and patterns before creating new ones, Stimulus only for small interaction behaviour.
- **Reuse before writing:** `product-search` (`app/javascript/controllers/product_search_controller.js`), `currency-input`, the `parseAmount`/`formatAmount` idiom and the order form's line-table pattern (`order_form_controller.js`) are the starting points. No new parser, no new searcher.
- **UI follows the operator's mental model, not persistence:** the screen says "una factura con productos", never "modo simple / modo full"; `has_items` is never shown.
- **UI copy in Spanish; code, comments, identifiers and specs in English.** Comments in code are minimal and never cite `AGENTS.md` or any doctrine document. The two existing invoice services carry English `ValidationError` messages; new messages in `Invoices::CreateInvoice` follow that file's convention so one flash is never bilingual.
- **HAML drops an attribute whose value is `false`.** A Stimulus boolean value that must read `false` is written as the string `"false"`.
- **No new Turbo Streams.** Turbo Streams exist only in the cash day screen; this feature's line table is Stimulus, like the order form.
- **A `submit` listener beats `turbo:submit-start`** when the submit may have to be cancelled: `turbo:submit-start` is not cancelable, a `submit` event is, and Turbo skips a submission whose `submit` event was `preventDefault()`ed.
- **Stale Tailwind watcher:** if a new class does not render in the browser, check `app/assets/builds/tailwind.css` (and `docker compose restart css`, which the owner runs) before touching markup.
- **Testing doctrine (`AGENTS.md` → Testing Rules, `docs/TESTING_GUIDE.md`):** `Invoices::CreateInvoice` becomes a write-money flow with per-line `unit_cost` input, so it needs a hostile-input request spec (`"abc"` must be rejected, never read as 0). Characterize existing behaviour before refactoring it. Verify every new spec bites by watching it fail first.
- **Commit at the end of each task** (the owner authorized intermediate commits for this feature and will squash them into one). Subject `type(feat_34): title` in English; body in bullets; **never** a `Co-Authored-By`, "Generated with Claude" or any Anthropic/Claude line — a `commit-msg` hook rejects both. `git add` only the files the task touched.
- **Subagents are dispatched only when the owner asks**, as `builder` / `reviewer` / `test-runner`.

---

## File structure

| File | Responsibility |
|---|---|
| `app/models/invoice.rb` | the `amount` guard keyed on the presence of items (Task 1) |
| `app/services/invoices/create_invoice.rb` | registers an invoice, with or without lines; the only writer of `invoice_items` and of `purchase` movements (Tasks 2–3) |
| `app/services/invoices/cancel_invoice.rb` | cancels a pending invoice and reverses its purchase movements, floored (Task 4) |
| `app/controllers/web/invoices_controller.rb` | `create` with `items`, failure re-render with values, `update` stripping `amount`, `cancel` through the service (Tasks 4–5) |
| `app/helpers/invoices_helper.rb` | the units count and the cancel confirmation text (Task 7) |
| `app/javascript/controllers/invoice_lines_controller.js` | the Productos card: lines, hidden inputs, subtotals, `lines-changed` (Task 6) |
| `app/javascript/controllers/invoice_form_controller.js` | amount freeze, stock summary, cost currency, zero-cost modal (Task 6) |
| `app/javascript/controllers/product_search_controller.js` | `dimOutOfStock` value (Task 6) |
| `app/views/web/invoices/new.html.haml` | Productos card, summary copy, params defaults, modal (Task 6) |
| `app/views/web/invoices/_zero_cost_modal.html.haml` | the D13 modal (Task 6) |
| `app/views/web/invoices/_lines_table.html.haml` | read-only lines table shared by show and edit (Task 7) |
| `app/views/web/invoices/show.html.haml`, `edit.html.haml` | products card, caption, frozen amount, confirmation text (Task 7) |
| `db/seeds.rb` | the two renamed calls (Task 2) |
| `docs/…`, `WORKING_CONTEXT.md` | what changed (Task 8) |

---

### Task 1: The amount guard keys on the presence of items

**Files:**
- Modify: `app/models/invoice.rb:25-29`
- Test: `spec/models/invoice_spec.rb:82-94`

**Interfaces:**
- Produces: `Invoice` accepts `amount: 0` when it has `invoice_items` built in memory and `has_items` is false; still rejects `amount: 0` with no items.

- [ ] **Step 1: Write the failing tests**

In `spec/models/invoice_spec.rb`, replace the `describe "validations for simple mode"` block with:

```ruby
  describe "validations for simple mode" do
    subject { build(:invoice, :simple_mode) }

    it { is_expected.to validate_presence_of(:invoice_number) }
    it { is_expected.to validate_presence_of(:due_date) }
    it { is_expected.to validate_presence_of(:amount) }

    it "validates amount is greater than 0 when the invoice has no items" do
      invoice = build(:invoice, :simple_mode, amount: 0)
      expect(invoice).not_to be_valid
      expect(invoice.errors[:amount]).to be_present
    end

    # An invoice with lines takes its amount from them and may sum to zero
    # (a warranty replacement); the lines are built before the save, so the
    # guard must see them in memory.
    it "accepts an amount of 0 when lines are built in memory" do
      invoice = build(:invoice, :simple_mode, amount: 0)
      invoice.invoice_items.build(product: create(:product), quantity: 1, unit_cost: 0)
      expect(invoice).to be_valid
    end

    it "still rejects a negative amount when lines exist" do
      invoice = build(:invoice, :simple_mode, amount: -1)
      invoice.invoice_items.build(product: create(:product), quantity: 1, unit_cost: 0)
      expect(invoice).not_to be_valid
      expect(invoice.errors[:amount]).to be_present
    end
  end
```

- [ ] **Step 2: Run them and watch the new ones fail**

Run: `docker compose exec -T web bundle exec rspec spec/models/invoice_spec.rb`
Expected: "accepts an amount of 0 when lines are built in memory" FAILS (`expected to be valid`); the other two pass.

- [ ] **Step 3: Change the guard**

In `app/models/invoice.rb` replace the two `amount` validations under `# === SIMPLE MODE VALIDATIONS` with:

```ruby
  validates :amount, presence: true, unless: :has_items?
  validates :amount, numericality: { greater_than: 0 }, if: -> { amount_required? && amount.present? }
  validates :amount, numericality: { greater_than_or_equal_to: 0 }, if: -> { !has_items? && !amount_required? && amount.present? }
```

and add, in the `private` section, above `usd_currency?`:

```ruby
  # An amount-only invoice carries a typed amount that must be positive. An
  # invoice with lines takes its amount from them and may sum to zero.
  def amount_required?
    !has_items? && invoice_items.empty?
  end
```

`invoice_items.empty?` answers from the in-memory target on a new record, which is why the service in Task 3 builds the lines before saving.

- [ ] **Step 4: Run the model spec, then the full suite**

Run: `docker compose exec -T web bundle exec rspec spec/models/invoice_spec.rb`
Expected: all PASS.
Run: `docker compose exec -T web bundle exec rspec` and `docker compose exec -T web bundle exec rubocop`
Expected: green, no offenses. Commit the task's files.

---

### Task 2: `Invoices::CreateInvoice` replaces `CreateSimpleInvoice`, transactional, flat errors

**Files:**
- Rename: `app/services/invoices/create_simple_invoice.rb` → `app/services/invoices/create_invoice.rb`
- Rename: `spec/services/invoices/create_simple_invoice_spec.rb` → `spec/services/invoices/create_invoice_spec.rb`
- Modify: `app/controllers/web/invoices_controller.rb:92` (the call site), `db/seeds.rb:523` and `db/seeds.rb:608` (the two calls)

**Interfaces:**
- Produces: `Invoices::CreateInvoice.call(supplier:, invoice_number:, amount:, currency:, exchange_rate: nil, purchase_date: nil, due_date:, notes: nil, early_payment_due_date: nil, early_payment_discount_percentage: nil)` → `Result` whose `errors` is a **flat** array of strings. Same behaviour as today otherwise. Task 3 adds `items:`.

- [ ] **Step 1: Rename the files and the class**

```bash
mv app/services/invoices/create_simple_invoice.rb app/services/invoices/create_invoice.rb
mv spec/services/invoices/create_simple_invoice_spec.rb spec/services/invoices/create_invoice_spec.rb
```

(`git mv` is fine too; either way the rename lands in this task's commit.) In `create_invoice.rb` change `class CreateSimpleInvoice` to `class CreateInvoice`, and in the spec change `RSpec.describe Invoices::CreateSimpleInvoice do` to `RSpec.describe Invoices::CreateInvoice do`. In the controller and in both seed calls replace `Invoices::CreateSimpleInvoice.call(` with `Invoices::CreateInvoice.call(`.

- [ ] **Step 2: Add the characterization of the flat error shape**

Append to the `describe ".call"` block of `spec/services/invoices/create_invoice_spec.rb`:

```ruby
    context "error shape" do
      # The controller joins the errors with ", ", so a nested array would
      # render as an inspected Ruby array on screen.
      it "returns a flat array of messages on a model validation failure" do
        invalid = Invoice.new
        invalid.errors.add(:base, "Boom")
        allow_any_instance_of(Invoice).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(invalid))

        result = described_class.call(
          supplier: supplier,
          invoice_number: "FAC-002",
          amount: 5000,
          currency: "USD",
          exchange_rate: 1200,
          purchase_date: Date.current,
          due_date: 30.days.from_now
        )

        expect(result.success?).to be false
        expect(result.errors).to eq([ "Boom" ])
      end
    end
```

- [ ] **Step 3: Run the spec, watch the new example fail**

Run: `docker compose exec -T web bundle exec rspec spec/services/invoices/create_invoice_spec.rb`
Expected: the renamed examples PASS (the class still exists under its new name); "returns a flat array of messages" FAILS with `expected: ["Boom"] got: [["Boom"]]` — today's rescue returns `[ full_messages ]`. (`Invoice.create!` calls `save!` on the instance, so the stub reaches it before and after the rewrite.) If any pre-existing example asserted on the nested shape (`result.errors.first` being an Array), flatten that expectation now: the nesting was a defect.

- [ ] **Step 4: Make the service transactional and flatten the errors**

Replace the whole `call` method in `app/services/invoices/create_invoice.rb` with:

```ruby
    def call
      validate_params

      ActiveRecord::Base.transaction do
        @invoice = Invoice.new(
          supplier: @supplier,
          invoice_number: @invoice_number,
          amount: @amount,
          currency: @currency,
          exchange_rate: @exchange_rate,
          purchase_date: @purchase_date,
          due_date: @due_date,
          status: "pending",
          has_items: false,
          notes: @notes,
          early_payment_due_date: @early_payment_due_date,
          early_payment_discount_percentage: @early_payment_discount_percentage
        )
        @invoice.save!

        Result.new(success?: true, record: @invoice, errors: [])
      end
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, record: nil, errors: e.record.errors.full_messages)
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue StandardError => e
      Rails.logger.error("Error in Invoices::CreateInvoice: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      Result.new(success?: false, record: nil, errors: [ "Error creating invoice" ])
    end
```

- [ ] **Step 5: Verify nothing references the old name**

Run: `grep -rn "CreateSimpleInvoice" app spec db lib docs/TESTING_GUIDE.md WORKING_CONTEXT.md`
Expected: only `docs/TESTING_GUIDE.md` and `WORKING_CONTEXT.md` (updated in Task 8). If `app`, `spec`, `db` or `lib` still match, fix the reference.

- [ ] **Step 6: Run the spec, the seeds check and the full suite**

Run: `docker compose exec -T web bundle exec rspec spec/services/invoices/create_invoice_spec.rb`
Expected: all PASS.
Run: `docker compose exec -T web bundle exec rails runner "puts Invoices::CreateInvoice.name"`
Expected: `Invoices::CreateInvoice`.
Run: `docker compose exec -T web bundle exec rspec` and `docker compose exec -T web bundle exec rubocop`
Expected: green. Commit the task's files.

---

### Task 3: Lines on `Invoices::CreateInvoice` — build, sum, stock

**Files:**
- Modify: `app/services/invoices/create_invoice.rb`
- Test: `spec/services/invoices/create_invoice_spec.rb`

**Interfaces:**
- Consumes: Task 1's guard (an itemized `amount: 0` saves).
- Produces: `Invoices::CreateInvoice.call(…, items: [])` where each item is a Hash with `:product_id`, `:quantity`, `:unit_cost` (extra keys such as `:sku`, `:name`, `:brand` are ignored; String keys accepted). A **complete** line has a present `product_id` and `quantity.to_i > 0`; incomplete rows are ignored. A blank `unit_cost` is 0; a nil `unit_cost` on a complete line means "unparseable" and is rejected. With complete lines: `amount = Σ(quantity × unit_cost)`, the submitted `amount` is ignored, one `invoice_items` row and one `purchase` `StockMovement` (`reference: invoice`) per line, `has_items` stays false. Task 5's controller relies on exactly this contract.

- [ ] **Step 1: Write the failing tests**

Append to the `describe ".call"` block of `spec/services/invoices/create_invoice_spec.rb`:

```ruby
    context "with product lines" do
      let!(:location) { create(:stock_location) }
      let(:filter)  { create(:product, name: "Filtro de aceite", current_stock: 0) }
      let(:pads)    { create(:product, name: "Pastillas", current_stock: 2) }

      def call_with(items, amount: nil, **overrides)
        described_class.call(
          **{ supplier: supplier, invoice_number: "FAC-100", amount: amount, currency: "ARS",
              purchase_date: Date.current, due_date: 30.days.from_now, items: items }.merge(overrides)
        )
      end

      it "stores the sum of the lines as the amount and ignores the submitted one" do
        result = call_with(
          [ { product_id: filter.id, quantity: 10, unit_cost: 4500 },
            { product_id: pads.id, quantity: 4, unit_cost: 21_000 } ],
          amount: 1
        )

        expect(result.success?).to be true
        invoice = result.record
        expect(invoice.amount).to eq(129_000)
        expect(invoice.has_items).to be false
        expect(invoice.invoice_items.count).to eq(2)
        expect(Invoice.simple_mode.pending_payment).to include(invoice)
      end

      it "adds each line's quantity to stock through purchase movements referencing the invoice" do
        result = call_with([ { product_id: filter.id, quantity: 10, unit_cost: 4500 },
                             { product_id: pads.id, quantity: 4, unit_cost: 21_000 } ])

        invoice = result.record
        expect(filter.reload.current_stock).to eq(10)
        expect(pads.reload.current_stock).to eq(6)
        movements = invoice.stock_movements.order(:id)
        expect(movements.map(&:movement_type)).to eq(%w[purchase purchase])
        expect(movements.map(&:quantity)).to eq([ 10, 4 ])
        expect(movements.map(&:stock_location)).to all(eq(location))
      end

      it "writes one movement per line, so the same product on two lines moves twice" do
        result = call_with([ { product_id: filter.id, quantity: 3, unit_cost: 4500 },
                             { product_id: filter.id, quantity: 2, unit_cost: 4000 } ])

        expect(result.record.invoice_items.count).to eq(2)
        expect(result.record.amount).to eq(21_500)
        expect(filter.reload.current_stock).to eq(5)
      end

      it "ignores rows without a product or without a positive quantity" do
        result = call_with([ { product_id: filter.id, quantity: 10, unit_cost: 4500 },
                             { product_id: "", quantity: 5, unit_cost: 100 },
                             { product_id: pads.id, quantity: 0, unit_cost: 21_000 },
                             { product_id: pads.id, quantity: "", unit_cost: 21_000 } ])

        expect(result.success?).to be true
        expect(result.record.invoice_items.count).to eq(1)
        expect(result.record.amount).to eq(45_000)
        expect(pads.reload.current_stock).to eq(2)
      end

      it "reads a blank unit cost as zero and still moves the stock" do
        result = call_with([ { product_id: filter.id, quantity: 2, unit_cost: "" } ])

        expect(result.success?).to be true
        expect(result.record.amount).to eq(0)
        expect(result.record.invoice_items.first.unit_cost).to eq(0)
        expect(filter.reload.current_stock).to eq(2)
      end

      it "accepts string keys, the shape params arrive in" do
        result = call_with([ { "product_id" => filter.id.to_s, "quantity" => "2", "unit_cost" => "4500" } ])

        expect(result.success?).to be true
        expect(result.record.amount).to eq(9_000)
      end

      it "rejects a negative unit cost" do
        result = call_with([ { product_id: filter.id, quantity: 1, unit_cost: -1 } ])

        expect(result.success?).to be false
        expect(result.errors).to include("Unit cost cannot be negative")
        expect(filter.reload.current_stock).to eq(0)
      end

      it "rejects an unparseable unit cost instead of reading it as free" do
        result = call_with([ { product_id: filter.id, quantity: 1, unit_cost: nil } ])

        expect(result.success?).to be false
        expect(result.errors).to include("Unit cost is not a number")
        expect(Invoice.count).to eq(0)
      end

      it "rejects a product that does not exist" do
        result = call_with([ { product_id: 999_999, quantity: 1, unit_cost: 100 } ])

        expect(result.success?).to be false
        expect(result.errors).to include("Product not found: 999999")
      end

      it "does not require a typed amount when there are complete lines" do
        result = call_with([ { product_id: filter.id, quantity: 1, unit_cost: 100 } ], amount: nil)

        expect(result.success?).to be true
      end

      it "still requires a positive amount when every row is incomplete" do
        result = call_with([ { product_id: filter.id, quantity: 0, unit_cost: 100 } ], amount: nil)

        expect(result.success?).to be false
        expect(result.errors).to include("Amount must be greater than zero")
      end

      it "rolls everything back when a header rule fails after the lines were read" do
        expect {
          result = call_with([ { product_id: filter.id, quantity: 10, unit_cost: 4500 } ],
                             due_date: Date.current - 1)
          expect(result.success?).to be false
        }.to not_change(Invoice, :count)
          .and not_change(InvoiceItem, :count)
          .and not_change(StockMovement, :count)
        expect(filter.reload.current_stock).to eq(0)
      end

      it "rolls everything back when a stock movement fails" do
        allow(Inventory::AdjustStock).to receive(:call)
          .and_return(Result.new(success?: false, record: nil, errors: [ "Error adjusting stock" ]))

        expect {
          result = call_with([ { product_id: filter.id, quantity: 10, unit_cost: 4500 } ])
          expect(result.success?).to be false
          expect(result.errors).to include("Error adjusting stock")
        }.to not_change(Invoice, :count).and not_change(InvoiceItem, :count)
      end

      it "sets the supplier's early-payment terms and applies the discount to the sum" do
        discounting = create(:supplier, :with_early_payment_discount)
        result = call_with([ { product_id: filter.id, quantity: 10, unit_cost: 4500 } ], supplier: discounting)

        invoice = result.record
        expect(invoice.early_payment_discount_percentage).to eq(5)
        expect(invoice.amount_with_discount).to eq(42_750)
      end
    end
```

`not_change` does not exist in this suite yet. Define it at the top of `spec/services/invoices/create_invoice_spec.rb`, right after `require "rails_helper"`, so the file is self-contained:

```ruby
RSpec::Matchers.define_negated_matcher :not_change, :change
```

- [ ] **Step 2: Run the spec, watch the new examples fail**

Run: `docker compose exec -T web bundle exec rspec spec/services/invoices/create_invoice_spec.rb`
Expected: every example in "with product lines" FAILS (`unknown keyword: :items`); the older examples still PASS.

- [ ] **Step 3: Implement the lines**

Rewrite `app/services/invoices/create_invoice.rb` as:

```ruby
# frozen_string_literal: true

module Invoices
  # Registers a supplier invoice. With product lines it also stocks them and
  # takes its amount from them; without lines it is the amount-only invoice.
  class CreateInvoice
    Line = Struct.new(:product, :quantity, :unit_cost, keyword_init: true)

    def self.call(supplier:, invoice_number:, amount:, currency:,
                  exchange_rate: nil, purchase_date: nil, due_date:, notes: nil,
                  early_payment_due_date: nil, early_payment_discount_percentage: nil,
                  items: [])
      new(
        supplier: supplier,
        invoice_number: invoice_number,
        amount: amount,
        currency: currency,
        exchange_rate: exchange_rate,
        purchase_date: purchase_date,
        due_date: due_date,
        notes: notes,
        early_payment_due_date: early_payment_due_date,
        early_payment_discount_percentage: early_payment_discount_percentage,
        items: items
      ).call
    end

    def initialize(supplier:, invoice_number:, amount:, currency:,
                   exchange_rate: nil, purchase_date: nil, due_date:, notes: nil,
                   early_payment_due_date: nil, early_payment_discount_percentage: nil,
                   items: [])
      @supplier = supplier
      @invoice_number = invoice_number
      @amount = amount
      @currency = currency
      @exchange_rate = exchange_rate
      @purchase_date = purchase_date || Date.current
      @due_date = due_date
      @notes = notes
      @early_payment_due_date = early_payment_due_date
      @early_payment_discount_percentage = early_payment_discount_percentage
      @items = Array(items).map { |item| item.to_h.symbolize_keys }
    end

    def call
      validate_params

      ActiveRecord::Base.transaction do
        build_invoice
        build_lines
        @invoice.save!
        move_stock

        Result.new(success?: true, record: @invoice, errors: [])
      end
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, record: nil, errors: e.record.errors.full_messages)
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue StandardError => e
      Rails.logger.error("Error in Invoices::CreateInvoice: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      Result.new(success?: false, record: nil, errors: [ "Error creating invoice" ])
    end

    private

    class ValidationError < StandardError; end

    def validate_params
      unless %w[USD ARS].include?(@currency)
        raise ValidationError, "Invalid currency. Must be USD or ARS"
      end

      if @currency == "USD" && (@exchange_rate.nil? || @exchange_rate <= 0)
        raise ValidationError, "Exchange rate required for USD invoices"
      end

      raise ValidationError, "Supplier is required" if @supplier.nil?
      raise ValidationError, "Invoice number is required" if @invoice_number.blank?

      if lines.empty? && !(@amount.to_f > 0)
        raise ValidationError, "Amount must be greater than zero"
      end

      raise ValidationError, "Due date is required" if @due_date.nil?

      if @due_date < @purchase_date
        raise ValidationError, "Due date cannot be before purchase date"
      end
    end

    # A row counts only with a product and a positive quantity; anything else
    # is an unfinished row the form left behind.
    def complete_items
      @items.select { |item| item[:product_id].present? && item[:quantity].to_i.positive? }
    end

    def lines
      @lines ||= complete_items.map do |item|
        Line.new(product: find_product(item[:product_id]),
                 quantity: item[:quantity].to_i,
                 unit_cost: unit_cost_from(item[:unit_cost]))
      end
    end

    def find_product(id)
      Product.find_by(id: id) || raise(ValidationError, "Product not found: #{id}")
    end

    # A blank cost is a free line; a nil one is an amount the controller could
    # not read, and a free line by accident is exactly what must not happen.
    def unit_cost_from(raw)
      raise ValidationError, "Unit cost is not a number" if raw.nil?
      return BigDecimal("0") if raw.to_s.strip.empty?

      cost = BigDecimal(raw.to_s)
      raise ValidationError, "Unit cost cannot be negative" if cost.negative?

      cost
    rescue ArgumentError
      raise ValidationError, "Unit cost is not a number"
    end

    def computed_amount
      lines.sum { |line| line.quantity * line.unit_cost }
    end

    def build_invoice
      @invoice = Invoice.new(
        supplier: @supplier,
        invoice_number: @invoice_number,
        amount: lines.any? ? computed_amount : @amount,
        currency: @currency,
        exchange_rate: @exchange_rate,
        purchase_date: @purchase_date,
        due_date: @due_date,
        status: "pending",
        has_items: false,
        notes: @notes,
        early_payment_due_date: @early_payment_due_date,
        early_payment_discount_percentage: @early_payment_discount_percentage
      )
    end

    # Built, not created: the amount guard on Invoice reads the lines in
    # memory to know the amount may be zero.
    def build_lines
      lines.each do |line|
        @invoice.invoice_items.build(product: line.product, quantity: line.quantity, unit_cost: line.unit_cost)
      end
    end

    def move_stock
      return if lines.empty?

      location = StockLocation.first!
      lines.each do |line|
        result = Inventory::AdjustStock.call(
          product: line.product,
          stock_location: location,
          movement_type: "purchase",
          quantity: line.quantity,
          reference: @invoice,
          note: "Factura #{@invoice_number}"
        )
        raise ValidationError, result.errors.join(", ") if result.failure?
      end
    end
  end
end
```

Note `BigDecimal("4500.0")` and `BigDecimal("4500")` both parse; a Float `4500.0` arrives from the controller's `parse_amount` and `to_s` keeps it parseable. The order of validations puts the amount rule after `lines` is computed, so a bad product or cost is reported before "Amount must be greater than zero".

- [ ] **Step 4: Run the spec until green, then the full suite**

Run: `docker compose exec -T web bundle exec rspec spec/services/invoices/create_invoice_spec.rb`
Expected: all PASS. If "rolls everything back when a header rule fails" fails because the amount guard fired first, the order in `validate_params` is wrong — the due-date check must run after the lines are parsed but the transaction must not open before `validate_params` returns.
Run: `docker compose exec -T web bundle exec rspec` and `docker compose exec -T web bundle exec rubocop`
Expected: green. Commit the task's files.

---

### Task 4: `Invoices::CancelInvoice` and the controller's `cancel`

**Files:**
- Create: `app/services/invoices/cancel_invoice.rb`
- Modify: `app/controllers/web/invoices_controller.rb:150-163` (`cancel`)
- Test: `spec/services/invoices/cancel_invoice_spec.rb` (create), `spec/requests/web/invoices_spec.rb` (add a `describe "PATCH /web/invoices/:id/cancel"`)

**Interfaces:**
- Consumes: Task 3's purchase movements (`invoice.stock_movements` with `movement_type: "purchase"`).
- Produces: `Invoices::CancelInvoice.call(invoice:)` → `Result`. Refuses a non-pending invoice with `"Solo se pueden cancelar facturas pendientes"`. Reverses, per product, `min(purchased quantity, product.current_stock)` as one `adjustment` movement referencing the invoice; skips a product with nothing left; then sets `status: "cancelled"`. Task 7's confirmation text describes exactly this.

- [ ] **Step 1: Characterize today's cancel with a request spec, and write the reversal specs**

Add to `spec/requests/web/invoices_spec.rb`, inside the top-level `describe`:

```ruby
  describe "PATCH /web/invoices/:id/cancel" do
    let!(:location) { create(:stock_location) }

    it "cancels a pending amount-only invoice and moves no stock" do
      invoice = create(:invoice, :simple_mode, supplier: supplier)

      expect { patch "/web/invoices/#{invoice.id}/cancel" }.not_to change(StockMovement, :count)

      expect(response).to redirect_to("/web/invoices")
      expect(invoice.reload.status).to eq("cancelled")
    end

    it "refuses a paid invoice" do
      invoice = create(:invoice, :paid, supplier: supplier)

      patch "/web/invoices/#{invoice.id}/cancel"

      # The policy refuses first; ApplicationController redirects to the
      # referrer or the root, so only the redirect and the untouched status matter.
      expect(response).to have_http_status(:redirect)
      expect(invoice.reload.status).to eq("paid")
    end

    it "takes back the stock an itemized invoice added, as far as there is stock" do
      product = create(:product, current_stock: 0)
      invoice = Invoices::CreateInvoice.call(
        supplier: supplier, invoice_number: "FAC-9", amount: nil, currency: "ARS",
        purchase_date: Date.current, due_date: 30.days.from_now,
        items: [ { product_id: product.id, quantity: 10, unit_cost: 100 } ]
      ).record
      Inventory::AdjustStock.call(product: product, stock_location: location,
                                  movement_type: "adjustment", quantity: -7)

      patch "/web/invoices/#{invoice.id}/cancel"

      expect(invoice.reload.status).to eq("cancelled")
      expect(product.reload.current_stock).to eq(0)
    end
  end
```

Create `spec/services/invoices/cancel_invoice_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::CancelInvoice do
  let!(:location) { create(:stock_location) }
  let(:supplier)  { create(:supplier) }
  let(:filter)    { create(:product, current_stock: 0) }
  let(:pads)      { create(:product, current_stock: 0) }

  def itemized(items)
    Invoices::CreateInvoice.call(
      supplier: supplier, invoice_number: "FAC-1", amount: nil, currency: "ARS",
      purchase_date: Date.current, due_date: 30.days.from_now, items: items
    ).record
  end

  def adjust(product, quantity)
    Inventory::AdjustStock.call(product: product, stock_location: location,
                                movement_type: "adjustment", quantity: quantity)
  end

  it "flips an amount-only invoice to cancelled and writes no movement" do
    invoice = create(:invoice, :simple_mode, supplier: supplier)

    expect { described_class.call(invoice: invoice) }.not_to change(StockMovement, :count)
    expect(invoice.reload.status).to eq("cancelled")
  end

  it "reverses every unit an itemized invoice added, as an adjustment referencing the invoice" do
    invoice = itemized([ { product_id: filter.id, quantity: 10, unit_cost: 100 },
                         { product_id: pads.id, quantity: 4, unit_cost: 100 } ])

    result = described_class.call(invoice: invoice)

    expect(result.success?).to be true
    expect(filter.reload.current_stock).to eq(0)
    expect(pads.reload.current_stock).to eq(0)
    reversals = invoice.stock_movements.where(movement_type: "adjustment")
    expect(reversals.map(&:quantity)).to contain_exactly(-10, -4)
    expect(invoice.stock_movements.where(movement_type: "purchase").count).to eq(2)
  end

  it "floors the reversal at the stock that is left, and still cancels" do
    invoice = itemized([ { product_id: filter.id, quantity: 10, unit_cost: 100 } ])
    adjust(filter, -7)

    result = described_class.call(invoice: invoice)

    expect(result.success?).to be true
    expect(filter.reload.current_stock).to eq(0)
    expect(invoice.reload.status).to eq("cancelled")
  end

  it "writes no reversal for a product with nothing left" do
    invoice = itemized([ { product_id: filter.id, quantity: 10, unit_cost: 100 } ])
    adjust(filter, -10)

    expect { described_class.call(invoice: invoice) }.not_to change(StockMovement, :count)
    expect(invoice.reload.status).to eq("cancelled")
  end

  it "reverses the same product on two lines once, by the total it added" do
    invoice = itemized([ { product_id: filter.id, quantity: 3, unit_cost: 100 },
                         { product_id: filter.id, quantity: 2, unit_cost: 90 } ])

    described_class.call(invoice: invoice)

    expect(filter.reload.current_stock).to eq(0)
    expect(invoice.stock_movements.where(movement_type: "adjustment").map(&:quantity)).to eq([ -5 ])
  end

  it "refuses an invoice that is not pending" do
    invoice = create(:invoice, :paid, supplier: supplier)

    result = described_class.call(invoice: invoice)

    expect(result.success?).to be false
    expect(result.errors).to include("Solo se pueden cancelar facturas pendientes")
    expect(invoice.reload.status).to eq("paid")
  end

  it "still cancels and reverses when the product was soft-deleted afterwards" do
    invoice = itemized([ { product_id: filter.id, quantity: 10, unit_cost: 100 } ])
    filter.destroy

    result = described_class.call(invoice: invoice)

    expect(result.success?).to be true
    expect(Product.with_deleted.find(filter.id).current_stock).to eq(0)
  end

  it "rolls the status back when a reversal fails" do
    invoice = itemized([ { product_id: filter.id, quantity: 10, unit_cost: 100 } ])
    allow(Inventory::AdjustStock).to receive(:call)
      .and_return(Result.new(success?: false, record: nil, errors: [ "Error adjusting stock" ]))

    result = described_class.call(invoice: invoice)

    expect(result.success?).to be false
    expect(invoice.reload.status).to eq("pending")
  end
end
```

- [ ] **Step 2: Run both files, watch them fail the right way**

Run: `docker compose exec -T web bundle exec rspec spec/services/invoices/cancel_invoice_spec.rb spec/requests/web/invoices_spec.rb`
Expected: the service spec FAILS with `uninitialized constant Invoices::CancelInvoice`; in the request spec "cancels a pending amount-only invoice" and "refuses a paid invoice" PASS (characterization) and "takes back the stock" FAILS (`expected 0, got 3`).

- [ ] **Step 3: Write the service**

Create `app/services/invoices/cancel_invoice.rb`:

```ruby
# frozen_string_literal: true

module Invoices
  # Cancels a pending invoice and takes back the stock it added, as far as
  # there is stock to take.
  class CancelInvoice
    def self.call(invoice:)
      new(invoice: invoice).call
    end

    def initialize(invoice:)
      @invoice = invoice
    end

    def call
      validate!

      ActiveRecord::Base.transaction do
        reverse_stock
        @invoice.update!(status: "cancelled")

        Result.new(success?: true, record: @invoice, errors: [])
      end
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, record: nil, errors: e.record.errors.full_messages)
    rescue StandardError => e
      Rails.logger.error("Error in Invoices::CancelInvoice: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      Result.new(success?: false, record: nil, errors: [ "Error al cancelar la factura" ])
    end

    private

    class ValidationError < StandardError; end

    def validate!
      raise ValidationError, "Solo se pueden cancelar facturas pendientes" unless @invoice.pending_status?
    end

    # The purchase rows stay as history; what comes back is what the invoice
    # added, capped at what is still on the shelf.
    def reverse_stock
      purchased_by_product.each do |(product_id, location_id), purchased|
        product = Product.with_deleted.find(product_id)
        quantity = [ purchased, product.current_stock ].min
        next unless quantity.positive?

        result = Inventory::AdjustStock.call(
          product: product,
          stock_location: StockLocation.find(location_id),
          movement_type: "adjustment",
          quantity: -quantity,
          reference: @invoice,
          note: "Cancelación de factura #{@invoice.invoice_number}"
        )
        raise ValidationError, result.errors.join(", ") if result.failure?
      end
    end

    def purchased_by_product
      @invoice.stock_movements
              .where(movement_type: "purchase")
              .group(:product_id, :stock_location_id)
              .sum(:quantity)
    end
  end
end
```

- [ ] **Step 4: Route the controller through it**

In `app/controllers/web/invoices_controller.rb` replace the `cancel` action with:

```ruby
    def cancel
      authorize @invoice

      result = Invoices::CancelInvoice.call(invoice: @invoice)

      if result.success?
        redirect_to web_invoices_path, notice: "Factura cancelada exitosamente."
      else
        redirect_to web_invoice_path(@invoice), alert: result.errors.join(", ")
      end
    end
```

The policy (`cancel?` = admin and pending) still runs first, so a paid invoice is refused before the service — the request spec's "refuses a paid invoice" keeps passing on the redirect the policy produces.

- [ ] **Step 5: Green, then the full suite**

Run: `docker compose exec -T web bundle exec rspec spec/services/invoices/cancel_invoice_spec.rb spec/requests/web/invoices_spec.rb`
Expected: all PASS.
Run: `docker compose exec -T web bundle exec rspec` and `docker compose exec -T web bundle exec rubocop`
Expected: green. Commit the task's files.

---

### Task 5: The controller — `create` with lines, failure keeps everything, `update` strips the amount

**Files:**
- Modify: `app/controllers/web/invoices_controller.rb` (`create`, `update`, new private `submitted_items`)
- Modify: `app/views/web/invoices/new.html.haml` — only the header fields' default values (the Productos card is Task 6)
- Test: `spec/requests/web/invoices_spec.rb`

**Interfaces:**
- Consumes: `Invoices::CreateInvoice.call(…, items:)` (Task 3).
- Produces: `POST /web/invoices` accepts `items[N][product_id]`, `items[N][quantity]`, `items[N][unit_cost]` and, for the re-render only, `items[N][sku]`, `items[N][name]`, `items[N][brand]`. On failure the action renders `new` with `422`, `flash.now[:alert]`, the header fields prefilled from `params`, and `@submitted_items` — an Array of Hashes with `product_id, sku, name, brand, quantity, unit_cost` (`unit_cost` as the raw string typed) — which Task 6's view hands to the lines controller. `PATCH /web/invoices/:id` ignores `invoice[amount]` when the invoice has items.

- [ ] **Step 1: Write the failing request specs**

Add to `spec/requests/web/invoices_spec.rb`:

```ruby
  describe "POST /web/invoices" do
    let!(:location) { create(:stock_location) }
    let(:product)   { create(:product, sku: "90915-YZZD2", name: "Filtro de aceite", current_stock: 0) }

    def header(overrides = {})
      { supplier_id: supplier.id, invoice_number: "FAC-0001234", currency: "ARS",
        amount: "1,00", purchase_date: Date.current.to_s, due_date: 30.days.from_now.to_date.to_s }.merge(overrides)
    end

    def line(product, quantity:, unit_cost:)
      { product_id: product.id, sku: product.sku, name: product.name, brand: product.brand,
        quantity: quantity, unit_cost: unit_cost }
    end

    it "registers an itemized invoice, sums the lines and stocks them" do
      post "/web/invoices", params: header.merge(items: { "0" => line(product, quantity: 10, unit_cost: "4.500,00") })

      invoice = Invoice.last
      expect(response).to redirect_to("/web/invoices/#{invoice.id}")
      expect(invoice.amount).to eq(45_000)
      expect(invoice.invoice_items.count).to eq(1)
      expect(product.reload.current_stock).to eq(10)
    end

    it "registers an amount-only invoice exactly as before" do
      post "/web/invoices", params: header(amount: "12.500,50")

      invoice = Invoice.last
      expect(invoice.amount).to eq(12_500.5)
      expect(invoice.invoice_items).to be_empty
      expect(StockMovement.count).to eq(0)
    end

    it "comes back with the header and the lines when the server refuses" do
      post "/web/invoices", params: header(due_date: (Date.current - 1).to_s)
                                          .merge(items: { "0" => line(product, quantity: 10, unit_cost: "4.500,00") })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Due date cannot be before purchase date")
      expect(response.body).to include('value="FAC-0001234"')
      expect(Invoice.count).to eq(0)
      expect(product.reload.current_stock).to eq(0)
    end

    # The backend must not trust the client to send a clean number: "abc" is
    # rejected, never read as a free line.
    it "rejects an unparseable unit cost" do
      post "/web/invoices", params: header.merge(items: { "0" => line(product, quantity: 1, unit_cost: "abc") })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Unit cost is not a number")
      expect(Invoice.count).to eq(0)
      expect(product.reload.current_stock).to eq(0)
    end

    it "reads a blank unit cost as a free line" do
      post "/web/invoices", params: header.merge(items: { "0" => line(product, quantity: 2, unit_cost: "") })

      expect(Invoice.last.amount).to eq(0)
      expect(product.reload.current_stock).to eq(2)
    end
  end

  describe "PATCH /web/invoices/:id" do
    let!(:location) { create(:stock_location) }

    it "ignores a submitted amount when the invoice has lines" do
      product = create(:product, current_stock: 0)
      invoice = Invoices::CreateInvoice.call(
        supplier: supplier, invoice_number: "FAC-7", amount: nil, currency: "ARS",
        purchase_date: Date.current, due_date: 30.days.from_now,
        items: [ { product_id: product.id, quantity: 10, unit_cost: 100 } ]
      ).record

      patch "/web/invoices/#{invoice.id}", params: { invoice: { amount: "1,00", notes: "corregida" } }

      expect(invoice.reload.amount).to eq(1_000)
      expect(invoice.notes).to eq("corregida")
    end

    it "still updates the amount of an amount-only invoice" do
      invoice = create(:invoice, :simple_mode, supplier: supplier, amount: 500)

      patch "/web/invoices/#{invoice.id}", params: { invoice: { amount: "700,00" } }

      expect(invoice.reload.amount).to eq(700)
    end
  end
```

- [ ] **Step 2: Run, watch the new ones fail**

Run: `docker compose exec -T web bundle exec rspec spec/requests/web/invoices_spec.rb`
Expected: "registers an itemized invoice" FAILS (no lines read → amount 1, no stock); "comes back with the header and the lines" FAILS (`value="FAC-0001234"` missing — today's form renders nil); "rejects an unparseable unit cost" FAILS (no items parsed, invoice created); "ignores a submitted amount when the invoice has lines" FAILS (amount became 1). The amount-only examples PASS.

- [ ] **Step 3: Parse the lines in the controller and keep them on failure**

In `app/controllers/web/invoices_controller.rb` replace `create` with:

```ruby
    def create
      authorize Invoice, :create?

      result = Invoices::CreateInvoice.call(
        supplier: find_supplier,
        invoice_number: params[:invoice_number],
        amount: parse_amount(params[:amount]),
        currency: params[:currency] || "USD",
        exchange_rate: parse_exchange_rate(params[:exchange_rate], params[:currency]),
        purchase_date: parse_date(params[:purchase_date]),
        due_date: parse_date(params[:due_date]),
        notes: params[:notes],
        early_payment_due_date: parse_optional_date(params[:early_payment_due_date]),
        early_payment_discount_percentage: parse_optional_integer(params[:early_payment_discount_percentage]),
        items: submitted_items.map { |item| item.merge(unit_cost: unit_cost_param(item[:unit_cost])) }
      )

      if result.success?
        redirect_to web_invoice_path(result.record), notice: "Factura registrada exitosamente."
      else
        flash.now[:alert] = result.errors.join(", ")
        @submitted_items = submitted_items
        load_suppliers
        render :new, status: :unprocessable_entity
      end
    end
```

and `update` with:

```ruby
    def update
      authorize @invoice

      unless @invoice.pending_status?
        redirect_to web_invoice_path(@invoice), alert: "Solo se pueden editar facturas pendientes."
        return
      end

      update_params = invoice_update_params
      # The lines own the amount; a value typed around the read-only field is ignored.
      update_params.delete(:amount) if @invoice.invoice_items.any?
      update_params[:amount] = parse_amount(update_params[:amount]) if update_params[:amount].present?
      update_params[:exchange_rate] = parse_amount(update_params[:exchange_rate]) if update_params[:exchange_rate].present?

      if @invoice.update(update_params)
        redirect_to web_invoice_path(@invoice), notice: "Factura actualizada exitosamente."
      else
        load_suppliers
        render :edit, status: :unprocessable_entity
      end
    end
```

Add, in the `private` section, after `find_supplier`:

```ruby
    # Lines arrive as `items[0][product_id]=…&items[0][quantity]=…`. The raw
    # unit cost is kept for the re-render; the service gets the parsed one.
    def submitted_items
      @submitted_items_memo ||= begin
        rows = params[:items]
        rows.blank? ? [] : rows.to_unsafe_h.values.map do |row|
          { product_id: row[:product_id].to_s, sku: row[:sku].to_s, name: row[:name].to_s, brand: row[:brand].to_s,
            quantity: row[:quantity].to_i, unit_cost: row[:unit_cost].to_s }
        end
      end
    end

    # Blank means free; anything that is not a number stays nil so the
    # service refuses it instead of reading it as zero.
    def unit_cost_param(raw)
      return "" if raw.to_s.strip.empty?

      decimal_string_from(raw)
    end
```

`decimal_string_from` comes from the `CurrencyParser` concern the controller already includes; it turns `"4.500,00"` into `"4500.00"` and returns `nil` for `"abc"`.

- [ ] **Step 4: Prefill the header from params in `new.html.haml`**

In `app/views/web/invoices/new.html.haml` change these field helpers (only the value/selection arguments):

```haml
= select_tag :supplier_id,
            options_for_select([["Seleccionar proveedor", "", { "data-payment-term-days": "0", "data-early-payment-days": "0", "data-early-payment-discount": "0" }]] + @suppliers.map { |s| [s.name, s.id, { "data-payment-term-days": s.payment_term_days || 0, "data-early-payment-days": s.early_payment_days || 0, "data-early-payment-discount": s.early_payment_discount_percentage || 0 }] }, params[:supplier_id]),
```

```haml
= text_field_tag :invoice_number, params[:invoice_number],
```

```haml
= radio_button_tag :currency, 'ARS', params[:currency].blank? || params[:currency] == 'ARS', id: "currency_ars", data: { action: "change->invoice-form#toggleExchangeRate" }
```

```haml
= radio_button_tag :currency, 'USD', params[:currency] == 'USD', id: "currency_usd", data: { action: "change->invoice-form#toggleExchangeRate" }
```

```haml
= text_field_tag :exchange_rate, params[:exchange_rate],
```

```haml
= text_field_tag :amount, params[:amount],
```

```haml
= date_field_tag :purchase_date, params[:purchase_date].presence || Date.current,
```

```haml
= date_field_tag :due_date, params[:due_date].presence || 30.days.from_now.to_date,
```

```haml
= date_field_tag :early_payment_due_date, params[:early_payment_due_date],
```

```haml
= text_field_tag :early_payment_discount_percentage, params[:early_payment_discount_percentage],
```

```haml
= text_area_tag :notes, params[:notes],
```

Everything else on each helper (placeholder, class, data) stays exactly as it is.

- [ ] **Step 5: Green, then the full suite**

Run: `docker compose exec -T web bundle exec rspec spec/requests/web/invoices_spec.rb`
Expected: all PASS.
Run: `docker compose exec -T web bundle exec rspec` and `docker compose exec -T web bundle exec rubocop`
Expected: green. Commit the task's files.

---

### Task 6: The form — Productos card, `invoice-lines`, frozen amount, summary, zero-cost modal

**Files:**
- Create: `app/javascript/controllers/invoice_lines_controller.js`, `app/views/web/invoices/_zero_cost_modal.html.haml`
- Modify: `app/javascript/controllers/invoice_form_controller.js`, `app/javascript/controllers/product_search_controller.js`, `app/views/web/invoices/new.html.haml`
- Test: `spec/requests/web/invoices_spec.rb` (markup), `spec/system/web/invoices_with_products_spec.rb` (create)

**Interfaces:**
- Consumes: `@submitted_items` (Task 5), `search_web_products_path` and the `product-selected` event of `product-search`.
- Produces: the card element carries `data-controller="invoice-lines"` and posts `items[N][…]`; it dispatches `lines-changed` (bubbling) with `detail = { lines, total, units, products, zeroCostLines }` where `lines` are the complete ones; `invoice-form` handles `lines-changed`, dispatches `currency-changed` on the form, and owns the modal. Task 7 reuses nothing from here.

- [ ] **Step 1: Write the failing markup specs**

Add to `spec/requests/web/invoices_spec.rb`:

```ruby
  describe "GET /web/invoices/new" do
    it "offers the products card and no longer promises that stock is untouched" do
      get "/web/invoices/new"

      html = Nokogiri::HTML(response.body)
      card = html.at('[data-controller="invoice-lines"]')
      expect(card).to be_present
      expect(card.text).to include("Productos")
      expect(card.at('[data-controller="product-search"]')["data-product-search-dim-out-of-stock-value"]).to eq("false")
      expect(response.body).not_to include("Modo Simple")
      expect(response.body).not_to include("Qué NO hace este registro")
      expect(response.body).to include("Sin productos: no mueve stock")
      expect(html.at('[data-invoice-form-target="zeroCostModal"]')).to be_present
    end
  end
```

and, inside `describe "POST /web/invoices"`, append to the example "comes back with the header and the lines when the server refuses" (after its last expectation):

```ruby
      card = Nokogiri::HTML(response.body).at('[data-controller="invoice-lines"]')
      lines = JSON.parse(card["data-invoice-lines-initial-items-value"])
      expect(lines).to eq([
        { "product_id" => product.id.to_s, "sku" => "90915-YZZD2", "name" => "Filtro de aceite",
          "brand" => product.brand, "quantity" => 10, "unit_cost" => "4.500,00" }
      ])
```

- [ ] **Step 2: Run, watch them fail**

Run: `docker compose exec -T web bundle exec rspec spec/requests/web/invoices_spec.rb`
Expected: "offers the products card" FAILS (`card` nil); "comes back with the header and the lines" FAILS on the card lookup.

- [ ] **Step 3: The `dimOutOfStock` value on `product-search`**

In `app/javascript/controllers/product_search_controller.js` change the values declaration to:

```js
  static values = { url: String, dimOutOfStock: { type: Boolean, default: true } }
```

and, in `displayResults`, the row's class attribute to:

```js
          class="px-4 py-3 hover:bg-gray-50 cursor-pointer border-b border-gray-100 last:border-b-0 transition-colors ${this.dimOutOfStockValue && product.current_stock <= 0 ? 'opacity-50' : ''}"
```

The order form sets nothing, so it keeps dimming.

- [ ] **Step 4: The `invoice-lines` controller**

Create `app/javascript/controllers/invoice_lines_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"

// The Productos card of the invoice form: keeps the lines, renders them with
// the hidden inputs the server reads, and tells the form what changed.
export default class extends Controller {
  static targets = ["lines", "counter"]
  static values = { initialItems: { type: Array, default: [] } }

  connect() {
    const checked = document.querySelector('input[name="currency"]:checked')
    this.currency = checked && checked.value === "USD" ? "US$" : "$"
    this.lines = this.initialItemsValue.map(item => ({
      product_id: item.product_id,
      sku: item.sku,
      name: item.name,
      brand: item.brand,
      quantity: parseInt(item.quantity) || 0,
      unit_cost: item.unit_cost === "" || item.unit_cost === null || item.unit_cost === undefined
        ? null
        : this.parseAmount(String(item.unit_cost))
    }))
    this.render()
    this.notify()
  }

  addProduct(event) {
    const product = event.detail.product
    this.lines.push({
      product_id: product.id, sku: product.sku, name: product.name, brand: product.brand,
      quantity: 1, unit_cost: null
    })
    this.render()
    this.notify()
    const costInputs = this.linesTarget.querySelectorAll("[data-cost]")
    costInputs[costInputs.length - 1]?.focus()
  }

  remove(event) {
    this.lines.splice(this.index(event), 1)
    this.render()
    this.notify()
  }

  updateQuantity(event) {
    const i = this.index(event)
    this.lines[i].quantity = parseInt(event.currentTarget.value) || 0
    this.refreshRow(i)
    this.notify()
  }

  updateCost(event) {
    const i = this.index(event)
    const raw = event.currentTarget.value.trim()
    this.lines[i].unit_cost = raw === "" ? null : this.parseAmount(raw)
    this.refreshRow(i)
    this.notify()
  }

  // A blank cost reads as zero once the operator leaves the field, so the
  // zero is on screen before the confirmation asks about it.
  settleCost(event) {
    const i = this.index(event)
    if (this.lines[i].unit_cost !== null) return
    this.lines[i].unit_cost = 0
    event.currentTarget.value = this.formatAmount(0)
    this.refreshRow(i)
    this.notify()
  }

  currencyChanged(event) {
    this.currency = event.detail.currency === "USD" ? "US$" : "$"
    this.element.querySelectorAll("[data-currency]").forEach(el => { el.textContent = this.currency })
  }

  index(event) { return parseInt(event.currentTarget.dataset.index) }

  complete(line) { return Boolean(line.product_id) && line.quantity > 0 }

  cost(line) { return line.unit_cost === null ? 0 : line.unit_cost }

  subtotal(line) { return this.complete(line) ? this.cost(line) * line.quantity : 0 }

  parseAmount(value) {
    if (!value) return 0
    return parseFloat(value.replace(/\./g, "").replace(/,/g, ".")) || 0
  }

  formatAmount(value) {
    return new Intl.NumberFormat("es-AR", { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(value || 0)
  }

  notify() {
    const complete = this.lines.filter(line => this.complete(line))
    const detail = {
      lines: complete.map(line => ({ product_id: line.product_id, name: line.name, quantity: line.quantity, unit_cost: this.cost(line) })),
      total: complete.reduce((sum, line) => sum + this.subtotal(line), 0),
      units: complete.reduce((sum, line) => sum + line.quantity, 0),
      products: complete.length,
      zeroCostLines: complete.filter(line => this.cost(line) === 0).map(line => ({ name: line.name, quantity: line.quantity }))
    }
    this.counterTarget.textContent = complete.length
      ? `${complete.length} ${complete.length === 1 ? "producto" : "productos"} · ${detail.units} ${detail.units === 1 ? "unidad" : "unidades"}`
      : "opcional"
    this.element.dispatchEvent(new CustomEvent("lines-changed", { detail, bubbles: true }))
  }

  refreshRow(i) {
    const row = this.linesTarget.querySelector(`[data-line-index="${i}"]`)
    if (!row) return
    const line = this.lines[i]
    row.classList.toggle("opacity-50", !this.complete(line))
    row.querySelector("[data-subtotal]").textContent = this.complete(line) ? this.formatAmount(this.subtotal(line)) : "—"
    row.querySelector('input[data-field="quantity"]').value = line.quantity
    row.querySelector('input[data-field="unit_cost"]').value = line.unit_cost === null ? "" : line.unit_cost
    this.linesTarget.querySelector("[data-total]").textContent = this.formatAmount(
      this.lines.reduce((sum, l) => sum + this.subtotal(l), 0)
    )
  }

  render() {
    if (this.lines.length === 0) {
      this.linesTarget.innerHTML = `
        <div class="rounded-lg border border-dashed border-slate-300 px-6 py-8 text-center">
          <p class="text-sm font-medium text-slate-700">No hay productos cargados.</p>
          <p class="mt-1 text-xs text-slate-500">Buscá y agregá si querés que esta factura sume stock.</p>
        </div>
      `
      return
    }

    const rows = this.lines.map((line, i) => `
      <tr data-line-index="${i}" class="${this.complete(line) ? "" : "opacity-50"}">
        <td class="py-2 pr-3">
          <span class="font-mono text-xs text-slate-500">${line.sku}</span><br>
          <span class="text-slate-900">${line.name}</span>${line.brand ? ` <span class="text-slate-400">· ${line.brand}</span>` : ""}
          <input type="hidden" name="items[${i}][product_id]" value="${line.product_id}">
          <input type="hidden" name="items[${i}][sku]" value="${line.sku}">
          <input type="hidden" name="items[${i}][name]" value="${line.name}">
          <input type="hidden" name="items[${i}][brand]" value="${line.brand || ""}">
          <input type="hidden" name="items[${i}][quantity]" value="${line.quantity}" data-field="quantity">
          <input type="hidden" name="items[${i}][unit_cost]" value="${line.unit_cost === null ? "" : line.unit_cost}" data-field="unit_cost">
        </td>
        <td class="py-2 text-right">
          <input type="number" min="0" value="${line.quantity}" data-index="${i}"
                 data-action="input->invoice-lines#updateQuantity"
                 class="w-20 rounded-lg border border-slate-300 px-2 py-1.5 text-right">
        </td>
        <td class="py-2 text-right">
          <input type="text" value="${line.unit_cost === null ? "" : this.formatAmount(line.unit_cost)}" data-index="${i}" data-cost
                 data-controller="currency-input"
                 data-action="input->invoice-lines#updateCost blur->invoice-lines#settleCost blur->currency-input#format focus->currency-input#unformat"
                 class="w-28 rounded-lg border border-slate-300 px-2 py-1.5 text-right">
        </td>
        <td class="py-2 text-right tabular-nums" data-subtotal>${this.complete(line) ? this.formatAmount(this.subtotal(line)) : "—"}</td>
        <td class="py-2 text-right">
          <button type="button" data-index="${i}" data-action="click->invoice-lines#remove"
                  class="h-8 w-8 rounded-lg text-slate-400 hover:bg-slate-100 hover:text-slate-700" title="Quitar">✕</button>
        </td>
      </tr>
    `).join("")

    this.linesTarget.innerHTML = `
      <table class="w-full text-sm">
        <thead class="text-xs uppercase tracking-wider text-slate-500">
          <tr>
            <th class="py-2 text-left font-medium">Producto</th>
            <th class="py-2 text-right font-medium">Cantidad</th>
            <th class="py-2 text-right font-medium">Costo unit. (<span data-currency>${this.currency}</span>)</th>
            <th class="py-2 text-right font-medium">Subtotal</th>
            <th class="py-2"></th>
          </tr>
        </thead>
        <tbody class="divide-y divide-slate-100">${rows}</tbody>
        <tfoot class="border-t-2 border-slate-200 font-semibold">
          <tr>
            <td class="py-2" colspan="3">Total</td>
            <td class="py-2 text-right tabular-nums" data-total>${this.formatAmount(this.lines.reduce((sum, l) => sum + this.subtotal(l), 0))}</td>
            <td></td>
          </tr>
        </tfoot>
      </table>
    `
  }
}
```

- [ ] **Step 5: The form's side — `invoice-form`**

In `app/javascript/controllers/invoice_form_controller.js`:

Add to `static targets`:

```js
    "amountCaption",
    "stockTitle",
    "stockNote",
    "stockList",
    "zeroCostModal",
    "zeroCostTitle",
    "zeroCostList",
    "zeroCostSummary"
```

Replace `handleFormSubmit` with:

```js
  // Runs on the form's `submit` event: cleans the AR-formatted amounts, and
  // holds the submission once when a line is free so the operator confirms it.
  handleFormSubmit(event) {
    if (this.zeroCostLines.length > 0 && !this.zeroCostConfirmed) {
      event.preventDefault()
      this.openZeroCostModal()
      return
    }

    if (this.hasAmountTarget && this.amountTarget.value) {
      this.amountTarget.value = this.cleanAmountValue(this.amountTarget.value)
    }

    if (this.hasExchangeRateInputTarget && this.exchangeRateInputTarget.value) {
      this.exchangeRateInputTarget.value = this.cleanAmountValue(this.exchangeRateInputTarget.value)
    }
  }
```

Add, after `handleFormSubmit`:

```js
  // ========== PRODUCT LINES ==========

  linesChanged(event) {
    const { lines, total, units, products, zeroCostLines } = event.detail
    this.zeroCostLines = zeroCostLines
    this.zeroCostConfirmed = false

    if (lines.length > 0) {
      if (!this.amountTarget.readOnly) this.typedAmount = this.amountTarget.value
      this.amountTarget.readOnly = true
      this.amountTarget.classList.add("bg-slate-50", "text-slate-600")
      this.amountTarget.value = new Intl.NumberFormat("es-AR", { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(total)
      this.amountCaptionTarget.textContent = "Calculado desde los productos. Quitá todas las líneas para escribirlo a mano."
      this.stockTitleTarget.textContent = `Suma stock: ${units} ${units === 1 ? "unidad" : "unidades"} en ${products} ${products === 1 ? "producto" : "productos"}`
      this.stockNoteTarget.textContent = "El stock se suma al registrar. El costo promedio no cambia."
      this.stockListTarget.innerHTML = lines.map(line =>
        `<li class="flex justify-between"><span>${line.name}</span><span>+${line.quantity}</span></li>`
      ).join("")
      this.stockListTarget.classList.remove("hidden")
    } else {
      if (this.amountTarget.readOnly) this.amountTarget.value = this.typedAmount || ""
      this.amountTarget.readOnly = false
      this.amountTarget.classList.remove("bg-slate-50", "text-slate-600")
      this.amountCaptionTarget.textContent = "Monto total de la factura (formato: 1.500.000,50)"
      this.stockTitleTarget.textContent = "Sin productos: no mueve stock"
      this.stockNoteTarget.textContent = "Se registra solo la factura, con el monto que escribas."
      this.stockListTarget.innerHTML = ""
      this.stockListTarget.classList.add("hidden")
    }

    this.updateSummary()
  }

  openZeroCostModal() {
    const count = this.zeroCostLines.length
    this.zeroCostTitleTarget.textContent = `${count} ${count === 1 ? "línea" : "líneas"} con costo 0`
    this.zeroCostListTarget.innerHTML = this.zeroCostLines.map(line =>
      `<li class="flex justify-between"><span>${line.name}</span><span>${line.quantity} ${line.quantity === 1 ? "unidad" : "unidades"} · $ 0,00</span></li>`
    ).join("")
    this.zeroCostSummaryTarget.textContent = `${this.stockTitleTarget.textContent}. Monto de la factura: ${this.amountTarget.value}.`
    this.zeroCostModalTarget.classList.remove("hidden")
  }

  closeZeroCostModal() {
    this.zeroCostModalTarget.classList.add("hidden")
  }

  confirmZeroCost() {
    this.zeroCostConfirmed = true
    this.closeZeroCostModal()
    this.element.requestSubmit()
  }
```

In `connect()`, add as the first line of the body:

```js
    this.zeroCostLines = []
    this.zeroCostConfirmed = false
```

In `toggleExchangeRate()`, add as its last line (inside the method, whatever its current body does):

```js
    const checked = this.element.querySelector('input[name="currency"]:checked')
    this.element.dispatchEvent(new CustomEvent("currency-changed", { detail: { currency: checked ? checked.value : "ARS" }, bubbles: true }))
```

Remove the two `console.log` calls inside the old `handleFormSubmit` (they are gone with the rewrite) and leave the one in `connect()` as it is.

- [ ] **Step 6: The view**

In `app/views/web/invoices/new.html.haml`:

(a) Change the `form_with` line to listen to the native submit and to the lines:

```haml
  = form_with url: web_invoices_path, method: :post, local: true, data: { controller: "invoice-form", action: "submit->invoice-form#handleFormSubmit lines-changed->invoice-form#linesChanged" } do |f|
```

(b) Under the amount field, give the caption a target — replace the `%p.text-xs.text-gray-500.mt-1 Monto total de la factura (formato: 1.500.000,50)` line with:

```haml
              %p.text-xs.text-gray-500.mt-1{ data: { invoice_form_target: "amountCaption" } } Monto total de la factura (formato: 1.500.000,50)
```

(c) Between `CARD 2 - Early payment discount` and `CARD 3 - Notes`, insert the products card (the early-payment card keeps its place, D14):

```haml
        -# CARD - Products (optional): lines drive the stock and the amount
        .bg-white.border.border-slate-200.rounded-lg.p-6{ data: { controller: "invoice-lines", invoice_lines_initial_items_value: (@submitted_items || []).to_json, action: "product-selected->invoice-lines#addProduct currency-changed@document->invoice-lines#currencyChanged" } }
          .flex.items-center.gap-2.mb-2
            %h3.text-lg.font-semibold.text-gray-900 Productos
            %span.text-sm.text-slate-500{ data: { invoice_lines_target: "counter" } } opcional
          %p.text-sm.text-slate-600.mb-4 Si cargás los productos de la factura, la factura suma ese stock y el monto se calcula solo.

          %div{ data: { controller: "product-search", product_search_url_value: search_web_products_path, product_search_dim_out_of_stock_value: "false", action: "click@window->product-search#clickOutside" }, class: "mb-4 relative" }
            %input{ type: "text", placeholder: "Buscar por SKU, nombre o marca...", autocomplete: "off", class: "w-full px-4 py-3 border border-slate-300 rounded-xl focus:ring-2 focus:ring-slate-500 focus:border-transparent transition-all", data: { product_search_target: "input", action: "input->product-search#search" } }
            %div{ data: { product_search_target: "results" }, class: "absolute z-50 w-full mt-2 bg-white border border-slate-200 rounded-lg shadow-lg hidden", style: "max-height: 400px; overflow-y: scroll;" }

          %div{ data: { invoice_lines_target: "lines" } }
```

`currency-changed@document` listens at the document because the event is dispatched on the form, an ancestor of the card. The Stimulus value is written as the string `"false"` on purpose.

(d) In the right column, replace the whole `-# Simple mode info` block (`.bg-blue-50…` with "Modo Simple") with:

```haml
          -# What registering will do (follows the lines)
          .rounded-lg.border.border-slate-200.bg-slate-50.p-4.mb-4
            %p.text-sm.font-medium.text-slate-900{ data: { invoice_form_target: "stockTitle" } } Sin productos: no mueve stock
            %p.text-xs.text-slate-500.mt-1{ data: { invoice_form_target: "stockNote" } } Se registra solo la factura, con el monto que escribas.
            %ul.mt-2.space-y-1.text-xs.text-slate-600.tabular-nums.hidden{ data: { invoice_form_target: "stockList" } }
```

and delete the whole `.border-t.border-gray-200.py-4` block headed `Qué NO hace este registro:` (the two `✗` lines with it).

(e) As the last line inside the `form_with` block (after the closing of the grid, same indentation as `.grid.grid-cols-1.lg:grid-cols-3.gap-6`), render the modal:

```haml
    = render "zero_cost_modal"
```

Create `app/views/web/invoices/_zero_cost_modal.html.haml`:

```haml
-# Second look at the lines that cost nothing; opened by invoice-form only then.
.hidden.fixed.inset-0.bg-black.bg-opacity-50.z-50.flex.items-center.justify-center{ data: { invoice_form_target: "zeroCostModal" } }
  .bg-white.rounded-lg.p-6.max-w-md.w-full.mx-4
    %h3.text-lg.font-semibold.text-gray-900.mb-4 Confirmar registro

    .rounded-lg.border.border-slate-200.bg-slate-50.p-3.mb-4
      %p.text-sm.font-medium.text-slate-900{ data: { invoice_form_target: "zeroCostTitle" } }
      %ul.mt-2.space-y-1.text-sm.text-slate-700.tabular-nums{ data: { invoice_form_target: "zeroCostList" } }
      %p.mt-2.text-xs.text-slate-500 Si es una garantía o una bonificación, está bien. Si te olvidaste el costo, volvé a revisar.

    %p.text-sm.text-slate-600.mb-4{ data: { invoice_form_target: "zeroCostSummary" } }

    .flex.items-center.gap-3
      %button.flex-1.px-4.py-2.border.border-slate-300.text-slate-700.font-semibold.rounded-lg.hover:bg-slate-50.transition-colors{ type: "button", data: { action: "click->invoice-form#closeZeroCostModal" } } Volver a revisar
      %button.flex-1.px-4.py-2.bg-slate-700.hover:bg-slate-800.text-white.font-semibold.rounded-lg.transition-colors{ type: "button", data: { action: "click->invoice-form#confirmZeroCost" } } Registrar
```

- [ ] **Step 7: Run the request specs**

Run: `docker compose exec -T web bundle exec rspec spec/requests/web/invoices_spec.rb`
Expected: all PASS.

- [ ] **Step 8: Write the system spec**

Create `spec/system/web/invoices_with_products_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

# The invoice form's Productos card: adding a line, the frozen amount, the
# summary, and the zero-cost confirmation. The server side is covered by the
# request and service specs.
RSpec.describe "Facturas con productos", type: :system do
  include Warden::Test::Helpers

  let(:admin)     { create(:user, role: "admin") }
  let!(:location) { create(:stock_location) }
  let!(:supplier) { create(:supplier, name: "Cromosol") }
  let!(:filter)   { create(:product, sku: "90915-YZZD2", name: "Filtro de aceite Toyota", current_stock: 0) }

  before do
    driven_by :selenium_chrome_headless, screen_size: [ 1400, 900 ]
    login_as(admin, scope: :user)
    visit "/web/invoices/new"
    select "Cromosol", from: "supplier_id"
    fill_in "invoice_number", with: "FAC-0001234"
    choose "currency_ars"
  end

  def add_line(query, quantity:, cost:)
    fill_in placeholder: "Buscar por SKU, nombre o marca...", with: query
    find("[data-product-search-target='results'] [data-action*='selectProduct']", text: query, match: :first).click
    within("[data-controller='invoice-lines'] tbody tr:last-child") do
      find("input[type='number']").fill_in(with: quantity)
      cost_input = find("[data-cost]")
      cost_input.fill_in(with: cost)
      cost_input.send_keys(:tab)
    end
  end

  it "freezes the amount to the sum, says what will be stocked, and registers the lines" do
    add_line("90915", quantity: 10, cost: "4.500,00")

    amount = find("#amount")
    expect(amount[:readonly]).to be_truthy
    expect(amount.value).to eq("45.000,00")
    expect(page).to have_text("Suma stock: 10 unidades en 1 producto")
    expect(page).to have_text("1 producto · 10 unidades")

    click_button "Registrar Factura"

    expect(page).to have_text("Factura registrada exitosamente")
    expect(filter.reload.current_stock).to eq(10)
    expect(Invoice.last.amount).to eq(45_000)
  end

  it "unfreezes the amount when the last line is removed" do
    fill_in "amount", with: "1.000,00"
    add_line("90915", quantity: 1, cost: "100,00")
    expect(find("#amount").value).to eq("100,00")

    find("button[title='Quitar']").click

    amount = find("#amount")
    expect(amount[:readonly]).to be_falsey
    expect(amount.value).to eq("1.000,00")
    expect(page).to have_text("Sin productos: no mueve stock")
  end

  it "asks for a second look at a free line, and only then" do
    add_line("90915", quantity: 2, cost: "")
    expect(find("[data-cost]").value).to eq("0,00")

    click_button "Registrar Factura"

    within("[data-invoice-form-target='zeroCostModal']") do
      expect(page).to have_text("1 línea con costo 0")
      expect(page).to have_text("Filtro de aceite Toyota")
      click_button "Volver a revisar"
    end
    expect(Invoice.count).to eq(0)
    expect(page).to have_css("[data-invoice-form-target='zeroCostModal'].hidden", visible: :all)

    click_button "Registrar Factura"
    within("[data-invoice-form-target='zeroCostModal']") { click_button "Registrar" }

    expect(page).to have_text("Factura registrada exitosamente")
    expect(Invoice.last.amount).to eq(0)
    expect(filter.reload.current_stock).to eq(2)
  end

  it "does not ask when every cost is above zero" do
    add_line("90915", quantity: 1, cost: "100,00")

    click_button "Registrar Factura"

    expect(page).to have_text("Factura registrada exitosamente")
    expect(page).not_to have_text("Confirmar registro")
  end
end
```

If `fill_in ... with: ""` does not fire `input` in the driver (it has happened in this suite), clear the cost with `cost_input.send_keys([:control, "a"], :backspace)` before tabbing.

- [ ] **Step 9: Run the system spec, then everything**

Run: `docker compose exec -T web bundle exec rspec spec/system/web/invoices_with_products_spec.rb`
Expected: all PASS. If a class added in this task does not render, check `app/assets/builds/tailwind.css` for it before touching the markup (stale watcher).
Run: `docker compose exec -T web bundle exec rspec` and `docker compose exec -T web bundle exec rubocop`
Expected: green. Commit the task's files.

---

### Task 7: Show and edit — the lines, the caption, the frozen amount, the confirmation text

**Files:**
- Create: `app/helpers/invoices_helper.rb`, `app/views/web/invoices/_lines_table.html.haml`
- Modify: `app/views/web/invoices/show.html.haml`, `app/views/web/invoices/edit.html.haml`
- Test: `spec/requests/web/invoices_spec.rb`, `spec/helpers/invoices_helper_spec.rb` (create)

**Interfaces:**
- Consumes: `invoice.invoice_items` (with `product`, `subtotal`), `Invoices::CancelInvoice` semantics (Task 4).
- Produces: `InvoicesHelper#invoice_units(invoice)` → Integer sum of line quantities; `InvoicesHelper#invoice_cancel_confirmation(invoice)` → the `turbo_confirm` text.

- [ ] **Step 1: Write the failing specs**

Create `spec/helpers/invoices_helper_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvoicesHelper, type: :helper do
  let(:invoice) { build(:invoice, :simple_mode) }

  it "counts the units the invoice's lines add" do
    invoice.invoice_items.build(product: build(:product), quantity: 10, unit_cost: 1)
    invoice.invoice_items.build(product: build(:product), quantity: 4, unit_cost: 1)

    expect(helper.invoice_units(invoice)).to eq(14)
  end

  it "names the units in the cancel confirmation of an itemized invoice" do
    invoice.invoice_items.build(product: build(:product), quantity: 15, unit_cost: 1)

    expect(helper.invoice_cancel_confirmation(invoice))
      .to eq("¿Cancelar esta factura? Se descuentan del stock las 15 unidades que sumó, hasta donde haya.")
  end

  it "keeps today's confirmation for an amount-only invoice" do
    expect(helper.invoice_cancel_confirmation(invoice)).to eq("¿Estás seguro de cancelar esta factura?")
  end
end
```

Add to `spec/requests/web/invoices_spec.rb`:

```ruby
  describe "GET /web/invoices/:id" do
    let!(:location) { create(:stock_location) }

    def itemized
      product = create(:product, sku: "90915-YZZD2", name: "Filtro de aceite", current_stock: 0)
      Invoices::CreateInvoice.call(
        supplier: supplier, invoice_number: "FAC-5", amount: nil, currency: "ARS",
        purchase_date: Date.current, due_date: 30.days.from_now,
        items: [ { product_id: product.id, quantity: 10, unit_cost: 4500 } ]
      ).record
    end

    it "shows the lines, the caption and the stock-aware cancel confirmation on an itemized invoice" do
      get "/web/invoices/#{itemized.id}"

      html = Nokogiri::HTML(response.body)
      expect(html.at("#invoice-lines")).to be_present
      expect(html.at("#invoice-lines").text).to include("90915-YZZD2", "Filtro de aceite", "10")
      expect(response.body).to include("calculado desde 1 producto")
      expect(response.body).to include("10 unidades sumadas al stock")
      expect(html.at("form[action$='/cancel']")["data-turbo-confirm"])
        .to eq("¿Cancelar esta factura? Se descuentan del stock las 10 unidades que sumó, hasta donde haya.")
    end

    it "shows an amount-only invoice exactly as before" do
      invoice = create(:invoice, :simple_mode, supplier: supplier)

      get "/web/invoices/#{invoice.id}"

      html = Nokogiri::HTML(response.body)
      expect(html.at("#invoice-lines")).to be_nil
      expect(response.body).not_to include("calculado desde")
      expect(html.at("form[action$='/cancel']")["data-turbo-confirm"]).to eq("¿Estás seguro de cancelar esta factura?")
    end
  end

  describe "GET /web/invoices/:id/edit" do
    let!(:location) { create(:stock_location) }

    it "freezes the amount and lists the lines read-only on an itemized invoice" do
      product = create(:product, current_stock: 0)
      invoice = Invoices::CreateInvoice.call(
        supplier: supplier, invoice_number: "FAC-6", amount: nil, currency: "ARS",
        purchase_date: Date.current, due_date: 30.days.from_now,
        items: [ { product_id: product.id, quantity: 3, unit_cost: 100 } ]
      ).record

      get "/web/invoices/#{invoice.id}/edit"

      html = Nokogiri::HTML(response.body)
      expect(html.at("#invoice_amount")["readonly"]).to be_present
      expect(response.body).to include("Calculado desde los productos; no se edita.")
      expect(html.at("#invoice-lines")).to be_present
      expect(response.body).to include("Las líneas no se editan. Si la factura está mal cargada, cancelala y registrala de nuevo.")
    end

    it "keeps the amount editable on an amount-only invoice" do
      invoice = create(:invoice, :simple_mode, supplier: supplier)

      get "/web/invoices/#{invoice.id}/edit"

      expect(Nokogiri::HTML(response.body).at("#invoice_amount")["readonly"]).to be_nil
    end
  end
```

- [ ] **Step 2: Run, watch them fail**

Run: `docker compose exec -T web bundle exec rspec spec/helpers/invoices_helper_spec.rb spec/requests/web/invoices_spec.rb`
Expected: the helper spec FAILS (`uninitialized constant InvoicesHelper`); the new show/edit examples FAIL on the missing markup; "shows an amount-only invoice exactly as before" PASSES except for nothing — it should pass already, since it asserts absence.

- [ ] **Step 3: The helper**

Create `app/helpers/invoices_helper.rb`:

```ruby
# frozen_string_literal: true

module InvoicesHelper
  def invoice_units(invoice)
    invoice.invoice_items.sum(&:quantity)
  end

  def invoice_cancel_confirmation(invoice)
    units = invoice_units(invoice)
    return "¿Estás seguro de cancelar esta factura?" if units.zero?

    "¿Cancelar esta factura? Se descuentan del stock las #{units} #{units == 1 ? 'unidad' : 'unidades'} que sumó, hasta donde haya."
  end
end
```

`sum(&:quantity)` runs in Ruby on purpose: it works on lines built in memory (the helper spec) and on loaded ones alike.

- [ ] **Step 4: The shared read-only table**

Create `app/views/web/invoices/_lines_table.html.haml` (locals: `invoice`):

```haml
%table#invoice-lines.w-full.text-sm.tabular-nums
  %thead.text-xs.uppercase.tracking-wider.text-slate-500
    %tr
      %th.py-2.text-left.font-medium Producto
      %th.py-2.text-right.font-medium Cantidad
      %th.py-2.text-right.font-medium= "Costo unit. (#{invoice.currency == 'USD' ? 'US$' : '$'})"
      %th.py-2.text-right.font-medium Subtotal
  %tbody.divide-y.divide-slate-100
    - invoice.invoice_items.includes(:product).each do |item|
      %tr
        %td.py-2
          %span.font-mono.text-xs.text-slate-500= item.product.sku
          %br
          = item.product.name
          - if item.product.brand.present?
            %span.text-slate-400= "· #{item.product.brand}"
        %td.py-2.text-right= item.quantity
        %td.py-2.text-right= number_ar(item.unit_cost)
        %td.py-2.text-right= number_ar(item.subtotal)
  %tfoot.border-t-2.border-slate-200.font-semibold
    %tr
      %td.py-2{ colspan: 3 } Total
      %td.py-2.text-right= "#{invoice.currency == 'USD' ? 'US$' : '$'} #{number_ar(invoice.amount)}"
```

- [ ] **Step 5: The show view**

In `app/views/web/invoices/show.html.haml`:

(a) In the `Monto:` row, after the `%span.text-2xl.font-bold.text-gray-900` block (which prints the currency and the amount), add:

```haml
            - if @invoice.invoice_items.any?
              %span.ml-2.text-xs.text-slate-500= "calculado desde #{@invoice.invoice_items.size} #{'producto'.pluralize(@invoice.invoice_items.size)}"
```

(b) Between the invoice info card and the `-# Notes card (if any)` comment, insert:

```haml
      -# Products card (only when the invoice carries lines)
      - if @invoice.invoice_items.any?
        .bg-white.border.border-slate-200.rounded-lg.p-6
          .flex.items-center.justify-between.mb-4
            %h3.text-lg.font-semibold.text-gray-900 Productos
            %span.text-sm.text-slate-500= "#{invoice_units(@invoice)} unidades sumadas al stock"
          = render "lines_table", invoice: @invoice
```

(c) On the cancel `button_to`, replace `data: { turbo_confirm: "¿Estás seguro de cancelar esta factura?" }` with `data: { turbo_confirm: invoice_cancel_confirmation(@invoice) }`. The button is already the red danger button.

- [ ] **Step 6: The edit view**

In `app/views/web/invoices/edit.html.haml`, replace the `-# Amount` block (the `%div` holding `f.label :amount` and `f.text_field :amount`) with:

```haml
        -# Amount: owned by the lines when there are any
        %div
          = f.label :amount, "Monto Total", class: "block text-sm font-medium text-gray-700 mb-2"
          - if @invoice.invoice_items.any?
            = f.text_field :amount,
                          value: number_with_precision(@invoice.amount, precision: 2, delimiter: '.', separator: ','),
                          readonly: true,
                          class: "w-full px-4 py-3 border border-gray-300 rounded-xl bg-slate-50 text-slate-600 text-lg font-semibold"
            %p.text-xs.text-gray-500.mt-1 Calculado desde los productos; no se edita.
          - else
            = f.text_field :amount,
                          value: number_with_precision(@invoice.amount, precision: 2, delimiter: '.', separator: ','),
                          placeholder: "0,00",
                          class: "w-full px-4 py-3 border border-gray-300 rounded-xl focus:ring-2 focus:ring-gray-700 focus:border-transparent transition-all text-lg font-semibold",
                          required: true,
                          data: { invoice_form_target: "amount", action: "blur->invoice-form#formatAmount focus->invoice-form#unformatAmount" }
```

and, after the card that holds the notes field (the last card before the submit buttons), add:

```haml
    - if @invoice.invoice_items.any?
      .bg-white.border.border-slate-200.rounded-lg.p-6
        .flex.items-center.justify-between.mb-4
          %h3.text-lg.font-semibold.text-gray-900 Productos
          %span.text-sm.text-slate-500= "#{@invoice.invoice_items.size} #{'producto'.pluralize(@invoice.invoice_items.size)} · #{invoice_units(@invoice)} unidades"
        = render "lines_table", invoice: @invoice
        %p.mt-3.text-xs.text-slate-500 Las líneas no se editan. Si la factura está mal cargada, cancelala y registrala de nuevo.
```

The frozen field keeps no `invoice_form_target: "amount"`: the form controller's `handleFormSubmit` cleans the amount only when the target exists, and Task 5's controller drops `:amount` anyway.

- [ ] **Step 7: Green, then everything**

Run: `docker compose exec -T web bundle exec rspec spec/helpers/invoices_helper_spec.rb spec/requests/web/invoices_spec.rb`
Expected: all PASS.
Run: `docker compose exec -T web bundle exec rspec` and `docker compose exec -T web bundle exec rubocop`
Expected: green. Commit the task's files.

---

### Task 8: Documentation

**Files:**
- Modify: `WORKING_CONTEXT.md` (Invoices, Stock, Key constraints, Active services, Important gaps), `docs/TESTING_GUIDE.md` (the money-flow catalogue), `docs/DEVELOPMENT_GUIDE.md` (the Purchases rules)

- [ ] **Step 1: `WORKING_CONTEXT.md`**

Under `### Invoices (simple mode in the UI)`, replace the first bullet (`Invoices::CreateSimpleInvoice creates has_items: false, status: pending records — no stock movements.`) with:

```markdown
* **`Invoices::CreateInvoice`** (was `CreateSimpleInvoice`) creates **`has_items: false`**, **`status: pending`** records — with or without **product lines** (`items: [{product_id, quantity, unit_cost}]`). A line counts only with a product and a quantity > 0; a blank unit cost is 0, an unparseable one is refused. With lines, `amount = Σ(quantity × unit_cost)` is computed server-side (the submitted amount is ignored), the `invoice_items` are **built before `save!`** so the model's amount guard sees them, and one **`purchase` `StockMovement`** per line (`reference: invoice`, `StockLocation.first!`) is written through `Inventory::AdjustStock` — all in one transaction. `has_items` stays false on purpose: `Invoice#total_amount`, `simple_mode`, `mark_as_paid?`, the early-payment discount and credit notes all read `amount` and never notice the lines. `Invoice`'s `amount > 0` rule applies only when there are no items (`amount_required?`); an itemized invoice may sum to 0.
* **Canceling** goes through **`Invoices::CancelInvoice`**: it reverses the invoice's actual `purchase` movements per product as one `adjustment`, **floored at the product's `current_stock`** (a product with nothing left gets no row; the cancellation always succeeds), then sets `status: cancelled`. An amount-only invoice has no purchase rows and only changes status. `InvoicePolicy#cancel?` still requires `pending`.
* **Editing an itemized invoice never touches the lines** and ignores `amount` (`Web::InvoicesController#update` drops it; the edit view renders it read-only). Every other header field, `exchange_rate` included, stays editable.
* **The form** (`new.html.haml`): a Productos card driven by `invoice-lines` (Stimulus) over the reused `product-search` (with `dimOutOfStock: false`); the amount freezes to the sum while complete lines exist; a submit with a zero-cost line opens a confirmation modal first (and only then); a failed submit re-renders with the header from `params` and the lines from `@submitted_items`. Lines post as `items[N][…]`.
```

Under `### Stock`, add:

```markdown
* **Invoices with lines write `purchase` movements at registration and floored `adjustment` reversals on cancel** (`Invoices::CreateInvoice` / `CancelInvoice`). **Sales still write nothing** — the sales half of the stock reactivation is pending (`docs/superpowers/specs/2026-07-09-invoice-items-stock-reactivation-design.md`, Decisions C/D).
```

Under `## Key constraints`, after the stock rule, add:

```markdown
* **An invoice's `amount` is typed only when it has no lines.** With lines the server computes it and both the create and update paths ignore what the client sends. A blank unit cost is a free line (0); an unparseable one is refused, never read as 0.
```

Under `## Active services`, change the Invoices line to:

```markdown
* **Invoices:** `Invoices::CreateInvoice`, `Invoices::CancelInvoice`, `Invoices::MarkAsPaid`, `Invoices::ProcessPayment`
```

Under `## Important gaps`, add:

```markdown
* **Average cost is not recalculated by invoices with lines** (owner's decision, 2026-09-21): `Product#recalculate_average_cost!` only reads `confirmed` invoices and these are `pending`. The lines keep their `unit_cost`, so it can be computed later.
```

- [ ] **Step 2: `docs/TESTING_GUIDE.md`**

In the write-money list, replace `- Invoices::CreateSimpleInvoice / MarkAsPaid / ProcessPayment — amounts + AppliedCredit` with:

```markdown
- `Invoices::CreateInvoice` — the typed `amount`, and per-line `quantity` + `unit_cost` that become the amount and the stock; the hostile-input case is a unit cost of `"abc"`, which must be refused and never read as a free line
- `Invoices::CancelInvoice` — the floored stock reversal (no input to attack; what it must get right is the floor and the transaction)
- `Invoices::MarkAsPaid` / `ProcessPayment` — amounts + `AppliedCredit`
```

- [ ] **Step 3: `docs/DEVELOPMENT_GUIDE.md`**

Under `### Purchases`, replace `* Must recalculate weighted average cost` with:

```markdown
* Weighted average cost recalculation is **deferred** (decision of 2026-09-21): invoices registered with lines keep each line's `unit_cost` but leave `product.cost_unit` untouched
```

- [ ] **Step 4: Verify and run everything one last time**

Run: `grep -rn "CreateSimpleInvoice" . --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=tmp --exclude-dir=log`
Expected: only the two design specs under `docs/superpowers/specs/` (history) and the plans folder.
Run: `docker compose exec -T web bundle exec rspec` and `docker compose exec -T web bundle exec rubocop`
Expected: green. Commit the task's files. The owner will squash the branch with a message like:

```
feat(feat_34): register supplier invoices with product lines that add stock

- An invoice can carry product lines; with lines its amount is the sum of
  quantity × unit cost, computed on the server, and one purchase movement per
  line is written through Inventory::AdjustStock in the same transaction.
  has_items stays false so accounts payable is untouched.
- Invoices::CreateInvoice replaces CreateSimpleInvoice: transactional, flat
  errors, lines built before save so an itemized invoice may sum to zero.
- Invoices::CancelInvoice reverses the invoice's actual purchase rows per
  product, floored at what is left, and the controller's cancel uses it.
- The form gains a Productos card (invoice-lines over the reused
  product-search), freezes the amount to the sum, says what will be stocked,
  asks a second time only when a line costs zero, and keeps everything typed
  when the server refuses. Show and edit list the lines; the amount is frozen
  on edit.
- Average cost stays deferred; sales still move no stock (part 2).
```

---

## Verification by hand (owner, after Task 8)

1. `/web/invoices/new`: register an amount-only invoice — identical to before; the summary says "Sin productos: no mueve stock".
2. Register one with two lines: the amount freezes to the sum, the summary lists the units, the product's stock goes up by the quantities on `/web/products/:id`.
3. Leave a cost blank, tab out: it reads `0,00`; submit: the modal names the line; "Volver a revisar" closes it; "Registrar" registers.
4. Set the due date before the invoice date with lines typed: the page comes back with everything.
5. On the itemized invoice's show, cancel: the confirmation names the units; stock goes back down; the invoice reads cancelled.
6. Edit an itemized invoice: the amount is read-only, the lines are listed, the notes still save.
7. Sign in as a non-admin: nothing changed for them (the policy is untouched).
