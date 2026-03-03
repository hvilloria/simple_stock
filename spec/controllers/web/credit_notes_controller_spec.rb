# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::CreditNotesController", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { create(:user, role: "admin") }
  let(:supplier) { create(:supplier) }

  before { sign_in user }

  describe "POST /web/credit_notes" do
    context "with valid ARS params" do
      let(:valid_params) do
        {
          credit_note: {
            supplier_id: supplier.id,
            credit_note_number: "NCC-001",
            amount: "10000",
            currency: "ARS",
            issue_date: Date.current.to_s,
            notes: ""
          }
        }
      end

      it "creates a credit note and redirects to show" do
        expect { post web_credit_notes_path, params: valid_params }
          .to change(CreditNote, :count).by(1)

        expect(response).to redirect_to(web_credit_note_path(CreditNote.last))
      end

      it "sets status to active automatically" do
        post web_credit_notes_path, params: valid_params

        expect(CreditNote.last.status).to eq("active")
      end

      it "sets the correct supplier and amount" do
        post web_credit_notes_path, params: valid_params

        cn = CreditNote.last
        expect(cn.supplier).to eq(supplier)
        expect(cn.amount).to eq(10_000)
      end
    end

    context "with valid USD params" do
      let(:usd_params) do
        {
          credit_note: {
            supplier_id: supplier.id,
            credit_note_number: "NCC-USD-001",
            amount: "500",
            currency: "USD",
            exchange_rate: "1200",
            issue_date: Date.current.to_s,
            notes: ""
          }
        }
      end

      it "creates a USD credit note" do
        expect { post web_credit_notes_path, params: usd_params }
          .to change(CreditNote, :count).by(1)

        cn = CreditNote.last
        expect(cn.currency).to eq("USD")
        expect(cn.exchange_rate).to eq(1200)
      end
    end

    context "with Argentine-formatted amounts" do
      it "parses amount with thousand separators correctly" do
        post web_credit_notes_path, params: {
          credit_note: {
            supplier_id: supplier.id,
            credit_note_number: "NCC-FMT-001",
            amount: "1.500.000,50",
            currency: "ARS",
            issue_date: Date.current.to_s
          }
        }

        expect(CreditNote.last.amount).to eq(1_500_000.50)
      end
    end

    context "regression: status not sent in params" do
      # The form never sends `status` — it must default to "active" via after_initialize.
      # Previously the DB column had default: "pending" (invalid enum value), causing
      # the attribute to be nil and a PG::NotNullViolation on save.
      it "creates successfully without status in params" do
        expect {
          post web_credit_notes_path, params: {
            credit_note: {
              supplier_id: supplier.id,
              credit_note_number: "NCC-NOSTATUS-001",
              amount: "324",
              currency: "ARS",
              issue_date: Date.current.to_s
            }
          }
        }.to change(CreditNote, :count).by(1)

        expect(CreditNote.last.status).to eq("active")
        expect(response).not_to have_http_status(:internal_server_error)
      end
    end

    context "with invalid params" do
      it "renders new with 422 when credit_note_number is missing" do
        post web_credit_notes_path, params: {
          credit_note: {
            supplier_id: supplier.id,
            amount: "1000",
            currency: "ARS",
            issue_date: Date.current.to_s
          }
        }

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "renders new with 422 when amount is missing" do
        post web_credit_notes_path, params: {
          credit_note: {
            supplier_id: supplier.id,
            credit_note_number: "NCC-FAIL-001",
            currency: "ARS",
            issue_date: Date.current.to_s
          }
        }

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "renders new with 422 when USD credit note has no exchange_rate" do
        post web_credit_notes_path, params: {
          credit_note: {
            supplier_id: supplier.id,
            credit_note_number: "NCC-FAIL-002",
            amount: "500",
            currency: "USD",
            issue_date: Date.current.to_s
          }
        }

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "does not create a record on validation failure" do
        expect {
          post web_credit_notes_path, params: {
            credit_note: {
              supplier_id: supplier.id,
              currency: "ARS",
              issue_date: Date.current.to_s
            }
          }
        }.not_to change(CreditNote, :count)
      end
    end

    context "with invoice_id" do
      let(:invoice) { create(:invoice, :simple_mode, supplier: supplier, currency: "ARS", status: "pending") }

      it "links the credit note to the invoice" do
        post web_credit_notes_path, params: {
          credit_note: {
            supplier_id: supplier.id,
            invoice_id: invoice.id,
            credit_note_number: "NCC-INV-001",
            amount: "1000",
            currency: "ARS",
            issue_date: Date.current.to_s
          }
        }

        expect(CreditNote.last.invoice).to eq(invoice)
      end
    end
  end
end
