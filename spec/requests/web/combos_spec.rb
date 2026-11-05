# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::Combos", type: :request do
  let(:admin)    { create(:user, :admin) }
  let(:vendedor) { create(:user, role: "vendedor") }
  let(:caja)     { create(:user, role: "caja") }
  let!(:part_a)  { create(:product, sku: "PA-1", name: "Amortiguador izq.", price_unit: 70_000) }
  let!(:part_b)  { create(:product, sku: "PB-1", name: "Amortiguador der.", price_unit: 70_000) }

  def combo_params(components:, name: "Par amortiguadores", price: "100.000,00", ml: "")
    {
      combo: { name: name, price_unit: price },
      channel_prices: { mercadolibre: ml },
      components: components.map { |product, quantity| { product_id: product.id, quantity: quantity } }
    }
  end

  describe "GET /web/products/combos/new" do
    it "renders the form for an admin" do
      sign_in admin
      get new_web_combo_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nuevo Combo", "El código se asigna al guardar")
    end

    it "refuses caja" do
      sign_in caja
      get new_web_combo_path

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to eq("No tiene permiso para realizar esta acción.")
    end

    it "refuses a vendedor" do
      sign_in vendedor
      get new_web_combo_path

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to eq("No tiene permiso para realizar esta acción.")
    end
  end

  describe "POST /web/products/combos" do
    before { sign_in admin }

    it "creates the combo with its components and channel price" do
      expect {
        post web_combos_path, params: combo_params(components: [ [ part_a, 1 ], [ part_b, 1 ] ], ml: "95.000,00")
      }.to change(Product.combos, :count).by(1)

      combo = Product.combos.last
      expect(response).to redirect_to(web_product_path(combo))
      expect(flash[:notice]).to eq("Combo creado")
      expect(combo.price_unit).to eq(100_000)
      expect(combo.price_for("mercadolibre")).to eq(95_000)
      expect(combo.combo_components.to_h { |row| [ row.product_id, row.quantity ] })
        .to eq(part_a.id => 1, part_b.id => 1)
    end

    it "re-renders with the error and the typed values when the combo is too small" do
      expect {
        post web_combos_path, params: combo_params(components: [ [ part_a, 1 ] ], name: "Kit chico")
      }.not_to change(Product, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("No se pudo guardar el combo: El combo necesita al menos 2 unidades en total")
      expect(response.body).to include("Kit chico", "PA-1", "100.000,00")
      expect(response.body).not_to include("CB-")
    end

    it "lists every problem in one message" do
      post web_combos_path, params: combo_params(components: [ [ part_a, 1 ] ], price: "")

      expect(response.body).to include(
        "No se pudo guardar el combo: El combo necesita al menos 2 unidades en total · El precio de venta debe ser mayor a 0"
      )
    end

    it "refuses a negative price" do
      expect {
        post web_combos_path, params: combo_params(components: [ [ part_a, 1 ], [ part_b, 1 ] ], price: "-5.000,00")
      }.not_to change(Product, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("El precio de venta debe ser mayor a 0")
    end

    it "refuses a non-numeric price" do
      expect {
        post web_combos_path, params: combo_params(components: [ [ part_a, 1 ], [ part_b, 1 ] ], price: "abc")
      }.not_to change(Product, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("El precio de venta debe ser mayor a 0")
    end

    [ "1.9", "2pieces" ].each do |quantity|
      it "refuses a component quantity of #{quantity.inspect}" do
        expect {
          post web_combos_path, params: combo_params(components: [ [ part_a, quantity ], [ part_b, 1 ] ])
        }.not_to change(Product, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("La cantidad de cada pieza debe ser un número entero mayor a 0")
      end
    end

    it "refuses an empty component list" do
      post web_combos_path, params: { combo: { name: "Kit", price_unit: "100.000,00" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("El combo necesita al menos 2 unidades en total")
    end
  end

  describe "GET /web/products/combos/:id/edit" do
    let(:combo) { create(:product, :combo, name: "Kit", components: [ [ part_a, 1 ], [ part_b, 1 ] ]) }

    it "shows the sku and editable parts for an unsold combo" do
      sign_in admin
      get edit_web_combo_path(combo)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Editar Combo", combo.sku)
      expect(response.body).not_to include("ya tiene ventas")
      expect(response.body).to include("Buscar por SKU, nombre o marca...")
    end

    it "shows the parts read-only once the combo has sales" do
      create(:order_item, product: combo)
      sign_in admin
      get edit_web_combo_path(combo)

      expect(response.body).to include("Las piezas no se pueden cambiar porque el combo ya tiene ventas.")
      expect(response.body).not_to include("Buscar por SKU, nombre o marca...")
      expect(response.body).to include('data-combo-form-editable-value="false"')
    end

    it "does not open a regular product" do
      sign_in admin
      get edit_web_combo_path(part_a)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /web/products/combos/:id" do
    let!(:combo) do
      create(:product, :combo, name: "Kit", price_unit: 130_000, components: [ [ part_a, 1 ], [ part_b, 1 ] ])
    end

    it "updates name, price and parts for an admin" do
      sign_in admin
      patch web_combo_path(combo), params: combo_params(components: [ [ part_a, 2 ] ], name: "Kit nuevo")

      expect(response).to redirect_to(web_product_path(combo))
      expect(flash[:notice]).to eq("Combo actualizado")
      combo.reload
      expect(combo.name).to eq("Kit nuevo")
      expect(combo.price_unit).to eq(100_000)
      expect(combo.combo_components.to_h { |row| [ row.product_id, row.quantity ] }).to eq(part_a.id => 2)
    end

    it "keeps the parts of a sold combo when none are sent" do
      create(:order_item, product: combo)
      sign_in admin
      patch web_combo_path(combo), params: { combo: { name: "Kit nuevo", price_unit: "120.000,00" } }

      expect(response).to redirect_to(web_product_path(combo))
      expect(combo.reload.name).to eq("Kit nuevo")
      expect(combo.combo_components.count).to eq(2)
    end

    it "re-renders with the error on an invalid edit" do
      sign_in admin
      patch web_combo_path(combo), params: combo_params(components: [ [ part_a, 1 ] ])

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("No se pudo guardar el combo: El combo necesita al menos 2 unidades en total")
      expect(combo.reload.combo_components.count).to eq(2)
    end

    it "refuses a vendedor and leaves the combo unchanged" do
      sign_in vendedor
      patch web_combo_path(combo), params: combo_params(components: [ [ part_a, 1 ], [ part_b, 1 ] ], name: "Hackeado")

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to eq("No tiene permiso para realizar esta acción.")
      expect(combo.reload.name).to eq("Kit")
    end
  end

  describe "PATCH archive / reactivate" do
    let!(:combo) { create(:product, :combo, components: [ [ part_a, 1 ], [ part_b, 1 ] ]) }

    it "archives the combo for an admin" do
      sign_in admin
      patch archive_web_combo_path(combo)

      expect(response).to redirect_to(web_product_path(combo))
      expect(flash[:notice]).to eq("Combo archivado")
      expect(combo.reload.active).to be(false)
    end

    it "reactivates an archived combo" do
      combo.update!(active: false)
      sign_in admin
      patch reactivate_web_combo_path(combo)

      expect(response).to redirect_to(web_product_path(combo))
      expect(flash[:notice]).to eq("Combo reactivado")
      expect(combo.reload.active).to be(true)
    end

    it "explains why a combo with an archived part cannot be reactivated" do
      combo.update!(active: false)
      part_a.update!(active: false)
      sign_in admin
      patch reactivate_web_combo_path(combo)

      expect(response).to redirect_to(web_product_path(combo))
      expect(flash[:alert]).to include("No se puede reactivar: la pieza PA-1 está archivada.")
      expect(combo.reload.active).to be(false)
    end

    it "refuses a vendedor" do
      sign_in vendedor
      patch archive_web_combo_path(combo)

      expect(response).to have_http_status(:redirect)
      expect(combo.reload.active).to be(true)
    end
  end
end
