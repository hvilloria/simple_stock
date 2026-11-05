# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::Products edit/update", type: :request do
  let(:vendedor) { create(:user, role: "vendedor") }
  let(:admin)    { create(:user, role: "admin") }
  let(:caja)     { create(:user, role: "caja") }
  let(:product)  { create(:product, name: "Disco viejo", brand: "Generic Brand", price_unit: 100) }

  describe "GET /web/products/search" do
    before { sign_in vendedor }

    it "includes each product's channel prices" do
      product.channel_prices.create!(channel: "mercadolibre", price: 15_000)
      get search_web_products_path, params: { q: product.name }

      item = JSON.parse(response.body).find { |p| p["id"] == product.id }
      expect(item["price_unit"].to_f).to eq(100.0)
      expect(item["channel_prices_map"]).to eq("mercadolibre" => 15_000.0)
    end

    context "with combos" do
      let!(:front) { create(:product, sku: "12345-123-12345", name: "Amortiguador izquierdo", current_stock: 4) }
      let!(:rear)  { create(:product, sku: "12345-456-12345", name: "Amortiguador derecho") }
      let!(:pair) do
        create(:product, :combo, name: "Aa par amortiguadores", components: [ [ front, 2 ], [ rear, 1 ] ])
      end

      it "returns regular products first and the combo with its components when asked" do
        get search_web_products_path, params: { q: "456", include_combos: "1" }

        items = JSON.parse(response.body)
        expect(items.map { |p| p["id"] }).to eq([ rear.id, pair.id ])
        expect(items.first).to include("combo" => false, "components" => [])
        expect(items.second["combo"]).to be(true)
        expect(items.second["components"]).to contain_exactly(
          { "sku" => "12345-123-12345", "name" => "Amortiguador izquierdo", "quantity" => 2, "current_stock" => 4 },
          { "sku" => "12345-456-12345", "name" => "Amortiguador derecho", "quantity" => 1,
            "current_stock" => rear.current_stock }
        )
      end

      it "leaves combos out by default" do
        get search_web_products_path, params: { q: "456" }

        expect(JSON.parse(response.body).map { |p| p["id"] }).to eq([ rear.id ])
      end

      it "keeps the combos after a full page of regular products" do
        regulars = Array.new(11) { |i| create(:product, name: format("Bb amortiguador %02d", i), sku: "X-456-#{i}") }
        get search_web_products_path, params: { q: "456", include_combos: "1" }

        ids = JSON.parse(response.body).map { |p| p["id"] }
        expect(ids.size).to eq(11)
        expect(ids.last).to eq(pair.id)
        expect(ids.first(10)).to all(satisfy { |id| ([ rear.id ] + regulars.map(&:id)).include?(id) })
      end

      it "never returns an archived combo" do
        pair.update!(active: false)
        get search_web_products_path, params: { q: "456", include_combos: "1" }

        expect(JSON.parse(response.body).map { |p| p["id"] }).to eq([ rear.id ])
      end
    end
  end

  describe "GET /web/products" do
    before { sign_in vendedor }

    it "paginates active products at 20 per page" do
      21.times { |i| create(:product, name: format("Producto %02d", i + 1)) }

      get web_products_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Producto 01")
      expect(response.body).not_to include("Producto 21")

      get web_products_path, params: { page: 2 }
      expect(response.body).to include("Producto 21")
    end

    it "composes search filter with pagination" do
      25.times { |i| create(:product, name: format("Filtro %02d", i + 1), brand: "FRAM") }
      create(:product, name: "Pastilla unica", brand: "Brembo")

      get web_products_path, params: { q: "FRAM" }
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Pastilla unica")
      expect(response.body).to include("Filtro 01")
      expect(response.body).not_to include("Filtro 25")

      get web_products_path, params: { q: "FRAM", page: 2 }
      expect(response.body).to include("Filtro 25")
    end
  end

  describe "GET /web/products with combos" do
    let!(:left)  { create(:product, sku: "12345-123-12345", name: "Amortiguador izquierdo", current_stock: 7) }
    let!(:right) { create(:product, sku: "12345-456-12345", name: "Amortiguador derecho", current_stock: 7) }
    let!(:pair) do
      create(:product, :combo, name: "Par amortiguadores", price_unit: 100_000,
                               components: [ [ left, 1 ], [ right, 2 ] ])
    end
    let!(:archived) do
      create(:product, :combo, name: "Par archivado", active: false, components: [ [ left, 1 ], [ right, 1 ] ])
    end

    def combo_cells(name)
      row = Nokogiri::HTML(response.body).css("tbody tr").find { |tr| tr.text.include?(name) }
      row.css("td").map { |td| td.text.squish }
    end

    def combo_row(name)
      combo_cells(name).join(" ")
    end

    context "as a vendedor" do
      before { sign_in vendedor }

      it "shows a combo in the Todos tab with its parts and no stock" do
        get web_products_path, params: { q: "456" }

        expect(combo_row("Par amortiguadores")).to include("Combo", "Incluye: 12345-123-12345 · 12345-456-12345")
        expect(combo_cells("Par amortiguadores")[6]).to eq("—")
        expect(response.body).to include("Amortiguador derecho")
      end

      it "lists only active combos in the Combos tab, with the active count on the tab" do
        get web_products_path, params: { tab: "combos" }

        expect(combo_row("Par amortiguadores")).to include("1 × 12345-123-12345", "2 × 12345-456-12345", "Activo")
        expect(response.body).not_to include("Par archivado")
        expect(response.body).not_to include("Amortiguador derecho")
        expect(response.body).to match(/Combos\s*<span[^>]*>\(1\)/)
      end

      it "lists only archived combos when asked" do
        get web_products_path, params: { tab: "combos", combo_status: "archived" }

        expect(combo_row("Par archivado")).to include("Archivado")
        expect(response.body).not_to include("Par amortiguadores")
      end

      it "lists every combo under Todos" do
        get web_products_path, params: { tab: "combos", combo_status: "all" }

        expect(response.body).to include("Par amortiguadores", "Par archivado")
      end

      it "offers neither creating nor editing combos" do
        get web_products_path, params: { tab: "combos" }

        expect(response.body).not_to include("Nuevo Combo")
        expect(response.body).not_to include(edit_web_combo_path(pair))
      end
    end

    context "as an admin" do
      before { sign_in admin }

      it "offers creating and editing combos" do
        get web_products_path, params: { tab: "combos" }

        expect(response.body).to include("Nuevo Combo", edit_web_combo_path(pair))
      end

      it "invites creating the first combo when there is none" do
        Product.combos.destroy_all
        get web_products_path, params: { tab: "combos" }

        expect(response.body).to include("Todavía no hay combos.", "Crear el primero")
      end

      it "says no combo matched when combos exist but the filter leaves none" do
        archived.destroy
        get web_products_path, params: { tab: "combos", combo_status: "archived" }

        expect(response.body).to include("No se encontraron combos.")
        expect(response.body).not_to include("Todavía no hay combos.", "Crear el primero")
      end
    end
  end

  describe "GET /web/products/:id/edit" do
    it "permite a un vendedor abrir la edición" do
      sign_in vendedor
      get edit_web_product_path(product)
      expect(response).to have_http_status(:ok)
    end

    it "permite a un admin abrir la edición" do
      sign_in admin
      get edit_web_product_path(product)
      expect(response).to have_http_status(:ok)
    end

    it "redirige a caja (no autorizado)" do
      sign_in caja
      get edit_web_product_path(product)
      expect(response).to have_http_status(:redirect)
    end
  end

  describe "PATCH /web/products/:id" do
    before { sign_in vendedor }

    it "actualiza campos descriptivos y de precio" do
      patch web_product_path(product), params: {
        product: { name: "Disco nuevo", brand: "TRW", origin: "japan", price_unit: "250,50" }
      }

      expect(response).to redirect_to(web_product_path(product))
      follow_redirect!
      product.reload
      expect(product.name).to eq("Disco nuevo")
      expect(product.brand).to eq("TRW")
      expect(product.origin).to eq("japan")
      expect(product.price_unit).to eq(250.50)
    end

    it "no modifica el sku aunque venga en params" do
      original_sku = product.sku
      patch web_product_path(product), params: {
        product: { sku: "HACKED999", name: "Otro nombre" }
      }

      product.reload
      expect(product.sku).to eq(original_sku)
      expect(product.name).to eq("Otro nombre")
    end

    it "re-renderiza edit con 422 cuando es inválido" do
      patch web_product_path(product), params: {
        product: { name: "" }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(product.reload.name).to eq("Disco viejo")
    end

    it "rechaza un cambio de variante que colisiona con otra variante del mismo sku" do
      existing = create(:product, sku: "OEM-123", product_type: "aftermarket", origin: "china", brand: "Marca1")
      target   = create(:product, sku: "OEM-123", product_type: "aftermarket", origin: "japan",  brand: "Marca1")

      patch web_product_path(target), params: {
        product: { origin: "china" }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(target.reload.origin).to eq("japan")
    end
  end

  describe "product cost in the product form" do
    let(:costed) { create(:product, name: "Disco", price_unit: 15_000, cost_unit: 8_100, cost_currency: "ARS") }

    it "hides the cost fields from a vendedor and shows them to an admin" do
      sign_in vendedor
      get edit_web_product_path(costed)
      expect(response.body).not_to include("Costo Unitario", "Moneda del Costo", "8.100,00")
      get new_web_product_path
      expect(response.body).not_to include("Costo Unitario", "Moneda del Costo")

      sign_in admin
      get edit_web_product_path(costed)
      expect(response.body).to include("Costo Unitario", "Moneda del Costo", "8.100,00")
    end

    it "ignores a cost sent by a vendedor while saving the other fields" do
      sign_in vendedor
      patch web_product_path(costed), params: {
        product: { name: "Disco nuevo", cost_unit: "1,00", cost_currency: "USD" }
      }

      costed.reload
      expect(costed.name).to eq("Disco nuevo")
      expect([ costed.cost_unit, costed.cost_currency ]).to eq([ 8_100, "ARS" ])
    end

    it "ignores a cost sent by a vendedor creating a product" do
      sign_in vendedor
      post web_products_path, params: {
        product: { sku: "BUJE-COST", name: "Buje", brand: "X", product_type: "aftermarket",
                   origin: "china", price_unit: "10.000,00", cost_unit: "5.000,00", active: "1" }
      }

      created = Product.find_by!(sku: "BUJE-COST")
      expect(created.cost_unit).to be_nil
    end

    it "lets an admin edit the cost" do
      sign_in admin
      patch web_product_path(costed), params: { product: { cost_unit: "9.692,10" } }

      expect(costed.reload.cost_unit).to eq(BigDecimal("9692.10"))
    end
  end

  describe "editing a combo through the product routes" do
    let!(:combo) { create(:product, :combo, name: "Kit") }

    it "refuses a vendedor PATCH and leaves the combo unchanged" do
      sign_in vendedor
      patch web_product_path(combo), params: { product: { name: "Hackeado", price_unit: "1,00" } }

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to eq("No tiene permiso para realizar esta acción.")
      expect(combo.reload.name).to eq("Kit")
    end

    it "sends an admin to the combo form" do
      sign_in admin

      get edit_web_product_path(combo)
      expect(response).to redirect_to(edit_web_combo_path(combo))

      patch web_product_path(combo), params: { product: { name: "Otro" } }
      expect(response).to redirect_to(edit_web_combo_path(combo))
      expect(combo.reload.name).to eq("Kit")
    end
  end

  describe "DELETE /web/products/:id" do
    let!(:target) { create(:product, name: "Para borrar") }

    it "lets an admin soft-delete the product" do
      sign_in admin
      delete web_product_path(target)

      expect(response).to redirect_to(web_products_path)
      expect(Product.exists?(target.id)).to be(false)          # hidden by default scope
      expect(Product.with_deleted.find(target.id).deleted_at).to be_present
      follow_redirect!
      expect(response.body).to include("Producto eliminado exitosamente")
    end

    it "forbids a vendedor" do
      sign_in vendedor
      delete web_product_path(target)

      expect(response).to have_http_status(:redirect)
      expect(Product.exists?(target.id)).to be(true)
    end

    it "forbids caja" do
      sign_in caja
      delete web_product_path(target)

      expect(response).to have_http_status(:redirect)
      expect(Product.exists?(target.id)).to be(true)
    end

    it "keeps a combo with sales and explains why" do
      combo = create(:product, :combo)
      create(:order_item, product: combo, order: create(:order, :cancelled))
      sign_in admin

      delete web_product_path(combo)

      expect(response).to redirect_to(web_product_path(combo))
      expect(flash[:alert]).to eq("El combo tiene ventas: solo se puede archivar")
      expect(Product.exists?(combo.id)).to be(true)
    end

    it "names a deleted combo as a combo" do
      combo = create(:product, :combo)
      sign_in admin

      delete web_product_path(combo)

      expect(response).to redirect_to(web_products_path)
      expect(flash[:notice]).to eq("Combo eliminado")
    end
  end

  describe "GET /web/products/:id — stock movements" do
    let!(:location) { create(:stock_location) }

    it "names the sale note behind a sale movement" do
      order = create(:order, :on_account, paper_number: "3340", total_amount: 100, original_total_amount: 100)
      line  = create(:order_item, order: order, product: product, quantity: 1, unit_price: 100)
      create(:stock_movement, :sale, product: product, stock_location: location, reference: line)

      sign_in admin
      get "/web/products/#{product.id}"

      expect(response.body).to include("Nota 3340")
    end

    it "names the admin and the reason behind a stock adjustment" do
      counter = create(:user, :admin, name: "Hosward")
      create(:stock_movement, product: product, stock_location: location, quantity: -3,
                              movement_type: "adjustment", note: "Conteo de fin de mes", user: counter)

      sign_in admin
      get "/web/products/#{product.id}"

      expect(response.body).to include("Hosward · Conteo de fin de mes")
    end

    it "keeps showing the note of an adjustment nobody signed" do
      create(:stock_movement, product: product, stock_location: location, quantity: 1,
                              movement_type: "adjustment", note: "Anulación nota 3301")

      sign_in admin
      get "/web/products/#{product.id}"

      expect(response.body).to include("Anulación nota 3301")
      expect(response.body).not_to include("· Anulación nota 3301")
    end

    it "offers the adjustment page to an admin only" do
      sign_in admin
      get "/web/products/#{product.id}"
      expect(response.body).to include(new_web_stock_adjustment_path(product_id: product.id))

      sign_in vendedor
      get "/web/products/#{product.id}"
      expect(response.body).not_to include(new_web_stock_adjustment_path(product_id: product.id))
    end
  end

  describe "GET /web/products/:id — cost" do
    let!(:location) { create(:stock_location) }
    let(:supplier)  { create(:supplier) }
    let(:product)   { create(:product, price_unit: 15_000, cost_unit: 8_100, cost_currency: "USD") }

    # Discount 10 and IVA 21: 8.900 printed is 9.692,10 final.
    def register(number, purchase_date: Date.new(2026, 11, 4), discount: 10, iva: 21)
      Invoices::CreateInvoice.call(
        supplier: supplier, invoice_number: number, amount: nil, currency: "ARS",
        purchase_date: purchase_date, due_date: purchase_date + 30, discount_percentage: discount, iva_percentage: iva,
        items: [ { product_id: product.id, quantity: 1, unit_cost: "8900" } ]
      ).record
    end

    def financial_text
      Nokogiri::HTML(response.body).text.squish
    end

    it "shows an admin the last purchase cost with its source invoice" do
      invoice = register("0003-00010197")
      sign_in admin

      get web_product_path(product)

      expect(financial_text).to include("Costo (última compra) ARS 9.692,10")
      expect(financial_text).to include("Factura #{invoice.reference} · 04/11/2026 · con IVA y descuento")
      link = Nokogiri::HTML(response.body).at_css("a[href='#{web_invoice_path(invoice)}']")
      expect(link.text.squish).to eq(invoice.reference)
      expect(response.body).not_to include("Cargado a mano o anterior al registro de compras con IVA")
      expect(response.body).to include("Margen")
    end

    it "links the purchase that set the cost when two share the same cost" do
      register("0003-00000001", purchase_date: Date.new(2026, 11, 10))
      newer = register("0003-00000002", purchase_date: Date.new(2026, 11, 1))
      sign_in admin

      get web_product_path(product)

      expect(financial_text).to include("Factura #{newer.reference} · 01/11/2026")
    end

    it "links the invoice recorded as the cost source" do
      older = register("0003-00000001")
      register("0003-00000002")
      product.update_columns(cost_source_invoice_item_id: older.invoice_items.first.id)
      sign_in admin

      get web_product_path(product)

      expect(financial_text).to include("Factura #{older.reference} · 04/11/2026")
    end

    it "shows no source invoice once that invoice is cancelled" do
      invoice = register("0003-00010197")
      invoice.update_columns(status: "cancelled")
      sign_in admin

      get web_product_path(product)

      expect(financial_text).to include("Costo ARS 9.692,10")
      expect(response.body).not_to include("Costo (última compra)")
    end

    it "treats a hand cost equal to an old purchase's cost as a hand cost" do
      register("0003-00010197")
      product.reload.update!(cost_unit: 9_000)
      product.update!(cost_unit: BigDecimal("9692.10"))
      sign_in admin

      get web_product_path(product)

      expect(financial_text).to include("Costo ARS 9.692,10", "Cargado a mano o anterior al registro de compras con IVA")
      expect(response.body).not_to include("Costo (última compra)")
    end

    it "names only the IVA when the invoice had no discount" do
      invoice = register("0003-00010197", discount: 0)
      sign_in admin

      get web_product_path(product)

      expect(financial_text).to include("Factura #{invoice.reference} · 04/11/2026 · con IVA Margen")
    end

    it "adds nothing after the date when the invoice had neither discount nor IVA" do
      invoice = register("0003-00010197", discount: 0, iva: 0)
      sign_in admin

      get web_product_path(product)

      expect(financial_text).to include("Factura #{invoice.reference} · 04/11/2026 Margen")
    end

    it "shows a legacy cost in its stored currency without a source invoice" do
      sign_in admin

      get web_product_path(product)

      expect(financial_text).to include("Costo USD 8.100,00")
      expect(response.body).to include("Cargado a mano o anterior al registro de compras con IVA")
      expect(response.body).not_to include("Costo (última compra)")
    end

    it "shows no cost caption when the product has no cost" do
      product.update!(cost_unit: nil)
      sign_in admin

      get web_product_path(product)

      expect(financial_text).to include("Sin costo registrado")
      expect(response.body).not_to include("Cargado a mano o anterior al registro de compras con IVA")
    end

    it "drops the source invoice once the cost was typed by hand after the purchase" do
      register("0003-00010197")
      product.reload.update!(cost_unit: 9_000)
      sign_in admin

      get web_product_path(product)

      expect(financial_text).to include("Costo ARS 9.000,00", "Cargado a mano o anterior al registro de compras con IVA")
      expect(response.body).not_to include("Costo (última compra)")
    end

    it "hides the cost and the margin from a vendedor and a caja" do
      register("0003-00010197")

      [ vendedor, caja ].each do |user|
        sign_in user
        get web_product_path(product)

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("Costo (última compra)", "Margen",
                                             "Cargado a mano o anterior al registro de compras con IVA",
                                             "9.692,10")
      end
    end
  end

  describe "GET /web/products/:id for a combo" do
    let!(:left)  { create(:product, sku: "12345-123-12345", name: "Amortiguador izquierdo", price_unit: 70_000, current_stock: 5) }
    let!(:right) { create(:product, sku: "12345-456-12345", name: "Amortiguador derecho", price_unit: 35_000, current_stock: 3) }
    let!(:combo) do
      create(:product, :combo, name: "Par amortiguadores", price_unit: 100_000,
                               components: [ [ left, 1 ], [ right, 2 ] ])
    end

    def buttons
      page = Nokogiri::HTML(response.body)
      page.css("a, button").map { |node| node.text.squish }
    end

    it "lists the pieces, compares the price with their sum and has no stock of its own" do
      sign_in admin
      get web_product_path(combo)

      page = Nokogiri::HTML(response.body)
      rows = page.css("tbody tr").map { |tr| tr.css("td").map { |td| td.text.squish } }
      expect(rows).to contain_exactly(
        [ "12345-123-12345 Amortiguador izquierdo", "1", "5", "ARS 70.000" ],
        [ "12345-456-12345 Amortiguador derecho", "2", "3", "ARS 35.000" ]
      )
      expect(page.at_css("a[href='#{web_product_path(left)}']").text.squish).to eq("12345-123-12345")
      expect(response.body).to include("Suma de las piezas")
      expect(page.text.squish).to include("ARS 140.000 (−ARS 40.000)")
      expect(response.body).to include("El combo no tiene stock propio. Cada venta descuenta de sus piezas.")
      expect(response.body).not_to include("Ajustar stock")
      expect(response.body).not_to include("Movimientos de Stock Recientes")
      expect(response.body).not_to include("Stock Actual")
    end

    it "shows no difference when the price is not below the sum of the pieces" do
      combo.update!(price_unit: 150_000)
      sign_in admin
      get web_product_path(combo)

      expect(Nokogiri::HTML(response.body).text).not_to include("(−")
    end

    it "lets an admin edit and delete a combo without sales" do
      sign_in admin
      get web_product_path(combo)

      expect(buttons).to include("Registrar Venta", "Editar Combo", "Eliminar")
      expect(buttons).not_to include("Archivar", "Reactivar")
      expect(response.body).to include(edit_web_combo_path(combo))
    end

    it "offers an admin to archive, not delete, a combo with sales" do
      create(:order_item, product: combo, order: create(:order, :cancelled))
      sign_in admin
      get web_product_path(combo)

      expect(buttons).to include("Archivar")
      expect(buttons).not_to include("Eliminar", "Reactivar")
      form = Nokogiri::HTML(response.body).at_css("form[action='#{archive_web_combo_path(combo)}']")
      expect(form.at_css("input[name='_method']")["value"]).to eq("patch")
      expect(form.at_css("button")["data-turbo-confirm"])
        .to eq("¿Archivar este combo? Dejará de aparecer en búsquedas y en la nota de pedido.")
    end

    it "shows an archived combo with its banner and lets an admin reactivate it" do
      create(:order_item, product: combo, order: create(:order, :cancelled))
      combo.update!(active: false)
      sign_in admin
      get web_product_path(combo)

      expect(buttons).to include("Reactivar")
      expect(buttons).not_to include("Archivar", "Eliminar", "Registrar Venta")
      expect(response.body).to include(reactivate_web_combo_path(combo))
      expect(response.body).to include("Este combo está archivado. No aparece en búsquedas ni se puede vender.")
      expect(response.body).to include("Archivado")
      expect(response.body).not_to include("Este producto está inactivo")
    end

    it "shows a vendedor neither the edit nor the archive actions" do
      create(:order_item, product: combo, order: create(:order, :cancelled))
      sign_in vendedor
      get web_product_path(combo)

      expect(buttons).to include("Registrar Venta")
      expect(buttons).not_to include("Editar Combo", "Archivar", "Eliminar", "Reactivar")
    end

    it "keeps the inactive banner and the stock card for a regular product" do
      product.update!(active: false)
      sign_in admin
      get web_product_path(product)

      expect(response.body).to include("Este producto está inactivo", "Stock Actual", "Ajustar stock")
      expect(response.body).not_to include("Suma de las piezas", "El combo no tiene stock propio")
    end
  end

  describe "channel prices" do
    before { sign_in vendedor }

    it "saves an AR-formatted ML price on update" do
      patch web_product_path(product), params: { product: { name: product.name },
                                                 channel_prices: { mercadolibre: "15.000,00" } }

      expect(response).to redirect_to(web_product_path(product))
      expect(product.reload.price_for("mercadolibre")).to eq(15_000)
    end

    it "removes the ML price when the field is blank" do
      product.channel_prices.create!(channel: "mercadolibre", price: 15_000)
      patch web_product_path(product), params: { product: { name: product.name },
                                                 channel_prices: { mercadolibre: "" } }

      expect(product.reload.channel_prices).to be_empty
    end

    it "ignores a non-hash channel_prices param" do
      product.channel_prices.create!(channel: "mercadolibre", price: 15_000)

      patch web_product_path(product), params: { product: { name: "Otro" }, channel_prices: "foo" }

      expect(response).to redirect_to(web_product_path(product))
      expect(product.reload.name).to eq("Otro")
      expect(product.price_for("mercadolibre")).to eq(15_000)
    end

    it "re-renders without saving on a negative or non-numeric ML price" do
      [ "-5", "abc" ].each do |raw|
        patch web_product_path(product), params: { product: { name: "Otro" },
                                                   channel_prices: { mercadolibre: raw } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Precio Mercado Libre debe ser mayor a 0")
        expect(product.reload.name).to eq("Disco viejo")
      end
    end

    it "creates a product with its ML price" do
      post web_products_path, params: {
        product: { sku: "BUJE-NEW", name: "Buje", brand: "X", product_type: "aftermarket",
                   origin: product.origin, price_unit: "10.000,00", cost_currency: "ARS", active: "1" },
        channel_prices: { mercadolibre: "15.000,00" }
      }

      created = Product.find_by(sku: "BUJE-NEW")
      expect(created.price_unit).to eq(10_000)
      expect(created.price_for("mercadolibre")).to eq(15_000)
    end

    describe "re-rendering after a failed save" do
      def ml_input_value
        Nokogiri::HTML(response.body).at_css("input#channel_prices_mercadolibre")["value"]
      end

      it "echoes a cleaned ML price AR-formatted so a later unformat cannot misread it" do
        patch web_product_path(product), params: { product: { name: "" },
                                                   channel_prices: { mercadolibre: "15000.00" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(ml_input_value).to eq("15.000,00")
      end

      it "echoes an invalid ML price as typed" do
        patch web_product_path(product), params: { product: { name: "Otro" },
                                                   channel_prices: { mercadolibre: "abc" } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(ml_input_value).to eq("abc")
      end
    end

    it "refuses to create a product on a non-numeric ML price" do
      origin = product.origin
      expect {
        post web_products_path, params: {
          product: { sku: "BUJE-BAD", name: "Buje", brand: "X", product_type: "aftermarket",
                     origin: origin, price_unit: "10.000,00", cost_currency: "ARS", active: "1" },
          channel_prices: { mercadolibre: "abc" }
        }
      }.not_to change(Product, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Precio Mercado Libre debe ser mayor a 0")
    end

    it "shows the ML price on the product page, or the fallback" do
      get web_product_path(product)
      expect(response.body).to include("Precio Mercado Libre")
      expect(response.body).to include("Usa el de mostrador")

      product.channel_prices.create!(channel: "mercadolibre", price: 15_000)
      get web_product_path(product)
      expect(response.body).to include("15.000")
    end

    it "prefills the ML price on the edit form" do
      product.channel_prices.create!(channel: "mercadolibre", price: 15_000)
      get edit_web_product_path(product)
      expect(response.body).to include("15.000,00")
    end
  end
end
