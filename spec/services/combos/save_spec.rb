require "rails_helper"

RSpec.describe Combos::Save do
  let!(:part_a) { create(:product, sku: "PA-1", price_unit: 70_000) }
  let!(:part_b) { create(:product, sku: "PB-1", price_unit: 70_000) }

  def components_for(*pairs)
    pairs.map { |product, quantity| { product_id: product.id, quantity: quantity } }
  end

  def call_new(attributes: { name: "Kit frenos", price_unit: 130_000 }, components: nil, channel_prices: {})
    described_class.call(combo: Product.new, attributes: attributes, components: components,
                         channel_prices: channel_prices)
  end

  def quantities_of(combo)
    combo.reload.combo_components.to_h { |row| [ row.product_id, row.quantity ] }
  end

  describe "creating a combo" do
    it "creates a combo with a CB- sku, no stock and its components" do
      result = call_new(components: components_for([ part_a, 1 ], [ part_b, 1 ]))

      expect(result).to be_success
      combo = result.record
      expect(combo).to be_persisted
      expect(combo).to be_combo
      expect(combo.sku).to match(/\ACB-\d{4,}\z/)
      expect(combo.current_stock).to eq(0)
      expect(quantities_of(combo)).to eq(part_a.id => 1, part_b.id => 1)
    end

    it "accepts one part times several units" do
      result = call_new(components: components_for([ part_a, 4 ]))

      expect(result).to be_success
      expect(quantities_of(result.record)).to eq(part_a.id => 4)
    end

    it "does not prefill the price" do
      result = call_new(attributes: { name: "Kit frenos" }, components: components_for([ part_a, 1 ], [ part_b, 1 ]))

      expect(result).to be_failure
      expect(result.errors).to include("El precio de venta debe ser mayor a 0")
    end

    it "creates the channel price row" do
      result = call_new(components: components_for([ part_a, 1 ], [ part_b, 1 ]),
                        channel_prices: { "mercadolibre" => 95_000 })

      expect(result).to be_success
      expect(result.record.reload.price_for("mercadolibre")).to eq(95_000)
    end

    it "creates nothing when the header is invalid" do
      expect {
        call_new(attributes: { name: "", price_unit: 130_000 }, components: components_for([ part_a, 1 ], [ part_b, 1 ]))
      }.not_to change(Product, :count)
      expect(ComboComponent.count).to eq(0)
    end

    it "creates nothing when the channel price is invalid" do
      expect {
        result = call_new(components: components_for([ part_a, 1 ], [ part_b, 1 ]),
                          channel_prices: { "mercadolibre" => 0 })
        expect(result).to be_failure
      }.not_to change(Product, :count)
      expect(ComboComponent.count).to eq(0)
    end
  end

  describe "component rules" do
    it "needs at least 2 units in total" do
      result = call_new(components: components_for([ part_a, 1 ]))

      expect(result).to be_failure
      expect(result.errors).to include("El combo necesita al menos 2 unidades en total")
      expect(result.record.errors[:base]).to include("El combo necesita al menos 2 unidades en total")
      expect(result.record).not_to be_persisted
    end

    it "refuses a repeated part" do
      result = call_new(components: components_for([ part_a, 1 ], [ part_a, 1 ]))

      expect(result).to be_failure
      expect(result.errors).to include("Una pieza no puede repetirse en el combo")
    end

    it "refuses another combo as a part" do
      other = create(:product, :combo)
      result = call_new(components: components_for([ other, 1 ], [ part_a, 1 ]))

      expect(result).to be_failure
      expect(result.errors).to include("Un combo no puede incluir otro combo")
    end

    it "refuses an archived part" do
      archived = create(:product, :inactive, sku: "ARC-1")
      result = call_new(components: components_for([ archived, 1 ], [ part_a, 1 ]))

      expect(result).to be_failure
      expect(result.errors).to include("La pieza ARC-1 no está activa")
    end

    it "refuses a deleted part" do
      deleted = create(:product, sku: "DEL-1")
      deleted.destroy
      result = call_new(components: components_for([ deleted, 1 ], [ part_a, 1 ]))

      expect(result).to be_failure
      expect(result.errors).to include("La pieza DEL-1 no está activa")
    end

    it "refuses an unknown part" do
      result = call_new(components: [ { product_id: 0, quantity: 1 }, { product_id: part_a.id, quantity: 1 } ])

      expect(result).to be_failure
      expect(result.errors).to include("Pieza inválida")
    end

    it "refuses a combo price of zero" do
      result = call_new(attributes: { name: "Kit", price_unit: 0 }, components: components_for([ part_a, 1 ], [ part_b, 1 ]))

      expect(result).to be_failure
      expect(result.errors).to include("El precio de venta debe ser mayor a 0")
    end

    it "reports every broken rule at once" do
      result = call_new(attributes: { name: "Kit" }, components: components_for([ part_a, 1 ]))

      expect(result.errors).to contain_exactly("El combo necesita al menos 2 unidades en total",
                                               "El precio de venta debe ser mayor a 0")
    end
  end

  describe "editing a combo" do
    let(:combo) { create(:product, :combo, price_unit: 130_000, components: [ [ part_a, 1 ], [ part_b, 1 ] ]) }

    it "replaces the components" do
      part_c = create(:product)
      result = described_class.call(combo: combo, attributes: {}, components: components_for([ part_a, 2 ], [ part_c, 1 ]))

      expect(result).to be_success
      expect(quantities_of(combo)).to eq(part_a.id => 2, part_c.id => 1)
    end

    it "keeps the components when none are given" do
      result = described_class.call(combo: combo, attributes: { name: "Otro nombre" })

      expect(result).to be_success
      expect(combo.reload.name).to eq("Otro nombre")
      expect(quantities_of(combo)).to eq(part_a.id => 1, part_b.id => 1)
    end

    context "when the combo has sales" do
      before { create(:order_item, product: combo, order: create(:order, :cancelled)) }

      it "edits name and price without components" do
        result = described_class.call(combo: combo, attributes: { name: "Kit nuevo", price_unit: 120_000 })

        expect(result).to be_success
        expect(combo.reload.name).to eq("Kit nuevo")
        expect(combo.price_unit).to eq(120_000)
      end

      it "accepts the same components" do
        result = described_class.call(combo: combo, attributes: { name: "Kit nuevo" },
                                      components: components_for([ part_b, 1 ], [ part_a, 1 ]))

        expect(result).to be_success
        expect(quantities_of(combo)).to eq(part_a.id => 1, part_b.id => 1)
      end

      it "refuses different components" do
        result = described_class.call(combo: combo, attributes: { name: "Kit nuevo" },
                                      components: components_for([ part_a, 2 ], [ part_b, 1 ]))

        expect(result).to be_failure
        expect(result.errors).to include(
          "Las piezas no se pueden cambiar porque el combo ya tiene ventas. " \
          "Para cambiarlas, archivar este combo y crear uno nuevo."
        )
        expect(combo.reload.name).not_to eq("Kit nuevo")
        expect(quantities_of(combo)).to eq(part_a.id => 1, part_b.id => 1)
      end
    end

    context "when reactivating" do
      let(:archived_combo) do
        create(:product, :combo, :inactive, price_unit: 130_000, components: [ [ part_a, 1 ], [ part_b, 1 ] ])
      end

      it "reactivates when every part is active" do
        result = described_class.call(combo: archived_combo, attributes: { active: true })

        expect(result).to be_success
        expect(archived_combo.reload).to be_active
      end

      it "refuses with one message per archived or deleted part" do
        archived_combo
        part_a.update!(active: false)
        part_b.destroy

        result = described_class.call(combo: archived_combo, attributes: { active: true })

        expect(result).to be_failure
        expect(result.errors).to contain_exactly(
          "No se puede reactivar: la pieza PA-1 está archivada. Reactivarla primero o crear un combo nuevo.",
          "No se puede reactivar: la pieza PB-1 está archivada. Reactivarla primero o crear un combo nuevo."
        )
        expect(archived_combo.reload).not_to be_active
      end
    end
  end
end
