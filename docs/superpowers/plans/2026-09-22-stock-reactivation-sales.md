# Stock reactivation, part 2: sales take stock off the shelf — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stock goes down when a product leaves the shelf — at creation for immediate and credit sales, at delivery for pagos a cuenta, floored at zero — and comes back, exactly what left, when a delivery is undone or a sale is cancelled.

**Architecture:** Two small inventory services own the shelf: `Inventory::DeductLineStock` (floor-at-zero `sale` movement referencing the `OrderItem`) and `Inventory::RestoreLineStock` (an `adjustment` of the line's net). `Sales::CreateOrder`, `Inventory::MarkDelivered` and `Sales::CancelOrder` call them inside their existing transactions; `MarkDelivered` becomes per-line and idempotent; `CancelOrder`'s stock restore joins its cash reversal. `StockMovement` learns to reference an `OrderItem`. No migration, no controller or policy change, one text label on the product page.

**Tech Stack:** Rails 7.2, HAML, RSpec + FactoryBot, Docker-only development.

**Spec:** `docs/superpowers/specs/2026-09-22-stock-reactivation-sales-design.md` (decisions S1–S11) — and its parents `2026-09-21-stock-reactivation-invoices-design.md` (part 1) and `2026-07-09-invoice-items-stock-reactivation-design.md` (decision C). Executors read the part-2 spec in full.

**Branch:** `feat-34_stock-reactivation`, on top of part 1 (HEAD `90495a5`). Commit scope `feat_34`, one commit per task; the owner squashes both parts together.

## Global Constraints

- **No host Ruby.** Every command runs in Docker, in the FOREGROUND: `docker compose exec -T web bundle exec rspec …`, `docker compose exec -T web bundle exec rubocop`. Full suite ONCE per task, at the end of the task.
- **Stock is never written directly.** Every stock change is `Inventory::AdjustStock` → `StockMovement` row → `Product#recalculate_current_stock!`. `product.update!(current_stock: x)` is forbidden.
- **Fixtures seed stock through movements (spec S10).** `Product#recalculate_current_stock!` overwrites `current_stock` with the SUM of movements, so a factory `current_stock: 50` with no movement behind it ends **negative** after the first sale. Every spec that asserts on stock starts its products at `current_stock: 0` and adds stock with a `purchase` movement through the `stock!` helper each task defines; every spec that moves stock creates a `StockLocation` first.
- **The floor at zero is defined once**, in `Inventory::DeductLineStock`; nobody else computes `min(quantity, current_stock)`. A restore is the line's net (`-order_item.stock_movements.sum(:quantity)`), defined once in `Inventory::RestoreLineStock`.
- **Services return `Result`** (`app/services/result.rb`); controllers stay thin — none change here; Pundit untouched; HAML only; no logic in views beyond the one label.
- **Code, comments and specs in English; comments minimal; no references to AGENTS.md or any doctrine document in code or specs.** Movement notes and any new user-facing message in Spanish; the existing English `ValidationError` messages of `CreateOrder` and `CancelOrder` stay as they are.
- **Reuse before writing:** `Inventory::AdjustStock`, the `Result` pattern, the `:stock_movement` factory, the existing spec files (extend them; do not fork).
- **Commit at the end of each task**, only the files the task touched (`git add <paths>`, never `git add -A` — the tree may hold uncommitted docs that are not yours). Subject `type(feat_34): title` in English, blank line, body in bullets. **Never** add `Co-Authored-By`, "Generated with Claude" or any Anthropic/Claude line — a `commit-msg` hook rejects both. Do not push.
- **Subagents are dispatched only when the owner asks**, as `builder` / `reviewer`.

---

## File structure

| File | Responsibility |
|---|---|
| `app/models/stock_movement.rb`, `app/models/order_item.rb`, `app/models/order.rb` | `OrderItem` as a movement reference; `Order#sale_movements` (Task 1) |
| `app/views/web/products/show.html.haml` | the "Nota N" label (Task 1) |
| `app/services/inventory/deduct_line_stock.rb` | the floor-at-zero deduction of one line (Task 2) |
| `app/services/inventory/restore_line_stock.rb` | the net restore of one line (Task 2) |
| `app/services/sales/create_order.rb` | deduct at creation; drop the `live` stock block (Task 3) |
| `app/services/inventory/mark_delivered.rb` | per-line delivery with deduct/restore (Task 4) |
| `app/services/sales/cancel_order.rb` | restore lines with the cash reversal (Task 5) |
| `WORKING_CONTEXT.md`, `docs/DEVELOPMENT_GUIDE.md`, `docs/TESTING_GUIDE.md` | the record (Task 6) |

---

### Task 1: A movement can reference the sale line

**Files:**
- Modify: `app/models/stock_movement.rb:18`, `app/models/order_item.rb:1-4`, `app/models/order.rb` (after `calculate_total!`), `app/views/web/products/show.html.haml:156-163`
- Test: `spec/models/stock_movement_spec.rb` (create if absent — check first), `spec/models/order_spec.rb` (append), `spec/requests/web/products_spec.rb` (append)

**Interfaces:**
- Produces: `StockMovement` accepts `reference: order_item`; `OrderItem#stock_movements` (`as: :reference`); `Order#sale_movements` → `StockMovement` relation of the lines' movements; the product page prints `Nota <paper_number>` for an `OrderItem` reference.

- [ ] **Step 1: Write the failing tests**

In `spec/models/order_spec.rb`, append inside the top-level `describe`:

```ruby
  describe "#sale_movements" do
    let!(:location) { create(:stock_location) }

    it "gathers the movements that reference the order's lines, and nothing else" do
      order = create(:order, :on_account, total_amount: 100, original_total_amount: 100)
      line  = create(:order_item, order: order, product: create(:product), quantity: 1, unit_price: 100)
      other = create(:order_item, order: create(:order, :on_account, total_amount: 100, original_total_amount: 100),
                     product: create(:product), quantity: 1, unit_price: 100)
      mine   = create(:stock_movement, :sale, product: line.product, stock_location: location, reference: line)
      theirs = create(:stock_movement, :sale, product: other.product, stock_location: location, reference: other)
      create(:stock_movement, product: line.product, stock_location: location, reference: order)

      expect(order.sale_movements).to contain_exactly(mine)
      expect(order.sale_movements).not_to include(theirs)
    end
  end
```

Create `spec/models/stock_movement_spec.rb` if there is none (if one exists, append the example):

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe StockMovement, type: :model do
  let!(:location) { create(:stock_location) }

  it "accepts an order line as its reference" do
    line = create(:order_item, product: create(:product), quantity: 1, unit_price: 100)
    movement = build(:stock_movement, :sale, product: line.product, stock_location: location, reference: line)

    expect(movement).to be_valid
    expect(line.stock_movements).to include(movement.tap(&:save!))
  end

  it "still refuses a reference of another kind" do
    movement = build(:stock_movement, product: create(:product), stock_location: location)
    movement.reference_type = "Customer"
    movement.reference_id = 1

    expect(movement).not_to be_valid
  end
end
```

In `spec/requests/web/products_spec.rb`, append a `describe`:

```ruby
  describe "GET /web/products/:id — stock movements" do
    let!(:location) { create(:stock_location) }

    it "names the sale note behind a sale movement" do
      order = create(:order, :on_account, paper_number: "3340", total_amount: 100, original_total_amount: 100)
      line  = create(:order_item, order: order, product: product, quantity: 1, unit_price: 100)
      create(:stock_movement, :sale, product: product, stock_location: location, reference: line)

      sign_in admin
      get "/web/products/#{product.id}"

      expect(response.body).to include("Nota 3340")
    end
  end
```

- [ ] **Step 2: Run them, watch them fail**

Run: `docker compose exec -T web bundle exec rspec spec/models/order_spec.rb spec/models/stock_movement_spec.rb spec/requests/web/products_spec.rb`
Expected: "gathers the movements" FAILS (`undefined method sale_movements`); "accepts an order line" FAILS on validity (`Reference type is not included in the list`) and on `line.stock_movements`; "names the sale note" FAILS (body has "Order #" not "Nota 3340"). The rest pass.

- [ ] **Step 3: The models**

`app/models/stock_movement.rb`, line 18:

```ruby
  validates :reference_type, inclusion: { in: %w[Order Invoice OrderItem] }, if: -> { reference_id.present? }
```

`app/models/order_item.rb`, after `belongs_to :product, -> { with_deleted }`:

```ruby
  has_many :stock_movements, as: :reference, dependent: :nullify
```

`app/models/order.rb`, after `calculate_total!`:

```ruby
  # What this sale took off the shelf, line by line.
  def sale_movements
    StockMovement.where(reference_type: "OrderItem", reference_id: order_items.select(:id))
  end
```

- [ ] **Step 4: The label**

In `app/views/web/products/show.html.haml`, the `-# Reference` block becomes:

```haml
                    -# Reference
                    - if movement.reference.present?
                      %p.text-sm.text-slate-600
                        - if movement.reference_type == 'OrderItem'
                          Nota #{movement.reference.order.paper_number}
                        - elsif movement.reference_type == 'Order'
                          Order ##{movement.reference_id}
                        - elsif movement.reference_type == 'Invoice'
                          Invoice ##{movement.reference_id}
                        - else
                          = movement.note || "-"
                    - elsif movement.note.present?
                      %p.text-sm.text-slate-600= movement.note
```

- [ ] **Step 5: Green, full suite, rubocop, commit**

Run the three files → all PASS. Then `docker compose exec -T web bundle exec rspec` and `… rubocop` → green. Commit the task's files.

---

### Task 2: `Inventory::DeductLineStock` and `Inventory::RestoreLineStock`

**Files:**
- Create: `app/services/inventory/deduct_line_stock.rb`, `app/services/inventory/restore_line_stock.rb`
- Test: `spec/services/inventory/deduct_line_stock_spec.rb`, `spec/services/inventory/restore_line_stock_spec.rb` (create both)

**Interfaces:**
- Consumes: Task 1 (`reference: order_item`, `order_item.stock_movements`).
- Produces: `Inventory::DeductLineStock.call(order_item:, note: nil)` → `Result` (record: the `StockMovement`, or `nil` on the no-op). Takes `min(order_item.quantity, product.reload.current_stock)` as one `sale` movement (negative quantity) referencing the line, at `StockLocation.first!`; writes nothing and succeeds when that is 0. `Inventory::RestoreLineStock.call(order_item:, note: nil)` → `Result`; puts back `-order_item.stock_movements.sum(:quantity)` when positive as one `adjustment` movement referencing the line; no-op otherwise. Tasks 3–5 call exactly these.

- [ ] **Step 1: Write the failing tests**

Create `spec/services/inventory/deduct_line_stock_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::DeductLineStock do
  let!(:location) { create(:stock_location) }
  let(:product)   { create(:product, current_stock: 0) }
  let(:order)     { create(:order, :on_account, total_amount: 100, original_total_amount: 100) }

  def stock!(quantity)
    create(:stock_movement, product: product, stock_location: location, quantity: quantity, movement_type: "purchase")
    product.recalculate_current_stock!
  end

  def line(quantity)
    create(:order_item, order: order, product: product, quantity: quantity, unit_price: 100)
  end

  it "takes the whole line when the shelf covers it" do
    stock!(3)

    result = described_class.call(order_item: line(2), note: "Nota 1")

    expect(result.success?).to be true
    expect(product.reload.current_stock).to eq(1)
    movement = result.record
    expect(movement.movement_type).to eq("sale")
    expect(movement.quantity).to eq(-2)
    expect(movement.reference).to eq(order.order_items.first)
    expect(movement.stock_location).to eq(location)
    expect(movement.note).to eq("Nota 1")
  end

  it "takes only what is there and stops at zero" do
    stock!(3)

    result = described_class.call(order_item: line(5))

    expect(result.success?).to be true
    expect(product.reload.current_stock).to eq(0)
    expect(result.record.quantity).to eq(-3)
  end

  it "writes nothing when the shelf is empty, and still succeeds" do
    result = nil
    expect { result = described_class.call(order_item: line(5)) }.not_to change(StockMovement, :count)

    expect(result.success?).to be true
    expect(result.record).to be_nil
    expect(product.reload.current_stock).to eq(0)
  end

  it "reads the shelf fresh, so two lines of the same product deduct in sequence" do
    stock!(3)
    first  = line(2)
    second = line(2)

    described_class.call(order_item: first)
    described_class.call(order_item: second)

    expect(product.reload.current_stock).to eq(0)
    expect(second.stock_movements.sum(:quantity)).to eq(-1)
  end

  it "fails when there is no stock location" do
    location.destroy!

    result = described_class.call(order_item: line(1))

    expect(result.success?).to be false
  end
end
```

Create `spec/services/inventory/restore_line_stock_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::RestoreLineStock do
  let!(:location) { create(:stock_location) }
  let(:product)   { create(:product, current_stock: 0) }
  let(:order)     { create(:order, :on_account, total_amount: 100, original_total_amount: 100) }
  let(:line)      { create(:order_item, order: order, product: product, quantity: 3, unit_price: 100) }

  def stock!(quantity)
    create(:stock_movement, product: product, stock_location: location, quantity: quantity, movement_type: "purchase")
    product.recalculate_current_stock!
  end

  it "puts back what the line took, as an adjustment referencing the line" do
    stock!(3)
    Inventory::DeductLineStock.call(order_item: line)

    result = described_class.call(order_item: line, note: "Cancelación nota 1")

    expect(result.success?).to be true
    expect(product.reload.current_stock).to eq(3)
    expect(result.record.movement_type).to eq("adjustment")
    expect(result.record.quantity).to eq(3)
    expect(result.record.reference).to eq(line)
    expect(result.record.note).to eq("Cancelación nota 1")
    expect(line.stock_movements.sum(:quantity)).to eq(0)
  end

  it "puts back the net of a line taken, restored and taken again" do
    stock!(3)
    Inventory::DeductLineStock.call(order_item: line)
    described_class.call(order_item: line)
    Inventory::DeductLineStock.call(order_item: line)

    described_class.call(order_item: line)

    expect(product.reload.current_stock).to eq(3)
    expect(line.stock_movements.sum(:quantity)).to eq(0)
  end

  it "puts back only what the floor let the line take" do
    stock!(1)
    Inventory::DeductLineStock.call(order_item: line)

    described_class.call(order_item: line)

    expect(product.reload.current_stock).to eq(1)
  end

  it "writes nothing for a line that took nothing" do
    result = nil
    expect { result = described_class.call(order_item: line) }.not_to change(StockMovement, :count)

    expect(result.success?).to be true
    expect(result.record).to be_nil
  end

  it "writes nothing for a line whose net is already zero" do
    stock!(3)
    Inventory::DeductLineStock.call(order_item: line)
    described_class.call(order_item: line)

    expect { described_class.call(order_item: line) }.not_to change(StockMovement, :count)
  end
end
```

- [ ] **Step 2: Run, watch them fail**

Run: `docker compose exec -T web bundle exec rspec spec/services/inventory/deduct_line_stock_spec.rb spec/services/inventory/restore_line_stock_spec.rb`
Expected: every example FAILS with `uninitialized constant Inventory::DeductLineStock` / `RestoreLineStock`.

- [ ] **Step 3: The two services**

Create `app/services/inventory/deduct_line_stock.rb`:

```ruby
# frozen_string_literal: true

module Inventory
  # Takes a sale line's quantity off the shelf, as far as there is stock to
  # take: the sale never fails for stock, and the count never goes below zero.
  class DeductLineStock
    def self.call(order_item:, note: nil)
      new(order_item: order_item, note: note).call
    end

    def initialize(order_item:, note: nil)
      @order_item = order_item
      @note = note
    end

    def call
      product = @order_item.product.reload
      quantity = [ @order_item.quantity, product.current_stock ].min
      return Result.new(success?: true, record: nil, errors: []) unless quantity.positive?

      Inventory::AdjustStock.call(
        product: product,
        stock_location: StockLocation.first!,
        movement_type: "sale",
        quantity: -quantity,
        reference: @order_item,
        note: @note
      )
    rescue ActiveRecord::RecordNotFound => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    end
  end
end
```

Create `app/services/inventory/restore_line_stock.rb`:

```ruby
# frozen_string_literal: true

module Inventory
  # Puts back on the shelf whatever a sale line's own movements say is out.
  class RestoreLineStock
    def self.call(order_item:, note: nil)
      new(order_item: order_item, note: note).call
    end

    def initialize(order_item:, note: nil)
      @order_item = order_item
      @note = note
    end

    def call
      out = -@order_item.stock_movements.sum(:quantity)
      return Result.new(success?: true, record: nil, errors: []) unless out.positive?

      Inventory::AdjustStock.call(
        product: @order_item.product,
        stock_location: StockLocation.first!,
        movement_type: "adjustment",
        quantity: out,
        reference: @order_item,
        note: @note
      )
    rescue ActiveRecord::RecordNotFound => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    end
  end
end
```

`AdjustStock` recalculates `current_stock` after every write, so a restore never trips its negative guard and a deduction never exceeds what the fresh read allowed.

- [ ] **Step 4: Green, full suite, rubocop, commit**

Run the two files → all PASS. Full suite and rubocop → green. Commit.

---

### Task 3: `Sales::CreateOrder` takes the goods at creation

**Files:**
- Modify: `app/services/sales/create_order.rb`
- Test: `spec/services/sales/create_order_spec.rb`

**Interfaces:**
- Consumes: `Inventory::DeductLineStock` (Task 2).
- Produces: `Sales::CreateOrder.call(…)` — same keywords — deducts every line for `immediate` and `credit`, and only the lines in `delivered_product_ids` for `on_account`, inside its transaction; never refuses a sale for stock (the `source == "live"` block is gone; `source:` is still accepted and stored). A failed deduction rolls everything back.

- [ ] **Step 1: Rewrite the stock examples**

In `spec/services/sales/create_order_spec.rb`, add right after `let(:customer_without_credit)`:

```ruby
  def stock!(product, quantity)
    create(:stock_movement, product: product, stock_location: stock_location, quantity: quantity, movement_type: "purchase")
    product.recalculate_current_stock!
  end
```

Replace the whole `context 'with insufficient stock' do … end` block with:

```ruby
    context 'stock leaves the shelf with the note' do
      let(:product) { create(:product, current_stock: 0, price_unit: 100) }

      def sell(quantity, order_type: 'immediate', source: 'live', customer: customer_with_credit)
        described_class.call(
          customer: customer,
          items: [ { product_id: product.id, quantity: quantity, unit_price: 100 } ],
          order_type: order_type,
          source: source,
          paper_number: '0001',
          user: user
        )
      end

      it 'takes the whole line when the shelf covers it' do
        stock!(product, 3)

        result = sell(2)

        expect(result.success?).to be true
        expect(product.reload.current_stock).to eq(1)
        expect(result.record.sale_movements.pluck(:quantity)).to eq([ -2 ])
      end

      it 'takes only what is there and still registers the sale' do
        stock!(product, 3)

        result = sell(5)

        expect(result.success?).to be true
        expect(product.reload.current_stock).to eq(0)
        expect(result.record.sale_movements.pluck(:quantity)).to eq([ -3 ])
      end

      it 'registers a sale with nothing on the shelf and writes no movement' do
        result = nil
        expect { result = sell(5) }.not_to change(StockMovement, :count)

        expect(result.success?).to be true
        expect(product.reload.current_stock).to eq(0)
      end

      it 'never refuses a live sale for stock any more' do
        stock!(product, 1)

        result = sell(100, source: 'live')

        expect(result.success?).to be true
        expect(result.errors).to be_empty
      end

      it 'takes the goods for a credit sale too' do
        stock!(product, 4)

        result = sell(3, order_type: 'credit')

        expect(result.success?).to be true
        expect(product.reload.current_stock).to eq(1)
      end

      it 'deducts two lines of the same product in sequence' do
        stock!(product, 3)

        result = described_class.call(
          customer: customer_with_credit,
          items: [ { product_id: product.id, quantity: 2, unit_price: 100 },
                   { product_id: product.id, quantity: 2, unit_price: 100 } ],
          order_type: 'immediate',
          paper_number: '0001',
          user: user
        )

        expect(result.success?).to be true
        expect(product.reload.current_stock).to eq(0)
        expect(result.record.sale_movements.order(:id).pluck(:quantity)).to eq([ -2, -1 ])
      end

      it 'names the note on the movement' do
        stock!(product, 1)

        sell(1)

        expect(StockMovement.last.note).to eq("Nota 0001")
      end

      it 'rolls the whole sale back when a deduction fails' do
        stock!(product, 3)
        allow(Inventory::DeductLineStock).to receive(:call)
          .and_return(Result.new(success?: false, record: nil, errors: [ "Error adjusting stock" ]))

        result = nil
        expect { result = sell(1) }.to not_change(Order, :count).and not_change(OrderItem, :count)
        expect(result.success?).to be false
        expect(result.errors).to include("Error adjusting stock")
      end
    end
```

If `not_change` is not defined in this file, add `RSpec::Matchers.define_negated_matcher :not_change, :change` right after `require 'rails_helper'`.

Replace the `context 'transaction rollback'` block's single example (`'rolls back everything on stock validation error'`) with:

```ruby
      it 'rolls back everything on a validation error' do
        product = create(:product, current_stock: 0)

        expect {
          described_class.call(
            customer: customer_with_credit,
            items: [ { product_id: product.id, quantity: 10, unit_price: 0 } ],
            order_type: 'immediate',
            paper_number: '0001',
            user: user
          )
        }.to not_change(Order, :count).and not_change(OrderItem, :count).and not_change(StockMovement, :count)
      end
```

In the `from_paper` context, rename `'skips stock validation (allows selling with zero stock)'` to `'sells with zero stock, like every source'` and keep its body.

In the on_account section, append after `"leaves items undelivered when not in delivered_product_ids"`:

```ruby
    it "takes only the lines the customer takes right away" do
      taken = create(:product, current_stock: 0, price_unit: 100)
      left  = create(:product, current_stock: 0, price_unit: 100)
      stock!(taken, 5)
      stock!(left, 5)

      result = described_class.call(
        customer: Customer.mostrador,
        order_type: "on_account",
        paper_number: "OA-003",
        contact_name: "Juan Pérez",
        contact_phone: "11 5555 1234",
        items: [ { product_id: taken.id, quantity: 2, unit_price: 100 },
                 { product_id: left.id, quantity: 2, unit_price: 100 } ],
        delivered_product_ids: [ taken.id ],
        user: user
      )

      expect(result).to be_success
      expect(taken.reload.current_stock).to eq(3)
      expect(left.reload.current_stock).to eq(5)
      expect(result.record.sale_movements.count).to eq(1)
    end
```

- [ ] **Step 2: Run, watch the new ones fail**

Run: `docker compose exec -T web bundle exec rspec spec/services/sales/create_order_spec.rb`
Expected: the floor examples FAIL (stock unchanged, no movements); "never refuses a live sale" FAILS with `Insufficient stock`; "takes only the lines the customer takes right away" FAILS (both at 5). The examples that only create orders keep passing.

- [ ] **Step 3: The service**

In `app/services/sales/create_order.rb`:

Replace the class comment's first lines with:

```ruby
  # Sales::CreateOrder
  #
  # Creates a sale note (Order) in `pending` status. Vendor-facing entry point:
  # no payments, no discount. The goods leave the shelf with the note for an
  # immediate or credit sale; an on_account line leaves only when delivered.
  #
  # unit_price must be > 0. The entered price is written back to
  # product.price_unit inside the transaction.
```

Delete from `validate_params` the tail that starts at `return if @source == "from_paper"` through the end of the `@items.each` stock block.

Replace `create_order_items` with:

```ruby
    def create_order_items
      @items.each do |item|
        product     = Product.find(item.product_id)
        final_price = item.unit_price

        order_item = OrderItem.create!(
          order:            @order,
          product:          product,
          quantity:         item.quantity,
          unit_price:       final_price,
          discount_percent: 0,
          delivered_at:     (@delivered_product_ids.include?(product.id) ? Time.current : nil)
        )

        product.update!(price_unit: final_price)
        take_from_shelf(order_item) if leaves_the_shelf?(order_item)
      end
    end

    # An immediate or credit sale hands the goods over with the note; an
    # on_account line leaves the shelf only when it is delivered.
    def leaves_the_shelf?(order_item)
      @order_type != "on_account" || order_item.delivered_at.present?
    end

    def take_from_shelf(order_item)
      result = Inventory::DeductLineStock.call(order_item: order_item, note: "Nota #{@paper_number}")
      raise ValidationError, result.errors.join(", ") if result.failure?
    end
```

- [ ] **Step 4: Green, full suite, rubocop, commit**

Run the file → all PASS. Full suite and rubocop → green (the request/system specs that create orders through the UI still pass: they never assert stock). Commit.

---

### Task 4: `Inventory::MarkDelivered` moves the stock, line by line

**Files:**
- Modify: `app/services/inventory/mark_delivered.rb`
- Test: `spec/services/inventory/mark_delivered_spec.rb`, `spec/requests/web/payments_on_account_spec.rb` (append)

**Interfaces:**
- Consumes: Task 2's services.
- Produces: `Inventory::MarkDelivered.call(order:, order_item_ids:, delivered: true)` — same signature. `delivered: true`: each listed line of the order that is not yet delivered gets `delivered_at` and is deducted; a delivered one is left alone. `delivered: false`: each delivered line is restored and cleared; an undelivered one is left alone. One transaction; a failed movement returns a failed `Result` and changes nothing.

- [ ] **Step 1: Rewrite the spec**

Replace `spec/services/inventory/mark_delivered_spec.rb` with:

```ruby
require "rails_helper"

RSpec.describe Inventory::MarkDelivered do
  let!(:location) { create(:stock_location) }
  let(:order) { create(:order, :on_account, paper_number: "OA-7", total_amount: 1000, original_total_amount: 1000) }
  let(:product_a) { create(:product, current_stock: 0) }
  let(:product_b) { create(:product, current_stock: 0) }
  let(:item_a) { create(:order_item, order: order, product: product_a, quantity: 2, unit_price: 500) }
  let(:item_b) { create(:order_item, order: order, product: product_b, quantity: 1, unit_price: 500) }

  def stock!(product, quantity)
    create(:stock_movement, product: product, stock_location: location, quantity: quantity, movement_type: "purchase")
    product.recalculate_current_stock!
  end

  before do
    stock!(product_a, 5)
    stock!(product_b, 5)
  end

  it "marks the given items as delivered and takes them off the shelf" do
    result = described_class.call(order: order, order_item_ids: [ item_a.id ], delivered: true)

    expect(result).to be_success
    expect(item_a.reload.delivered_at).to be_present
    expect(item_b.reload.delivered_at).to be_nil
    expect(product_a.reload.current_stock).to eq(3)
    expect(product_b.reload.current_stock).to eq(5)
    expect(item_a.stock_movements.pluck(:quantity, :movement_type, :note)).to eq([ [ -2, "sale", "Entrega nota OA-7" ] ])
  end

  it "takes only what is on the shelf" do
    product_a.stock_movements.destroy_all
    stock!(product_a, 1)

    described_class.call(order: order, order_item_ids: [ item_a.id ], delivered: true)

    expect(item_a.reload.delivered_at).to be_present
    expect(product_a.reload.current_stock).to eq(0)
  end

  it "does nothing twice for a line already delivered" do
    described_class.call(order: order, order_item_ids: [ item_a.id ], delivered: true)

    expect {
      described_class.call(order: order, order_item_ids: [ item_a.id ], delivered: true)
    }.not_to change(StockMovement, :count)
    expect(product_a.reload.current_stock).to eq(3)
  end

  it "reverts delivery when delivered: false and puts the goods back" do
    described_class.call(order: order, order_item_ids: [ item_a.id ], delivered: true)

    result = described_class.call(order: order, order_item_ids: [ item_a.id ], delivered: false)

    expect(result).to be_success
    expect(item_a.reload.delivered_at).to be_nil
    expect(product_a.reload.current_stock).to eq(5)
    expect(item_a.stock_movements.sum(:quantity)).to eq(0)
  end

  it "leaves an undelivered line alone on delivered: false" do
    expect {
      described_class.call(order: order, order_item_ids: [ item_a.id ], delivered: false)
    }.not_to change(StockMovement, :count)
    expect(item_a.reload.delivered_at).to be_nil
  end

  it "ignores ids that do not belong to the order" do
    other = create(:order_item, order: create(:order, :on_account, total_amount: 1, original_total_amount: 1),
                   product: create(:product), quantity: 1, unit_price: 1)
    result = described_class.call(order: order, order_item_ids: [ other.id ], delivered: true)

    expect(result).to be_success
    expect(other.reload.delivered_at).to be_nil
  end

  it "marks nothing when a movement fails" do
    allow(Inventory::DeductLineStock).to receive(:call)
      .and_return(Result.new(success?: false, record: nil, errors: [ "Error adjusting stock" ]))

    result = described_class.call(order: order, order_item_ids: [ item_a.id, item_b.id ], delivered: true)

    expect(result).to be_failure
    expect(result.errors).to include("Error adjusting stock")
    expect(item_a.reload.delivered_at).to be_nil
    expect(item_b.reload.delivered_at).to be_nil
  end

  it "rejects a non on_account order" do
    immediate = create(:order, order_type: "immediate", total_amount: 100, original_total_amount: 100)
    item = create(:order_item, order: immediate, product: create(:product), quantity: 1, unit_price: 100)
    result = described_class.call(order: immediate, order_item_ids: [ item.id ], delivered: true)
    expect(result).to be_failure
  end
end
```

Append to `spec/requests/web/payments_on_account_spec.rb`, inside the top-level `describe`:

```ruby
  describe "POST deliver" do
    let!(:location) { create(:stock_location) }

    it "takes the delivered lines off the shelf" do
      create(:stock_movement, product: product, stock_location: location, quantity: 4, movement_type: "purchase")
      product.recalculate_current_stock!
      line = open_order.order_items.first

      sign_in vendedor
      post deliver_web_payments_on_account_path(open_order), params: { order_item_ids: [ line.id ] }

      expect(response).to redirect_to(web_payments_on_account_path(open_order))
      expect(line.reload.delivered_at).to be_present
      expect(product.reload.current_stock).to eq(3)
    end
  end
```

- [ ] **Step 2: Run, watch them fail**

Run: `docker compose exec -T web bundle exec rspec spec/services/inventory/mark_delivered_spec.rb spec/requests/web/payments_on_account_spec.rb`
Expected: every stock assertion FAILS (stock stays 5, no movements); "marks nothing when a movement fails" FAILS (delivered_at is set); the pure-flag examples pass.

- [ ] **Step 3: The service**

Replace `app/services/inventory/mark_delivered.rb` with:

```ruby
# frozen_string_literal: true

module Inventory
  # Marks (or unmarks) the delivery of order_items on an on_account order. A
  # line leaves the shelf when it is delivered and comes back if the delivery
  # is undone; a line already in the asked state is left alone.
  class MarkDelivered
    def self.call(order:, order_item_ids:, delivered: true)
      new(order: order, order_item_ids: order_item_ids, delivered: delivered).call
    end

    def initialize(order:, order_item_ids:, delivered:)
      @order          = order
      @order_item_ids = Array(order_item_ids).map(&:to_i)
      @delivered      = delivered
    end

    def call
      unless @order.on_account_order_type?
        return Result.new(success?: false, record: nil, errors: [ "La operación no es un pago a cuenta" ])
      end

      ActiveRecord::Base.transaction do
        lines.each { |line| @delivered ? deliver(line) : undo(line) }
      end

      Result.new(success?: true, record: @order, errors: [])
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue StandardError => e
      Rails.logger.error("Error in Inventory::MarkDelivered: #{e.message}")
      Result.new(success?: false, record: nil, errors: [ "Error registrando la entrega" ])
    end

    private

    class ValidationError < StandardError; end

    def lines
      @order.order_items.where(id: @order_item_ids)
    end

    def deliver(line)
      return if line.delivered_at.present?

      line.update!(delivered_at: Time.current)
      unwrap!(Inventory::DeductLineStock.call(order_item: line, note: "Entrega nota #{@order.paper_number}"))
    end

    def undo(line)
      return if line.delivered_at.nil?

      unwrap!(Inventory::RestoreLineStock.call(order_item: line, note: "Entrega deshecha nota #{@order.paper_number}"))
      line.update!(delivered_at: nil)
    end

    def unwrap!(result)
      raise ValidationError, result.errors.join(", ") if result.failure?
    end
  end
end
```

- [ ] **Step 4: Green, full suite, rubocop, commit**

Run the two files → all PASS. Full suite and rubocop → green. Commit.

---

### Task 5: `Sales::CancelOrder` gives back what left, with the cash

**Files:**
- Modify: `app/services/sales/cancel_order.rb`
- Test: `spec/services/sales/cancel_order_spec.rb`

**Interfaces:**
- Consumes: `Inventory::RestoreLineStock` (Task 2); `Sales::CreateOrder` deducting (Task 3); `Inventory::MarkDelivered` (Task 4).
- Produces: `Sales::CancelOrder.call(order:, user:, reason: nil)` — same signature — restores every line's net inside the transaction that also reverses cash and destroys allocations; any failure leaves all four untouched. The `reason` (or "Cancelación nota <paper_number>") is the restore's note.

- [ ] **Step 1: Rewrite the dormant examples**

In `spec/services/sales/cancel_order_spec.rb`:

Replace `let(:product) { create(:product, current_stock: 50, price_unit: 100) }` with `let(:product) { create(:product, current_stock: 0, price_unit: 100) }`, and replace the `before do stock_location end` block with:

```ruby
  def stock!(product, quantity)
    create(:stock_movement, product: product, stock_location: stock_location, quantity: quantity, movement_type: "purchase")
    product.recalculate_current_stock!
  end

  before do
    stock_location
    stock!(product, 50)
  end
```

In `context 'with valid confirmed order'`, replace the four skipped examples (`'restores product stock'`, `'creates positive stock movements'`, `'accepts reason parameter'`, `'uses default reason when not provided'`) with:

```ruby
      it 'puts back on the shelf what the sale took' do
        order
        expect(product.reload.current_stock).to eq(45)

        expect {
          described_class.call(order: order, user: user)
        }.to change { product.reload.current_stock }.from(45).to(50)
      end

      it 'writes one positive adjustment per line, referencing the line' do
        described_class.call(order: order, user: user)

        restore = StockMovement.where(movement_type: 'adjustment').last
        expect(restore.product).to eq(product)
        expect(restore.quantity).to eq(5)
        expect(restore.reference).to eq(order.order_items.first)
        expect(order.order_items.first.stock_movements.sum(:quantity)).to eq(0)
      end

      it 'accepts reason parameter' do
        result = described_class.call(order: order, user: user, reason: 'Customer requested cancellation')

        expect(result.success?).to be true
        expect(StockMovement.where(movement_type: 'adjustment').last.note).to eq('Customer requested cancellation')
      end

      it 'names the note when no reason is given' do
        described_class.call(order: order, user: user)

        expect(StockMovement.where(movement_type: 'adjustment').last.note).to eq("Cancelación nota L-2001")
      end

      it 'gives back only what the floor let the sale take' do
        product.stock_movements.destroy_all
        stock!(product, 2)
        order
        expect(product.reload.current_stock).to eq(0)

        described_class.call(order: order, user: user)

        expect(product.reload.current_stock).to eq(2)
      end
```

In `context 'with multiple items'`, replace the two skipped examples with:

```ruby
      it 'restores stock for all products' do
        multi_item_order

        expect {
          described_class.call(order: multi_item_order, user: user)
        }.to change { product.reload.current_stock }.by(3)
          .and change { product2.reload.current_stock }.by(2)
      end

      it 'writes one adjustment per line' do
        multi_item_order

        expect {
          described_class.call(order: multi_item_order, user: user)
        }.to change { StockMovement.where(movement_type: 'adjustment').count }.by(2)
      end
```

In that same context, change `product2`'s `let` to `create(:product, current_stock: 0, price_unit: 50)` and add `before { stock!(product2, 30) }` as the context's first line, so its 30 units are backed by a movement like `product`'s 50.

In `context 'cash reversal'`, extend `'rolls the whole cancellation back when the reversal fails'` with two assertions before its final `expect`:

```ruby
        expect(product.reload.current_stock).to eq(45)
        expect(order.sale_movements.sum(:quantity)).to eq(-5)
```

(the credit order there sells 5 units: `amount / 100`).

Add a new context before `context 'with already cancelled order'`:

```ruby
    context 'on_account with a partial delivery' do
      let(:kept)  { create(:product, current_stock: 0, price_unit: 100) }
      let(:taken) { create(:product, current_stock: 0, price_unit: 100) }

      it 'gives back only the lines that were delivered' do
        stock!(kept, 5)
        stock!(taken, 5)
        order = Sales::CreateOrder.call(
          customer: Customer.mostrador, order_type: 'on_account', paper_number: 'OA-9',
          contact_name: 'Juan', contact_phone: '11 5555 1234', user: user,
          items: [ { product_id: taken.id, quantity: 2, unit_price: 100 },
                   { product_id: kept.id, quantity: 2, unit_price: 100 } ],
          delivered_product_ids: [ taken.id ]
        ).record
        expect(taken.reload.current_stock).to eq(3)

        expect(described_class.call(order: order, user: user).success?).to be true

        expect(taken.reload.current_stock).to eq(5)
        expect(kept.reload.current_stock).to eq(5)
        expect(StockMovement.where(movement_type: 'adjustment').count).to eq(1)
      end
    end
```

In `context 'transaction rollback'`, turn `xit 'rolls back order status change if stock adjustment fails'` into `it`, and stub `Inventory::RestoreLineStock` instead of `Inventory::AdjustStock`:

```ruby
      it 'rolls back order status change if the stock restore fails' do
        initial_status = order.status

        allow(Inventory::RestoreLineStock).to receive(:call).and_return(
          Result.new(success?: false, record: nil, errors: [ 'Stock adjustment failed' ])
        )

        result = described_class.call(order: order, user: user)

        expect(result.success?).to be false
        expect(order.reload.status).to eq(initial_status)
      end
```

- [ ] **Step 2: Run, watch them fail**

Run: `docker compose exec -T web bundle exec rspec spec/services/sales/cancel_order_spec.rb`
Expected: every restore assertion FAILS (stock stays at 45, no adjustment rows); the partial-delivery example FAILS; the rollback example FAILS on `success?`; the cash examples still pass.

- [ ] **Step 3: The service**

In `app/services/sales/cancel_order.rb`:

Replace the transaction body with:

```ruby
      ActiveRecord::Base.transaction do
        cancel_order
        restore_stock
        reverse_cash_movements
        destroy_associated_allocations

        Result.new(success?: true, record: @order, errors: [])
      end
```

Replace `reverse_stock_movements` (the whole method) with:

```ruby
    # Back on the shelf goes what each line's own movements say is out: an
    # undelivered on_account line took nothing and gives nothing back.
    def restore_stock
      @order.order_items.each do |line|
        result = Inventory::RestoreLineStock.call(order_item: line, note: @reason || "Cancelación nota #{@order.paper_number}")

        raise ValidationError, result.errors.join(", ") if result.failure?
      end
    end
```

- [ ] **Step 4: Green, full suite, rubocop, commit**

Run the file → all PASS; then `spec/services/sales/replace_order_item_spec.rb` (its no-movement example must still pass — the line is undelivered). Full suite and rubocop → green. Commit.

---

### Task 6: Documentation

**Files:**
- Modify: `WORKING_CONTEXT.md`, `docs/DEVELOPMENT_GUIDE.md`, `docs/TESTING_GUIDE.md`, `app/services/inventory/mark_delivered.rb` (nothing — its comment was rewritten in Task 4), `docs/TESTING_PENDIENTE.md` (only if it lists the stock examples as pending — check)

- [ ] **Step 1: `WORKING_CONTEXT.md`**

Under `### Orders`, find the bullet containing "**It captures neither payments nor discount**" and append a new bullet after it:

```markdown
* **The goods leave the shelf with the note.** `Sales::CreateOrder` writes one `sale` `StockMovement` per line (referencing the `OrderItem`) for `immediate` and `credit` orders, and for the `on_account` lines in `delivered_product_ids`, through `Inventory::DeductLineStock` — **floored at zero**: a line takes `min(quantity, current_stock)`, writes nothing when that is 0, and **a sale is never refused for stock** (the old `source: "live"` block is gone; `source` is stored and gates nothing).
```

Under `### Payments on account (`on_account`)`, replace the bullet that starts with `* **Per-item delivery**:` with:

```markdown
* **Per-item delivery is the stock event.** `order_items.delivered_at` is set by the **vendedor**: at creation (`delivered_product_ids`) or later from the detail view via `Inventory::MarkDelivered` (member `POST deliver`). Marking a line delivered takes it off the shelf (`Inventory::DeductLineStock`, floored at zero); `delivered: false` (service only, no screen) puts back the line's net (`Inventory::RestoreLineStock`). The service is per line, idempotent and transactional. **`Sales::ReplaceOrderItem` moves no stock**: it only touches undelivered lines, which have taken nothing.
```

Under `### Stock`, replace the bullet added by part 1 (`* **Invoices with lines write purchase movements …**`) with:

```markdown
* **Invoices with lines write `purchase` movements at registration and floored `adjustment` reversals on cancel** (`Invoices::CreateInvoice` / `CancelInvoice`). **Sales write `sale` movements that reference the `OrderItem`** — at creation for immediate/credit, at delivery for on_account — and `Sales::CancelOrder` puts back each line's **net** (`-order_item.stock_movements.sum(:quantity)`) as an `adjustment`, in the same transaction as the cash reversal. `Order#sale_movements` gathers a sale's rows through its lines; `Order has_many :stock_movements, as: :reference` is no longer written.
```

Under `## Key constraints`, after the part-1 bullet on the invoice `amount`, add:

```markdown
* **Stock never gates a sale, a delivery or a cancellation.** The floor is defined once (`Inventory::DeductLineStock`); the restore is the line's net, defined once (`Inventory::RestoreLineStock`). Nothing else computes either.
```

Also delete the `* **Validate stock before selling (`live` source only)** …` bullet and the sentence in the `**\`Order\` validation:**` bullet that says the UI flow "does **not** validate stock at sale time … The `live` branch and its stock validation remain in the service for future use" — replace that sentence with "Stock is deducted on every source, floored at zero; `source` is stored and gates nothing (its removal is a separate cleanup)."

Under `## Active services`, change the Inventory line to:

```markdown
* **Inventory:** `Inventory::AdjustStock`, `Inventory::MarkDelivered`, `Inventory::DeductLineStock`, `Inventory::RestoreLineStock`
```

Under `## Important gaps`, add:

```markdown
* **`source` / `from_paper` are dead** (every sale is on paper and stock never gates a sale) but the column, the scopes and the hidden field remain until the cleanup work-item drops them with a migration.
```

- [ ] **Step 2: `docs/DEVELOPMENT_GUIDE.md`**

Under `### Sales`, the two sub-bullets under "Cancelling a sale must:" stay (`revert stock` is now true). Under `### Stock`, after `* Stock = sum of movements`, add:

```markdown
* A sale takes `min(quantity, current_stock)` — never below zero, and never refused for stock; what comes back on cancel is what actually left
```

- [ ] **Step 3: `docs/TESTING_GUIDE.md`**

In the "Out of scope on purpose" line, replace `Inventory::AdjustStock / Inventory::MarkDelivered — quantity/delivery, not money` with `Inventory::AdjustStock / MarkDelivered / DeductLineStock / RestoreLineStock — quantity/delivery, not money`.

- [ ] **Step 4: Verify and finish**

Run: `grep -rn "temporarily disabled\|TRACK_STOCK" app spec docs WORKING_CONTEXT.md`
Expected: no hit in `app/` or `spec/` (the `mark_delivered.rb` comment and the skips are gone); any remaining hit in `docs/superpowers/**` is history.
Run: `docker compose exec -T web bundle exec rspec` and `docker compose exec -T web bundle exec rubocop`
Expected: green; the pending count drops by the five stock examples this plan enabled. Commit. The owner will squash both parts with a message like:

```
feat(feat_34): reactivate stock on invoices and sales

- Supplier invoices can carry product lines; with lines the amount is the
  server's sum and one purchase movement per line is written in the same
  transaction; cancelling an invoice takes back what it added, floored.
- Sales take stock off the shelf, floored at zero and never refused for
  stock: at creation for immediate and credit sales, line by line at
  delivery for pagos a cuenta; changing an undelivered line moves nothing.
- Cancelling a sale puts back each line's net, in one transaction with the
  cash reversal. Movements of a sale reference the order line.
- Average cost stays deferred; source/from_paper cleanup is a separate item.
```

---

## Verification by hand (owner, after Task 6)

1. Product with stock 3: sell 2 on a nota inmediata → the product page shows 1 and a "Venta · Nota N" movement; sell 5 more → 0, movement −1; sell again → 0, no movement.
2. Pago a cuenta with two lines, none taken: stock unchanged; mark one delivered → that product drops; cancel → it comes back, the other never moved.
3. Change an undelivered line's product: no stock movement anywhere.
4. Cancel a collected credit sale: stock comes back and the cash reversal appears in Caja, both at once.
