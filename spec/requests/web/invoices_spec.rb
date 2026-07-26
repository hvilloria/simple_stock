# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::Invoices", type: :request do
  let(:admin) { create(:user, role: "admin") }
  let(:supplier) { create(:supplier, name: "Distribuidora Norte") }

  before { sign_in admin }

  describe "GET /web/invoices" do
    it "renders a status select with the values the scope actually understands" do
      get "/web/invoices"

      expect(response.body).to match(/<option[^>]*value="pending"[^>]*>/)
      expect(response.body).to match(/<option[^>]*value="paid"[^>]*>/)
      expect(response.body).to match(/<option[^>]*value="cancelled"[^>]*>/)
    end

    it "shows pending invoices by default and hides the paid ones" do
      create(:invoice, :simple_mode, supplier: supplier, invoice_number: "PEND-1")
      create(:invoice, :paid, supplier: supplier, invoice_number: "PAID-1")

      get "/web/invoices"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("PEND-1")
      expect(response.body).not_to include("PAID-1")
      expect(response.body).to include("Vencimiento")
    end

    it "shows only paid invoices when the status is paid" do
      create(:invoice, :simple_mode, supplier: supplier, invoice_number: "PEND-1")
      paid = create(:invoice, :paid, supplier: supplier, invoice_number: "PAID-1", paid_at: Date.new(2026, 5, 20))

      get "/web/invoices", params: { status: "paid" }

      expect(response.body).to include("PAID-1")
      expect(response.body).not_to include("PEND-1")
      expect(response.body).to include("Pagada el")
      expect(response.body).to include(paid.paid_at.strftime("%d/%m/%Y"))
    end

    it "shows only cancelled invoices when the status is cancelled" do
      create(:invoice, :simple_mode, supplier: supplier, invoice_number: "PEND-1")
      create(:invoice, :simple_mode, supplier: supplier, invoice_number: "CANC-1", status: "cancelled")

      get "/web/invoices", params: { status: "cancelled" }

      expect(response.body).to include("CANC-1")
      expect(response.body).not_to include("PEND-1")
    end

    it "falls back to pending when the status is outside the enum" do
      create(:invoice, :simple_mode, supplier: supplier, invoice_number: "PEND-1")
      create(:invoice, :paid, supplier: supplier, invoice_number: "PAID-1")

      get "/web/invoices", params: { status: "'; DROP TABLE invoices; --" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("PEND-1")
      expect(response.body).not_to include("PAID-1")
    end

    it "sorts paid invoices by payment date, not by due date" do
      create(:invoice, :paid, supplier: supplier, invoice_number: "PAID-TODAY",
             due_date: 1.month.from_now.to_date, paid_at: Date.current)
      create(:invoice, :paid, supplier: supplier, invoice_number: "PAID-LAST-WEEK",
             due_date: 6.months.ago.to_date, paid_at: 1.week.ago.to_date)

      get "/web/invoices", params: { status: "paid" }

      expect(response.body.index("PAID-TODAY")).to be < response.body.index("PAID-LAST-WEEK")
    end

    it "keeps the supplier filter while filtering by status" do
      other_supplier = create(:supplier, name: "Mayorista Sur")
      create(:invoice, :paid, supplier: supplier, invoice_number: "MINE-1")
      create(:invoice, :paid, supplier: other_supplier, invoice_number: "THEIRS-1")

      get "/web/invoices", params: { status: "paid", supplier_id: supplier.id }

      expect(response.body).to include("MINE-1")
      expect(response.body).not_to include("THEIRS-1")
    end

    it "does not issue one applied_credits query per credit note when rendering the index" do
      other_invoice = create(:invoice, :simple_mode, supplier: supplier)
      8.times do |i|
        cn = create(:credit_note, supplier: supplier, amount: 1000, credit_note_number: "NC-Q#{i}")
        create(:applied_credit, credit_note: cn, invoice: other_invoice, amount: 100)
      end

      applied_credit_queries = []
      subscriber = lambda do |*, payload|
        applied_credit_queries << payload[:sql] if payload[:sql].match?(/applied_credits/)
      end

      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        get "/web/invoices"
      end

      expect(applied_credit_queries.size).to eq(1)
      # 8 notes * (1000 - 100) = 7200 remaining balance, still totalled correctly
      expect(response.body).to include("ARS 7.200,00")
    end

    it "keeps the pending-debt metric independent of the status filter" do
      create(:invoice, :simple_mode, supplier: supplier, invoice_number: "PEND-1", amount: 1000, currency: "ARS")
      create(:invoice, :paid, supplier: supplier, invoice_number: "PAID-1", amount: 5000, currency: "ARS")

      get "/web/invoices", params: { status: "paid" }

      expect(response.body).to include("ARS 1.000,00")
      expect(response.body).not_to include("ARS 6.000,00")
    end

    it "orders tied due dates by newest id first, without repeating across pages" do
      due = 10.days.from_now.to_date
      invoices = 25.times.map { |i| create(:invoice, :simple_mode, supplier: supplier, invoice_number: "TIE-#{i}", due_date: due) }
      by_newest_id = invoices.sort_by(&:id).reverse.map(&:invoice_number)

      get "/web/invoices"
      first_page = response.body.scan(/TIE-\d+/).uniq

      get "/web/invoices", params: { page: 2 }
      second_page = response.body.scan(/TIE-\d+/).uniq

      expect(first_page).to eq(by_newest_id.first(20))
      expect(second_page).to eq(by_newest_id.last(5))
    end
  end
end
