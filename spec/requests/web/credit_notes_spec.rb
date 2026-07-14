# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::CreditNotes edit/update/destroy", type: :request do
  let(:admin)    { create(:user, role: "admin") }
  let(:supplier) { create(:supplier) }
  let(:credit_note) do
    create(:credit_note, supplier: supplier, credit_note_number: "NC-100", amount: 1_000, currency: "ARS")
  end

  before { sign_in admin }

  describe "GET /web/credit_notes/:id/edit" do
    it "renders the edit form for the note" do
      get edit_web_credit_note_path(credit_note)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("NC-100")
    end
  end

  describe "PATCH /web/credit_notes/:id" do
    it "updates the note and redirects to show" do
      patch web_credit_note_path(credit_note), params: {
        credit_note: {
          supplier_id: supplier.id,
          credit_note_number: "NC-100-B",
          amount: "2.500,75",
          currency: "ARS",
          issue_date: Date.current.to_s,
          notes: "Corregida"
        }
      }

      expect(response).to redirect_to(web_credit_note_path(credit_note))
      credit_note.reload
      expect(credit_note.credit_note_number).to eq("NC-100-B")
      expect(credit_note.amount).to eq(2_500.75)
      expect(credit_note.notes).to eq("Corregida")

      follow_redirect!
      expect(response.body).to include("Nota de crédito actualizada exitosamente")
    end

    it "re-renders edit with 422 and keeps the record intact when invalid" do
      patch web_credit_note_path(credit_note), params: {
        credit_note: {
          supplier_id: supplier.id,
          credit_note_number: "",
          amount: "2500",
          currency: "ARS",
          issue_date: Date.current.to_s
        }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      credit_note.reload
      expect(credit_note.credit_note_number).to eq("NC-100")
      expect(credit_note.amount).to eq(1_000)
    end
  end

  # Money values POSTed straight at the endpoint, bypassing Stimulus. The backend must
  # normalize correctly or reject — never book a wrong number.
  describe "POST /web/credit_notes — hostile amount" do
    def post_amount(amount, currency: "ARS", exchange_rate: nil)
      post web_credit_notes_path, params: {
        credit_note: {
          supplier_id: supplier.id,
          credit_note_number: "NC-H-#{SecureRandom.hex(3)}",
          amount: amount,
          currency: currency,
          exchange_rate: exchange_rate,
          issue_date: Date.current.to_s
        }
      }
    end

    it "persists 1500000.50 for the Argentine format '1.500.000,50'" do
      expect { post_amount("1.500.000,50") }.to change(CreditNote, :count).by(1)

      expect(CreditNote.last.amount).to eq(BigDecimal("1500000.50"))
    end

    it "persists 1500000 for the Argentine thousands '1.500.000'" do
      expect { post_amount("1.500.000") }.to change(CreditNote, :count).by(1)

      expect(CreditNote.last.amount).to eq(1_500_000)
    end

    it "persists 1500.50 for the clean decimal '1500.50'" do
      expect { post_amount("1500.50") }.to change(CreditNote, :count).by(1)

      expect(CreditNote.last.amount).to eq(BigDecimal("1500.50"))
    end

    it "rejects a non-numeric amount instead of booking zero" do
      expect { post_amount("abc") }.not_to change(CreditNote, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects a negative amount" do
      expect { post_amount("-500") }.not_to change(CreditNote, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects a blank amount" do
      expect { post_amount("") }.not_to change(CreditNote, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "persists 1200.50 for the Argentine exchange rate '1.200,50'" do
      expect { post_amount("1000", currency: "USD", exchange_rate: "1.200,50") }
        .to change(CreditNote, :count).by(1)

      expect(CreditNote.last.exchange_rate).to eq(BigDecimal("1200.50"))
    end

    it "rejects a non-numeric exchange rate on a USD note" do
      expect { post_amount("1000", currency: "USD", exchange_rate: "abc") }
        .not_to change(CreditNote, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /web/credit_notes/:id — hostile amount" do
    def patch_amount(amount)
      patch web_credit_note_path(credit_note), params: {
        credit_note: {
          supplier_id: supplier.id,
          credit_note_number: "NC-100",
          amount: amount,
          currency: "ARS",
          issue_date: Date.current.to_s
        }
      }
    end

    it "persists 1500000 for the Argentine thousands '1.500.000'" do
      patch_amount("1.500.000")

      expect(response).to redirect_to(web_credit_note_path(credit_note))
      expect(credit_note.reload.amount).to eq(1_500_000)
    end

    it "persists 1500.50 for the clean decimal '1500.50'" do
      patch_amount("1500.50")

      expect(response).to redirect_to(web_credit_note_path(credit_note))
      expect(credit_note.reload.amount).to eq(BigDecimal("1500.50"))
    end

    it "rejects a non-numeric amount and keeps the record intact" do
      patch_amount("abc")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(credit_note.reload.amount).to eq(1_000)
    end

    it "rejects a negative amount and keeps the record intact" do
      patch_amount("-500")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(credit_note.reload.amount).to eq(1_000)
    end
  end

  describe "DELETE /web/credit_notes/:id" do
    it "deletes the note and redirects to the index" do
      target = create(:credit_note, supplier: supplier)

      expect { delete web_credit_note_path(target) }.to change(CreditNote, :count).by(-1)

      expect(response).to redirect_to(web_credit_notes_path)
      expect(CreditNote.exists?(target.id)).to be(false)

      follow_redirect!
      expect(response.body).to include("Nota de crédito eliminada exitosamente")
    end
  end
end
