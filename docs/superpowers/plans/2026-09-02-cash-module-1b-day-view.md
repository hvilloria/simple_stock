# Cash module — slice 1b: Vista Día and drawer-zone loading

Builds on slice 1a, which landed the data foundation: `cash_movements`,
`daily_closings`, `CashMovement`, `DailyClosing`, `Cash::RecordMovement`, the
balance scopes and the opening-balances rake task. Nothing in 1a is user-facing.

This slice puts the first screen on top of it: the day view, and the drawer-zone
live row that replaces the daily spreadsheet.

Design spec: `docs/CASH_MODULE_DESIGN.md`. Sections that govern this slice are
§7.1 (loading the day), §8.1 (Vista Día), §9 (roles) and rules R-5, R-6, R-8 and
R-15.

---

## Environment

This project has no host Ruby — everything runs in Docker, as documented in
`README.md`. Bring the stack up once and leave it running:

```
docker compose up -d
docker compose exec web bin/rails db:prepare
```

Every command in this plan is already written in its `docker compose exec web …`
form. Pass `-T` when running non-interactively. If a command fails with a
connection error, the stack is down.

**Branch:** `feat-28_cash-day-view` off `main` once 1a is merged, or off the 1a
branch if it has not been merged yet. Scope for every commit: `feat_28`.

---

## Global constraints

Copy these into every task brief — subagents do not see this section otherwise.

### The constant-resolution trap

The services live in `Cash::`. The controllers live in `Web::Cash::`. Inside
`module Web; module Cash`, the bare constant `Cash` resolves to `Web::Cash`, so
`Cash::RecordMovement` becomes `Web::Cash::RecordMovement` and blows up with a
`NameError` that reads like a missing file.

**Every reference to a service from a controller in this slice must be written
`::Cash::RecordMovement`, with the leading colons.** Same for `::Cash::DayQuery`.
Top-level models (`CashMovement`, `DailyClosing`) are unaffected.

### Turbo Streams are new to this project

There is no `format.turbo_stream` and no `.turbo_stream.haml` anywhere in the
codebase today. `turbo-rails` is installed and Turbo Drive is active, but the
stream pattern is being introduced here, deliberately, and its shape is what the
arca zone, the daily close and the transfer form will copy in later slices.

Consequences:

- Do not go looking for an existing example to follow — there is none.
- Keep it boring. A stream response is a list of `turbo_stream.<verb> "<dom-id>"`
  calls and nothing else. No stream broadcasting, no `turbo_stream_from`, no
  models broadcasting on save. This slice is request-response only.
- Every element a stream targets needs a stable `id`. A stream aimed at an id
  that is not on the page fails silently — no error, no visible effect. When a
  stream "does nothing", suspect the id first.

### What a zone is, in data terms

There is no `zone` column and there must not be one. The two zones of §7.1 are
derived:

```
drawer zone = category = 'sale' OR account = 'drawer'
arca zone   = everything else
```

Checked against the cases the design argues about: a USD sale is `sale`, so it
shows in the drawer zone while its arca is `usd` and it never enters the peso
count (R-6). Bags bought out of the till are `account = 'drawer'` → drawer zone.
The same bags bought out of a bundle at 9am are `account = 'main_cash'` → arca
zone, which is exactly the distinction R-6 makes. A supplier paid from the bank
→ arca zone.

**This slice renders the drawer zone only.** The arca zone is tramo 2. Do not
build it, do not leave a placeholder for it.

### The sign is derived, never typed

The table displays two columns, Ingreso and Egreso, but the live row has **one**
amount field. The sign comes from the category:

```
sale                        → positive
suppliers, fixed_expense    → negative
```

The cashier never types a minus and never picks a column. R-5 already removed
the other place a sign could go wrong: change given back is not a movement.

### Amount format at the boundary

`currency-input` submits the Argentine display format (`1.500.000,50`).
`Cash::RecordMovement` accepts a `Numeric` or a strict plain decimal string and
rejects everything else — deliberately, because `"1.500.000,50".to_f` is `1.5`
and `BigDecimal("101.800")` is `101.8`.

So the controller has to convert presentation format to a plain decimal before
calling the service. Do **not** add a fourth `parse_amount`: there are already
three (`app/controllers/concerns/currency_parser.rb` plus private copies in two
payments controllers). Add one method to the existing concern, leaving
`parse_amount` untouched so its three callers do not change:

```ruby
  # Argentine display format to a plain decimal string, or nil when the value is
  # not a number. Returns a String rather than a Float so the caller can hand it
  # to a service that validates it, instead of silently turning "abc" into 0.0.
  def decimal_string_from(raw)
    value = raw.to_s.strip
    return nil if value.blank?

    normalized = value.include?(",") ? value.delete(".").tr(",", ".") : value
    normalized.match?(/\A-?\d+(\.\d{1,2})?\z/) ? normalized : nil
  end
```

The controller passes that string straight through. A `nil` means the input was
not a number and the row is refused with a message that says so.

### Everything else

- **HAML only.** No ERB. No queries or business logic in views.
- **Services return `Result`; controllers stay thin.** Direct ActiveRecord is
  acceptable only for a trivial single-model read.
- **Reuse before building:** `currency-input`, `CurrencyHelper#number_ar`,
  the table markup of `app/views/web/orders/index.html.haml`, the sidebar's
  active-state idiom, `ApplicationPolicy`.
- **Visual language:** `docs/UI_DESIGN_SPEC.md` — slate base, sober, semantic
  colour only where it means something. UI labels in Spanish.
- **Comments in code are in English and minimal.** Code and specs never cite
  project docs; a file explains itself.
- **Timezone:** `Date.current` is Buenos Aires as of 1a. The business date is
  always an explicit parameter, never an implicit `Date.current`, except when
  choosing which day to redirect to.

---

## File structure

New:

```
app/controllers/web/cash/days_controller.rb
app/controllers/web/cash/movements_controller.rb
app/services/cash/day_query.rb
app/policies/cash_movement_policy.rb
app/javascript/controllers/cash_live_row_controller.js
app/views/web/cash/days/show.html.haml
app/views/web/cash/days/_drawer_zone.html.haml
app/views/web/cash/days/_sales_by_channel.html.haml
app/views/web/cash/movements/_row.html.haml
app/views/web/cash/movements/_live_row.html.haml
app/views/web/cash/movements/_edit_row.html.haml
app/views/web/cash/movements/create.turbo_stream.haml
app/views/web/cash/movements/update.turbo_stream.haml
app/views/web/cash/movements/destroy.turbo_stream.haml
spec/services/cash/day_query_spec.rb
spec/policies/cash_movement_policy_spec.rb
spec/requests/web/cash/days_spec.rb
spec/requests/web/cash/movements_spec.rb
spec/system/web/cash_live_row_spec.rb
```

Modified:

```
config/routes.rb
app/controllers/concerns/currency_parser.rb
app/views/layouts/web/_sidebar.html.haml
```

---

## Task 1: `CashMovementPolicy`

The restriction on the cashier is on data as well as actions (§9), so the scope
has to be real, not decorative.

**Files:**
- Create: `app/policies/cash_movement_policy.rb`
- Test: `spec/policies/cash_movement_policy_spec.rb`

**Interfaces:**
- Consumes: `CashMovement#sealed?` from 1a.
- Produces: `index?`, `create?`, `update?`, `destroy?` and `Scope`. Every later
  task authorizes through this.

- [ ] **Step 1: Write the failing test**

`spec/policies/cash_movement_policy_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe CashMovementPolicy do
  subject { described_class }

  let(:cashier) { build(:user, role: "caja") }
  let(:admin)   { build(:user, role: "admin") }
  let(:seller)  { build(:user, role: "vendedor") }

  permissions :index?, :create? do
    it { is_expected.to permit(cashier, CashMovement) }
    it { is_expected.to permit(admin, CashMovement) }
    it { is_expected.not_to permit(seller, CashMovement) }
  end

  permissions :update?, :destroy? do
    let(:open_movement) { build(:cash_movement) }

    it { is_expected.to permit(cashier, open_movement) }
    it { is_expected.to permit(admin, open_movement) }
    it { is_expected.not_to permit(seller, open_movement) }

    it "refuses a movement sealed by a closing" do
      sealed = create(:cash_movement, :sealed)
      expect(subject).not_to permit(cashier, sealed)
      expect(subject).not_to permit(admin, sealed)
    end
  end

  describe "Scope" do
    it "gives the cashier and the admin every movement" do
      movement = create(:cash_movement)

      expect(described_class::Scope.new(cashier, CashMovement).resolve).to include(movement)
      expect(described_class::Scope.new(admin, CashMovement).resolve).to include(movement)
    end

    it "gives the seller nothing" do
      create(:cash_movement)

      expect(described_class::Scope.new(seller, CashMovement).resolve).to be_empty
    end
  end
end
```

Run: `docker compose exec -T web bundle exec rspec spec/policies/cash_movement_policy_spec.rb`
Expected: FAIL — uninitialized constant `CashMovementPolicy`.

- [ ] **Step 2: Write the policy**

`app/policies/cash_movement_policy.rb`:

```ruby
# frozen_string_literal: true

class CashMovementPolicy < ApplicationPolicy
  # Categories the drawer zone offers. partner and opening_balance are not the
  # cashier's to load, and internal_transfer is written as a pair by
  # Cash::RecordTransfer, never one leg at a time.
  DRAWER_CATEGORIES = %w[sale suppliers fixed_expense].freeze

  def index?
    user.caja? || user.admin?
  end

  def create?
    index?
  end

  def update?
    index? && !record.sealed?
  end

  def destroy?
    update?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user.caja? || user.admin?

      scope.none
    end
  end
end
```

- [ ] **Step 3: Run the test**

Expected: PASS. If `permit` is not available, add
`config.include Pundit::Matchers` to `spec/rails_helper.rb` — check whether the
gem is in the Gemfile first, and if it is not, rewrite the examples as plain
`described_class.new(user, record).index?` assertions rather than adding a
dependency for this slice.

- [ ] **Step 4: Rubocop**

`docker compose exec -T web bundle exec rubocop app/policies/cash_movement_policy.rb spec/policies/cash_movement_policy_spec.rb`

**Commit message:**

```
feat(feat_28): add the cash movement policy

- The cashier and the admin load and correct movements; nobody else sees
  the module at all.
- A sealed movement is refused at the policy layer as well as the model
  one, so the UI never offers an edit the model would reject.
- The scope is real rather than decorative: the restriction is on the
  data, not only on the buttons.
```

---

## Task 2: `Cash::DayQuery`

Everything the day screen reads, in one object. Read-heavy logic belongs in a
query object, not in the controller.

**Files:**
- Create: `app/services/cash/day_query.rb`
- Test: `spec/services/cash/day_query_spec.rb`

**Interfaces:**
- Consumes: `CashMovement.on`, `.sales`, `.drawer_balance_on` from 1a.
- Produces: `#drawer_movements`, `#sales_by_channel`, `#amount_to_wrap`,
  `#closed?`. Tasks 3, 6 and 7 read all four.

- [ ] **Step 1: Write the failing test**

`spec/services/cash/day_query_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cash::DayQuery do
  let(:date) { Date.new(2026, 8, 3) }

  subject(:query) { described_class.new(date) }

  describe "#drawer_movements" do
    it "takes every sale, whatever arca it lands in" do
      cash_sale = create(:cash_movement, business_date: date, channel: "cash", account: "drawer")
      card_sale = create(:cash_movement, :card_sale, business_date: date)
      usd_sale  = create(:cash_movement, business_date: date, channel: "usd", account: "usd", amount: 50)

      expect(query.drawer_movements).to contain_exactly(cash_sale, card_sale, usd_sale)
    end

    it "takes an expense paid out of the till" do
      expense = create(:cash_movement, :store_expense, business_date: date)

      expect(query.drawer_movements).to include(expense)
    end

    it "leaves out an expense paid out of a bundle" do
      create(:cash_movement, :store_expense, business_date: date, account: "main_cash")

      expect(query.drawer_movements).to be_empty
    end

    it "leaves out a supplier paid from the bank" do
      create(:cash_movement, :supplier_payment, business_date: date)

      expect(query.drawer_movements).to be_empty
    end

    it "leaves out another day" do
      create(:cash_movement, business_date: date + 1)

      expect(query.drawer_movements).to be_empty
    end

    it "orders by load order, oldest first" do
      first  = create(:cash_movement, business_date: date, description: "primera")
      second = create(:cash_movement, business_date: date, description: "segunda")

      expect(query.drawer_movements.map(&:description)).to eq([ "primera", "segunda" ])
    end
  end

  describe "#sales_by_channel" do
    it "groups the day's sales by channel and ignores expenses" do
      create(:cash_movement, business_date: date, channel: "cash", account: "drawer", amount: 299_700)
      create(:cash_movement, business_date: date, channel: "cash", account: "drawer", amount: 25_000)
      create(:cash_movement, :card_sale, business_date: date)
      create(:cash_movement, :store_expense, business_date: date)

      expect(query.sales_by_channel).to eq("cash" => 324_700, "card" => 54_700)
    end

    it "is empty on a day with no sales" do
      expect(query.sales_by_channel).to be_empty
    end
  end

  describe "#amount_to_wrap" do
    it "is the drawer's net for the day, expenses included" do
      create(:cash_movement, business_date: date, channel: "cash", account: "drawer", amount: 324_700)
      create(:cash_movement, :store_expense, business_date: date)

      expect(query.amount_to_wrap).to eq(311_700)
    end

    it "leaves out sales that never touched the drawer" do
      create(:cash_movement, :card_sale, business_date: date)

      expect(query.amount_to_wrap).to eq(0)
    end
  end

  describe "#closed?" do
    it "is false while no closing exists for the date" do
      expect(query).not_to be_closed
    end

    it "is true once the day is closed" do
      create(:daily_closing, business_date: date)

      expect(query).to be_closed
    end
  end
end
```

Run: `docker compose exec -T web bundle exec rspec spec/services/cash/day_query_spec.rb`
Expected: FAIL — uninitialized constant.

- [ ] **Step 2: Write the query object**

`app/services/cash/day_query.rb`:

```ruby
# frozen_string_literal: true

module Cash
  # Everything the day screen reads. The two zones of the design are not a
  # column: the drawer zone is every sale plus whatever was paid out of the
  # till, and the arca zone is the rest.
  class DayQuery
    def initialize(business_date)
      @business_date = business_date
    end

    def drawer_movements
      CashMovement
        .on(@business_date)
        .where("category = :sale OR account = :drawer", sale: "sale", drawer: "drawer")
        .order(:created_at, :id)
    end

    def sales_by_channel
      drawer_movements.sales.group(:channel).sum(:amount)
    end

    def amount_to_wrap
      CashMovement.drawer_balance_on(@business_date)
    end

    def closed?
      DailyClosing.exists?(business_date: @business_date)
    end
  end
end
```

- [ ] **Step 3: Run the test**

Expected: PASS. If the ordering example is flaky because two rows share a
`created_at` to the microsecond, that is what the `:id` tiebreaker is for —
confirm it is in the `order` call rather than loosening the expectation.

- [ ] **Step 4: Rubocop**

**Commit message:**

```
feat(feat_28): add the cash day query

- One object for everything the day screen reads, so the controller stays
  a router and the view stays free of queries.
- The drawer zone is derived, not stored: every sale plus whatever was
  paid out of the till. A dollar sale shows there while its arca is usd,
  and bags bought out of a bundle do not.
- The amount to wrap is the drawer's own balance for the date, so a sale
  that never touched the drawer cannot inflate it.
```

---

## Task 3: Route, controller and the read-only day screen

The screen before anything is writable: navigate to a date, see that day's
drawer zone, see nothing but a message on an empty day.

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/web/cash/days_controller.rb`
- Create: `app/views/web/cash/days/show.html.haml`
- Create: `app/views/web/cash/days/_drawer_zone.html.haml`
- Create: `app/views/web/cash/movements/_row.html.haml`
- Test: `spec/requests/web/cash/days_spec.rb`

**Interfaces:**
- Consumes: `Cash::DayQuery`, `CashMovementPolicy`.
- Produces: `web_cash_day_path(business_date)`, the `#drawer-rows` tbody and the
  `_row` partial. Tasks 4, 6 and 7 all target ids defined here.

- [ ] **Step 1: Routes**

Inside the existing `namespace :web do` block in `config/routes.rb`, after
`resources :credit_notes`:

```ruby
    namespace :cash do
      resources :days, only: [ :index, :show ], param: :business_date
      resources :movements, only: [ :create, :edit, :update, :destroy ]
    end
```

`days#index` redirects to today. `days#show` receives
`params[:business_date]` as `"2026-08-03"`. Movements are declared now so the
form in Task 4 has a URL; the actions arrive in Tasks 4 and 6.

- [ ] **Step 2: Write the failing request spec**

`spec/requests/web/cash/days_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::Cash::Days", type: :request do
  let(:cashier) { create(:user, role: "caja") }
  let(:date)    { Date.new(2026, 8, 3) }

  describe "GET /web/cash/days" do
    it "sends the cashier to today" do
      sign_in cashier

      get "/web/cash/days"

      expect(response).to redirect_to("/web/cash/days/#{Date.current}")
    end
  end

  describe "GET /web/cash/days/:business_date" do
    before { sign_in cashier }

    it "renders the day's drawer movements" do
      create(:cash_movement, business_date: date, description: "Venta mostrador")

      get "/web/cash/days/2026-08-03"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Venta mostrador")
    end

    it "does not render another day's movements" do
      create(:cash_movement, business_date: date + 1, description: "De otro día")

      get "/web/cash/days/2026-08-03"

      expect(response.body).not_to include("De otro día")
    end

    it "does not render an arca-zone movement" do
      create(:cash_movement, :supplier_payment, business_date: date, description: "Cromosol")

      get "/web/cash/days/2026-08-03"

      expect(response.body).not_to include("Cromosol")
    end

    it "falls back to today when the date is not a date" do
      get "/web/cash/days/no-es-fecha"

      expect(response).to redirect_to("/web/cash/days/#{Date.current}")
    end
  end

  describe "authorization" do
    it "turns a seller away" do
      sign_in create(:user, role: "vendedor")

      get "/web/cash/days/2026-08-03"

      expect(response).to redirect_to(authenticated_root_path)
    end

    it "sends an anonymous visitor to the login" do
      get "/web/cash/days/2026-08-03"

      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
```

Run it. Expected: FAIL — no route, then no controller.

- [ ] **Step 3: Write the controller**

`app/controllers/web/cash/days_controller.rb`:

```ruby
# frozen_string_literal: true

module Web
  module Cash
    class DaysController < ApplicationController
      def index
        authorize CashMovement, :index?

        redirect_to web_cash_day_path(Date.current)
      end

      def show
        authorize CashMovement, :index?

        business_date = parse_business_date
        return redirect_to web_cash_day_path(Date.current) if business_date.nil?

        @business_date = business_date
        @day = ::Cash::DayQuery.new(@business_date)
      end

      private

      def parse_business_date
        Date.parse(params[:business_date])
      rescue Date::Error, TypeError
        nil
      end
    end
  end
end
```

Note the `::Cash::DayQuery`. Without the leading colons this resolves to
`Web::Cash::DayQuery` and fails.

- [ ] **Step 4: Write the views**

`app/views/web/cash/days/show.html.haml` — the page shell, the date header with
previous/next links, and the drawer zone. Follow the container and heading
markup of `app/views/web/orders/index.html.haml`:

```haml
- content_for :page_title, "Caja"

.container.mx-auto.px-6.py-6
  .flex.items-center.justify-between.mb-6
    %div
      %h1.text-3xl.font-bold.text-slate-900= l(@business_date, format: :long)
      - if @day.closed?
        %p.text-sm.text-slate-500.mt-1 Día cerrado — solo lectura

    .flex.items-center.gap-2
      = link_to "← Día anterior", web_cash_day_path(@business_date - 1),
                class: "px-3 py-2 text-sm font-medium text-slate-600 hover:text-slate-900 hover:bg-slate-50 rounded-lg transition-colors"
      = link_to "Hoy", web_cash_day_path(Date.current),
                class: "px-3 py-2 text-sm font-medium text-slate-600 hover:text-slate-900 hover:bg-slate-50 rounded-lg transition-colors"
      = link_to "Día siguiente →", web_cash_day_path(@business_date + 1),
                class: "px-3 py-2 text-sm font-medium text-slate-600 hover:text-slate-900 hover:bg-slate-50 rounded-lg transition-colors"

  = render "web/cash/days/drawer_zone", day: @day, business_date: @business_date
```

If `l(@business_date, format: :long)` has no Spanish locale behind it, use
`@business_date.strftime("%d/%m/%Y")` rather than adding an i18n file in this
slice.

`app/views/web/cash/days/_drawer_zone.html.haml`:

```haml
.bg-white.border.border-slate-200.rounded-lg.overflow-hidden
  %table.min-w-full.divide-y.divide-slate-200
    %thead.bg-slate-50
      %tr
        %th.px-4.py-3.text-left.text-xs.font-medium.text-slate-500.uppercase.tracking-wider Descripción
        %th.px-4.py-3.text-left.text-xs.font-medium.text-slate-500.uppercase.tracking-wider Canal
        %th.px-4.py-3.text-right.text-xs.font-medium.text-slate-500.uppercase.tracking-wider Ingreso
        %th.px-4.py-3.text-right.text-xs.font-medium.text-slate-500.uppercase.tracking-wider Egreso
        %th.px-4.py-3.w-24
    %tbody#drawer-rows.divide-y.divide-slate-100.bg-white
      = render partial: "web/cash/movements/row", collection: day.drawer_movements, as: :movement

  - if day.drawer_movements.empty?
    .p-12.text-center
      %p.text-slate-500 No hay movimientos cargados en este día.
```

`app/views/web/cash/movements/_row.html.haml`:

```haml
%tr{ id: dom_id(movement), class: "hover:bg-slate-50 transition-colors" }
  %td.px-4.py-3.text-sm.text-slate-900= movement.description
  %td.px-4.py-3.text-sm.text-slate-600= movement.channel.present? ? CashMovement.channel_label(movement.channel) : "—"
  %td.px-4.py-3.text-sm.text-right.text-slate-900= movement.inflow? ? number_ar(movement.amount) : ""
  %td.px-4.py-3.text-sm.text-right.text-slate-900= movement.outflow? ? number_ar(movement.amount.abs) : ""
  %td.px-4.py-3.text-right
```

The actions cell is empty for now; Task 6 fills it.

- [ ] **Step 5: Run the tests**

Expected: PASS, all seven examples.

- [ ] **Step 6: Rubocop**

**Commit message:**

```
feat(feat_28): add the cash day screen

- One URL per business day, so the whole month is reachable and a day can
  be linked to.
- The screen shows the drawer zone only: sales and whatever was paid out
  of the till. The arca zone lands with its own loading, later.
- A date that does not parse sends the cashier to today rather than
  raising, since the segment is user-editable.
```

---

## Task 4: The live row

The gesture the whole module is judged on. Enter saves, a fresh empty row
appears, the focus goes back to the first field.

**Files:**
- Modify: `app/controllers/concerns/currency_parser.rb`
- Create: `app/controllers/web/cash/movements_controller.rb`
- Create: `app/views/web/cash/movements/_live_row.html.haml`
- Create: `app/views/web/cash/movements/create.turbo_stream.haml`
- Create: `app/javascript/controllers/cash_live_row_controller.js`
- Modify: `app/views/web/cash/days/_drawer_zone.html.haml`
- Test: `spec/requests/web/cash/movements_spec.rb`

**Interfaces:**
- Consumes: `::Cash::RecordMovement`, `CashMovementPolicy`, `#drawer-rows`.
- Produces: `#drawer-live-row`, the `create.turbo_stream` shape every later
  screen copies.

- [ ] **Step 1: The HTML problem, decided before any code**

A `<form>` cannot be a child of `<tbody>` — the parser hoists it out and the
inputs end up orphaned. The live row therefore renders the `<form>` element
outside the table and binds the inputs to it by id:

```haml
= form_with url: web_cash_movements_path, id: "drawer-form", class: "contents" do |f|
  = hidden_field_tag :business_date, business_date
```

and each input inside the `<td>` carries `form: "drawer-form"`. This is standard
HTML5 form association and needs no JavaScript. Do not solve it by replacing the
table with divs.

- [ ] **Step 2: Extend the currency concern**

Add `decimal_string_from` to `app/controllers/concerns/currency_parser.rb`
exactly as given in the Global constraints section. Leave `parse_amount` alone —
three controllers depend on its current behaviour.

Add a spec for the new method covering `"1.500.000,50"` → `"1500000.50"`,
`"101.800"` → `"101800"`, `"200000.50"` → `"200000.50"`, `"abc"` → `nil`,
`""` → `nil`, `nil` → `nil`.

- [ ] **Step 3: Write the failing request spec**

`spec/requests/web/cash/movements_spec.rb`:

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::Cash::Movements", type: :request do
  let(:cashier) { create(:user, role: "caja") }
  let(:date)    { "2026-08-03" }

  before { sign_in cashier }

  def post_movement(params)
    post "/web/cash/movements",
         params: { business_date: date }.merge(params),
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
  end

  describe "POST /web/cash/movements" do
    it "records a cash sale against the drawer" do
      post_movement(category: "sale", channel: "cash", description: "Venta mostrador", amount: "324.700,00")

      movement = CashMovement.last
      expect(movement.category).to eq("sale")
      expect(movement.account).to eq("drawer")
      expect(movement.amount).to eq(324_700)
      expect(movement.business_date).to eq(Date.new(2026, 8, 3))
    end

    it "routes a card sale to the bank without asking" do
      post_movement(category: "sale", channel: "card", description: "Venta tarjeta", amount: "54.700,00")

      expect(CashMovement.last.account).to eq("bank")
    end

    it "records an expense as an outflow from the drawer" do
      post_movement(category: "fixed_expense", subcategory: "store_expenses", description: "Bolsas", amount: "13.000,00")

      movement = CashMovement.last
      expect(movement.amount).to eq(-13_000)
      expect(movement.account).to eq("drawer")
    end

    it "answers with a turbo stream that appends the row" do
      post_movement(category: "sale", channel: "cash", description: "Venta mostrador", amount: "1.000,00")

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('action="append"', 'target="drawer-rows"')
      expect(response.body).to include('target="drawer-live-row"')
    end

    it "refuses an amount that is not a number and writes nothing" do
      expect {
        post_movement(category: "sale", channel: "cash", description: "Venta", amount: "abc")
      }.not_to change(CashMovement, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "refuses a sale with no channel" do
      expect {
        post_movement(category: "sale", channel: "", description: "Venta", amount: "1.000,00")
      }.not_to change(CashMovement, :count)
    end

    it "refuses a category the drawer zone does not offer" do
      expect {
        post_movement(category: "partner", description: "Retiro", amount: "1.000,00")
      }.not_to change(CashMovement, :count)
    end

    it "refuses to write into a closed day" do
      create(:daily_closing, business_date: Date.new(2026, 8, 3))

      expect {
        post_movement(category: "sale", channel: "cash", description: "Tarde", amount: "1.000,00")
      }.not_to change(CashMovement, :count)
    end

    it "turns a seller away" do
      sign_in create(:user, role: "vendedor")

      expect {
        post_movement(category: "sale", channel: "cash", description: "Venta", amount: "1.000,00")
      }.not_to change(CashMovement, :count)
    end
  end
end
```

- [ ] **Step 4: Write the controller**

`app/controllers/web/cash/movements_controller.rb`:

```ruby
# frozen_string_literal: true

module Web
  module Cash
    class MovementsController < ApplicationController
      include CurrencyParser

      OUTFLOW_CATEGORIES = %w[suppliers fixed_expense].freeze

      def create
        authorize CashMovement, :create?

        @business_date = Date.parse(params[:business_date])
        return refuse("El día está cerrado.") if day_closed?
        return refuse("Esa categoría no se carga en la caja del día.") unless drawer_category?

        amount = signed_amount
        return refuse("El monto no es un número.") if amount.nil?

        result = ::Cash::RecordMovement.call(
          business_date: @business_date,
          account: account_for(params[:category], params[:channel]),
          amount: amount,
          category: params[:category],
          subcategory: params[:subcategory].presence,
          channel: params[:channel].presence,
          description: params[:description].presence,
          user: current_user
        )

        return refuse(result.errors.join(", ")) if result.failure?

        @movement = result.record
        @day = ::Cash::DayQuery.new(@business_date)
        render :create
      end

      private

      def drawer_category?
        CashMovementPolicy::DRAWER_CATEGORIES.include?(params[:category])
      end

      def day_closed?
        DailyClosing.exists?(business_date: @business_date)
      end

      # A sale lands in the arca its channel implies; an expense loaded here came
      # out of the till by definition.
      def account_for(category, channel)
        return "drawer" unless category == "sale"

        CashMovement::CHANNEL_ACCOUNTS[channel.to_s]
      end

      # The cashier types a bare amount; the category decides the sign.
      def signed_amount
        decimal = decimal_string_from(params[:amount])
        return nil if decimal.nil?

        OUTFLOW_CATEGORIES.include?(params[:category]) ? "-#{decimal.delete_prefix('-')}" : decimal
      end

      def refuse(message)
        @error = message
        @day = ::Cash::DayQuery.new(@business_date)
        render :create, status: :unprocessable_entity
      end
    end
  end
end
```

Note `CashMovement::CHANNEL_ACCOUNTS[...]` rather than
`CashMovement.account_for_channel(...)`: the class method raises `KeyError` on an
unknown channel, and here the channel is user input. A `nil` account then fails
the model's own validation and comes back as a `Result` failure, which is what we
want.

- [ ] **Step 5: Write the live row and the stream**

`app/views/web/cash/movements/_live_row.html.haml`:

```haml
%tr#drawer-live-row{ data: { controller: "cash-live-row" } }
  %td.px-4.py-2
    = text_field_tag :description, nil, form: "drawer-form",
                     placeholder: "Descripción",
                     data: { "cash-live-row-target": "firstField" },
                     class: "w-full px-3 py-2 border border-slate-300 rounded-lg text-sm"
  %td.px-4.py-2
    = select_tag :category,
                 options_for_select(CashMovementPolicy::DRAWER_CATEGORIES.map { |c| [ CashMovement.category_label(c), c ] }),
                 form: "drawer-form",
                 class: "w-full px-3 py-2 border border-slate-300 rounded-lg text-sm",
                 data: { action: "change->cash-live-row#toggleChannel" }
    = select_tag :channel,
                 options_for_select(CashMovement::CHANNEL_LABELS.map { |k, v| [ v, k ] }),
                 form: "drawer-form",
                 data: { "cash-live-row-target": "channel" },
                 class: "w-full mt-1 px-3 py-2 border border-slate-300 rounded-lg text-sm"
  %td.px-4.py-2{ colspan: 2 }
    = text_field_tag :amount, nil, form: "drawer-form",
                     placeholder: "0,00",
                     data: { controller: "currency-input",
                             action: "blur->currency-input#format focus->currency-input#unformat" },
                     class: "w-full px-3 py-2 border border-slate-300 rounded-lg text-sm text-right"
  %td.px-4.py-2.text-right
    = submit_tag "Guardar", form: "drawer-form",
                 class: "px-3 py-2 bg-slate-700 hover:bg-slate-800 text-white text-sm font-semibold rounded-lg"
  - if @error.present?
    %tr
      %td.px-4.py-2.text-sm.text-red-700{ colspan: 5 }= @error
```

The trailing error row is inside the same partial so a refused save shows its
reason without a separate stream target. Adjust the markup if a second `<tr>`
inside a replaced `<tr>` proves awkward — the constraint is that the message is
visible next to the row that produced it.

Add the form element and the live row to `_drawer_zone.html.haml`: the
`form_with` goes before the `%table`, and a `%tfoot` after the `%tbody` renders
`_live_row` when the day is open.

`app/views/web/cash/movements/create.turbo_stream.haml`:

```haml
- if @movement.present?
  = turbo_stream.append "drawer-rows" do
    = render "web/cash/movements/row", movement: @movement

= turbo_stream.replace "drawer-live-row" do
  = render "web/cash/movements/live_row", business_date: @business_date

= turbo_stream.replace "sales-by-channel" do
  = render "web/cash/days/sales_by_channel", day: @day
```

Three instructions from one action: the new row, a fresh live row, and the panel
recalculated. The panel target arrives in Task 7 — until then, drop that third
block and add it there.

- [ ] **Step 6: Write the Stimulus controller**

`app/javascript/controllers/cash_live_row_controller.js`:

```js
import { Controller } from "@hotwired/stimulus"

// Keeps the cashier's hands on the keyboard: the live row takes focus as soon
// as it appears, including the fresh one a save puts back.
export default class extends Controller {
  static targets = ["firstField", "channel"]

  connect() {
    this.toggleChannel()
    this.firstFieldTarget.focus()
  }

  toggleChannel() {
    const category = this.element.querySelector("select[name='category']").value
    this.channelTarget.hidden = category !== "sale"
  }
}
```

`connect()` runs both on page load and every time the stream replaces the row,
which is exactly the behaviour wanted and is why no explicit focus call is
needed in the stream.

- [ ] **Step 7: Run the tests**

Expected: PASS. Then verify by hand in the browser — this is the first Turbo
Stream in the project and the request spec cannot see whether the DOM actually
updated. Task 9 automates that.

- [ ] **Step 8: Rubocop**

**Commit message:**

```
feat(feat_28): add the drawer zone live row

- Enter saves and a fresh empty row takes its place with the focus back on
  the first field. A modal per row is slower than the spreadsheet it
  replaces.
- The cashier picks no arca: a sale lands wherever its channel implies and
  an expense loaded here came out of the till by definition.
- The sign comes from the category, so there is no minus to forget and no
  column to pick wrong.
- Amounts arrive in Argentine format and are normalised to a plain decimal
  before the service sees them; the service still refuses anything that is
  not a number rather than guessing.
- First Turbo Stream in the project: the response is a list of operations
  on element ids, and the row partial is the same one the full page render
  uses.
```

---

## Task 5: Sidebar entry

**Files:**
- Modify: `app/views/layouts/web/_sidebar.html.haml`

Add a Caja item, gated to `caja` and `admin`, following the existing idiom
exactly — the inline ternary on `controller_path`, the emoji span, the same
classes. Place it near Notas de pedido, which is the cashier's other daily
screen. Active state: `controller_path.start_with?('web/cash')`.

No spec; the sidebar has none today and this slice is not the place to introduce
one.

---

## Task 6: Correcting a row

R-8 makes movements of a *closed* day immutable. On an open day the cashier
corrects in place — that is the spreadsheet behaviour being preserved.

**Files:**
- Modify: `app/controllers/web/cash/movements_controller.rb`
- Create: `app/views/web/cash/movements/_edit_row.html.haml`
- Create: `app/views/web/cash/movements/update.turbo_stream.haml`
- Create: `app/views/web/cash/movements/destroy.turbo_stream.haml`
- Modify: `app/views/web/cash/movements/_row.html.haml`
- Test: append to `spec/requests/web/cash/movements_spec.rb`

**Interfaces:**
- Consumes: `CashMovementPolicy#update?`, which already refuses a sealed row.
- Produces: the edit/destroy stream shape.

`edit` replaces the row with a form row. `update` replaces it back with the
saved row. `destroy` removes it. All three re-render the channel panel.

Authorize with `authorize @movement` so the policy's sealed check applies. The
model raises `SealedMovementError` on a sealed row — the policy should stop it
first, but add a request spec proving a sealed movement cannot be updated or
destroyed through HTTP, and that the response is a redirect with a flash rather
than a 500.

Both actions must also refuse a closed day, since a day can be closed while the
screen is open in another tab.

**Commit message:**

```
feat(feat_28): let the cashier correct an open day's rows

- Editing in place is the spreadsheet gesture being preserved; the
  alternative is a correcting movement for every typo.
- Only while the day is open. Once a closing seals a row the policy
  refuses it, before the model's own guard has to.
- A day closed in another tab is refused too, rather than raising.
```

---

## Task 7: Ventas por canal

**Files:**
- Create: `app/views/web/cash/days/_sales_by_channel.html.haml`
- Modify: `show.html.haml`, `create.turbo_stream.haml`, `update.turbo_stream.haml`, `destroy.turbo_stream.haml`
- Test: append to `spec/requests/web/cash/days_spec.rb`

A right-hand panel, id `sales-by-channel`, titled **"Ventas por canal"** — the
title is load-bearing: the balance report groups by arca and shares words with
these channels, so without the label "Efectivo" means two different things on
two screens.

Contents: one line per channel with a sale that day, and the **monto a fajar**
(`day.amount_to_wrap`) in the footer. No accumulated balances — the cashier does
not see those.

Every stream that changes a movement replaces this panel.

**Commit message:**

```
feat(feat_28): add the sales-by-channel panel

- Groups the day's sales by channel and shows the amount to wrap, which is
  what the cashier needs at closing time.
- Titled by channel on purpose: the balance report groups by arca and
  reuses some of these words, so an unlabelled "Efectivo" would mean two
  different things on two screens.
- No accumulated balances here; those belong to the report.
```

---

## Task 8: A closed day is read-only

**Files:**
- Modify: `_drawer_zone.html.haml`, `_row.html.haml`
- Test: append to both request specs

No live row, no edit or delete affordances, and a visible "Día cerrado" marker.
The writes are already refused server-side by Tasks 4 and 6; this task removes
the affordances so the UI never offers what the server will reject.

Nothing in this slice creates a `DailyClosing` — the closing flow is 1d. The
specs create one with the factory.

**Commit message:**

```
feat(feat_28): make a closed day read-only in the day view

- The server already refuses the writes; this removes the affordances so
  the screen never offers what it would reject.
- Closings are still only created by the factory in specs. The closing
  flow itself is a later slice.
```

---

## Task 9: System spec for the live row

`spec/system/web/cash_live_row_spec.rb`, `driven_by :selenium_chrome_headless`,
`login_as(cashier, scope: :user)`.

This is the one part of the slice a request spec cannot cover: whether the DOM
actually updated. The project's own rule is that system specs exist for what
depends on Stimulus and nothing else, which is exactly this.

Cover: filling the live row and pressing Enter appends a row and leaves an empty
live row focused; the channel select hides when the category is not a sale; the
amount displays in Argentine format after blur.

Follow `spec/system/web/payments_on_account_item_swap_spec.rb` for the setup.

---

## Verification for the whole slice

```
docker compose exec -T web bundle exec rspec
docker compose exec -T web bundle exec rubocop
```

Then, by hand, on a day with a few rows already loaded:

1. Load a cash sale. The row appears, the live row empties, the focus is back on
   the description, and the channel panel grew.
2. Load a card sale. It lands on `bank` — check in the console — and the panel
   shows it under Tarjeta while the amount to wrap does not move.
3. Load an expense. It shows in the Egreso column and the amount to wrap drops.
4. Type `abc` in the amount. The row is refused with a message that says it is
   not a number, and nothing is written.
5. Type `1.500`. It is refused too — the trap 1a was fixed for.
6. Create a closing for the day in the console. Reload: no live row, no edit
   buttons, the read-only marker is visible.

---

## What 1b deliberately leaves out

So the next slice starts from a known place:

- **The arca zone.** Tramo 2, together with movements between arcas and partner
  movements. The day screen renders one zone.
- **Rows born from collections and the origin marker.** 1c. Nothing writes
  `source_payment_id` yet, so every row on this screen is manual.
- **Invoice type and number.** They arrive on `orders` in 1c, together with the
  deliberate exception that lets them stay editable on a sealed day.
- **The closing flow.** 1d. `DailyClosing` rows exist only if a spec or the
  console makes one.
- **The paper-number column.** It comes from the linked payment's order, which
  is 1c. A manually loaded sale has no paper number today.
- **The balance report and the movement history.** Tramo 3.
