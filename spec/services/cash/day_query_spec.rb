# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cash::DayQuery do
  let(:date) { Date.new(2026, 8, 3) }

  subject(:query) { described_class.new(date) }

  describe "#entries" do
    def transfer_pair(from:, to:, amount:)
      group = SecureRandom.uuid
      outflow = create(:cash_movement, :transfer_leg, business_date: date, transfer_group_id: group,
                                                      account: from, amount: -amount)
      inflow  = create(:cash_movement, :transfer_leg, business_date: date, transfer_group_id: group,
                                                      account: to, amount: amount)
      [ outflow, inflow ]
    end

    it "accounts for every movement of the day exactly once" do
      cash_sale      = create(:cash_movement, business_date: date, channel: "cash", account: "drawer")
      card_sale      = create(:cash_movement, :card_sale, business_date: date)
      usd_sale       = create(:cash_movement, business_date: date, channel: "usd", account: "usd", amount: 50)
      compensation   = create(:cash_movement, :compensation_sale, business_date: date)
      till_expense   = create(:cash_movement, :store_expense, business_date: date)
      bundle_expense = create(:cash_movement, :store_expense, business_date: date, account: "main_cash")
      supplier       = create(:cash_movement, :supplier_payment, business_date: date)
      withdrawal     = create(:cash_movement, business_date: date, category: "partner", channel: nil,
                                              account: "main_cash", amount: -100_000)
      outflow, inflow = transfer_pair(from: "main_cash", to: "bank", amount: 50_000)

      movements = query.entries.flat_map(&:movements)

      expect(movements).to contain_exactly(
        cash_sale, card_sale, usd_sale, compensation, till_expense, bundle_expense,
        supplier, withdrawal, outflow, inflow
      )
      expect(movements.size).to eq(CashMovement.on(date).count)
      expect(query.entries.size).to eq(9)
    end

    it "folds a transfer's two legs into one :move entry, outflow leg first" do
      outflow, inflow = transfer_pair(from: "mercado_pago", to: "bank", amount: 20_000)

      entry = query.entries.sole

      expect(entry.kind).to eq(:move)
      expect(entry.movements).to eq([ outflow, inflow ])
      expect(entry.movement).to eq(outflow)
      expect(entry.from).to eq("mercado_pago")
      expect(entry.to).to eq("bank")
      expect(entry.amount).to eq(20_000)
    end

    it "orders the legs outflow first even when the inflow was loaded first" do
      group = SecureRandom.uuid
      inflow  = create(:cash_movement, :transfer_leg, business_date: date, transfer_group_id: group,
                                                      account: "bank", amount: 5_000)
      outflow = create(:cash_movement, :transfer_leg, business_date: date, transfer_group_id: group,
                                                      account: "main_cash", amount: -5_000)

      expect(query.entries.sole.movements).to eq([ outflow, inflow ])
    end

    it "keeps load order, with a transfer where its first leg sits" do
      first    = create(:cash_movement, business_date: date, description: "primera")
      outflow, = transfer_pair(from: "main_cash", to: "bank", amount: 1_000)
      last     = create(:cash_movement, :store_expense, business_date: date, description: "última")

      expect(query.entries.map(&:movement)).to eq([ first, outflow, last ])
    end

    it "reads the kind from the stored sign, not the category" do
      sale = create(:cash_movement, business_date: date)
      expense = create(:cash_movement, :store_expense, business_date: date)
      contribution = create(:cash_movement, business_date: date, category: "partner", channel: nil,
                                            account: "main_cash", amount: 30_000)
      # The model allows it; the query must not second-guess the stored sign.
      odd_sale = create(:cash_movement, business_date: date, amount: -1_000)

      kinds = query.entries.to_h { |entry| [ entry.movement, entry.kind ] }

      expect(kinds).to eq(sale => :in, expense => :out, contribution => :in, odd_sale => :out)
    end

    it "counts an entry in the drawer when any of its movements is the drawer" do
      drawer_sale = create(:cash_movement, business_date: date)
      card_sale   = create(:cash_movement, :card_sale, business_date: date)
      compensation = create(:cash_movement, :compensation_sale, business_date: date)
      to_drawer, = transfer_pair(from: "change_fund", to: "drawer", amount: 10_000)
      between_bundles, = transfer_pair(from: "main_cash", to: "bank", amount: 10_000)

      counts = query.entries.to_h { |entry| [ entry.movement, entry.counts_in_drawer ] }

      expect(counts).to eq(
        drawer_sale => true, card_sale => false, compensation => false,
        to_drawer => true, between_bundles => false
      )
    end

    it "leaves out another day" do
      create(:cash_movement, business_date: date + 1)

      expect(query.entries).to be_empty
    end

    it "reads every entry's paper numbers without firing a single extra query" do
      customer = create(:customer, :with_credit)
      3.times do |i|
        payment = create(:payment, customer: customer, amount: 100)
        order = create(:order, customer: customer, paper_number: "020#{i}", total_amount: 100)
        create(:payment_allocation, payment: payment, order: order, amount: 100)
        create(:cash_movement, business_date: date, source_payment: payment)
      end
      transfer_pair(from: "main_cash", to: "bank", amount: 1_000)

      entries = query.entries

      queries = capture_sql { entries.flat_map(&:movements).flat_map(&:paper_numbers) }

      expect(entries.size).to eq(4)
      expect(queries).to be_empty
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

  describe "#future?" do
    it "is true while the date has not come yet" do
      travel_to date - 1 do
        expect(query).to be_future
      end
    end

    it "is false on the date itself" do
      travel_to date do
        expect(query).not_to be_future
      end
    end

    it "is false once the date has passed" do
      travel_to date + 1 do
        expect(query).not_to be_future
      end
    end
  end

  describe "#uncollected_notes_count" do
    it "counts only the date's pending sale notes" do
      create(:order, :pending, sale_date: date)
      create(:order, :pending, sale_date: date + 1)
      create(:order, sale_date: date)

      expect(query.uncollected_notes_count).to eq(1)
    end
  end

  describe "#sales_without_invoice_type_count" do
    it "counts the date's active sales with no invoice type, ignoring cancelled ones" do
      create(:order, sale_date: date, invoice_type: nil)
      create(:order, :cancelled, sale_date: date, invoice_type: nil)
      create(:order, :invoice_b, sale_date: date)

      expect(query.sales_without_invoice_type_count).to eq(1)
    end
  end

  describe "digital totals" do
    it "reads the Payway total from card sales and Mercado Pago from its own channel" do
      create(:cash_movement, :card_sale, business_date: date, amount: 54_700)
      create(:cash_movement, business_date: date, channel: "qr", account: "bank", amount: 9_000)
      create(:cash_movement, business_date: date, channel: "mercado_pago", account: "mercado_pago", amount: 21_300)

      expect(query.payway_recorded_total).to eq(54_700)
      expect(query.mercado_pago_recorded_total).to eq(21_300)
    end

    it "is zero when the date has no such sales" do
      expect(query.payway_recorded_total).to eq(0)
      expect(query.mercado_pago_recorded_total).to eq(0)
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
