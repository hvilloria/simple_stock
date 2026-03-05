# frozen_string_literal: true

require "rails_helper"

# Tests for POST /web/invoices/mark_supplier_paid.
# The controller receives explicit invoice_ids and credit_note_ids — no amounts.
# ProcessPayment distributes NC balances across invoices internally.

RSpec.describe "Web::InvoicesController - mark_supplier_paid with credits", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin)    { create(:user, role: "admin") }
  let(:supplier) { create(:supplier, name: "Proveedor Test") }

  before { sign_in admin }

  def invoice_this_week(amount:, number: "FAC-#{SecureRandom.hex(3).upcase}")
    create(:invoice, :simple_mode,
           supplier: supplier,
           amount: amount,
           currency: "ARS",
           invoice_number: number,
           due_date: Date.current.beginning_of_week(:monday),
           purchase_date: 30.days.ago.to_date)
  end

  def post_payment(invoice_ids:, credit_note_ids: [], payment_date: Date.current)
    post mark_supplier_paid_web_invoices_path, params: {
      invoice_ids:     Array(invoice_ids),
      credit_note_ids: credit_note_ids,
      period:          "this_week",
      payment_date:    payment_date.to_s
    }
  end

  # ─────────────────────────────────────────────────────────────────
  # Scenario 1: factura $100k, NC $50k — NC se aplica completamente
  # ─────────────────────────────────────────────────────────────────
  describe "Scenario 1: invoice $100k, single NC $50k" do
    let!(:invoice) { invoice_this_week(amount: 100_000, number: "FAC-SC1") }
    let!(:cn)      { create(:credit_note, supplier: supplier, amount: 50_000) }

    it "marks the invoice as paid" do
      post_payment(invoice_ids: [ invoice.id ], credit_note_ids: [ cn.id ])
      expect(invoice.reload.paid_status?).to be true
    end

    it "exhausts the credit note balance" do
      post_payment(invoice_ids: [ invoice.id ], credit_note_ids: [ cn.id ])
      expect(cn.reload.remaining_balance).to eq(0)
    end

    it "creates one AppliedCredit linked to the correct invoice and CN" do
      expect {
        post_payment(invoice_ids: [ invoice.id ], credit_note_ids: [ cn.id ])
      }.to change(AppliedCredit, :count).by(1)

      ac = AppliedCredit.last
      expect(ac.invoice).to eq(invoice)
      expect(ac.credit_note).to eq(cn)
      expect(ac.amount).to eq(50_000)
    end

    it "redirects to the pending page" do
      post_payment(invoice_ids: [ invoice.id ], credit_note_ids: [ cn.id ])
      expect(response).to redirect_to(pending_web_invoices_path(period: "this_week"))
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Scenario 2: factura $100k, 2 NCs de $50k — ambas seleccionadas
  # ─────────────────────────────────────────────────────────────────
  describe "Scenario 2: invoice $100k, two NCs of $50k each" do
    let!(:invoice) { invoice_this_week(amount: 100_000, number: "FAC-SC2") }
    let!(:cn1)     { create(:credit_note, supplier: supplier, amount: 50_000) }
    let!(:cn2)     { create(:credit_note, supplier: supplier, amount: 50_000) }

    it "marks the invoice as paid" do
      post_payment(invoice_ids: [ invoice.id ], credit_note_ids: [ cn1.id, cn2.id ])
      expect(invoice.reload.paid_status?).to be true
    end

    it "exhausts both credit notes" do
      post_payment(invoice_ids: [ invoice.id ], credit_note_ids: [ cn1.id, cn2.id ])
      expect(cn1.reload.remaining_balance).to eq(0)
      expect(cn2.reload.remaining_balance).to eq(0)
    end

    it "creates two AppliedCredit records" do
      expect {
        post_payment(invoice_ids: [ invoice.id ], credit_note_ids: [ cn1.id, cn2.id ])
      }.to change(AppliedCredit, :count).by(2)
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Scenario 3: factura $100k, NC $150k — NC capea al monto de la factura
  # La NC queda con $50k de saldo disponible
  # ─────────────────────────────────────────────────────────────────
  describe "Scenario 3: invoice $100k, NC $150k (service caps to invoice amount)" do
    let!(:invoice) { invoice_this_week(amount: 100_000, number: "FAC-SC3") }
    let!(:cn)      { create(:credit_note, supplier: supplier, amount: 150_000) }

    it "marks the invoice as paid" do
      post_payment(invoice_ids: [ invoice.id ], credit_note_ids: [ cn.id ])
      expect(invoice.reload.paid_status?).to be true
    end

    it "leaves $50k remaining in the credit note" do
      post_payment(invoice_ids: [ invoice.id ], credit_note_ids: [ cn.id ])
      expect(cn.reload.remaining_balance).to eq(50_000)
    end

    it "credit note stays available for future use" do
      post_payment(invoice_ids: [ invoice.id ], credit_note_ids: [ cn.id ])
      expect(cn.reload.available?).to be true
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Scenario 4: factura $100k, 2 NCs de $100k — solo se selecciona la primera
  # La segunda NC debe quedar intacta
  # ─────────────────────────────────────────────────────────────────
  describe "Scenario 4: invoice $100k, two NCs of $100k (only first selected)" do
    let!(:invoice) { invoice_this_week(amount: 100_000, number: "FAC-SC4") }
    let!(:cn1)     { create(:credit_note, supplier: supplier, amount: 100_000) }
    let!(:cn2)     { create(:credit_note, supplier: supplier, amount: 100_000) }

    before { post_payment(invoice_ids: [ invoice.id ], credit_note_ids: [ cn1.id ]) }

    it "marks the invoice as paid" do
      expect(invoice.reload.paid_status?).to be true
    end

    it "exhausts cn1" do
      expect(cn1.reload.remaining_balance).to eq(0)
    end

    it "leaves cn2 completely untouched" do
      expect(cn2.reload.remaining_balance).to eq(100_000)
      expect(cn2.reload.available?).to be true
      expect(AppliedCredit.where(credit_note: cn2).count).to eq(0)
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Scenario 5: 2 facturas ($60k + $40k), NC $80k — distribución automática
  # ProcessPayment distribuye internamente:
  #   FAC-A: aplica min(80k, 60k) = 60k → NC restante = 20k
  #   FAC-B: aplica min(20k, 40k) = 20k → NC restante = 0
  # ─────────────────────────────────────────────────────────────────
  describe "Scenario 5: two invoices ($60k + $40k), NC $80k distributed automatically" do
    let!(:invoice1) { invoice_this_week(amount: 60_000, number: "FAC-A") }
    let!(:invoice2) { invoice_this_week(amount: 40_000, number: "FAC-B") }
    let!(:cn)       { create(:credit_note, supplier: supplier, amount: 80_000) }

    before { post_payment(invoice_ids: [ invoice1.id, invoice2.id ], credit_note_ids: [ cn.id ]) }

    it "marks both invoices as paid" do
      expect(invoice1.reload.paid_status?).to be true
      expect(invoice2.reload.paid_status?).to be true
    end

    it "exhausts the credit note" do
      expect(cn.reload.remaining_balance).to eq(0)
    end

    it "creates two AppliedCredit records (one per invoice)" do
      expect(AppliedCredit.where(credit_note: cn).count).to eq(2)
    end

    it "applies $60k to invoice1 and $20k to invoice2" do
      ac1 = AppliedCredit.find_by(credit_note: cn, invoice: invoice1)
      ac2 = AppliedCredit.find_by(credit_note: cn, invoice: invoice2)

      expect(ac1.amount).to eq(60_000)
      expect(ac2.amount).to eq(20_000)
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Escenario de rechazo: NC de otro proveedor
  # ─────────────────────────────────────────────────────────────────
  describe "Rejection: NC from a different supplier" do
    let(:other_supplier) { create(:supplier) }
    let!(:invoice)       { invoice_this_week(amount: 100_000, number: "FAC-REJ") }
    let!(:foreign_cn)    { create(:credit_note, supplier: other_supplier, amount: 50_000) }

    before { post_payment(invoice_ids: [ invoice.id ], credit_note_ids: [ foreign_cn.id ]) }

    it "does not mark the invoice as paid" do
      expect(invoice.reload.pending_status?).to be true
    end

    it "does not modify the NC balance" do
      expect(foreign_cn.reload.remaining_balance).to eq(50_000)
    end

    it "does not create any AppliedCredit" do
      expect(AppliedCredit.count).to eq(0)
    end

    it "redirects with an error flash" do
      follow_redirect!
      expect(response.body).to include("otro proveedor")
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Sin credit_note_ids — pago directo sin créditos
  # ─────────────────────────────────────────────────────────────────
  describe "No credit_note_ids param (direct payment)" do
    let!(:invoice) { invoice_this_week(amount: 50_000, number: "FAC-DIR") }

    it "marks the invoice as paid without creating any AppliedCredit" do
      expect {
        post_payment(invoice_ids: [ invoice.id ])
      }.not_to change(AppliedCredit, :count)

      expect(invoice.reload.paid_status?).to be true
    end
  end
end
