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

  describe "PATCH /web/invoices/:id/cancel" do
    let!(:location) { create(:stock_location) }

    it "cancels a pending amount-only invoice and moves no stock" do
      invoice = create(:invoice, :simple_mode, supplier: supplier)

      expect { patch "/web/invoices/#{invoice.id}/cancel" }.not_to change(StockMovement, :count)

      expect(response).to redirect_to("/web/invoices")
      expect(invoice.reload.status).to eq("cancelled")
    end

    it "refuses a paid invoice" do
      invoice = create(:invoice, :paid, supplier: supplier)

      patch "/web/invoices/#{invoice.id}/cancel"

      # The policy refuses first; ApplicationController redirects to the
      # referrer or the root, so only the redirect and the untouched status matter.
      expect(response).to have_http_status(:redirect)
      expect(invoice.reload.status).to eq("paid")
    end

    it "takes back the stock an itemized invoice added, as far as there is stock" do
      product = create(:product, current_stock: 0)
      invoice = Invoices::CreateInvoice.call(
        supplier: supplier, invoice_number: "FAC-9", amount: nil, currency: "ARS",
        purchase_date: Date.current, due_date: 30.days.from_now,
        items: [ { product_id: product.id, quantity: 10, unit_cost: 100 } ]
      ).record
      Inventory::AdjustStock.call(product: product.reload, stock_location: location,
                                  movement_type: "adjustment", quantity: -7)

      patch "/web/invoices/#{invoice.id}/cancel"

      expect(invoice.reload.status).to eq("cancelled")
      expect(product.reload.current_stock).to eq(0)
    end
  end

  describe "GET /web/invoices/new" do
    it "offers the products card and no longer promises that stock is untouched" do
      get "/web/invoices/new"

      html = Nokogiri::HTML(response.body)
      card = html.at('[data-controller="invoice-lines"]')
      expect(card).to be_present
      expect(card.text).to include("Productos")
      expect(card.at('[data-controller="product-search"]')["data-product-search-dim-out-of-stock-value"]).to eq("false")
      expect(response.body).not_to include("Modo Simple")
      expect(response.body).not_to include("Qué NO hace este registro")
      expect(response.body).to include("Sin productos: no mueve stock")
      expect(html.at('[data-invoice-form-target="zeroCostModal"]')).to be_present
    end
  end

  describe "POST /web/invoices" do
    let!(:location) { create(:stock_location) }
    let(:product)   { create(:product, sku: "90915-YZZD2", name: "Filtro de aceite", current_stock: 0) }

    def header(overrides = {})
      { supplier_id: supplier.id, invoice_number: "FAC-0001234", currency: "ARS",
        amount: "1,00", purchase_date: Date.current.to_s, due_date: 30.days.from_now.to_date.to_s }.merge(overrides)
    end

    def line(product, quantity:, unit_cost:)
      { product_id: product.id, sku: product.sku, name: product.name, brand: product.brand,
        quantity: quantity, unit_cost: unit_cost }
    end

    it "registers an itemized invoice, sums the lines and stocks them" do
      post "/web/invoices", params: header.merge(items: { "0" => line(product, quantity: 10, unit_cost: "4.500,00") })

      invoice = Invoice.last
      expect(response).to redirect_to("/web/invoices/#{invoice.id}")
      expect(invoice.amount).to eq(45_000)
      expect(invoice.invoice_items.count).to eq(1)
      expect(product.reload.current_stock).to eq(10)
    end

    it "registers an amount-only invoice exactly as before" do
      post "/web/invoices", params: header(amount: "12.500,50")

      invoice = Invoice.last
      expect(invoice.amount).to eq(12_500.5)
      expect(invoice.invoice_items).to be_empty
      expect(StockMovement.count).to eq(0)
    end

    it "comes back with the header and the lines when the server refuses" do
      post "/web/invoices", params: header(due_date: (Date.current - 1).to_s)
                                          .merge(items: { "0" => line(product, quantity: 10, unit_cost: "4.500,00") })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Due date cannot be before purchase date")
      expect(response.body).to include('value="FAC-0001234"')
      expect(Invoice.count).to eq(0)
      expect(product.reload.current_stock).to eq(0)

      card = Nokogiri::HTML(response.body).at('[data-controller="invoice-lines"]')
      lines = JSON.parse(card["data-invoice-lines-initial-items-value"])
      expect(lines).to eq([
        { "product_id" => product.id.to_s, "sku" => "90915-YZZD2", "name" => "Filtro de aceite",
          "brand" => product.brand, "quantity" => 10, "unit_cost" => "4.500,00" }
      ])
    end

    # The backend must not trust the client to send a clean number: "abc" is
    # rejected, never read as a free line.
    it "rejects an unparseable unit cost" do
      post "/web/invoices", params: header.merge(items: { "0" => line(product, quantity: 1, unit_cost: "abc") })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Unit cost is not a number")
      expect(Invoice.count).to eq(0)
      expect(product.reload.current_stock).to eq(0)
    end

    it "reads a blank unit cost as a free line" do
      post "/web/invoices", params: header.merge(items: { "0" => line(product, quantity: 2, unit_cost: "") })

      expect(Invoice.last.amount).to eq(0)
      expect(product.reload.current_stock).to eq(2)
    end

    # The form cleans the amount before posting, so the refusal must hand it
    # back in Argentine format: a second cleaning would multiply it by 100.
    it "returns the refused amount in Argentine format" do
      post "/web/invoices", params: header(amount: "12.500,50", due_date: (Date.current - 1).to_s)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Nokogiri::HTML(response.body).at("#amount")["value"]).to eq("12.500,50")
    end

    it "returns the refused exchange rate in Argentine format" do
      post "/web/invoices", params: header(currency: "USD", exchange_rate: "1.480,00",
                                           due_date: (Date.current - 1).to_s)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Nokogiri::HTML(response.body).at("#exchange_rate")["value"]).to eq("1.480,00")
    end

    it "ignores an items param that is not a hash of rows" do
      post "/web/invoices", params: header.merge(items: "garbage")

      expect(response.status).not_to eq(500)
      expect(InvoiceItem.count).to eq(0)
      expect(StockMovement.count).to eq(0)
    end
  end

  describe "PATCH /web/invoices/:id" do
    let!(:location) { create(:stock_location) }

    it "ignores a submitted amount when the invoice has lines" do
      product = create(:product, current_stock: 0)
      invoice = Invoices::CreateInvoice.call(
        supplier: supplier, invoice_number: "FAC-7", amount: nil, currency: "ARS",
        purchase_date: Date.current, due_date: 30.days.from_now,
        items: [ { product_id: product.id, quantity: 10, unit_cost: 100 } ]
      ).record

      patch "/web/invoices/#{invoice.id}", params: { invoice: { amount: "1,00", notes: "corregida" } }

      expect(invoice.reload.amount).to eq(1_000)
      expect(invoice.notes).to eq("corregida")
    end

    it "updates the exchange rate of an itemized invoice without touching its amount" do
      product = create(:product, current_stock: 0)
      invoice = Invoices::CreateInvoice.call(
        supplier: supplier, invoice_number: "FAC-8", amount: nil, currency: "USD", exchange_rate: 1200,
        purchase_date: Date.current, due_date: 30.days.from_now,
        items: [ { product_id: product.id, quantity: 10, unit_cost: 100 } ]
      ).record

      patch "/web/invoices/#{invoice.id}", params: { invoice: { exchange_rate: "1.480,00" } }

      expect(invoice.reload.exchange_rate).to eq(1_480)
      expect(invoice.amount).to eq(1_000)
      expect(invoice.total_amount_ars).to eq(1_480_000)
    end

    it "still updates the amount of an amount-only invoice" do
      invoice = create(:invoice, :simple_mode, supplier: supplier, amount: 500)

      patch "/web/invoices/#{invoice.id}", params: { invoice: { amount: "700,00" } }

      expect(invoice.reload.amount).to eq(700)
    end
  end

  describe "GET /web/invoices/:id" do
    let!(:location) { create(:stock_location) }

    def itemized
      product = create(:product, sku: "90915-YZZD2", name: "Filtro de aceite", current_stock: 0)
      Invoices::CreateInvoice.call(
        supplier: supplier, invoice_number: "FAC-5", amount: nil, currency: "ARS",
        purchase_date: Date.current, due_date: 30.days.from_now,
        items: [ { product_id: product.id, quantity: 10, unit_cost: 4500 } ]
      ).record
    end

    it "shows the lines, the caption and the stock-aware cancel confirmation on an itemized invoice" do
      get "/web/invoices/#{itemized.id}"

      html = Nokogiri::HTML(response.body)
      expect(html.at("#invoice-lines")).to be_present
      expect(html.at("#invoice-lines").text).to include("90915-YZZD2", "Filtro de aceite", "10")
      expect(response.body).to include("calculado desde 1 producto")
      expect(response.body).to include("Suma 10 unidades al stock")
      expect(html.at("form[action$='/cancel']")["data-turbo-confirm"])
        .to eq("¿Cancelar esta factura? Se descuentan del stock las 10 unidades que sumó, hasta donde haya.")
    end

    it "shows an amount-only invoice exactly as before" do
      invoice = create(:invoice, :simple_mode, supplier: supplier)

      get "/web/invoices/#{invoice.id}"

      html = Nokogiri::HTML(response.body)
      expect(html.at("#invoice-lines")).to be_nil
      expect(response.body).not_to include("calculado desde")
      expect(html.at("form[action$='/cancel']")["data-turbo-confirm"]).to eq("¿Estás seguro de cancelar esta factura?")
    end
  end

  describe "GET /web/invoices/:id/edit" do
    let!(:location) { create(:stock_location) }

    it "freezes the amount and lists the lines read-only on an itemized invoice" do
      product = create(:product, current_stock: 0)
      invoice = Invoices::CreateInvoice.call(
        supplier: supplier, invoice_number: "FAC-6", amount: nil, currency: "ARS",
        purchase_date: Date.current, due_date: 30.days.from_now,
        items: [ { product_id: product.id, quantity: 3, unit_cost: 100 } ]
      ).record

      get "/web/invoices/#{invoice.id}/edit"

      html = Nokogiri::HTML(response.body)
      expect(html.at("#invoice_amount")["readonly"]).to be_present
      expect(response.body).to include("Calculado desde los productos; no se edita.")
      expect(html.at("#invoice-lines")).to be_present
      expect(response.body).to include("Las líneas no se editan. Si la factura está mal cargada, cancelala y registrala de nuevo.")
    end

    it "keeps the amount editable on an amount-only invoice" do
      invoice = create(:invoice, :simple_mode, supplier: supplier)

      get "/web/invoices/#{invoice.id}/edit"

      expect(Nokogiri::HTML(response.body).at("#invoice_amount")["readonly"]).to be_nil
    end
  end
end
