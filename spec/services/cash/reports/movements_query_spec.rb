# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cash::Reports::MovementsQuery do
  let(:user) { create(:user, :caja) }
  let(:from) { Date.new(2026, 8, 1) }
  let(:to)   { Date.new(2026, 8, 31) }

  def movement(*traits, **attrs)
    create(:cash_movement, *traits, { user: user, business_date: from + 3 }.merge(attrs))
  end

  def result(**filters)
    described_class.call(from: from, to: to, **filters).to_a
  end

  describe "the range" do
    it "returns the rows inside it, newest first" do
      older = movement(business_date: from + 1, amount: 10_000)
      newer = movement(business_date: from + 9, amount: 20_000)

      expect(result).to eq([ newer, older ])
    end

    it "leaves out what falls outside it" do
      movement(business_date: from - 1, amount: 10_000)
      movement(business_date: to + 1, amount: 20_000)

      expect(result).to be_empty
    end
  end

  # The design decision this screen rests on: the filter is coarse so that a
  # filtered history still adds up to the report it explains.
  describe "the arca filter" do
    it "takes a reporting group and matches every fine arca in it" do
      drawer      = movement(account: "drawer", amount: 10_000)
      main_cash   = movement(account: "main_cash", category: "suppliers", channel: nil, amount: -1_000)
      change_fund = movement(account: "change_fund", category: "suppliers", channel: nil, amount: -2_000)
      movement(:card_sale)

      expect(result(group: "efectivo")).to match_array([ drawer, main_cash, change_fund ])
    end

    it "narrows to a group of a single arca" do
      card = movement(:card_sale)
      movement(account: "drawer", amount: 10_000)

      expect(result(group: "banco")).to eq([ card ])
    end

    it "ignores a group nobody offers instead of returning nothing" do
      drawer = movement(account: "drawer", amount: 10_000)

      expect(result(group: "no-existe")).to eq([ drawer ])
    end

    it "ignores a blank group" do
      drawer = movement(account: "drawer", amount: 10_000)

      expect(result(group: "")).to eq([ drawer ])
    end
  end

  # The one filter that reaches a compensation: it has no arca, so the arca
  # filter cannot find it, and its category is the same "Venta" every sale of
  # the month carries.
  describe "the channel filter" do
    it "narrows to one channel" do
      card = movement(:card_sale)
      movement(account: "drawer", amount: 10_000)

      expect(result(channel: "card")).to eq([ card ])
    end

    it "reaches the compensations of the period, which no arca filter can" do
      compensation = movement(:compensation_sale)
      movement(account: "drawer", amount: 10_000)
      movement(:card_sale)

      expect(result(channel: "compensation")).to eq([ compensation ])
    end

    it "ignores a channel nobody offers" do
      drawer = movement(account: "drawer", amount: 10_000)

      expect(result(channel: "no-existe")).to eq([ drawer ])
    end

    it "ignores a blank channel" do
      drawer = movement(account: "drawer", amount: 10_000)

      expect(result(channel: "")).to eq([ drawer ])
    end
  end

  describe "the category filter" do
    it "narrows to one category" do
      expense = movement(:store_expense)
      movement(account: "drawer", amount: 10_000)

      expect(result(category: "fixed_expense")).to eq([ expense ])
    end

    it "ignores a category nobody offers" do
      sale = movement(account: "drawer", amount: 10_000)

      expect(result(category: "no-existe")).to eq([ sale ])
    end
  end

  describe "the description search" do
    it "matches part of the description, whatever the case" do
      cromosol = movement(:supplier_payment, description: "Cromosol — pago parcial")
      movement(:store_expense, description: "Mundo de la Bolsa")

      expect(result(search: "cromo")).to eq([ cromosol ])
    end

    it "leaves a row with no description out of a search" do
      movement(account: "drawer", amount: 10_000, description: nil)

      expect(result(search: "cromo")).to be_empty
    end

    it "reads a wildcard as text, not as a pattern" do
      movement(:supplier_payment, description: "Cromosol")

      expect(result(search: "%")).to be_empty
    end
  end

  describe "the filters together" do
    it "narrows by all of them at once" do
      wanted = movement(account: "main_cash", category: "suppliers", channel: nil,
                        amount: -50_000, description: "Cromosol agosto")
      movement(account: "bank", category: "suppliers", channel: nil,
               amount: -50_000, description: "Cromosol agosto")
      movement(account: "main_cash", category: "fixed_expense", subcategory: "rent",
               channel: nil, amount: -50_000, description: "Cromosol agosto")
      movement(account: "main_cash", category: "suppliers", channel: nil,
               amount: -50_000, description: "Otro proveedor")
      movement(business_date: to + 1, account: "main_cash", category: "suppliers",
               channel: nil, amount: -50_000, description: "Cromosol agosto")

      expect(result(group: "efectivo", category: "suppliers", search: "cromosol")).to eq([ wanted ])
    end

    it "narrows a compensation by channel, category and search at once" do
      wanted = movement(:compensation_sale, description: "Cromosol compensación")
      movement(:compensation_sale, description: "Otro proveedor")
      movement(:card_sale, description: "Cromosol compensación")
      movement(business_date: to + 1, channel: "compensation", account: nil,
               supplier: create(:supplier), amount: 1_000, description: "Cromosol compensación")

      expect(result(channel: "compensation", category: "sale", search: "cromosol")).to eq([ wanted ])
    end
  end

  # Dollars never enter a peso sum, so the foot of the history carries two
  # figures at most: what the pesos add up to and what the dollars do.
  describe "the totals of a filter" do
    def totals(**filters)
      described_class.new(from: from, to: to, **filters).totals
    end

    it "adds the filtered rows up into entrada and salida, both positive" do
      movement(amount: 10_000)
      movement(amount: 20_000)
      movement(:store_expense, amount: -13_000)

      expect(totals.inflow).to eq(30_000)
      expect(totals.outflow).to eq(13_000)
    end

    it "adds up what the filter left, not the whole range" do
      movement(amount: 10_000)
      movement(:store_expense, amount: -13_000)

      expect(totals(category: "fixed_expense").inflow).to eq(0)
      expect(totals(category: "fixed_expense").outflow).to eq(13_000)
    end

    it "keeps dollars out of the peso figures" do
      movement(account: "usd", channel: "usd", amount: 500)
      movement(:store_expense, account: "usd", amount: -2_300)
      movement(amount: 10_000)

      expect(totals.inflow).to eq(10_000)
      expect(totals.outflow).to eq(0)
      expect(totals.usd_inflow).to eq(500)
      expect(totals.usd_outflow).to eq(2_300)
      expect(totals.usd?).to be(true)
    end

    it "reads zero when the filter matches nothing" do
      movement(amount: 10_000)

      expect(totals(category: "partner").inflow).to eq(0)
      expect(totals(category: "partner").outflow).to eq(0)
      expect(totals(category: "partner").usd?).to be(false)
    end
  end

  # The paper-number column reads through the source payment, the transfer
  # counterpart through the shared transfer_group_id and the supplier column
  # through the compensation's supplier, so a page of rows must cost the same
  # round trips as a single row.
  describe "the cost of a page" do
    it "costs five round trips, not one per row" do
      3.times { movement(:from_collection, account: "drawer", amount: 10_000) }
      movement(account: "drawer", amount: 20_000)
      movement(:compensation_sale)
      transfer_pair

      expect(round_trips).to eq(5)
    end

    it "costs the same however many rows the page holds" do
      3.times { movement(:from_collection, account: "drawer", amount: 10_000) }
      movement(:compensation_sale)
      transfer_pair
      few = round_trips

      12.times { movement(:from_collection, account: "drawer", amount: 10_000) }
      3.times { movement(:compensation_sale) }
      3.times { transfer_pair }

      expect(round_trips).to eq(few)
    end

    it "adds the whole filter up in two queries, however many rows it holds" do
      12.times { movement(amount: 10_000) }
      movement(:store_expense, account: "usd", amount: -2_300)

      expect(capture_sql { described_class.new(from: from, to: to).totals }.size).to eq(2)
    end

    def transfer_pair
      ::Cash::RecordTransfer.call(
        from: "drawer", to: "bank", amount: 5_000,
        business_date: from + 3, user: user
      ).record
    end

    def round_trips
      capture_sql do
        described_class.call(from: from, to: to).limit(50).each do |row|
          row.paper_numbers
          row.transfer_counterpart_label
          row.supplier&.name
        end
      end.size
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
