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
