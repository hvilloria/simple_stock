# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::CreditNotes", type: :request do
  let(:admin) { create(:user, role: "admin") }
  let(:supplier) { create(:supplier, name: "Distribuidora Norte") }
  let(:invoice) { create(:invoice, :simple_mode, supplier: supplier) }

  before { sign_in admin }

  describe "GET /web/credit_notes" do
    it "renders a status select with the values the scope actually understands" do
      get "/web/credit_notes"

      expect(response.body).to match(/<option[^>]*value=""[^>]*>/)
      expect(response.body).to match(/<option[^>]*value="available"[^>]*>/)
      expect(response.body).to match(/<option[^>]*value="applied"[^>]*>/)
      expect(response.body).to match(/<option[^>]*value="cancelled"[^>]*>/)
    end

    it "returns the notes that still have balance for 'available'" do
      create(:credit_note, supplier: supplier, amount: 1000, credit_note_number: "NC-FREE")
      used = create(:credit_note, supplier: supplier, amount: 1000, credit_note_number: "NC-USED")
      create(:applied_credit, credit_note: used, invoice: invoice, amount: 1000)

      get "/web/credit_notes", params: { status: "available" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("NC-FREE")
      expect(response.body).not_to include("NC-USED")
    end

    it "returns the notes with no balance left for 'applied'" do
      create(:credit_note, supplier: supplier, amount: 1000, credit_note_number: "NC-FREE")
      used = create(:credit_note, supplier: supplier, amount: 1000, credit_note_number: "NC-USED")
      create(:applied_credit, credit_note: used, invoice: invoice, amount: 1000)

      get "/web/credit_notes", params: { status: "applied" }

      expect(response.body).to include("NC-USED")
      expect(response.body).not_to include("NC-FREE")
    end

    it "returns cancelled notes for 'cancelled'" do
      create(:credit_note, supplier: supplier, amount: 1000, credit_note_number: "NC-FREE")
      create(:credit_note, :cancelled, supplier: supplier, amount: 1000, credit_note_number: "NC-VOID")

      get "/web/credit_notes", params: { status: "cancelled" }

      expect(response.body).to include("NC-VOID")
      expect(response.body).not_to include("NC-FREE")
    end

    it "paginates instead of truncating at a fixed limit" do
      25.times { |i| create(:credit_note, supplier: supplier, amount: 1000, credit_note_number: "NC-#{i.to_s.rjust(3, '0')}") }

      get "/web/credit_notes"
      first_page = response.body.scan(/NC-\d{3}/).uniq

      get "/web/credit_notes", params: { page: 2 }
      second_page = response.body.scan(/NC-\d{3}/).uniq

      expect(first_page.size).to eq(20)
      expect(second_page.size).to eq(5)
      expect(first_page & second_page).to be_empty
    end

    it "totals every available note, not only the ones on the page" do
      21.times { create(:credit_note, supplier: supplier, amount: 1000) }
      create(:credit_note, :usd, supplier: supplier, amount: 100)
      partially_applied = create(:credit_note, supplier: supplier, amount: 2000)
      create(:applied_credit, credit_note: partially_applied, invoice: invoice, amount: 500)
      fully_applied = create(:credit_note, supplier: supplier, amount: 3000)
      create(:applied_credit, credit_note: fully_applied, invoice: invoice, amount: 3000)

      get "/web/credit_notes"

      # 21 * 1000 (ARS) + 100 * 1200 (USD converted) + 1500 (partial balance) + 0 (exhausted) = 142_500
      expect(response.body).to include("ARS 142.500,00")
      # excludes the fully-applied note, which is active status but has no remaining balance
      expect(response.body).to include("23 notas")
    end

    it "does not issue one applied_credits query per note when rendering the index" do
      6.times do |i|
        cn = create(:credit_note, supplier: supplier, amount: 1000, credit_note_number: "NC-Q#{i}")
        create(:applied_credit, credit_note: cn, invoice: invoice, amount: 100)
      end

      applied_credit_queries = []
      subscriber = lambda do |*, payload|
        applied_credit_queries << payload[:sql] if payload[:sql].match?(/applied_credits/)
      end

      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        get "/web/credit_notes"
      end

      expect(applied_credit_queries.size).to eq(2)
    end

    it "keeps the total independent of the status filter" do
      create(:credit_note, supplier: supplier, amount: 1000)
      create(:credit_note, :cancelled, supplier: supplier, amount: 5000)

      get "/web/credit_notes", params: { status: "cancelled" }

      expect(response.body).to include("ARS 1.000,00")
      expect(response.body).not_to include("ARS 6.000,00")
    end
  end
end
