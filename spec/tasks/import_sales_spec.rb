# frozen_string_literal: true

require "rails_helper"
require "rake"

# Integration spec for the historical sales import (lib/tasks/import_sales.rake).
# Uses the real sales_to_import.json file at the project root and evaluates the
# result produced by the import_sales:run task.
#
# In production the 3 salespeople already exist; here we create them to reproduce
# that state.
RSpec.describe "import_sales:run", type: :task do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("import_sales:run")
  end

  # --- file data (source of truth for the expected counts) ---
  let(:data)     { JSON.parse(File.read(Rails.root.join("sales_to_import.json"))) }
  let(:tickets)  { data.group_by { |r| r["ticket_number"] } }
  let(:expected_orders)   { tickets.size }
  let(:expected_products) { data.map { |r| r["oem_code"] }.uniq.size }

  before do
    create(:user, name: "Ariel",   last_name: "Almaraz",  email: "ariel.almaraz@gentedelsol.com")
    create(:user, name: "Alfredo", last_name: "Baysse",   email: "alfredo@gentedelsol.com")
    create(:user, name: "Yoward",  last_name: "Villoria", email: "yoward.villoria@gentedelsol.com")
  end

  # Invokes the task while silencing its output (it does a lot of puts).
  def run_import
    original = $stdout
    $stdout = StringIO.new
    Rake::Task["import_sales:run"].reenable
    Rake::Task["import_sales:run"].invoke
  ensure
    $stdout = original
  end

  describe "import result" do
    before { run_import }

    it "creates one order per ticket and one product per oem_code" do
      expect(Order.count).to eq(expected_orders)
      expect(Product.count).to eq(expected_products)
    end

    it "records one payment (allocation) for each order" do
      expect(Payment.count).to eq(expected_orders)
      expect(PaymentAllocation.count).to eq(expected_orders)
    end

    it "leaves all orders immediate, from_paper, confirmed and settled" do
      expect(Order.pluck(:order_type).uniq).to eq([ "immediate" ])
      expect(Order.pluck(:source).uniq).to eq([ "from_paper" ])
      expect(Order.where.not(status: "confirmed")).to be_empty
      expect(Order.includes(:payment_allocations).select { |o| o.outstanding_balance != 0 }).to be_empty
    end

    it "sets each order total to the sum of its line items (qty × price)" do
      offending = Order.includes(:order_items).reject do |o|
        o.total_amount == o.order_items.sum { |i| i.quantity * i.unit_price }
      end
      expect(offending).to be_empty
    end

    it "assigns the ticket's salesperson as the order user (find_by name)" do
      expect(Order.includes(:user).map { |o| o.user.name }.uniq)
        .to match_array(%w[Ariel Alfredo Yoward])
    end

    it "only uses mapped payment methods (cash, bank_card, mercado_pago)" do
      expect(Payment.distinct.pluck(:payment_method) - %w[cash bank_card mercado_pago])
        .to be_empty
    end

    it "maps bank -> bank_card" do
      # pick a ticket whose method in the file is 'bank'
      bank_ticket = tickets.find { |_n, rows| rows.first["payment_method"] == "bank" }&.first
      skip "no 'bank' tickets in the file" unless bank_ticket
      order = Order.find_by(paper_number: bank_ticket)
      expect(order.payments.first.payment_method).to eq("bank_card")
    end

    describe "known ticket 1402 (Ariel, cash, 2 line items of 41.500)" do
      let(:order) { Order.find_by(paper_number: "1402") }

      it "ends up with the correct salesperson, total, payment and status" do
        expect(order).to be_present
        expect(order.user.name).to eq("Ariel")
        expect(order.order_items.count).to eq(2)
        expect(order.total_amount).to eq(83_000)
        expect(order).to be_confirmed_status
        payment = order.payments.first
        expect(payment.payment_method).to eq("cash")
        expect(payment.amount).to eq(83_000)
        expect(order.sale_date.to_s).to eq("2026-04-01")
      end
    end
  end

  describe "idempotency" do
    it "does not duplicate orders or products when run twice" do
      run_import
      orders, products, payments = Order.count, Product.count, Payment.count

      run_import

      expect(Order.count).to eq(orders)
      expect(Product.count).to eq(products)
      expect(Payment.count).to eq(payments)
    end
  end

  describe "validation of missing salespeople" do
    it "aborts if a salesperson does not exist in the DB" do
      User.find_by(name: "Yoward").destroy
      expect { run_import }.to raise_error(SystemExit)
      expect(Order.count).to eq(0)
    end
  end
end
