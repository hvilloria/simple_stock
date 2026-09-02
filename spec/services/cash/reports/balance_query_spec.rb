# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cash::Reports::BalanceQuery do
  let(:user) { create(:user, :caja) }
  let(:from) { Date.new(2026, 8, 1) }
  let(:to)   { Date.new(2026, 8, 31) }

  subject(:query) { described_class.new(from: from, to: to) }

  def movement(*traits, **attrs)
    create(:cash_movement, *traits, { user: user, business_date: from + 3 }.merge(attrs))
  end

  def row_for(group)
    query.rows.find { |row| row.group == group }
  end

  describe "#rows" do
    it "returns one row per reporting group, USD standing alone" do
      expect(query.rows.map(&:group)).to eq(%w[efectivo banco mercado_pago usd])
    end

    it "labels every row for the screen" do
      expect(query.rows.map(&:label)).to eq([ "Efectivo", "Banco", "Mercado Pago", "USD" ])
    end

    it "has no grand total: the query answers with rows and nothing else" do
      expect(query).not_to respond_to(:total)
    end
  end

  describe "the opening figure" do
    it "is everything the group held before the range, whatever the category" do
      movement(business_date: from - 1, amount: 100_000, account: "drawer")
      movement(business_date: from - 5, amount: -20_000, account: "main_cash",
               category: "suppliers", channel: nil)

      expect(row_for("efectivo").opening).to eq(80_000)
    end

    it "leaves out another group's history" do
      movement(business_date: from - 1, amount: 100_000, account: "bank", channel: "card")

      expect(row_for("efectivo").opening).to eq(0)
    end

    # The startup rows exist on exactly one date. Inside the range they belong
    # to no category column, so they are read as the starting position.
    it "adds an opening_balance row that falls inside the range" do
      movement(business_date: from - 1, amount: 100_000, account: "drawer")
      movement(:opening_balance, business_date: from + 2, amount: 500_000, account: "main_cash")

      expect(row_for("efectivo").opening).to eq(600_000)
    end
  end

  describe "the closing figure" do
    it "is everything the group holds up to the end of the range" do
      movement(business_date: from - 1, amount: 100_000, account: "drawer")
      movement(business_date: from + 4, amount: 30_000, account: "drawer")
      movement(business_date: to + 1, amount: 999_999, account: "drawer")

      expect(row_for("efectivo").closing).to eq(130_000)
    end
  end

  describe "the category columns" do
    it "names each column after its category and sums only rows inside the range" do
      movement(amount: 300_000, account: "drawer", channel: "cash")
      movement(amount: -150_000, account: "main_cash", category: "suppliers", channel: nil)
      movement(:store_expense, amount: -13_000, account: "drawer")
      movement(amount: -80_000, account: "main_cash", category: "partner", channel: nil)
      movement(:transfer_leg, amount: -50_000, account: "main_cash")
      movement(amount: -1_200, account: "drawer", category: "cash_discrepancy", channel: nil)
      movement(business_date: to + 1, amount: 777_000, account: "drawer", channel: "cash")

      row = row_for("efectivo")

      expect(row.sales).to eq(300_000)
      expect(row.suppliers).to eq(-150_000)
      expect(row.fixed_expenses).to eq(-13_000)
      expect(row.partner).to eq(-80_000)
      expect(row.transfers).to eq(-50_000)
      expect(row.discrepancies).to eq(-1_200)
    end

    it "reads a sale by the arca it landed in, not by the group that sold it" do
      movement(:card_sale, amount: 54_700)

      expect(row_for("banco").sales).to eq(54_700)
      expect(row_for("efectivo").sales).to eq(0)
    end

    it "leaves a compensation sale out of every group: it reaches no arca" do
      movement(:compensation_sale, amount: 661_188)

      expect(query.rows.map(&:sales)).to all(eq(0))
    end

    it "reports zero for a group with no movements at all" do
      row = row_for("usd")

      expect([ row.opening, row.sales, row.closing ]).to all(eq(0))
    end
  end

  # The reason this query exists. A row that does not reconcile is a bug, not
  # something to audit by hand.
  describe "the reconciliation invariant" do
    let(:accounts_by_group) do
      { "efectivo" => "main_cash", "banco" => "bank", "mercado_pago" => "mercado_pago", "usd" => "usd" }
    end

    before do
      accounts_by_group.each_value.with_index do |account, i|
        movement(business_date: from - 10, amount: 1_000_000 + i, account: account,
                 category: "opening_balance", channel: nil)
        movement(business_date: from + 1, amount: 200_000 + i, account: account,
                 category: "sale", channel: account == "main_cash" ? "cash" : "transfer")
        movement(business_date: from + 2, amount: -30_000 - i, account: account,
                 category: "suppliers", channel: nil)
        movement(business_date: from + 3, amount: -11_000 - i, account: account,
                 category: "fixed_expense", subcategory: "utilities", channel: nil)
        movement(business_date: from + 4, amount: -7_000 - i, account: account,
                 category: "partner", channel: nil)
        movement(business_date: from + 5, amount: -250 - i, account: account,
                 category: "cash_discrepancy", channel: nil)
        # A startup row inside the range: the case that leaves a figure in no
        # column unless the opening figure absorbs it.
        movement(business_date: from + 6, amount: 5_000 + i, account: account,
                 category: "opening_balance", channel: nil)
      end

      # The everyday transfer: two legs landing in DIFFERENT groups.
      group_id = SecureRandom.uuid
      movement(business_date: from + 7, amount: -400_000, account: "main_cash",
               category: "internal_transfer", channel: nil, transfer_group_id: group_id)
      movement(business_date: from + 7, amount: 400_000, account: "bank",
               category: "internal_transfer", channel: nil, transfer_group_id: group_id)

      # A same-group transfer: both legs cancel inside Efectivo.
      inner_id = SecureRandom.uuid
      movement(business_date: from + 8, amount: -60_000, account: "main_cash",
               category: "internal_transfer", channel: nil, transfer_group_id: inner_id)
      movement(business_date: from + 8, amount: 60_000, account: "change_fund",
               category: "internal_transfer", channel: nil, transfer_group_id: inner_id)
    end

    it "reconciles every row: opening plus every column equals closing" do
      query.rows.each do |row|
        columns = row.sales + row.suppliers + row.fixed_expenses +
                  row.partner + row.transfers + row.discrepancies

        expect(row.opening + columns).to eq(row.closing),
          "#{row.group} does not reconcile: #{row.opening} + #{columns} != #{row.closing}"
      end
    end

    it "moves the transfer between groups without inventing or losing money" do
      expect(row_for("efectivo").transfers).to eq(-400_000)
      expect(row_for("banco").transfers).to eq(400_000)
    end

    it "keeps USD apart instead of folding it into a total" do
      expect(row_for("usd").closing).to eq(row_for("usd").opening + row_for("usd").sales +
        row_for("usd").suppliers + row_for("usd").fixed_expenses + row_for("usd").partner +
        row_for("usd").transfers + row_for("usd").discrepancies)
    end

    # The project has no query-count tooling, so this is the standing guard:
    # four groups times eight figures must not become thirty-two round trips.
    it "costs two round trips, not one per figure" do
      queries = capture_sql { query.rows.each { |row| row.closing } }

      expect(queries.size).to eq(2)
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
end
