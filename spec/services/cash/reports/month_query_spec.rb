# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cash::Reports::MonthQuery do
  let(:user)  { create(:user, :caja) }
  let(:month) { Date.new(2026, 8, 17) }

  subject(:query) { described_class.new(month: month) }

  around do |example|
    travel_to(Date.new(2026, 9, 19)) { example.run }
  end

  def movement(*traits, **attrs)
    create(:cash_movement, *traits, { user: user, business_date: Date.new(2026, 8, 10) }.merge(attrs))
  end

  def fixed_expense(subcategory, amount, **attrs)
    movement(:store_expense, subcategory: subcategory, amount: amount, **attrs)
  end

  def sold_in(group)
    query.sold_by_group.find { |line| line.key == group }.amount
  end

  describe "sold" do
    it "reads zero for a month without sales" do
      expect(query.sold_total).to eq(0)
      expect(query.sold_by_group.map(&:amount)).to eq([ 0, 0, 0 ])
      expect(query.sold_compensation).to eq(0)
      expect(query.sold_usd).to eq(0)
    end

    it "gives one line per peso reporting group, in the report's order" do
      expect(query.sold_by_group.map(&:label)).to eq([ "Efectivo", "Banco", "Mercado Pago" ])
    end

    it "counts every sale of the month, whatever arca it reached" do
      movement(account: "drawer", channel: "cash", amount: 299_700)
      movement(:card_sale)
      movement(account: "bank", channel: "transfer", amount: 10_000)
      movement(account: "mercado_pago", channel: "mercado_pago", amount: 110_000)

      expect(sold_in("efectivo")).to eq(299_700)
      expect(sold_in("banco")).to eq(64_700)
      expect(sold_in("mercado_pago")).to eq(110_000)
      expect(query.sold_total).to eq(474_400)
    end

    it "counts sales on the first and last day of the month and none outside it" do
      movement(amount: 1_000, business_date: Date.new(2026, 8, 1))
      movement(amount: 2_000, business_date: Date.new(2026, 8, 31))
      movement(amount: 4_000, business_date: Date.new(2026, 7, 31))
      movement(amount: 8_000, business_date: Date.new(2026, 9, 1))

      expect(query.sold_total).to eq(3_000)
    end

    it "adds a compensation sale to the peso total and reports it on its own" do
      movement(amount: 100_000)
      movement(:compensation_sale, amount: 661_188)

      expect(query.sold_compensation).to eq(661_188)
      expect(query.sold_total).to eq(761_188)
    end

    it "reports a dollar sale apart and never adds it to the peso total" do
      movement(amount: 100_000)
      movement(account: "usd", channel: "usd", amount: 500)

      expect(query.sold_usd).to eq(500)
      expect(query.sold_total).to eq(100_000)
    end

    it "lets a reversed collection reduce what was sold" do
      movement(:from_collection, amount: 100_000)
      movement(:from_collection, amount: -30_000)

      expect(sold_in("efectivo")).to eq(70_000)
      expect(query.sold_total).to eq(70_000)
    end

    it "ignores every movement that is not a sale" do
      movement(:supplier_payment)
      movement(:store_expense)
      movement(:opening_balance)

      expect(query.sold_total).to eq(0)
    end
  end

  describe "fixed expenses" do
    it "reads zero and lists nothing for a month without fixed expenses" do
      expect(query.fixed_total).to eq(0)
      expect(query.fixed_expenses).to be_empty
      expect(query.fixed_usd).to eq(0)
    end

    it "reads what was spent as a positive figure" do
      fixed_expense("store_expenses", -13_000)

      expect(query.fixed_total).to eq(13_000)
    end

    it "lists every fixed expense of the month, newest first" do
      first  = fixed_expense("salaries", -900_000, account: "bank", business_date: Date.new(2026, 8, 5))
      second = fixed_expense("salaries", -100_000, account: "main_cash", business_date: Date.new(2026, 8, 5))
      later  = fixed_expense("utilities", -45_000, account: "mercado_pago", business_date: Date.new(2026, 8, 12))

      expect(query.fixed_expenses).to eq([ later, second, first ])
      expect(query.fixed_total).to eq(1_045_000)
    end

    it "lists a fixed expense paid in dollars but never adds it to the peso total" do
      dollars = fixed_expense("rent", -2_300, account: "usd")
      pesos   = fixed_expense("salaries", -900_000, account: "bank")

      expect(query.fixed_expenses).to contain_exactly(dollars, pesos)
      expect(query.fixed_usd).to eq(2_300)
      expect(query.fixed_total).to eq(900_000)
    end

    it "ignores fixed expenses outside the month and movements of other categories" do
      fixed_expense("rent", -500_000, business_date: Date.new(2026, 7, 31))
      movement(:supplier_payment)
      movement(amount: 100_000)

      expect(query.fixed_total).to eq(0)
      expect(query.fixed_expenses).to be_empty
    end
  end

  it "reads the whole month in two queries: the sales it sums, the fixed expenses it lists" do
    movement(account: "drawer", channel: "cash", amount: 299_700)
    movement(:card_sale)
    movement(account: "mercado_pago", channel: "mercado_pago", amount: 110_000)
    movement(account: "usd", channel: "usd", amount: 500)
    movement(:compensation_sale, amount: 661_188)
    movement(:from_collection, amount: 100_000)
    movement(:from_collection, amount: -30_000)
    fixed_expense("salaries", -900_000, account: "bank")
    fixed_expense("store_expenses", -13_000)
    fixed_expense("rent", -2_300, account: "usd")
    movement(:supplier_payment)
    movement(amount: 9_999, business_date: Date.new(2026, 9, 1))

    figures = nil
    queries = capture_sql do
      figures = [ query.sold_total, query.sold_by_group.map(&:amount), query.sold_compensation,
                  query.sold_usd, query.fixed_total, query.fixed_expenses.map { |row| row.amount.abs },
                  query.fixed_usd ]
    end

    expect(queries.size).to eq(2)
    expect(figures).to eq([ 1_195_588, [ 369_700, 54_700, 110_000 ], 661_188,
                            500, 913_000, [ 2_300, 13_000, 900_000 ], 2_300 ])
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
