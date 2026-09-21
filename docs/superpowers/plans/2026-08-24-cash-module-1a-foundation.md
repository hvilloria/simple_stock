# Cash Module 1a — Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the persistence layer of the cash module — two tables, two models, the validation rules, the immutability guard, the single write service and the opening-balance loader — with no UI.

**Architecture:** Every money movement is a row of `cash_movements`; a balance is `SUM(amount)` over that table filtered by `account`, never a stored column. `daily_closings` exists first because `cash_movements.daily_closing_id` points at it and its presence is what makes a row immutable. Writes go through `Cash::RecordMovement`, which returns a `Result` like every other service in this project. Opening balances are ordinary movements with category `opening_balance`, loaded by a rake task.

**Tech Stack:** Rails 7.2.3, PostgreSQL, RSpec + FactoryBot, `shoulda-matchers`.

**Spec:** `docs/CASH_MODULE_DESIGN.md` — read §3 (concepts), §5 (rules R-1 to R-17), §6 (data model) and §7.4 (startup) before starting. This plan implements slice 1a of the four in §13.

**Environment:** this project has no host Ruby — everything runs in Docker, as
documented in `README.md`. Bring the stack up once before Task 1 and leave it
running:

```bash
docker compose up -d
docker compose exec web bin/rails db:prepare
```

Every command in this plan is already written in its `docker compose exec web …`
form. If a command fails with a connection error, the stack is down.

**Branch:** create `feat-27_cash-module-foundation` before the first commit. The commit scope is taken from the branch name and stays constant: `feat(feat_27): …`. The `commit-msg` hook enforces this.

## Global Constraints

Copied verbatim from `docs/CASH_MODULE_DESIGN.md` §12. Every task's requirements implicitly include this section.

- **Reuse before building.** Look for the existing pattern before writing a new one. Relevant here: the `Result` struct in `app/services/result.rb`, the string-backed `enum` + `LABELS` constant pattern in `app/models/payment.rb` and `app/models/order.rb`.
- **Services return `Result`; controllers stay thin.** Direct ActiveRecord is acceptable only in trivial single-model actions.
- **Comments in code are in English, and minimal** — only where genuinely needed. Code and specs never cite `AGENTS.md` or project doctrine; a file explains itself.
- **UI text in Spanish** (labels, flashes, buttons). Code, comments and commit messages stay in English. This slice has no UI, but the `*_LABELS` constants hold the Spanish strings.
- **Dates and times use `Date.current` / `Time.current`**, never `Date.today` / `Time.now`.
- **Commits:** English, `type(scope): title`, scope constant from the branch name, body in bullets, one logical change per commit, no attribution lines. **The agent never runs `git commit`** — it stages and hands the message over.
- **Amount columns are `decimal(10,2)`**, matching every other money column in the schema.
- **Enums are `string` columns in the database and `enum` in the model**, string-backed, following `users.role` and `orders.status`.

---

## File Structure

| File | Responsibility |
|---|---|
| `config/application.rb` | Sets the app timezone. The day boundary is the cash module's model. |
| `db/migrate/*_create_daily_closings.rb` | The closing table. One row per day, unique on `business_date`. |
| `db/migrate/*_create_cash_movements.rb` | The movement table. |
| `app/models/daily_closing.rb` | Associations, validations, and the label constants for the closing. |
| `app/models/cash_movement.rb` | Enums, label constants, the channel→account map, conditional validations, the immutability guard, and the balance scopes. |
| `app/services/cash/record_movement.rb` | The single write path for one movement. Returns `Result`. |
| `lib/tasks/cash.rake` | `cash:opening_balances` — the one-time startup load. |
| `spec/factories/cash_movements.rb` | Factory with a trait per category. |
| `spec/factories/daily_closings.rb` | Factory. |
| `spec/models/cash_movement_spec.rb` | Enums, validations, guard, scopes. |
| `spec/models/daily_closing_spec.rb` | Associations and validations. |
| `spec/services/cash/record_movement_spec.rb` | Service behaviour, including hostile input. |

---

## Task 1: Set the application timezone

The app runs in UTC with no zone configured, which already caused off-by-one bugs elsewhere (`WORKING_CONTEXT.md` → Key constraints). In this module the day boundary *is* the model: a movement loaded at 21:30 local time would otherwise land on the next business day. This task changes it and proves the existing suite still passes.

**Files:**
- Modify: `config/application.rb:24`
- Test: the whole existing suite

**Interfaces:**
- Consumes: nothing.
- Produces: `Time.zone` is `America/Argentina/Buenos_Aires` for every later task. `Date.current` now means the local business day.

- [ ] **Step 1: Record the current suite state**

Run: `docker compose exec web bundle exec rspec`
Expected: PASS. Write down the example and failure counts — the point of this task is that they do not change.

- [ ] **Step 2: Write the failing test**

Create `spec/models/application_timezone_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Application timezone" do
  it "runs in Buenos Aires time" do
    expect(Time.zone.name).to eq("America/Argentina/Buenos_Aires")
  end

  it "resolves Date.current to the local business day near midnight UTC" do
    # 2026-08-04 01:30 UTC is still 2026-08-03 22:30 in Buenos Aires.
    travel_to(Time.utc(2026, 8, 4, 1, 30)) do
      expect(Date.current).to eq(Date.new(2026, 8, 3))
    end
  end
end
```

- [ ] **Step 3: Enable the time helpers**

`travel_to` is not available yet — `spec/rails_helper.rb` does not include it. Add this line inside the existing `RSpec.configure do |config|` block:

```ruby
  config.include ActiveSupport::Testing::TimeHelpers
```

- [ ] **Step 4: Run it to verify it fails**

Run: `docker compose exec web bundle exec rspec spec/models/application_timezone_spec.rb -v`
Expected: FAIL — `Time.zone.name` is `"UTC"`.

- [ ] **Step 5: Set the timezone**

In `config/application.rb`, replace the commented line 24 with:

```ruby
    config.time_zone = "America/Argentina/Buenos_Aires"
```

Leave `config.active_record.default_timezone` alone — timestamps keep being stored in UTC, which is what we want.

- [ ] **Step 6: Run the new test**

Run: `docker compose exec web bundle exec rspec spec/models/application_timezone_spec.rb -v`
Expected: PASS (2 examples).

- [ ] **Step 7: Run the whole suite**

Run: `docker compose exec web bundle exec rspec`
Expected: the same example and failure counts as Step 1, plus 2 new examples.

If something broke, it is almost certainly a spec that hardcoded a UTC date. Fix the spec, not the config — the config is correct.

- [ ] **Step 8: Lint and stage**

```bash
docker compose exec web bundle exec rubocop config/application.rb spec/models/application_timezone_spec.rb
git add config/application.rb spec/models/application_timezone_spec.rb spec/rails_helper.rb
```

Hand the user this message (do not run `git commit`):

```
chore(feat_27): set the application timezone to Buenos Aires

- The app ran in UTC with no zone configured, which pushed anything
  recorded after 21:00 local time onto the next calendar day.
- The cash module's day boundary is part of its model, so this has to be
  correct before any of it lands.
- Timestamps are still stored in UTC; only the application zone changes.
```

---

## Task 2: `daily_closings` table and model

Created before `cash_movements` because that table's `daily_closing_id` points here, and because the presence of that reference is what makes a movement immutable.

**Files:**
- Create: `db/migrate/<timestamp>_create_daily_closings.rb`
- Create: `app/models/daily_closing.rb`
- Create: `spec/factories/daily_closings.rb`
- Test: `spec/models/daily_closing_spec.rb`

**Interfaces:**
- Consumes: `User` (existing).
- Produces: `DailyClosing` with `business_date` (date, unique), `expected_cash`, `counted_cash` (decimal, required), `payway_batch_total`, `mercado_pago_total` (decimal, **nullable**), `user`, `closed_at`. Instance method `#difference` returning `counted_cash - expected_cash`. Task 3 references `daily_closings` by foreign key; Task 5 reads `daily_closing_id`.

- [ ] **Step 1: Write the failing test**

Create `spec/models/daily_closing_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe DailyClosing, type: :model do
  describe "associations" do
    it { should belong_to(:user) }
  end

  describe "validations" do
    subject { build(:daily_closing) }

    it { should validate_presence_of(:business_date) }
    it { should validate_presence_of(:expected_cash) }
    it { should validate_presence_of(:counted_cash) }
    it { should validate_uniqueness_of(:business_date) }
  end

  describe "verification columns" do
    it "allows both to be nil, meaning not verified" do
      closing = build(:daily_closing, payway_batch_total: nil, mercado_pago_total: nil)
      expect(closing).to be_valid
    end

    it "keeps nil distinct from zero" do
      closing = create(:daily_closing, payway_batch_total: nil, mercado_pago_total: 0)
      expect(closing.reload.payway_batch_total).to be_nil
      expect(closing.reload.mercado_pago_total).to eq(0)
    end
  end

  describe "#difference" do
    it "is zero when the count matches" do
      closing = build(:daily_closing, expected_cash: 311_700, counted_cash: 311_700)
      expect(closing.difference).to eq(0)
    end

    it "is negative on a shortfall" do
      closing = build(:daily_closing, expected_cash: 311_700, counted_cash: 291_700)
      expect(closing.difference).to eq(-20_000)
    end

    it "is positive on a surplus" do
      closing = build(:daily_closing, expected_cash: 311_700, counted_cash: 320_000)
      expect(closing.difference).to eq(8_300)
    end
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `docker compose exec web bundle exec rspec spec/models/daily_closing_spec.rb -v`
Expected: FAIL — `uninitialized constant DailyClosing`.

- [ ] **Step 3: Generate and write the migration**

Run: `docker compose exec web bin/rails generate migration CreateDailyClosings`

Replace the generated file's contents with:

```ruby
class CreateDailyClosings < ActiveRecord::Migration[7.2]
  def change
    create_table :daily_closings do |t|
      t.date :business_date, null: false
      t.decimal :expected_cash, precision: 10, scale: 2, null: false
      t.decimal :counted_cash, precision: 10, scale: 2, null: false
      t.decimal :payway_batch_total, precision: 10, scale: 2
      t.decimal :mercado_pago_total, precision: 10, scale: 2
      t.references :user, null: false, foreign_key: true
      t.datetime :closed_at, null: false

      t.timestamps
    end

    add_index :daily_closings, :business_date, unique: true
  end
end
```

`payway_batch_total` and `mercado_pago_total` are deliberately nullable: null means *not verified*, which is not the same as zero (spec §6.3).

- [ ] **Step 4: Run the migration**

Run: `docker compose exec web bin/rails db:migrate`
Expected: `db/schema.rb` gains the `daily_closings` table.

- [ ] **Step 5: Write the model**

Create `app/models/daily_closing.rb`:

```ruby
# frozen_string_literal: true

class DailyClosing < ApplicationRecord
  belongs_to :user
  has_many :cash_movements, dependent: :restrict_with_exception

  validates :business_date, presence: true, uniqueness: true
  validates :expected_cash, presence: true, numericality: true
  validates :counted_cash, presence: true, numericality: true
  validates :closed_at, presence: true

  scope :recent, -> { order(business_date: :desc) }

  def difference
    counted_cash - expected_cash
  end

  def payway_verified?
    payway_batch_total.present?
  end

  def mercado_pago_verified?
    mercado_pago_total.present?
  end
end
```

`has_many :cash_movements` is declared now and resolves once Task 3 creates the table; the spec for this task does not exercise it.

- [ ] **Step 6: Write the factory**

Create `spec/factories/daily_closings.rb`:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :daily_closing do
    association :user, factory: [ :user, :caja ]
    sequence(:business_date) { |n| Date.new(2026, 8, 1) + n.days }
    expected_cash { 311_700 }
    counted_cash { 311_700 }
    payway_batch_total { nil }
    mercado_pago_total { nil }
    closed_at { Time.current }

    trait :with_shortfall do
      counted_cash { 291_700 }
    end

    trait :fully_verified do
      payway_batch_total { 109_020 }
      mercado_pago_total { 77_200 }
    end
  end
end
```

- [ ] **Step 7: Run the test**

Run: `docker compose exec web bundle exec rspec spec/models/daily_closing_spec.rb -v`
Expected: PASS.

- [ ] **Step 8: Lint and stage**

```bash
docker compose exec web bundle exec rubocop app/models/daily_closing.rb spec/models/daily_closing_spec.rb spec/factories/daily_closings.rb
git add app/models/daily_closing.rb spec/models/daily_closing_spec.rb spec/factories/daily_closings.rb db/migrate db/schema.rb
```

Hand the user this message:

```
feat(feat_27): add the daily_closing model

- One row per business day, enforced by a unique index on business_date.
- Stores only what cannot be derived: expected and counted cash, plus the
  two digital verification totals.
- Those two are nullable on purpose: null means "not verified", which is
  not the same as a verified zero.
- #difference derives the discrepancy instead of storing it.
```

---

## Task 3: `cash_movements` table and model skeleton

The table, the enums, the associations and the unconditional validations. The conditional rules come in Task 4 and the immutability guard in Task 5, so a reviewer can reject either without rejecting the table.

**Files:**
- Create: `db/migrate/<timestamp>_create_cash_movements.rb`
- Create: `app/models/cash_movement.rb`
- Create: `spec/factories/cash_movements.rb`
- Test: `spec/models/cash_movement_spec.rb`

**Interfaces:**
- Consumes: `DailyClosing` (Task 2), `Payment` and `User` (existing).
- Produces: `CashMovement` with the constants `ACCOUNT_LABELS`, `CATEGORY_LABELS`, `SUBCATEGORY_LABELS`, `CHANNEL_LABELS` and `CHANNEL_ACCOUNTS`; enums on `account`, `category`, `subcategory` and `channel`, all with `suffix: true`; `belongs_to :daily_closing` (optional), `:source_payment` (optional, class `Payment`), `:user`. Class method `CashMovement.account_for_channel(channel)`. Tasks 4 to 8 all build on this.

- [ ] **Step 1: Write the failing test**

Create `spec/models/cash_movement_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CashMovement, type: :model do
  describe "associations" do
    it { should belong_to(:user) }
    it { should belong_to(:daily_closing).optional }
    it { should belong_to(:source_payment).class_name("Payment").optional }
  end

  describe "validations" do
    it { should validate_presence_of(:business_date) }
    it { should validate_presence_of(:category) }

    it "rejects a zero amount" do
      movement = build(:cash_movement, amount: 0)
      expect(movement).not_to be_valid
      expect(movement.errors[:amount]).to be_present
    end

    it "accepts a negative amount" do
      expect(build(:cash_movement, amount: -13_000)).to be_valid
    end
  end

  describe "enums" do
    it "exposes the six arcas" do
      expect(described_class.accounts.keys).to contain_exactly(
        "drawer", "main_cash", "change_fund", "bank", "mercado_pago", "usd"
      )
    end

    it "exposes the seven categories" do
      expect(described_class.categories.keys).to contain_exactly(
        "sale", "suppliers", "fixed_expense", "internal_transfer",
        "partner", "cash_discrepancy", "opening_balance"
      )
    end

    it "suffixes the predicates so account and channel do not collide" do
      movement = build(:cash_movement, account: "mercado_pago", channel: "cash")
      expect(movement.mercado_pago_account?).to be(true)
      expect(movement.cash_channel?).to be(true)
    end
  end

  describe ".account_for_channel" do
    it "routes each channel to its arca" do
      expect(described_class.account_for_channel("cash")).to eq("drawer")
      expect(described_class.account_for_channel("card")).to eq("bank")
      expect(described_class.account_for_channel("qr")).to eq("bank")
      expect(described_class.account_for_channel("transfer")).to eq("bank")
      expect(described_class.account_for_channel("mercado_pago")).to eq("mercado_pago")
      expect(described_class.account_for_channel("usd")).to eq("usd")
    end

    it "routes compensation to no arca at all" do
      expect(described_class.account_for_channel("compensation")).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `docker compose exec web bundle exec rspec spec/models/cash_movement_spec.rb -v`
Expected: FAIL — `uninitialized constant CashMovement`.

- [ ] **Step 3: Generate and write the migration**

Run: `docker compose exec web bin/rails generate migration CreateCashMovements`

Replace the generated file's contents with:

```ruby
class CreateCashMovements < ActiveRecord::Migration[7.2]
  def change
    create_table :cash_movements do |t|
      t.date :business_date, null: false
      t.string :account
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :category, null: false
      t.string :subcategory
      t.string :channel
      t.string :description
      t.uuid :transfer_group_id
      t.references :daily_closing, foreign_key: true
      t.references :source_payment, foreign_key: { to_table: :payments }
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end

    add_index :cash_movements, :business_date
    add_index :cash_movements, :account
    add_index :cash_movements, :category
    add_index :cash_movements, :transfer_group_id
  end
end
```

`account` is nullable because a `compensation` sale touches no arca (spec §3.3). `transfer_group_id` is nullable because only the two legs of a movement between arcas carry one; nothing writes it until slice 2.

- [ ] **Step 4: Run the migration**

Run: `docker compose exec web bin/rails db:migrate`
Expected: `db/schema.rb` gains the `cash_movements` table.

- [ ] **Step 5: Write the model**

Create `app/models/cash_movement.rb`:

```ruby
# frozen_string_literal: true

class CashMovement < ApplicationRecord
  ACCOUNT_LABELS = {
    "drawer"       => "Caja del día",
    "main_cash"    => "Caja grande",
    "change_fund"  => "Remanente",
    "bank"         => "Banco",
    "mercado_pago" => "Mercado Pago",
    "usd"          => "USD"
  }.freeze

  CATEGORY_LABELS = {
    "sale"              => "Venta",
    "suppliers"         => "Proveedores",
    "fixed_expense"     => "Gastos fijos",
    "internal_transfer" => "Movimiento entre arcas",
    "partner"           => "Socio",
    "cash_discrepancy"  => "Diferencia de arqueo",
    "opening_balance"   => "Saldo inicial"
  }.freeze

  SUBCATEGORY_LABELS = {
    "rent"           => "Alquiler",
    "salaries"       => "Salarios",
    "social_charges" => "Cargas sociales",
    "taxes"          => "Impuestos",
    "utilities"      => "Servicios",
    "store_expenses" => "Gastos de local"
  }.freeze

  CHANNEL_LABELS = {
    "cash"         => "Efectivo",
    "card"         => "Tarjeta",
    "qr"           => "QR",
    "transfer"     => "Transferencia",
    "mercado_pago" => "Mercado Pago",
    "usd"          => "USD",
    "compensation" => "Compensación"
  }.freeze

  # A sale's channel determines the arca it lands in. Compensation is the one
  # channel that reaches no arca: it bills, but no money moves.
  CHANNEL_ACCOUNTS = {
    "cash"         => "drawer",
    "card"         => "bank",
    "qr"           => "bank",
    "transfer"     => "bank",
    "mercado_pago" => "mercado_pago",
    "usd"          => "usd",
    "compensation" => nil
  }.freeze

  # Arcas that hold physical or digital pesos. USD is excluded: it never
  # sums with the others.

  belongs_to :daily_closing, optional: true
  belongs_to :source_payment, class_name: "Payment", optional: true
  belongs_to :user

  # Suffixed because `mercado_pago` and `usd` are both an account and a
  # channel; without the suffix the predicates would collide.
  enum :account, ACCOUNT_LABELS.keys.to_h { |k| [ k.to_sym, k ] }, suffix: true
  enum :category, CATEGORY_LABELS.keys.to_h { |k| [ k.to_sym, k ] }, suffix: true
  enum :subcategory, SUBCATEGORY_LABELS.keys.to_h { |k| [ k.to_sym, k ] }, suffix: true
  enum :channel, CHANNEL_LABELS.keys.to_h { |k| [ k.to_sym, k ] }, suffix: true

  validates :business_date, presence: true
  validates :category, presence: true
  validates :amount, presence: true, numericality: { other_than: 0 }

  def self.account_for_channel(channel)
    CHANNEL_ACCOUNTS.fetch(channel.to_s)
  end

  def self.account_label(key) = ACCOUNT_LABELS.fetch(key.to_s, key.to_s)
  def self.category_label(key) = CATEGORY_LABELS.fetch(key.to_s, key.to_s)
  def self.channel_label(key) = CHANNEL_LABELS.fetch(key.to_s, key.to_s)
  def self.subcategory_label(key) = SUBCATEGORY_LABELS.fetch(key.to_s, key.to_s)

  def inflow? = amount.positive?
  def outflow? = amount.negative?
end
```

- [ ] **Step 6: Write the factory**

Create `spec/factories/cash_movements.rb`:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :cash_movement do
    association :user, factory: [ :user, :caja ]
    business_date { Date.new(2026, 8, 3) }
    amount { 299_700 }
    category { "sale" }
    channel { "cash" }
    account { "drawer" }
    description { nil }

    trait :card_sale do
      channel { "card" }
      account { "bank" }
      amount { 54_700 }
    end

    trait :compensation_sale do
      channel { "compensation" }
      account { nil }
      amount { 661_188 }
    end

    trait :store_expense do
      category { "fixed_expense" }
      subcategory { "store_expenses" }
      channel { nil }
      account { "drawer" }
      amount { -13_000 }
      description { "Mundo de la Bolsa — 100 bolsas" }
    end

    trait :supplier_payment do
      category { "suppliers" }
      channel { nil }
      account { "bank" }
      amount { -153_951 }
      description { "Cromosol" }
    end

    trait :opening_balance do
      category { "opening_balance" }
      channel { nil }
      account { "main_cash" }
      amount { 12_497_899.30 }
      description { "Saldo inicial" }
    end

    trait :sealed do
      association :daily_closing
    end
  end
end
```

- [ ] **Step 7: Run the test**

Run: `docker compose exec web bundle exec rspec spec/models/cash_movement_spec.rb -v`
Expected: PASS.

- [ ] **Step 8: Lint and stage**

```bash
docker compose exec web bundle exec rubocop app/models/cash_movement.rb spec/models/cash_movement_spec.rb spec/factories/cash_movements.rb
git add app/models/cash_movement.rb spec/models/cash_movement_spec.rb spec/factories/cash_movements.rb db/migrate db/schema.rb
```

Hand the user this message:

```
feat(feat_27): add the cash_movement model

- One row per change in the amount of money held by an arca. Amounts are
  signed, so a balance is a SUM with no special cases.
- Six arcas, seven categories, seven sale channels, all string-backed
  enums following the users.role and orders.status convention.
- Predicates are suffixed because mercado_pago and usd are both an
  account and a channel.
- account is nullable: a compensation sale bills without touching any
  arca.
```

---

## Task 4: Conditional validations

The four rules from spec §6.2 that depend on the value of another column.

**Files:**
- Modify: `app/models/cash_movement.rb`
- Test: `spec/models/cash_movement_spec.rb`

**Interfaces:**
- Consumes: `CashMovement` (Task 3).
- Produces: a `CashMovement` that rejects an invalid combination of `account`, `category`, `subcategory` and `channel`. Task 7's service relies on these instead of re-checking them.

- [ ] **Step 1: Write the failing test**

Append to `spec/models/cash_movement_spec.rb`, inside the top-level `describe`:

```ruby
  describe "conditional validations" do
    context "account" do
      it "is required on an ordinary movement" do
        movement = build(:cash_movement, account: nil)
        expect(movement).not_to be_valid
        expect(movement.errors[:account]).to be_present
      end

      it "must be absent on a compensation sale" do
        expect(build(:cash_movement, :compensation_sale)).to be_valid
      end

      it "is rejected when a compensation sale names an arca" do
        movement = build(:cash_movement, :compensation_sale, account: "bank")
        expect(movement).not_to be_valid
        expect(movement.errors[:account]).to be_present
      end
    end

    context "channel" do
      it "is required on a sale" do
        movement = build(:cash_movement, category: "sale", channel: nil)
        expect(movement).not_to be_valid
        expect(movement.errors[:channel]).to be_present
      end

      it "must be absent on anything that is not a sale" do
        movement = build(:cash_movement, :supplier_payment, channel: "cash")
        expect(movement).not_to be_valid
        expect(movement.errors[:channel]).to be_present
      end
    end

    context "subcategory" do
      it "is required on a fixed expense" do
        movement = build(:cash_movement, :store_expense, subcategory: nil)
        expect(movement).not_to be_valid
        expect(movement.errors[:subcategory]).to be_present
      end

      it "must be absent on anything that is not a fixed expense" do
        movement = build(:cash_movement, :supplier_payment, subcategory: "rent")
        expect(movement).not_to be_valid
        expect(movement.errors[:subcategory]).to be_present
      end
    end
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `docker compose exec web bundle exec rspec spec/models/cash_movement_spec.rb -e "conditional validations" -v`
Expected: FAIL — the records are all valid because nothing checks the combinations yet.

- [ ] **Step 3: Add the validations**

In `app/models/cash_movement.rb`, below the existing `validates` lines, add:

```ruby
  validate :account_required_unless_compensation
  validate :channel_only_on_sales
  validate :subcategory_only_on_fixed_expenses
```

and in a `private` section at the bottom of the class:

```ruby
  private

  def account_required_unless_compensation
    if compensation_channel?
      errors.add(:account, "must be blank on a compensation sale") if account.present?
    elsif account.blank?
      errors.add(:account, "can't be blank")
    end
  end

  def channel_only_on_sales
    if sale_category?
      errors.add(:channel, "can't be blank") if channel.blank?
    elsif channel.present?
      errors.add(:channel, "is only valid on a sale")
    end
  end

  def subcategory_only_on_fixed_expenses
    if fixed_expense_category?
      errors.add(:subcategory, "can't be blank") if subcategory.blank?
    elsif subcategory.present?
      errors.add(:subcategory, "is only valid on a fixed expense")
    end
  end
```

- [ ] **Step 4: Run the test**

Run: `docker compose exec web bundle exec rspec spec/models/cash_movement_spec.rb -v`
Expected: PASS, including the earlier examples.

- [ ] **Step 5: Lint and stage**

```bash
docker compose exec web bundle exec rubocop app/models/cash_movement.rb spec/models/cash_movement_spec.rb
git add app/models/cash_movement.rb spec/models/cash_movement_spec.rb
```

Hand the user this message:

```
feat(feat_27): validate the cash movement column combinations

- account is required except on a compensation sale, which bills without
  touching any arca.
- channel is required on a sale and rejected everywhere else, so a
  sale can never be recorded without saying how the money arrived.
- subcategory is required on a fixed expense and rejected elsewhere:
  loading always uses the fine subcategory, because summing is free and
  splitting later is not.
```

---

## Task 5: The immutability guard

R-8: movements of a closed day are never edited and never deleted. The guard has one subtlety worth reading before writing it — see Step 3.

**Files:**
- Modify: `app/models/cash_movement.rb`
- Test: `spec/models/cash_movement_spec.rb`

**Interfaces:**
- Consumes: `CashMovement` (Tasks 3-4), `DailyClosing` (Task 2).
- Produces: `CashMovement::SealedMovementError`, `CashMovement#sealed?`. Slice 1d's `Cash::CloseDay` depends on being able to stamp `daily_closing_id` on an unsealed row without tripping the guard.

- [ ] **Step 1: Write the failing test**

Append to `spec/models/cash_movement_spec.rb`, inside the top-level `describe`:

```ruby
  describe "immutability once sealed" do
    let(:closing) { create(:daily_closing) }

    it "is not sealed while daily_closing_id is blank" do
      expect(create(:cash_movement)).not_to be_sealed
    end

    it "allows the closing to stamp an unsealed movement" do
      movement = create(:cash_movement)
      expect { movement.update!(daily_closing: closing) }.not_to raise_error
      expect(movement.reload).to be_sealed
    end

    it "refuses any later update" do
      movement = create(:cash_movement, daily_closing: closing)
      expect { movement.update!(amount: 1) }
        .to raise_error(described_class::SealedMovementError)
    end

    it "refuses destruction" do
      movement = create(:cash_movement, daily_closing: closing)
      expect { movement.destroy }
        .to raise_error(described_class::SealedMovementError)
    end

    it "leaves the row untouched after a refused update" do
      movement = create(:cash_movement, daily_closing: closing, amount: 299_700)
      expect { movement.update!(amount: 1) }.to raise_error(described_class::SealedMovementError)
      expect(movement.reload.amount).to eq(299_700)
    end
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `docker compose exec web bundle exec rspec spec/models/cash_movement_spec.rb -e "immutability" -v`
Expected: FAIL — `SealedMovementError` is not defined.

- [ ] **Step 3: Add the guard**

The subtlety: inside `before_update`, `daily_closing_id` already holds the **new** value. Guarding on it would make the closing's own stamping raise. Guard on `daily_closing_id_was` — the persisted value — so stamping a blank row is allowed and every later change is not.

In `app/models/cash_movement.rb`, add near the top of the class body:

```ruby
  class SealedMovementError < StandardError; end
```

after the `belongs_to` declarations add:

```ruby
  before_update :prevent_sealed_change
  before_destroy :prevent_sealed_change
```

as a public instance method:

```ruby
  def sealed? = daily_closing_id.present?
```

and in the `private` section:

```ruby
  # Guards on the persisted value, not the assigned one, so Cash::CloseDay can
  # stamp daily_closing_id on a row that has none yet.
  def prevent_sealed_change
    return if daily_closing_id_was.blank?

    raise SealedMovementError,
          "cash movement #{id} is sealed by closing #{daily_closing_id_was}"
  end
```

- [ ] **Step 4: Run the test**

Run: `docker compose exec web bundle exec rspec spec/models/cash_movement_spec.rb -v`
Expected: PASS.

- [ ] **Step 5: Run the whole suite**

Run: `docker compose exec web bundle exec rspec`
Expected: PASS. A `before_destroy` that raises can surprise unrelated cleanup code; this confirms it does not.

- [ ] **Step 6: Lint and stage**

```bash
docker compose exec web bundle exec rubocop app/models/cash_movement.rb spec/models/cash_movement_spec.rb
git add app/models/cash_movement.rb spec/models/cash_movement_spec.rb
```

Hand the user this message:

```
feat(feat_27): make sealed cash movements immutable

- A movement carrying a daily_closing_id is never updated and never
  destroyed; errors get corrected with a new movement instead.
- The guard reads the persisted daily_closing_id, not the assigned one,
  so the closing can still stamp a row that has none yet.
- Enforced in the model rather than a database trigger: the project has
  no triggers, and this is cheap to test.
```

---

## Task 6: Balance scopes

Everything downstream — the daily count, the balance report, the history — reads balances the same way. This puts that in one place.

**Files:**
- Modify: `app/models/cash_movement.rb`
- Test: `spec/models/cash_movement_spec.rb`

**Interfaces:**
- Consumes: `CashMovement` (Tasks 3-5).
- Produces: scopes `.for_account(account)`, `.on(date)`, `.between(from, to)`, `.sales`; class methods `.balance_for(account)` and `.drawer_balance_on(date)`. Slice 1d computes `expected_cash` with `.drawer_balance_on`; slice 3's report builds on `.between`.

- [ ] **Step 1: Write the failing test**

Append to `spec/models/cash_movement_spec.rb`, inside the top-level `describe`:

```ruby
  describe "balances" do
    let(:day) { Date.new(2026, 8, 3) }

    before do
      create(:cash_movement, business_date: day, account: "drawer", amount: 299_700)
      create(:cash_movement, business_date: day, account: "drawer", amount: 25_000)
      create(:cash_movement, :store_expense, business_date: day, amount: -13_000)
      create(:cash_movement, :card_sale, business_date: day)
      create(:cash_movement, business_date: day + 1.day, account: "drawer", amount: 100_000)
    end

    it "sums a single arca across every date" do
      expect(described_class.balance_for("drawer")).to eq(411_700)
    end

    it "sums a single arca on one date" do
      expect(described_class.drawer_balance_on(day)).to eq(311_700)
    end

    it "keeps the arcas separate" do
      expect(described_class.balance_for("bank")).to eq(54_700)
    end

    it "returns zero for an arca with no movements" do
      expect(described_class.balance_for("usd")).to eq(0)
    end

    it "ignores a compensation sale, which touches no arca" do
      create(:cash_movement, :compensation_sale, business_date: day)
      expect(described_class.drawer_balance_on(day)).to eq(311_700)
      expect(described_class.where(account: nil).count).to eq(1)
    end
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `docker compose exec web bundle exec rspec spec/models/cash_movement_spec.rb -e "balances" -v`
Expected: FAIL — `undefined method 'balance_for'`.

- [ ] **Step 3: Add the scopes**

In `app/models/cash_movement.rb`, below the validations, add:

```ruby
  scope :for_account, ->(account) { where(account: account) }
  scope :on, ->(date) { where(business_date: date) }
  scope :between, ->(from, to) { where(business_date: from..to) }
  scope :sales, -> { where(category: "sale") }

  def self.balance_for(account)
    for_account(account).sum(:amount)
  end

  def self.drawer_balance_on(date)
    for_account("drawer").on(date).sum(:amount)
  end
```

- [ ] **Step 4: Run the test**

Run: `docker compose exec web bundle exec rspec spec/models/cash_movement_spec.rb -v`
Expected: PASS.

- [ ] **Step 5: Lint and stage**

```bash
docker compose exec web bundle exec rubocop app/models/cash_movement.rb spec/models/cash_movement_spec.rb
git add app/models/cash_movement.rb spec/models/cash_movement_spec.rb
```

Hand the user this message:

```
feat(feat_27): derive arca balances from movements

- A balance is SUM(amount) filtered by account, never a stored column,
  so it cannot drift from the rows that produced it.
- drawer_balance_on is the daily count's expected figure; the closing
  will read it.
- Compensation movements carry no account and drop out of every balance
  on their own, with no filtering.
```

---

## Task 7: `Cash::RecordMovement`

The single write path for one movement. Slice 1b's live row and slice 1c's collection hook both go through it.

**Files:**
- Create: `app/services/cash/record_movement.rb`
- Test: `spec/services/cash/record_movement_spec.rb`

**Interfaces:**
- Consumes: `CashMovement` (Tasks 3-6), `Result` (`app/services/result.rb`).
- Produces: `Cash::RecordMovement.call(business_date:, account:, amount:, category:, user:, subcategory: nil, channel: nil, description: nil, source_payment: nil) => Result`. On success `result.record` is the persisted `CashMovement`; on failure `result.errors` is an array of strings. Task 8 calls it; slices 1b, 1c and 2 call it.

- [ ] **Step 1: Write the failing test**

Create `spec/services/cash/record_movement_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cash::RecordMovement do
  let(:user) { create(:user, :caja) }
  let(:day) { Date.new(2026, 8, 3) }

  def call(**overrides)
    described_class.call(
      **{
        business_date: day,
        account: "drawer",
        amount: 299_700,
        category: "sale",
        channel: "cash",
        user: user
      }.merge(overrides)
    )
  end

  describe "success" do
    it "persists the movement and returns it" do
      result = call

      expect(result).to be_success
      expect(result.record).to be_persisted
      expect(result.record.amount).to eq(299_700)
      expect(result.record.account).to eq("drawer")
      expect(result.record.user).to eq(user)
    end

    it "records an outflow as a negative amount" do
      result = call(category: "fixed_expense", subcategory: "store_expenses",
                    channel: nil, amount: -13_000)

      expect(result).to be_success
      expect(result.record.amount).to eq(-13_000)
      expect(result.record).to be_outflow
    end

    it "records a compensation sale with no arca" do
      result = call(channel: "compensation", account: nil, amount: 661_188)

      expect(result).to be_success
      expect(result.record.account).to be_nil
    end
  end

  describe "failure" do
    it "rejects a zero amount" do
      result = call(amount: 0)

      expect(result).to be_failure
      expect(result.errors.join).to match(/amount/i)
      expect(CashMovement.count).to eq(0)
    end

    it "rejects a sale with no channel" do
      result = call(channel: nil)

      expect(result).to be_failure
      expect(CashMovement.count).to eq(0)
    end

    it "rejects a missing business_date" do
      result = call(business_date: nil)

      expect(result).to be_failure
      expect(CashMovement.count).to eq(0)
    end

    it "rejects a missing user" do
      result = call(user: nil)

      expect(result).to be_failure
      expect(CashMovement.count).to eq(0)
    end
  end

  describe "hostile input" do
    it "rejects an AR-formatted string instead of silently truncating it" do
      result = call(amount: "1.500.000,50")

      expect(result).to be_failure
      expect(CashMovement.count).to eq(0)
    end

    it "rejects a non-numeric amount" do
      result = call(amount: "abc")

      expect(result).to be_failure
      expect(CashMovement.count).to eq(0)
    end

    it "rejects a blank amount" do
      result = call(amount: "")

      expect(result).to be_failure
      expect(CashMovement.count).to eq(0)
    end

    it "rejects an unknown account" do
      result = call(account: "petty_cash")

      expect(result).to be_failure
      expect(CashMovement.count).to eq(0)
    end

    it "rejects an unknown category" do
      result = call(category: "shrinkage")

      expect(result).to be_failure
      expect(CashMovement.count).to eq(0)
    end
  end
end
```

`"1.500.000,50".to_f` is `1.5` in Ruby — it stops at the first dot. The service must never accept that silently; see `docs/TESTING_GUIDE.md`.

- [ ] **Step 2: Run it to verify it fails**

Run: `docker compose exec web bundle exec rspec spec/services/cash/record_movement_spec.rb -v`
Expected: FAIL — `uninitialized constant Cash`.

- [ ] **Step 3: Write the service**

Create `app/services/cash/record_movement.rb`:

```ruby
# frozen_string_literal: true

module Cash
  # Records a single cash movement. Movements between arcas need two rows and
  # go through Cash::RecordTransfer instead.
  class RecordMovement
    def self.call(**params)
      new(**params).call
    end

    def initialize(business_date:, account:, amount:, category:, user:,
                   subcategory: nil, channel: nil, description: nil,
                   source_payment: nil)
      @business_date  = business_date
      @account        = account
      @amount         = amount
      @category       = category
      @user           = user
      @subcategory    = subcategory
      @channel        = channel
      @description    = description
      @source_payment = source_payment
    end

    def call
      validate!

      movement = CashMovement.create!(
        business_date:  @business_date,
        account:        @account,
        amount:         normalized_amount,
        category:       @category,
        subcategory:    @subcategory,
        channel:        @channel,
        description:    @description,
        source_payment: @source_payment,
        user:           @user
      )

      Result.new(success?: true, record: movement, errors: [])
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue ArgumentError => e
      # Raised by ActiveRecord when an enum receives a value outside its set.
      Result.new(success?: false, record: nil, errors: [ e.message ])
    rescue ActiveRecord::RecordInvalid => e
      Result.new(success?: false, record: nil, errors: e.record.errors.full_messages)
    rescue StandardError => e
      Rails.logger.error("Error in Cash::RecordMovement: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      Result.new(success?: false, record: nil, errors: [ "Error registrando el movimiento" ])
    end

    private

    class ValidationError < StandardError; end

    def validate!
      raise ValidationError, "El usuario es obligatorio" if @user.blank?
      raise ValidationError, "La fecha es obligatoria" if @business_date.blank?
      raise ValidationError, "El monto debe ser un número distinto de cero" if normalized_amount.nil?
    end

    # Only accepts values that are already numeric or a plain decimal string.
    # An AR-formatted string like "1.500.000,50" is rejected rather than run
    # through to_f, which would silently return 1.5.
    def normalized_amount
      return @normalized_amount if defined?(@normalized_amount)

      @normalized_amount =
        case @amount
        when Numeric then BigDecimal(@amount.to_s)
        when String  then decimal_from(@amount)
        end
    end

    def decimal_from(string)
      BigDecimal(string)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
```

`BigDecimal("1.500.000,50")` raises `ArgumentError`, so `decimal_from` returns `nil` and `validate!` rejects it. `BigDecimal("abc")` and `BigDecimal("")` do the same.

- [ ] **Step 4: Run the test**

Run: `docker compose exec web bundle exec rspec spec/services/cash/record_movement_spec.rb -v`
Expected: PASS.

- [ ] **Step 5: Add the flow to the testing catalog**

In `docs/TESTING_GUIDE.md`, under "Write-money", add:

```markdown
- `Cash::RecordMovement` — signed `amount`, arca and category routing
```

- [ ] **Step 6: Lint and stage**

```bash
docker compose exec web bundle exec rubocop app/services/cash/record_movement.rb spec/services/cash/record_movement_spec.rb
git add app/services/cash/record_movement.rb spec/services/cash/record_movement_spec.rb docs/TESTING_GUIDE.md
```

Hand the user this message:

```
feat(feat_27): add Cash::RecordMovement

- The single write path for one cash movement; returns a Result like
  every other service here.
- Amounts are parsed with BigDecimal rather than to_f, so an
  AR-formatted string such as "1.500.000,50" is rejected instead of
  silently becoming 1.5.
- An enum value outside its set fails as a Result, not an exception.
- Added to the write-money catalog in docs/TESTING_GUIDE.md.
```

---

## Task 8: Opening balances rake task

R-17 and §7.4: the one-time startup load, one movement per arca, taken from the last Excel close. Rake-only, following `Inventory::SyncFromCsv`, which is invoked from `lib/tasks/inventory.rake` and never exposed over HTTP.

**Files:**
- Create: `lib/tasks/cash.rake`
- Test: `spec/tasks/cash_opening_balances_spec.rb`

**Interfaces:**
- Consumes: `Cash::RecordMovement` (Task 7), `CashMovement` (Tasks 3-6).
- Produces: `rake cash:opening_balances` — the last step of slice 1a and the prerequisite for every later slice.

- [ ] **Step 1: Write the failing test**

Create `spec/tasks/cash_opening_balances_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "cash:opening_balances" do
  let(:task_name) { "cash:opening_balances" }
  let!(:admin) { create(:user, :admin) }

  before do
    Rake::Task.clear
    Rails.application.load_tasks
    ENV["ON"] = "2026-08-31"
    ENV["MAIN_CASH"] = "12497899.30"
    ENV["BANK"] = "2522996.25"
    ENV["MERCADO_PAGO"] = "4285964.02"
    ENV["CHANGE_FUND"] = "101800"
    ENV["USD"] = "500"
  end

  after do
    %w[ON MAIN_CASH BANK MERCADO_PAGO CHANGE_FUND USD DRAWER].each { |k| ENV.delete(k) }
  end

  def run_task
    Rake::Task[task_name].reenable
    Rake::Task[task_name].invoke
  end

  it "creates one opening_balance movement per arca given a value" do
    run_task

    expect(CashMovement.where(category: "opening_balance").count).to eq(5)
    expect(CashMovement.balance_for("main_cash")).to eq(BigDecimal("12497899.30"))
    expect(CashMovement.balance_for("bank")).to eq(BigDecimal("2522996.25"))
    expect(CashMovement.balance_for("usd")).to eq(500)
  end

  it "dates every movement on the given day" do
    run_task

    dates = CashMovement.pluck(:business_date).uniq
    expect(dates).to eq([ Date.new(2026, 8, 31) ])
  end

  it "skips an arca with no value given" do
    run_task

    expect(CashMovement.balance_for("drawer")).to eq(0)
  end

  it "refuses to run twice" do
    run_task

    expect { run_task }.to raise_error(SystemExit)
    expect(CashMovement.where(category: "opening_balance").count).to eq(5)
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `docker compose exec web bundle exec rspec spec/tasks/cash_opening_balances_spec.rb -v`
Expected: FAIL — `Don't know how to build task 'cash:opening_balances'`.

- [ ] **Step 3: Write the rake task**

Create `lib/tasks/cash.rake`:

```ruby
# frozen_string_literal: true

namespace :cash do
  desc "Load the one-time opening balance per arca (ON=YYYY-MM-DD MAIN_CASH=... BANK=...)"
  task opening_balances: :environment do
    if CashMovement.where(category: "opening_balance").exists?
      abort "Opening balances were already loaded. They are a one-time operation."
    end

    business_date = Date.parse(ENV.fetch("ON"))
    user = User.where(role: "admin").first
    abort "No admin user found to attribute the opening balances to." if user.nil?

    amounts = CashMovement::ACCOUNT_LABELS.keys.filter_map do |account|
      raw = ENV[account.upcase]
      [ account, raw ] if raw.present?
    end

    abort "No amounts given. Pass at least one, e.g. MAIN_CASH=12497899.30" if amounts.empty?

    amounts.each do |account, raw|
      result = Cash::RecordMovement.call(
        business_date: business_date,
        account: account,
        amount: raw,
        category: "opening_balance",
        description: "Saldo inicial",
        user: user
      )

      abort "#{account}: #{result.errors.join(', ')}" if result.failure?

      puts "#{CashMovement.account_label(account)}: #{result.record.amount}"
    end

    puts "Loaded #{amounts.size} opening balances on #{business_date}."
  end
end
```

`User.where(role: "admin").first` rather than the enum scope: `User#role` uses the older `_suffix: true` form and the generated scope name is easy to get wrong from memory.

- [ ] **Step 4: Run the test**

Run: `docker compose exec web bundle exec rspec spec/tasks/cash_opening_balances_spec.rb -v`
Expected: PASS.

- [ ] **Step 5: Run the whole suite**

Run: `docker compose exec web bundle exec rspec`
Expected: PASS.

- [ ] **Step 6: Lint and stage**

```bash
docker compose exec web bundle exec rubocop lib/tasks/cash.rake spec/tasks/cash_opening_balances_spec.rb
git add lib/tasks/cash.rake spec/tasks/cash_opening_balances_spec.rb
```

Hand the user this message:

```
feat(feat_27): add the opening balances rake task

- Loads one opening_balance movement per arca from the last Excel close,
  which is how the module starts with the right numbers.
- Rake-only, following Inventory::SyncFromCsv: it is a one-time
  operation and does not belong over HTTP.
- Refuses to run a second time, since a duplicate load would silently
  double every balance.
```

---

## Verification for the whole slice

After Task 8, this is what "1a is done" means. Run it and read the output.

- [ ] **Step 1: Full suite green**

Run: `docker compose exec web bundle exec rspec`
Expected: PASS, no pending.

- [ ] **Step 2: Lint clean**

Run: `docker compose exec web bundle exec rubocop`
Expected: no offenses.

- [ ] **Step 3: Balances add up in the console**

Run: `docker compose exec web bin/rails console`

```ruby
CashMovement::ACCOUNT_LABELS.keys.map { |a| [ a, CashMovement.balance_for(a) ] }.to_h
```

Expected: the six arcas with the amounts the rake task loaded, and `0` for any that got none.

- [ ] **Step 4: The guard actually guards**

Still in the console:

```ruby
m = CashMovement.first
m.update!(daily_closing: DailyClosing.create!(business_date: Date.current, expected_cash: 0, counted_cash: 0, closed_at: Time.current, user: User.where(role: "admin").first))
m.update!(amount: 1)   # => raises CashMovement::SealedMovementError
m.destroy              # => raises CashMovement::SealedMovementError
```

Expected: the first update succeeds, the next two raise.

---

## What 1a deliberately leaves out

So the next slice starts from a known place:

- **No UI.** No controllers, no routes, no views, no policies. That is 1b.
- **No collection hook.** `source_payment_id` exists as a column but nothing writes it until 1c.
- **`Cash::RecordTransfer`, `Cash::CloseDay`, `Cash::ReversePayment`** — slices 2, 1d and 1c respectively. `transfer_group_id` and `daily_closing_id` exist as columns, unwritten.
- **No `invoice_type` / `invoice_number` on `orders`.** They belong with the collection screen, in 1c.
- **No reports.** Slice 3.
