# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cash::Reports::FixedExpenseBreakdownQuery do
  let(:user) { create(:user, :caja) }
  let(:from) { Date.new(2026, 8, 1) }
  let(:to)   { Date.new(2026, 8, 31) }

  subject(:query) { described_class.new(from: from, to: to) }

  def movement(**attrs)
    create(:cash_movement, { user: user, business_date: from + 3, category: "fixed_expense",
                             channel: nil, account: "main_cash" }.merge(attrs))
  end

  def row_for(subcategory)
    query.rows.find { |row| row.subcategory == subcategory }
  end

  describe "#rows" do
    it "returns the six subcategories in a fixed order, so the shape reads the same every month" do
      expect(query.rows.map(&:subcategory))
        .to eq(%w[rent salaries social_charges taxes utilities store_expenses])
    end

    it "labels every row for the screen" do
      expect(query.rows.map(&:label))
        .to eq([ "Alquiler", "Salarios", "Cargas sociales", "Impuestos", "Servicios", "Gastos de local" ])
    end

    it "reads at the reporting group, the same grain as the row it expands" do
      expect(query.groups).to eq(CashMovement::REPORTING_GROUPS.keys)
    end

    it "folds the fine arcas of a group into the one figure the report shows" do
      movement(subcategory: "rent", account: "main_cash", amount: -400_000)
      movement(subcategory: "rent", account: "drawer",    amount: -50_000)
      movement(subcategory: "rent", account: "bank",      amount: -120_000)

      expect(row_for("rent").amount_for("efectivo")).to eq(-450_000)
      expect(row_for("rent").amount_for("banco")).to eq(-120_000)
    end

    it "keeps each subcategory apart" do
      movement(subcategory: "salaries", amount: -900_000)
      movement(subcategory: "taxes",    amount: -75_000)

      expect(row_for("salaries").amount_for("efectivo")).to eq(-900_000)
      expect(row_for("taxes").amount_for("efectivo")).to eq(-75_000)
      expect(row_for("utilities").amount_for("efectivo")).to eq(0)
    end

    it "reports zero for a subcategory and arca with no movements at all" do
      expect(query.rows.flat_map { |row| query.groups.map { |g| row.amount_for(g) } }).to all(eq(0))
    end

    it "sums only what falls inside the range" do
      movement(subcategory: "utilities", business_date: from - 1, amount: -11_000)
      movement(subcategory: "utilities", business_date: to + 1,   amount: -12_000)
      movement(subcategory: "utilities", business_date: to,       amount: -13_000)

      expect(row_for("utilities").amount_for("efectivo")).to eq(-13_000)
    end

    it "leaves out every category that is not a fixed expense" do
      movement(category: "suppliers", subcategory: nil, amount: -150_000)
      movement(category: "partner", subcategory: nil, amount: -80_000)

      expect(query.totals_by_group.values).to all(eq(0))
    end

    it "costs one round trip, not one per subcategory" do
      queries = capture_sql { query.rows.each { |row| row.amount_for("efectivo") } }

      expect(queries.size).to eq(1)
    end
  end

  # The reason the breakdown is a query of its own: it aggregates the same rows
  # independently of the balance report, so the two figures can genuinely
  # disagree. Derived from the column it expands, this check could never fail.
  describe "the breakdown invariant" do
    let(:balance_rows) { Cash::Reports::BalanceQuery.call(from: from, to: to) }

    before do
      # Several subcategories across several arcas, spanning three groups.
      movement(subcategory: "rent",           account: "main_cash",    amount: -400_000)
      movement(subcategory: "rent",           account: "bank",         amount: -150_000)
      movement(subcategory: "salaries",       account: "main_cash",    amount: -1_250_000)
      movement(subcategory: "salaries",       account: "bank",         amount: -830_000)
      movement(subcategory: "social_charges", account: "bank",         amount: -212_500)
      movement(subcategory: "taxes",          account: "bank",         amount: -96_300)
      movement(subcategory: "taxes",          account: "mercado_pago", amount: -14_200)
      movement(subcategory: "utilities",      account: "drawer",       amount: -37_400)
      movement(subcategory: "utilities",      account: "change_fund",  amount: -8_900)
      movement(subcategory: "store_expenses", account: "drawer",       amount: -13_000)
      movement(subcategory: "store_expenses", account: "mercado_pago", amount: -6_750)

      # Noise the breakdown must not pick up.
      movement(category: "sale", subcategory: nil, channel: "cash", account: "drawer", amount: 900_000)
      movement(category: "suppliers", subcategory: nil, amount: -300_000)
      movement(subcategory: "rent", business_date: to + 1, account: "main_cash", amount: -400_000)
    end

    it "totals, per group, exactly the fixed-expenses column it expands" do
      balance_rows.each do |balance_row|
        expect(query.totals_by_group.fetch(balance_row.group)).to eq(balance_row.fixed_expenses),
          "#{balance_row.group}: breakdown #{query.totals_by_group.fetch(balance_row.group)} " \
          "!= column #{balance_row.fixed_expenses}"
      end
    end

    it "covers every group the report has a row for" do
      expect(query.totals_by_group.keys).to eq(balance_rows.map(&:group))
    end
  end

  def capture_sql
    queries = []
    subscriber = lambda do |*, payload|
      next if payload[:cached] || %w[SCHEMA TRANSACTION].include?(payload[:name])
      queries << payload[:sql]
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") { yield }
    queries
  end
end
