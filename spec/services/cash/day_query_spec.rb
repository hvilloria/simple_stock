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

    # The project has no query-count tooling, so this is the standing N+1 guard
    # for the paper-number column: it pins that the payment and its orders come
    # back already loaded, and fails if the `includes` is ever dropped.
    context "the payment chain behind an automatic row" do
      let(:customer) { create(:customer, :with_credit) }

      before do
        3.times do |i|
          payment = create(:payment, customer: customer, amount: 100)
          order = create(:order, customer: customer, paper_number: "010#{i}", total_amount: 100)
          create(:payment_allocation, payment: payment, order: order, amount: 100)
          create(:cash_movement, business_date: date, source_payment: payment)
        end
      end

      it "comes back already loaded, so no row walks the association itself" do
        movements = query.drawer_movements.to_a

        expect(movements.size).to eq(3)
        movements.each do |movement|
          expect(movement.association(:source_payment)).to be_loaded
          expect(movement.source_payment.association(:orders)).to be_loaded
        end
      end

      it "reads every row's paper numbers without firing a single extra query" do
        movements = query.drawer_movements.to_a

        queries = capture_sql { movements.flat_map(&:paper_numbers) }

        expect(queries).to be_empty
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
