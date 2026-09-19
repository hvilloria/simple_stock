# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cash::Reports::HoldingsQuery do
  let(:user) { create(:user, :caja) }
  let(:on)   { Date.new(2026, 9, 10) }

  subject(:query) { described_class.new(on: on) }

  around do |example|
    travel_to(Date.new(2026, 9, 19)) { example.run }
  end

  def movement(*traits, **attrs)
    create(:cash_movement, *traits, { user: user, business_date: on }.merge(attrs))
  end

  def amount_of(group)
    query.holdings.find { |row| row.group == group }.amount
  end

  describe "#holdings" do
    it "returns one row per reporting group, in the report's order" do
      expect(query.holdings.map(&:group)).to eq(%w[efectivo banco mercado_pago usd])
    end

    it "labels every row for the screen, the dollars by name" do
      expect(query.holdings.map(&:label)).to eq([ "Efectivo", "Banco", "Mercado Pago", "Dólares" ])
    end

    it "reads zero for a group that has never moved" do
      expect(query.holdings.map(&:amount)).to eq([ 0, 0, 0, 0 ])
    end

    it "sums every arca of the group, whatever the category" do
      movement(account: "drawer", amount: 100_000)
      movement(:opening_balance, account: "main_cash", amount: 500_000, business_date: on - 30)
      movement(:store_expense, account: "change_fund", amount: -13_000)

      expect(amount_of("efectivo")).to eq(587_000)
    end

    it "counts a movement dated on the date and leaves out one dated after it" do
      movement(account: "bank", channel: "card", amount: 54_700)
      movement(account: "bank", channel: "card", amount: 11_111, business_date: on + 1)

      expect(amount_of("banco")).to eq(54_700)
    end

    it "keeps each group to its own arcas" do
      movement(account: "mercado_pago", channel: "mercado_pago", amount: 110_000)
      movement(account: "usd", channel: "usd", amount: 500)

      expect(amount_of("mercado_pago")).to eq(110_000)
      expect(amount_of("usd")).to eq(500)
      expect(amount_of("efectivo")).to eq(0)
    end

    it "leaves out a compensation sale, which reaches no arca" do
      movement(:compensation_sale, amount: 661_188)

      expect(query.holdings.sum(&:amount)).to eq(0)
    end

    it "has no total: dollars are never added to pesos" do
      expect(query).not_to respond_to(:total)
    end

    it "reads all four groups in a single query" do
      movement(account: "drawer", amount: 100_000)
      movement(account: "main_cash", category: "suppliers", channel: nil, amount: -20_000)
      movement(:card_sale)
      movement(account: "mercado_pago", channel: "mercado_pago", amount: 110_000)
      movement(account: "usd", channel: "usd", amount: 500)
      movement(:compensation_sale)
      movement(account: "drawer", amount: 9_999, business_date: on + 1)

      holdings = nil
      queries = capture_sql { holdings = query.holdings }

      expect(queries.size).to eq(1)
      expect(holdings.map(&:amount)).to eq([ 80_000, 54_700, 110_000, 500 ])
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
