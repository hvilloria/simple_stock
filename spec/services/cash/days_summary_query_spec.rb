# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cash::DaysSummaryQuery do
  let(:date) { Date.new(2026, 8, 10) }

  def row_for(day)
    described_class.new([ day ]).rows.first
  end

  describe ".dates" do
    it "includes today with no activity" do
      expect(described_class.dates(today: date)).to eq([ date ])
    end

    it "lists movement and closing dates newest first, once each" do
      create(:cash_movement, business_date: date - 3)
      create(:cash_movement, business_date: date - 1)
      create(:cash_movement, :card_sale, business_date: date - 1)
      create(:daily_closing, business_date: date - 2)

      expect(described_class.dates(today: date)).to eq([ date, date - 1, date - 2, date - 3 ])
    end

    it "skips days without movements or closing" do
      create(:cash_movement, business_date: date - 5)

      expect(described_class.dates(today: date)).not_to include(date - 4)
    end
  end

  describe "#rows" do
    it "keeps the order of the given dates" do
      rows = described_class.new([ date, date - 1 ]).rows

      expect(rows.map(&:date)).to eq([ date, date - 1 ])
    end

    it "matches DayQuery#sales_by_group for the day" do
      create(:cash_movement, business_date: date, channel: "cash", account: "drawer", amount: 10_000)
      create(:cash_movement, :card_sale, business_date: date)
      create(:cash_movement, business_date: date, channel: "qr", account: "bank", amount: 7_000)
      create(:cash_movement, business_date: date, channel: "transfer", account: "bank", amount: 3_000)
      create(:cash_movement, business_date: date, channel: "mercado_pago", account: "mercado_pago", amount: 20_000)
      create(:cash_movement, business_date: date, channel: "usd", account: "usd", amount: 50)
      create(:cash_movement, :compensation_sale, business_date: date)
      create(:cash_movement, :store_expense, business_date: date)

      groups = row_for(date).sales_by_group
      expected = Cash::DayQuery.new(date).sales_by_group

      expect(groups.slice(*Cash::DayQuery::PESO_SALE_GROUPS))
        .to eq(expected.slice(*Cash::DayQuery::PESO_SALE_GROUPS))
      expect(groups["efectivo"]).to eq(10_000)
      expect(groups["banco"]).to eq(54_700 + 7_000 + 3_000)
      expect(groups["mercado_pago"]).to eq(20_000)
    end

    it "reads zero for a group without sales" do
      expect(row_for(date).sales_by_group["banco"]).to eq(0)
    end

    it "counts units of notes settled that day" do
      settled = create(:order, settled_on: date)
      create(:order_item, order: settled, quantity: 3)
      create(:order_item, order: settled, quantity: 1)
      cancelled = create(:order, :cancelled, settled_on: date)
      create(:order_item, order: cancelled, quantity: 5)
      open_note = create(:order, :pending, settled_on: nil)
      create(:order_item, order: open_note, quantity: 7)

      expect(row_for(date).units_sold).to eq(4)
    end

    it "counts an installment note on its settling day only" do
      note = create(:order, :credit_order, settled_on: date)
      create(:order_item, order: note, quantity: 2)

      rows = described_class.new([ date, date - 1 ]).rows

      expect(rows.map(&:units_sold)).to eq([ 2, 0 ])
    end

    it "drops a note reopened by a void" do
      note = create(:order, settled_on: date)
      create(:order_item, order: note, quantity: 2)
      note.update!(status: "pending", settled_on: nil)

      expect(row_for(date).units_sold).to eq(0)
    end

    it "reads the counted cash of the closing" do
      create(:daily_closing, business_date: date, counted_cash: 23_000)

      row = row_for(date)

      expect(row.counted_cash).to eq(23_000)
      expect(row).to be_closed
    end

    it "leaves an open day without counted cash" do
      row = row_for(date)

      expect(row.counted_cash).to be_nil
      expect(row).not_to be_closed
    end

    it "keeps a zero closing as closed" do
      create(:daily_closing, business_date: date, counted_cash: 0)

      expect(row_for(date)).to be_closed
    end

    it "marks today" do
      expect(row_for(Date.current)).to be_today
      expect(row_for(Date.current - 1)).not_to be_today
    end

    it "runs a fixed number of queries" do
      many = (0...15).map { |n| date - n }
      many.each { |day| create(:cash_movement, business_date: day) }

      count_queries = lambda do |dates|
        count = 0
        counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" }
        ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
          described_class.new(dates).rows
        end
        count
      end

      expect(count_queries.call(many)).to eq(count_queries.call([ date ]))
    end
  end
end
