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

  describe "GET /web/invoices/:id/edit supplier choices" do
    let(:afip)     { create(:supplier, name: "AFIP", expense_types: %w[taxes]) }
    let!(:billing) { create(:supplier, name: "Bills Taxes", expense_types: %w[taxes]) }
    let!(:other)   { create(:supplier, name: "Only Goods") }

    def selectable_names(html)
      html.css("#invoice_supplier_id option").reject { |o| o["disabled"] || o["value"].blank? }.map(&:text)
    end

    it "lists the suppliers billing the invoice type and no others" do
      invoice = create(:invoice, :simple_mode, :in_ars, supplier: afip, expense_type: "taxes")

      get "/web/invoices/#{invoice.id}/edit"

      html = Nokogiri::HTML(response.body)
      expect(selectable_names(html)).to contain_exactly("AFIP", "Bills Taxes")
      expect(html.at("#invoice_supplier_id option[value='#{billing.id}']")["data-expense-types"]).to eq("taxes")
    end

    it "keeps the current supplier even when it no longer bills the type" do
      invoice = create(:invoice, :simple_mode, :in_ars, supplier: afip, expense_type: "taxes")
      afip.update!(expense_types: %w[utilities])

      get "/web/invoices/#{invoice.id}/edit"

      html = Nokogiri::HTML(response.body)
      expect(selectable_names(html)).to contain_exactly("AFIP", "Bills Taxes")
      expect(html.at("#invoice_supplier_id option[selected]").text).to eq("AFIP")
    end

    it "refuses an update that picks a supplier not billing the type" do
      invoice = create(:invoice, :simple_mode, :in_ars, supplier: afip, expense_type: "taxes")

      patch web_invoice_path(invoice), params: { invoice: { supplier_id: other.id } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Only Goods no factura Impuestos")
      expect(invoice.reload.supplier).to eq(afip)
    end
  end

  describe "expense type" do
    let(:afip) { create(:supplier, name: "AFIP", expense_types: %w[supplier taxes social_charges utilities]) }

    it "creates a tax invoice" do
      post web_invoices_path, params: {
        supplier_id: afip.id, expense_type: "taxes", period: "2026-09", amount: "250.000,00",
        currency: "ARS", purchase_date: Date.current.to_s, due_date: (Date.current + 10).to_s
      }
      expect(Invoice.last.expense_type).to eq("taxes")
    end

    it "refuses an unknown type on create without a server error" do
      expect {
        post web_invoices_path, params: {
          supplier_id: afip.id, expense_type: "bogus", invoice_number: "X-1", amount: "100,00",
          currency: "ARS", purchase_date: Date.current.to_s, due_date: (Date.current + 10).to_s
        }
      }.not_to change(Invoice, :count)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Tipo de factura inválido")
    end

    it "changes the type of an amount-only invoice" do
      invoice = create(:invoice, :simple_mode, :in_ars, supplier: afip)
      patch web_invoice_path(invoice), params: { invoice: { expense_type: "utilities", period: "2026-09" } }
      expect(invoice.reload.expense_type).to eq("utilities")
    end

    it "ignores an unknown type on update instead of raising" do
      invoice = create(:invoice, :simple_mode, :in_ars, supplier: afip)
      patch web_invoice_path(invoice), params: { invoice: { expense_type: "bogus" } }
      expect(response).to redirect_to(web_invoice_path(invoice))
      expect(invoice.reload.expense_type).to eq("supplier")
    end

    it "keeps the type of an invoice with product lines" do
      invoice = create(:invoice, :simple_mode, :in_ars, supplier: afip)
      invoice.invoice_items.create!(product: create(:product), quantity: 1, unit_cost: 10)
      patch web_invoice_path(invoice), params: { invoice: { expense_type: "taxes" } }
      expect(invoice.reload.expense_type).to eq("supplier")
    end

    it "filters the index by type" do
      create(:invoice, :simple_mode, :in_ars, supplier: afip, expense_type: "taxes", detail: "TAX-1")
      create(:invoice, :simple_mode, :in_ars, invoice_number: "SUP-1")
      get web_invoices_path, params: { expense_type: "taxes" }
      expect(response.body).to include("TAX-1")
      expect(response.body).not_to include("SUP-1")
    end
  end

  describe "identification by type" do
    let(:afip) { create(:supplier, name: "AFIP", expense_types: %w[supplier taxes social_charges utilities]) }

    def taxes_params(overrides = {})
      { supplier_id: afip.id, expense_type: "taxes", period: "2026-09", detail: "IVA", amount: "250.000,00",
        currency: "ARS", purchase_date: Date.current.to_s, due_date: (Date.current + 10).to_s }.merge(overrides)
    end

    def field_group(html, name)
      html.at("fieldset[data-invoice-form-target='#{name}']")
    end

    matcher :have_attribute do |name|
      match { |node| node.has_attribute?(name) }
    end

    describe "POST /web/invoices" do
      it "registers a taxes invoice by period and detail, and lists it under Comprobante" do
        post web_invoices_path, params: taxes_params

        invoice = Invoice.last
        expect(invoice.period).to eq(Date.new(2026, 9, 1))
        expect(invoice.detail).to eq("IVA")
        expect(invoice.invoice_number).to be_nil

        get web_invoices_path
        html = Nokogiri::HTML(response.body)
        expect(html.css("th").map { |th| th.text.strip }).to include("Comprobante")
        expect(html.css("td").map { |td| td.text.strip }).to include("IVA · 09/2026")
      end

      it "reads the period as the first of its month and ignores an unreadable one" do
        post web_invoices_path, params: taxes_params(period: "2026-13")

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Falta el período")
        expect(Invoice.count).to eq(0)
      end

      it "reads a period typed as MM/YYYY or M/YYYY" do
        post web_invoices_path, params: taxes_params(period: "09/2026")
        post web_invoices_path, params: taxes_params(period: "3/2026", detail: "Ganancias")

        expect(Invoice.order(:id).pluck(:period)).to eq([ Date.new(2026, 9, 1), Date.new(2026, 3, 1) ])
      end

      it "refuses a typed period with an invalid month" do
        post web_invoices_path, params: taxes_params(period: "13/2026")

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Falta el período")
      end

      it "refuses a detail over 40 characters" do
        post web_invoices_path, params: taxes_params(detail: "a" * 41)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("El detalle no puede superar 40 caracteres")
      end

      it "refuses a taxes invoice in dollars" do
        post web_invoices_path, params: taxes_params(currency: "USD", exchange_rate: "1.200,00")

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Las boletas de Impuestos son en pesos")
      end

      it "refuses a supplier invoice without a number" do
        post web_invoices_path, params: taxes_params(expense_type: "supplier", invoice_number: "")

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Invoice number is required")
      end

      it "keeps the period and detail fields, and their values, when the server refuses" do
        post web_invoices_path, params: taxes_params(amount: "")

        expect(response).to have_http_status(:unprocessable_entity)
        html = Nokogiri::HTML(response.body)
        expect(html.at("input[name='period']")["value"]).to eq("2026-09")
        expect(html.at("input[name='detail']")["value"]).to eq("IVA")
        expect(field_group(html, "periodField")).not_to have_attribute("hidden")
        expect(field_group(html, "numberField")).to have_attribute("hidden")
        expect(field_group(html, "numberField")).to have_attribute("disabled")
      end
    end

    describe "GET /web/invoices/new" do
      it "shows the number for a supplier and the period for the other types" do
        get new_web_invoice_path

        html = Nokogiri::HTML(response.body)
        expect(field_group(html, "numberField")).not_to have_attribute("hidden")
        expect(field_group(html, "periodField")).to have_attribute("hidden")
        expect(html.at("input[name='period']")["type"]).to eq("month")
        expect(html.at("input[name='period']")["value"]).to eq(Date.current.prev_month.strftime("%Y-%m"))
        expect(html.at("input[name='detail']")["maxlength"]).to eq("40")
      end
    end

    describe "GET /web/invoices" do
      let!(:iva)  { create(:invoice, :simple_mode, :in_ars, supplier: afip, expense_type: "taxes", detail: "IVA", period: Date.new(2026, 9, 1)) }
      let!(:sicoss) { create(:invoice, :simple_mode, :in_ars, supplier: afip, expense_type: "social_charges", detail: "SICOSS", period: Date.new(2026, 8, 1)) }
      let!(:fac)  { create(:invoice, :simple_mode, :in_ars, supplier: supplier, invoice_number: "FAC-777") }

      it "finds a non-supplier invoice by detail or period, and a supplier one by number" do
        get web_invoices_path, params: { invoice_search: "IVA" }
        expect(response.body).to include("IVA · 09/2026")
        expect(response.body).not_to include("SICOSS · 08/2026")

        get web_invoices_path, params: { invoice_search: "08/2026" }
        expect(response.body).to include("SICOSS · 08/2026")
        expect(response.body).not_to include("IVA · 09/2026")

        get web_invoices_path, params: { invoice_search: "FAC-777" }
        expect(response.body).to include("FAC-777")
        expect(response.body).not_to include("IVA · 09/2026")
      end

      it "names the number, detail and period in the search placeholder" do
        get web_invoices_path

        placeholder = Nokogiri::HTML(response.body).at("input[name='invoice_search']")["placeholder"]
        expect(placeholder).to include("detalle").and include("período")
      end
    end

    describe "GET /web/invoices/:id" do
      it "titles the page and shows the Comprobante row with the reference" do
        invoice = create(:invoice, :simple_mode, :in_ars, supplier: afip, expense_type: "taxes", detail: "IVA", period: Date.new(2026, 9, 1))

        get web_invoice_path(invoice)

        html = Nokogiri::HTML(response.body)
        expect(html.css("h1").map { |h| h.text.squish }).to include("Factura IVA · 09/2026")
        expect(response.body).to include("Comprobante:")
        expect(response.body).not_to include("N° Factura")
        expect(response.body).to include("Pagar factura IVA · 09/2026")
      end

      it "names the sibling invoices of the same payment by reference" do
        iva = create(:invoice, :simple_mode, :in_ars, supplier: afip, expense_type: "taxes", detail: "IVA", period: Date.new(2026, 9, 1))
        gan = create(:invoice, :simple_mode, :in_ars, supplier: afip, expense_type: "taxes", detail: "Ganancias", period: Date.new(2026, 9, 1))
        Invoices::PayInvoices.call(invoices: [ iva, gan ], account: "main_cash", payment_date: Date.current, user: admin)

        get web_invoice_path(iva)

        expect(response.body).to include("Pagada junto con Ganancias · 09/2026")
      end
    end

    describe "GET /web/suppliers/:id" do
      it "lists the pending and paid invoices of a non-supplier type by reference" do
        create(:invoice, :simple_mode, :in_ars, supplier: afip, expense_type: "taxes", detail: "IVA", period: Date.new(2026, 9, 1))
        create(:invoice, :paid, :in_ars, supplier: afip, expense_type: "taxes", detail: "Ganancias", period: Date.new(2026, 8, 1))

        get web_supplier_path(afip)

        expect(response.body).to include("IVA · 09/2026")
        expect(response.body).to include("Ganancias · 08/2026")
      end
    end

    describe "GET /web/invoices/:id/edit" do
      it "shows the period and detail of a non-supplier invoice and hides the number" do
        invoice = create(:invoice, :simple_mode, :in_ars, supplier: afip, expense_type: "taxes", detail: "IVA", period: Date.new(2026, 9, 1))

        get edit_web_invoice_path(invoice)

        html = Nokogiri::HTML(response.body)
        expect(html.css("h1").map { |h| h.text.squish }).to include("Editar Factura IVA · 09/2026")
        expect(html.at("input[name='invoice[period]']")["value"]).to eq("2026-09")
        expect(html.at("input[name='invoice[detail]']")["value"]).to eq("IVA")
        expect(field_group(html, "numberField")).to have_attribute("disabled")
        expect(field_group(html, "periodField")).not_to have_attribute("hidden")
      end

      it "shows the number of a supplier invoice and hides the period" do
        invoice = create(:invoice, :simple_mode, :in_ars, invoice_number: "FAC-9")

        get edit_web_invoice_path(invoice)

        html = Nokogiri::HTML(response.body)
        expect(html.at("input[name='invoice[invoice_number]']")["value"]).to eq("FAC-9")
        expect(field_group(html, "periodField")).to have_attribute("disabled")
      end
    end

    describe "PATCH /web/invoices/:id" do
      it "clears the number when a supplier invoice becomes taxes" do
        invoice = create(:invoice, :simple_mode, :in_ars, supplier: afip, invoice_number: "FAC-1")

        patch web_invoice_path(invoice), params: { invoice: { expense_type: "taxes", period: "2026-09", detail: "IVA", invoice_number: "FAC-1" } }

        invoice.reload
        expect(invoice.expense_type).to eq("taxes")
        expect(invoice.invoice_number).to be_nil
        expect(invoice.period).to eq(Date.new(2026, 9, 1))
        expect(invoice.reference).to eq("IVA · 09/2026")
      end

      it "refuses turning a supplier invoice into taxes without a period" do
        invoice = create(:invoice, :simple_mode, :in_ars, supplier: afip, invoice_number: "FAC-1")

        patch web_invoice_path(invoice), params: { invoice: { expense_type: "taxes", period: "" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Falta el período")
        expect(invoice.reload.expense_type).to eq("supplier")
      end

      it "clears the period and detail when taxes becomes a supplier invoice with a number" do
        invoice = create(:invoice, :simple_mode, :in_ars, supplier: afip, expense_type: "taxes", detail: "IVA", period: Date.new(2026, 9, 1))

        patch web_invoice_path(invoice), params: { invoice: { expense_type: "supplier", invoice_number: "FAC-2", period: "2026-09", detail: "IVA" } }

        invoice.reload
        expect(invoice.expense_type).to eq("supplier")
        expect(invoice.invoice_number).to eq("FAC-2")
        expect(invoice.period).to be_nil
        expect(invoice.detail).to be_nil
      end

      it "refuses turning taxes into a supplier invoice without a number" do
        invoice = create(:invoice, :simple_mode, :in_ars, supplier: afip, expense_type: "taxes", detail: "IVA", period: Date.new(2026, 9, 1))

        patch web_invoice_path(invoice), params: { invoice: { expense_type: "supplier", invoice_number: "" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Invoice number can&#39;t be blank")
        expect(invoice.reload.expense_type).to eq("taxes")
        expect(invoice.period).to eq(Date.new(2026, 9, 1))

        html = Nokogiri::HTML(response.body)
        expect(html.css("h1").map { |h| h.text.squish }).to include("Editar Factura IVA · 09/2026")
        expect(html.at("input[name='invoice[period]']")["value"]).to eq("2026-09")
        expect(html.at("input[name='invoice[detail]']")["value"]).to eq("IVA")
      end

      it "re-renders a refused USD to taxes edit with the supplier number still in the form" do
        invoice = create(:invoice, :simple_mode, supplier: afip, currency: "USD", exchange_rate: 1200, invoice_number: "FAC-1")

        patch web_invoice_path(invoice), params: { invoice: { expense_type: "taxes", period: "2026-09" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Las boletas de Impuestos son en pesos")
        html = Nokogiri::HTML(response.body)
        expect(html.at("input[name='invoice[invoice_number]']")["value"]).to eq("FAC-1")
        expect(html.css("h1").map { |h| h.text.squish }).to include("Editar Factura FAC-1")
        expect(invoice.reload.invoice_number).to eq("FAC-1")
      end

      it "updates the period and detail of a non-supplier invoice" do
        invoice = create(:invoice, :simple_mode, :in_ars, supplier: afip, expense_type: "taxes", detail: "IVA", period: Date.new(2026, 9, 1))

        patch web_invoice_path(invoice), params: { invoice: { period: "2026-08", detail: "Ganancias" } }

        expect(invoice.reload.reference).to eq("Ganancias · 08/2026")
      end
    end
  end

  describe "index credit cards under the type filter" do
    let(:afip) { create(:supplier, name: "AFIP", expense_types: %w[supplier taxes social_charges utilities]) }

    before do
      create(:credit_note, supplier: supplier, amount: 5_000)
      create(:invoice, :simple_mode, :in_ars, supplier: afip, expense_type: "taxes", detail: "TAX-9")
    end

    it "shows the available credit when the type is supplier or unset" do
      get web_invoices_path
      expect(response.body).to include("5.000,00")
    end

    it "shows no credit under a type that credit notes do not apply to" do
      get web_invoices_path, params: { expense_type: "taxes" }
      expect(response.body).not_to include("5.000,00")
    end
  end

  describe "invoice page payment" do
    let(:afip) { create(:supplier, name: "AFIP", expense_types: %w[supplier taxes social_charges utilities]) }
    let(:invoice) do
      create(:invoice, :simple_mode, :in_ars, supplier: afip, amount: 250_000, expense_type: "taxes",
             detail: "IIBB", period: Date.new(2026, 9, 1), purchase_date: Date.current - 5)
    end

    it "offers the four origins and the type" do
      get web_invoice_path(invoice)
      %w[Caja\ del\ día Caja\ grande Banco Mercado\ Pago].each { |label| expect(response.body).to include(label) }
      expect(response.body).to include("Impuestos")
      expect(response.body).to include("Pagar")
    end

    it "shows where a paid invoice was paid from" do
      Invoices::PayInvoices.call(invoices: [ invoice ], account: "main_cash", payment_date: Date.current, user: create(:user, :admin))
      get web_invoice_path(invoice)
      expect(response.body).to include("desde Caja grande")
      expect(response.body).to include(web_cash_day_path(Date.current.to_s))
    end

    it "says no money left when credit notes covered the invoice" do
      credit = create(:credit_note, supplier: afip, amount: 300_000)
      invoice.update!(expense_type: "supplier", invoice_number: "FAC-1")
      Invoices::PayInvoices.call(invoices: [ invoice ], account: "main_cash", payment_date: Date.current,
                                 user: create(:user, :admin), credit_note_ids: [ credit.id ])
      get web_invoice_path(invoice)
      expect(response.body).to include("con notas de crédito · no salió plata")
    end

    it "says no money left when a USD note rounded up to cover the invoice" do
      invoice.update!(expense_type: "supplier", invoice_number: "FAC-1", amount: 1_000)
      credit = create(:credit_note, :usd, supplier: afip, amount: 1, exchange_rate: 1200)
      Invoices::PayInvoices.call(invoices: [ invoice ], account: "main_cash", payment_date: Date.current,
                                 user: create(:user, :admin), credit_note_ids: [ credit.id ])
      get web_invoice_path(invoice)
      expect(response.body).to include("no salió plata")
    end

    it "does not claim that no money left for a legacy invoice paid partly with credits" do
      credit = create(:credit_note, supplier: afip, amount: 5_000)
      invoice.update!(expense_type: "supplier", invoice_number: "FAC-1")
      AppliedCredit.create!(credit_note: credit, invoice: invoice, amount: 5_000, applied_at: Date.current)
      invoice.update!(status: "paid", paid_at: Date.current)
      get web_invoice_path(invoice)
      expect(response.body).to include("Pagada el #{Date.current.strftime('%d/%m/%Y')}")
      expect(response.body).not_to include("no salió plata")
    end

    it "shows only the date for an invoice paid before invoices wrote outflows" do
      invoice.update!(status: "paid", paid_at: Date.current)
      get web_invoice_path(invoice)
      expect(response.body).to include("Pagada el #{Date.current.strftime('%d/%m/%Y')}")
    end
  end
end
