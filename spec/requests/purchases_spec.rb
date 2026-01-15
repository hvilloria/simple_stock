require "rails_helper"

RSpec.describe "Purchases", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:user, role: "admin") }
  let(:supplier) { create(:supplier, payment_term_days: 30) }

  before do
    sign_in admin
  end

  describe "POST /web/purchases" do
    context "when creating a purchase in ARS" do
      let(:valid_params) do
        {
          supplier_id: supplier.id,
          invoice_number: "FAC-ARS-001",
          amount: "5000",
          currency: "ARS",
          exchange_rate: "", # Campo vacío cuando es ARS
          purchase_date: Date.today.to_s,
          due_date: 30.days.from_now.to_date.to_s,
          notes: "Test purchase in ARS"
        }
      end

      it "creates a purchase successfully" do
        expect {
          post web_purchases_path, params: valid_params
        }.to change(Purchase, :count).by(1)

        purchase = Purchase.last
        expect(response).to redirect_to(web_purchase_path(purchase))
        follow_redirect!
        expect(response.body).to include("Factura registrada exitosamente")

        expect(purchase.supplier).to eq(supplier)
        expect(purchase.invoice_number).to eq("FAC-ARS-001")
        expect(purchase.amount).to eq(5000)
        expect(purchase.currency).to eq("ARS")
        expect(purchase.exchange_rate).to be_nil
        expect(purchase.status).to eq("pending")
        expect(purchase.has_items).to be false
      end
    end

    context "when creating a purchase in USD" do
      let(:valid_params) do
        {
          supplier_id: supplier.id,
          invoice_number: "FAC-USD-001",
          amount: "1000",
          currency: "USD",
          exchange_rate: "1200.50",
          purchase_date: Date.today.to_s,
          due_date: 30.days.from_now.to_date.to_s,
          notes: "Test purchase in USD"
        }
      end

      it "creates a purchase successfully" do
        expect {
          post web_purchases_path, params: valid_params
        }.to change(Purchase, :count).by(1)

        purchase = Purchase.last
        expect(response).to redirect_to(web_purchase_path(purchase))
        follow_redirect!
        expect(response.body).to include("Factura registrada exitosamente")

        expect(purchase.supplier).to eq(supplier)
        expect(purchase.invoice_number).to eq("FAC-USD-001")
        expect(purchase.amount).to eq(1000)
        expect(purchase.currency).to eq("USD")
        expect(purchase.exchange_rate).to eq(1200.50)
        expect(purchase.status).to eq("pending")
        expect(purchase.has_items).to be false
      end
    end

    context "when creating a purchase in USD without exchange_rate" do
      let(:invalid_params) do
        {
          supplier_id: supplier.id,
          invoice_number: "FAC-USD-002",
          amount: "1000",
          currency: "USD",
          exchange_rate: "", # Falta exchange_rate para USD
          purchase_date: Date.today.to_s,
          due_date: 30.days.from_now.to_date.to_s
        }
      end

      it "fails with validation error" do
        expect {
          post web_purchases_path, params: invalid_params
        }.not_to change(Purchase, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Exchange rate required for USD purchases")
      end
    end

    context "when creating a purchase with invalid amount" do
      let(:invalid_params) do
        {
          supplier_id: supplier.id,
          invoice_number: "FAC-001",
          amount: "0",
          currency: "ARS",
          purchase_date: Date.today.to_s,
          due_date: 30.days.from_now.to_date.to_s
        }
      end

      it "fails with validation error" do
        expect {
          post web_purchases_path, params: invalid_params
        }.not_to change(Purchase, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Amount must be greater than zero")
      end
    end

    context "when creating a purchase with formatted amount from frontend" do
      it "handles amount with thousand separators correctly (154400.80)" do
        params = {
          supplier_id: supplier.id,
          invoice_number: "FAC-FORMAT-001",
          amount: "154400.80", # Formato limpio que envía JS
          currency: "ARS",
          purchase_date: Date.today.to_s,
          due_date: 30.days.from_now.to_date.to_s
        }

        expect {
          post web_purchases_path, params: params
        }.to change(Purchase, :count).by(1)

        purchase = Purchase.last
        expect(purchase.amount).to eq(154400.80)
      end

      it "handles large amount correctly (1500000.50)" do
        params = {
          supplier_id: supplier.id,
          invoice_number: "FAC-FORMAT-002",
          amount: "1500000.50",
          currency: "ARS",
          purchase_date: Date.today.to_s,
          due_date: 30.days.from_now.to_date.to_s
        }

        expect {
          post web_purchases_path, params: params
        }.to change(Purchase, :count).by(1)

        purchase = Purchase.last
        expect(purchase.amount).to eq(1500000.50)
      end

      it "handles amount with two decimal places (999.99)" do
        params = {
          supplier_id: supplier.id,
          invoice_number: "FAC-FORMAT-003",
          amount: "999.99",
          currency: "ARS",
          purchase_date: Date.today.to_s,
          due_date: 30.days.from_now.to_date.to_s
        }

        expect {
          post web_purchases_path, params: params
        }.to change(Purchase, :count).by(1)

        purchase = Purchase.last
        expect(purchase.amount).to eq(999.99)
      end
    end
  end
end
