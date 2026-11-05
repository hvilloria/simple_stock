require 'rails_helper'

RSpec.describe Product, type: :model do
  describe 'associations' do
    it { is_expected.to have_many(:stock_movements) }
  end

  describe 'validations' do
    subject { build(:product) }

    it { is_expected.to validate_presence_of(:sku) }
    it { is_expected.to validate_presence_of(:name) }

    describe 'sku uniqueness (condicional a origin)' do
      it 'permite duplicar sku+type cuando origin es nil (no valida)' do
        create(:product, sku: 'OEM-1', product_type: 'oem', origin: nil, brand: nil)
        dup = build(:product, sku: 'OEM-1', product_type: 'oem', origin: nil, brand: nil)

        expect(dup).to be_valid
      end

      it 'bloquea el duplicado exacto cuando hay origin (brand nil)' do
        create(:product, sku: 'OEM-1', product_type: 'oem', origin: 'japan', brand: nil)
        dup = build(:product, sku: 'OEM-1', product_type: 'oem', origin: 'japan', brand: nil)

        expect(dup).not_to be_valid
        expect(dup.errors[:sku]).to be_present
      end

      it 'permite mismo sku+type con distinto origin' do
        create(:product, sku: 'OEM-1', product_type: 'oem', origin: 'japan', brand: nil)
        other = build(:product, sku: 'OEM-1', product_type: 'oem', origin: 'china', brand: nil)

        expect(other).to be_valid
      end

      it 'permite mismo sku+type+origin con distinta marca' do
        create(:product, sku: 'OEM-1', product_type: 'oem', origin: 'japan', brand: nil)
        other = build(:product, sku: 'OEM-1', product_type: 'oem', origin: 'japan', brand: 'Honda')

        expect(other).to be_valid
      end

      it 'permite mismo sku+type+origin con distinta marca (ambas presentes)' do
        create(:product, sku: 'OEM-1', product_type: 'oem', origin: 'japan', brand: 'Honda')
        other = build(:product, sku: 'OEM-1', product_type: 'oem', origin: 'japan', brand: 'Yamaha')

        expect(other).to be_valid
      end

      it 'bloquea el duplicado exacto con la clave completa (origin + marca)' do
        create(:product, sku: 'OEM-1', product_type: 'oem', origin: 'japan', brand: 'Honda')
        dup = build(:product, sku: 'OEM-1', product_type: 'oem', origin: 'japan', brand: 'Honda')

        expect(dup).not_to be_valid
        expect(dup.errors[:sku]).to be_present
      end
    end

    describe 'numericality validations' do
      it { is_expected.to validate_numericality_of(:price_unit).is_greater_than_or_equal_to(0).allow_nil }
      it { is_expected.to validate_numericality_of(:cost_unit).is_greater_than_or_equal_to(0).allow_nil }

      it 'allows nil price_unit' do
        product = build(:product, price_unit: nil)
        expect(product).to be_valid
      end

      it 'allows nil cost_unit' do
        product = build(:product, cost_unit: nil)
        expect(product).to be_valid
      end

      it 'does not allow negative price_unit' do
        product = build(:product, price_unit: -10)
        expect(product).not_to be_valid
        expect(product.errors[:price_unit]).to be_present
      end

      it 'does not allow negative cost_unit' do
        product = build(:product, cost_unit: -10)
        expect(product).not_to be_valid
        expect(product.errors[:cost_unit]).to be_present
      end
    end

    describe 'cost_currency validation' do
      it { is_expected.to validate_inclusion_of(:cost_currency).in_array(%w[USD ARS]) }

      it 'allows USD' do
        product = build(:product, cost_currency: 'USD')
        expect(product).to be_valid
      end

      it 'allows ARS' do
        product = build(:product, cost_currency: 'ARS')
        expect(product).to be_valid
      end

      it 'rejects invalid currency' do
        product = build(:product, cost_currency: 'EUR')
        expect(product).not_to be_valid
        expect(product.errors[:cost_currency]).to be_present
      end
    end

    describe 'origin validation' do
      it 'allows valid origins' do
        Product::ORIGINS.each do |origin|
          product = build(:product, origin: origin)
          expect(product).to be_valid
        end
      end

      it 'allows blank origin for OEM products' do
        product = build(:product, product_type: 'oem', origin: nil)
        expect(product).to be_valid
      end

      it 'allows blank origin for aftermarket products (relaxed for CSV import)' do
        # The origin validation for aftermarket is intentionally disabled
        # to allow the sales importer to create products without a known origin.
        # See: app/models/product.rb — validation commented out with an explanatory note.
        product = build(:product, product_type: 'aftermarket', origin: nil)
        expect(product).to be_valid
      end

      it 'allows origin for aftermarket products' do
        product = build(:product, product_type: 'aftermarket', origin: 'china')
        expect(product).to be_valid
      end

      it 'rejects invalid origin' do
        product = build(:product, origin: 'invalid_origin')
        expect(product).not_to be_valid
        expect(product.errors[:origin]).to be_present
      end
    end

    describe 'product_type validation' do
      it 'allows oem' do
        product = build(:product, product_type: 'oem')
        expect(product).to be_valid
      end

      it 'allows aftermarket' do
        product = build(:product, product_type: 'aftermarket', origin: 'china')
        expect(product).to be_valid
      end

      it 'allows blank product_type' do
        product = build(:product, product_type: nil)
        expect(product).to be_valid
      end

      it 'rejects invalid product_type' do
        product = build(:product, product_type: 'invalid_type')
        expect(product).not_to be_valid
        expect(product.errors[:product_type]).to be_present
      end
    end

    describe 'category validation' do
      it 'allows valid categories' do
        Product::CATEGORIES.each do |category|
          product = build(:product, category: category)
          expect(product).to be_valid
        end
      end

      it 'allows blank category' do
        product = build(:product, category: nil)
        expect(product).to be_valid
      end

      it 'rejects invalid category' do
        product = build(:product, category: 'invalid_category')
        expect(product).not_to be_valid
        expect(product.errors[:category]).to be_present
      end
    end
  end

  describe 'scopes' do
    let!(:active_product) { create(:product, active: true) }
    let!(:inactive_product) { create(:product, :inactive) }
    let!(:low_stock_product) { create(:product, :low_stock) }
    let!(:oem_product) { create(:product, :oem) }
    let!(:aftermarket_product) { create(:product, :aftermarket_china) }

    describe '.active' do
      it 'returns only active products' do
        expect(Product.active).to include(active_product)
        expect(Product.active).not_to include(inactive_product)
      end
    end

    describe '.inactive' do
      it 'returns only inactive products' do
        expect(Product.inactive).to include(inactive_product)
        expect(Product.inactive).not_to include(active_product)
      end
    end

    describe '.with_low_stock' do
      it 'returns products with stock less than 5' do
        expect(Product.with_low_stock).to include(low_stock_product)
        expect(Product.with_low_stock).not_to include(active_product)
      end
    end

    describe '.by_category' do
      let!(:brake_product) { create(:product, category: 'frenos') }
      let!(:motor_product) { create(:product, category: 'motor') }

      it 'filters by category when provided' do
        expect(Product.by_category('frenos')).to include(brake_product)
        expect(Product.by_category('frenos')).not_to include(motor_product)
      end

      it 'returns all products when category is nil' do
        expect(Product.by_category(nil).count).to eq(Product.count)
      end

      it 'returns all products when category is blank' do
        expect(Product.by_category('').count).to eq(Product.count)
      end
    end

    describe '.by_origin' do
      let!(:japan_product) { create(:product, origin: 'japan') }
      let!(:china_product) { create(:product, origin: 'china') }

      it 'filters by origin when provided' do
        expect(Product.by_origin('japan')).to include(japan_product)
        expect(Product.by_origin('japan')).not_to include(china_product)
      end

      it 'returns all products when origin is nil' do
        expect(Product.by_origin(nil).count).to eq(Product.count)
      end
    end

    describe '.by_product_type' do
      it 'filters by product_type when provided' do
        expect(Product.by_product_type('oem')).to include(oem_product)
        expect(Product.by_product_type('oem')).not_to include(aftermarket_product)
      end

      it 'returns all products when type is nil' do
        expect(Product.by_product_type(nil).count).to eq(Product.count)
      end
    end

    describe '.oem' do
      it 'returns only OEM products' do
        expect(Product.oem).to include(oem_product)
        expect(Product.oem).not_to include(aftermarket_product)
      end
    end

    describe '.aftermarket' do
      it 'returns only aftermarket products' do
        expect(Product.aftermarket).to include(aftermarket_product)
        expect(Product.aftermarket).not_to include(oem_product)
      end
    end

    describe '.search' do
      let!(:searchable_product) { create(:product, sku: 'ABC123', name: 'Brake Pads', brand: 'Honda') }

      it 'searches by SKU' do
        expect(Product.search('ABC')).to include(searchable_product)
      end

      it 'searches by name' do
        expect(Product.search('Brake')).to include(searchable_product)
      end

      it 'searches by brand' do
        expect(Product.search('Honda')).to include(searchable_product)
      end

      it 'is case insensitive' do
        expect(Product.search('abc')).to include(searchable_product)
        expect(Product.search('brake')).to include(searchable_product)
        expect(Product.search('honda')).to include(searchable_product)
      end

      it 'returns all products when query is nil' do
        expect(Product.search(nil).count).to eq(Product.count)
      end

      it 'returns all products when query is blank' do
        expect(Product.search('').count).to eq(Product.count)
      end
    end
  end

  describe '.search' do
    let!(:plug)   { create(:product, sku: 'BUJ-1180', name: 'Bujías iridium', brand: 'NGK') }
    let!(:pinion) { create(:product, sku: 'PIN-0042', name: 'Piñón de distribución', brand: 'Citroën') }
    let!(:belt)   { create(:product, sku: 'COR-0310', name: 'Correa', brand: 'Gates') }

    it 'finds a name written with accents from a query without them' do
      expect(Product.search('bujias')).to contain_exactly(plug)
      expect(Product.search('pinon')).to contain_exactly(pinion)
    end

    it 'finds a name written without accents from a query with them' do
      plain = create(:product, sku: 'BUJ-2000', name: 'Bujia simple', brand: 'Bosch')

      expect(Product.search('bujía')).to contain_exactly(plug, plain)
    end

    it 'ignores accents in the brand too' do
      expect(Product.search('citroen')).to contain_exactly(pinion)
    end

    it 'still matches the SKU, whatever the case' do
      expect(Product.search('cor-03')).to contain_exactly(belt)
    end

    context 'with several words' do
      let!(:cables) { create(:product, sku: 'CAB-0100', name: 'Cables de Bujía Honda', brand: 'Taiwan') }

      it 'finds a product holding every word, even as part of a longer one' do
        expect(Product.search('cable buji')).to contain_exactly(cables)
      end

      it 'matches the words in any order' do
        expect(Product.search('buji cable')).to contain_exactly(cables)
      end

      it 'matches each word in any of sku, name or brand' do
        expect(Product.search('iridium ngk')).to contain_exactly(plug)
        expect(Product.search('buj-1180 iridium')).to contain_exactly(plug)
      end

      it 'leaves out a product missing one of the words' do
        expect(Product.search('cable gates')).to be_empty
      end

      it 'ignores extra spaces' do
        expect(Product.search('  cable   buji  ')).to contain_exactly(cables)
      end

      it 'only reads the first 8 distinct words' do
        expect(Product.search("cable cable buji #{%w[a b c d e h].join(' ')} zzz")).to contain_exactly(cables)
      end
    end

    it 'treats % and _ as plain characters' do
      expect(Product.search('%')).to be_empty
      expect(Product.search('_')).to be_empty
    end

    context 'with combos' do
      let!(:front) { create(:product, sku: '12345-123-12345', name: 'Amortiguador izquierdo', brand: 'Showa') }
      let!(:rear)  { create(:product, sku: '12345-456-12345', name: 'Amortiguador derecho', brand: 'Showa') }
      let!(:pair)  { create(:product, :combo, name: 'Par amortiguadores CRF250', components: [ [ front, 1 ], [ rear, 1 ] ]) }

      it 'finds the combo and the part itself by a component sku' do
        expect(Product.search('456')).to contain_exactly(rear, pair)
      end

      it 'finds the combo when each word matches a different component' do
        expect(Product.search('izquierdo derecho')).to contain_exactly(pair)
        expect(Product.search('123 456')).to contain_exactly(rear, pair)
      end

      it 'finds the combo by its own name' do
        expect(Product.search('crf250')).to contain_exactly(pair)
      end

      it 'ignores accents in component names' do
        spark = create(:product, :combo, name: 'Kit encendido', components: [ [ plug, 2 ] ])

        expect(Product.search('bujia')).to contain_exactly(plug, spark)
      end
    end
  end

  describe '#low_stock?' do
    it 'returns true when stock is less than 5' do
      product = build(:product, current_stock: 4)
      expect(product.low_stock?).to be true
    end

    it 'returns false when stock is 5 or more' do
      product = build(:product, current_stock: 5)
      expect(product.low_stock?).to be false
    end

    it 'returns true when stock is 0' do
      product = build(:product, current_stock: 0)
      expect(product.low_stock?).to be true
    end
  end

  describe '#cost_in_ars' do
    context 'when cost_unit is nil' do
      it 'returns 0' do
        product = build(:product, cost_unit: nil)
        expect(product.cost_in_ars).to eq(0)
      end
    end

    context 'when cost_currency is ARS' do
      it 'returns the cost_unit directly' do
        product = build(:product, cost_currency: 'ARS', cost_unit: 5000)
        expect(product.cost_in_ars).to eq(5000)
      end
    end

    context 'when cost_currency is USD' do
      it 'converts using default exchange rate' do
        product = build(:product, cost_currency: 'USD', cost_unit: 10)
        expect(product.cost_in_ars).to eq(10000) # 10 * 1000 (default rate)
      end

      it 'converts using provided exchange rate' do
        product = build(:product, cost_currency: 'USD', cost_unit: 10)
        expect(product.cost_in_ars(800)).to eq(8000) # 10 * 800
      end
    end
  end

  describe '#margin' do
    context 'when price_unit is nil' do
      it 'returns 0' do
        product = build(:product, price_unit: nil, cost_unit: 100)
        expect(product.margin).to eq(0)
      end
    end

    context 'when cost is in ARS' do
      it 'calculates margin correctly' do
        product = build(:product, price_unit: 15000, cost_currency: 'ARS', cost_unit: 10000)
        expect(product.margin).to eq(5000)
      end
    end

    context 'when cost is in USD' do
      it 'calculates margin correctly using default rate' do
        product = build(:product, price_unit: 15000, cost_currency: 'USD', cost_unit: 10)
        # price_unit (15000) - (10 * 1000) = 5000
        expect(product.margin).to eq(5000)
      end

      it 'calculates margin correctly using provided rate' do
        product = build(:product, price_unit: 15000, cost_currency: 'USD', cost_unit: 10)
        # price_unit (15000) - (10 * 800) = 7000
        expect(product.margin(800)).to eq(7000)
      end
    end
  end

  describe '#margin_percentage' do
    context 'when price_unit is nil' do
      it 'returns 0' do
        product = build(:product, price_unit: nil, cost_unit: 100)
        expect(product.margin_percentage).to eq(0)
      end
    end

    context 'when cost is 0' do
      it 'returns 0' do
        product = build(:product, price_unit: 100, cost_unit: 0)
        expect(product.margin_percentage).to eq(0)
      end
    end

    context 'when cost is in ARS' do
      it 'calculates margin percentage correctly' do
        product = build(:product, price_unit: 15000, cost_currency: 'ARS', cost_unit: 10000)
        # ((15000 - 10000) / 10000) * 100 = 50%
        expect(product.margin_percentage).to eq(50.0)
      end
    end

    context 'when cost is in USD' do
      it 'calculates margin percentage correctly' do
        product = build(:product, price_unit: 15000, cost_currency: 'USD', cost_unit: 10)
        # cost_in_ars = 10 * 1000 = 10000
        # ((15000 - 10000) / 10000) * 100 = 50%
        expect(product.margin_percentage).to eq(50.0)
      end

      it 'rounds to 2 decimal places' do
        product = build(:product, price_unit: 10000, cost_currency: 'ARS', cost_unit: 6000)
        # ((10000 - 6000) / 6000) * 100 = 66.666...
        expect(product.margin_percentage).to eq(66.67)
      end
    end
  end

  describe '#oem?' do
    it 'returns true when product_type is oem' do
      product = build(:product, product_type: 'oem')
      expect(product.oem?).to be true
    end

    it 'returns false when product_type is aftermarket' do
      product = build(:product, product_type: 'aftermarket')
      expect(product.oem?).to be false
    end

    it 'returns false when product_type is nil' do
      product = build(:product, product_type: nil)
      expect(product.oem?).to be false
    end
  end

  describe '#aftermarket?' do
    it 'returns true when product_type is aftermarket' do
      product = build(:product, product_type: 'aftermarket')
      expect(product.aftermarket?).to be true
    end

    it 'returns false when product_type is oem' do
      product = build(:product, product_type: 'oem')
      expect(product.aftermarket?).to be false
    end

    it 'returns false when product_type is nil' do
      product = build(:product, product_type: nil)
      expect(product.aftermarket?).to be false
    end
  end

  describe 'sku normalization' do
    it 'upcases the sku before validation' do
      product = build(:product, sku: 'lub-mot-8100-0w20-4l')
      product.valid?
      expect(product.sku).to eq('LUB-MOT-8100-0W20-4L')
    end

    it 'strips surrounding whitespace' do
      product = build(:product, sku: '  71508-tj5-k00  ')
      product.valid?
      expect(product.sku).to eq('71508-TJ5-K00')
    end

    it 'persists the sku in uppercase' do
      product = create(:product, sku: 'abc-123')
      expect(product.reload.sku).to eq('ABC-123')
    end

    it 'leaves a blank sku untouched' do
      product = build(:product, sku: nil)
      expect { product.valid? }.not_to raise_error
      expect(product.sku).to be_nil
    end
  end

  describe '#recalculate_current_stock!' do
    it 'recalculates stock from stock_movements' do
      product = create(:product, current_stock: 0)
      stock_location = create(:stock_location)

      create(:stock_movement, product: product, stock_location: stock_location, quantity: 10, movement_type: 'purchase')
      create(:stock_movement, product: product, stock_location: stock_location, quantity: -3, movement_type: 'sale')
      create(:stock_movement, product: product, stock_location: stock_location, quantity: 5, movement_type: 'purchase')

      product.recalculate_current_stock!

      expect(product.reload.current_stock).to eq(12) # 10 - 3 + 5
    end
  end

  describe "average cost recalculation" do
    it "is gone, so nothing can overwrite the cost the last purchase set" do
      expect(build(:product)).not_to respond_to(:recalculate_average_cost!)
    end
  end

  describe "cost source" do
    let(:product) { create(:product, cost_unit: 9_000, cost_currency: "ARS") }
    let(:item)    { create(:invoice_item, product: product) }

    before { product.update_columns(cost_source_invoice_item_id: item.id) }

    it "is cleared when the cost is changed by hand" do
      product.update!(cost_unit: 9_500)

      expect(product.reload.cost_source_invoice_item_id).to be_nil
    end

    it "is cleared when the cost currency is changed by hand" do
      product.update!(cost_currency: "USD")

      expect(product.reload.cost_source_invoice_item_id).to be_nil
    end

    it "is kept by a save that leaves the cost alone" do
      product.update!(name: "Disco ventilado", cost_unit: 9_000)

      expect(product.reload.cost_source_invoice_item).to eq(item)
    end
  end

  describe '#average_cost' do
    it 'is an alias for cost_unit' do
      product = create(:product, cost_unit: 50.0)
      expect(product.average_cost).to eq(product.cost_unit)
      expect(product.average_cost).to eq(50.0)
    end
  end

  describe "soft delete (paranoia)" do
    it "sets deleted_at and hides the row from the default scope" do
      product = create(:product)

      expect { product.destroy }.to change { Product.count }.by(-1)
      expect(product.deleted_at).to be_present
      expect(Product.with_deleted).to include(product)
      expect(Product.only_deleted).to include(product)
    end

    it "lets a live variant reuse the identity of a soft-deleted one" do
      attrs = { sku: "AB-100", product_type: "aftermarket", origin: "china", brand: "Marca1" }
      deleted = create(:product, **attrs)
      deleted.destroy

      fresh = build(:product, **attrs)
      expect(fresh).to be_valid
      expect { fresh.save! }.not_to raise_error
    end

    it "keeps stock movements when the product is soft-deleted" do
      product = create(:product)
      location = StockLocation.first || create(:stock_location)
      movement = StockMovement.create!(product: product, stock_location: location,
                                       quantity: 5, movement_type: "adjustment")

      product.destroy
      expect(StockMovement.find_by(id: movement.id)).to eq(movement)
    end
  end

  describe "#price_for" do
    let(:product) { create(:product, price_unit: 10_000) }

    it "returns the channel price when the product has one" do
      product.channel_prices.create!(channel: "mercadolibre", price: 15_000)
      expect(product.price_for("mercadolibre")).to eq(15_000)
    end

    it "falls back to the counter price without a channel price" do
      expect(product.price_for("mercadolibre")).to eq(10_000)
    end

    it "returns the counter price for counter, whatsapp and a nil channel" do
      product.channel_prices.create!(channel: "mercadolibre", price: 15_000)
      expect(product.price_for("counter")).to eq(10_000)
      expect(product.price_for("whatsapp")).to eq(10_000)
      expect(product.price_for(nil)).to eq(10_000)
    end
  end

  describe "#channel_prices_map" do
    it "maps each channel to its price" do
      product = create(:product, price_unit: 10_000)
      product.channel_prices.create!(channel: "mercadolibre", price: 15_000)
      expect(product.reload.channel_prices_map).to eq("mercadolibre" => 15_000.0)
    end
  end

  it "deletes its channel prices when destroyed" do
    product = create(:product)
    product.channel_prices.create!(channel: "mercadolibre", price: 15_000)
    expect { product.destroy }.to change(ProductChannelPrice, :count).by(-1)
  end

  describe "combos" do
    it "generates increasing CB- skus" do
      first = Product.next_combo_sku
      second = Product.next_combo_sku

      expect(first).to match(/\ACB-\d{4,}\z/)
      expect(second).to match(/\ACB-\d{4,}\z/)
      expect(second.delete_prefix("CB-").to_i).to be > first.delete_prefix("CB-").to_i
    end

    it "refuses a CB- sku on a regular product after normalization" do
      product = build(:product, sku: "cb-77")

      expect(product).not_to be_valid
      expect(product.errors[:sku]).to include("no puede empezar con CB- (reservado para combos)")
    end

    it "still saves a regular product already persisted with a CB- sku" do
      product = create(:product, sku: "LEGACY-1")
      product.update_column(:sku, "CB-9")
      create(:stock_movement, product: product, stock_location: create(:stock_location),
                              quantity: 3, movement_type: "purchase")

      expect(product.reload.update(price_unit: 250)).to be(true)
      expect { product.recalculate_current_stock! }.not_to raise_error
      expect(product.reload.current_stock).to eq(3)
    end

    it "refuses creating a regular product with a lowercase cb- sku" do
      expect { create(:product, sku: "cb-1") }.to raise_error(ActiveRecord::RecordInvalid, /CB-/)
    end

    it "allows a CB- sku on a combo" do
      expect(build(:product, :combo, sku: "CB-0003")).to be_valid
    end

    it "refuses a second combo with the same sku, even after the first is deleted" do
      first = create(:product, :combo)
      first.destroy

      expect { create(:product, :combo, sku: first.sku, components: []) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "splits products into combos and regular ones" do
      combo = create(:product, :combo)
      regular = create(:product)

      expect(Product.combos).to include(combo)
      expect(Product.combos).not_to include(regular)
      expect(Product.regular).to include(regular)
      expect(Product.regular).not_to include(combo)
      expect(combo).to be_combo
    end

    it "lists its components through combo_components" do
      part_a = create(:product)
      part_b = create(:product)
      combo = create(:product, :combo, components: [ [ part_a, 1 ], [ part_b, 4 ] ])

      expect(combo.components).to contain_exactly(part_a, part_b)
      expect(combo.combo_components.find_by(product: part_b).quantity).to eq(4)
    end

    describe "#has_sales?" do
      it "is false without order items" do
        expect(create(:product, :combo)).not_to have_sales
      end

      it "is true with an order item on a cancelled order" do
        combo = create(:product, :combo)
        create(:order_item, product: combo, order: create(:order, :cancelled))

        expect(combo).to have_sales
      end
    end

    describe "#active_combos_containing" do
      it "returns the active combos with the product, not the archived ones" do
        part = create(:product)
        active_combo = create(:product, :combo, components: [ [ part, 2 ] ])
        create(:product, :combo, :inactive, components: [ [ part, 2 ] ])

        expect(part.active_combos_containing).to contain_exactly(active_combo)
      end
    end

    describe "#components_price_sum" do
      it "adds each component price times its quantity" do
        combo = create(:product, :combo, components: [
          [ create(:product, price_unit: 70_000), 1 ],
          [ create(:product, price_unit: 70_000), 1 ]
        ])

        expect(combo.components_price_sum).to eq(140_000)
      end

      it "counts a component without price as zero" do
        combo = create(:product, :combo, components: [
          [ create(:product, price_unit: nil), 3 ],
          [ create(:product, price_unit: 1_000), 2 ]
        ])

        expect(combo.components_price_sum).to eq(2_000)
      end
    end

    describe "destroy guards" do
      it "refuses to delete a combo with sales and keeps its components" do
        combo = create(:product, :combo)
        create(:order_item, product: combo, order: create(:order, :cancelled))

        expect(combo.destroy).to be(false)
        expect(combo.errors[:base]).to include("El combo tiene ventas: solo se puede archivar")
        expect(Product.find(combo.id)).to be_present
        expect(combo.combo_components.count).to eq(2)
      end

      it "deletes a combo without sales" do
        combo = create(:product, :combo)

        expect(combo.destroy).to be_truthy
        expect(Product.only_deleted).to include(combo)
      end

      it "refuses to delete a part of active combos, listing them" do
        part = create(:product)
        first = create(:product, :combo, components: [ [ part, 2 ] ])
        second = create(:product, :combo, components: [ [ part, 3 ] ])

        expect(part.destroy).to be(false)
        expect(part.errors[:base]).to include("Forma parte de #{first.sku}, #{second.sku}; archivar esos combos primero.")
        expect(Product.find(part.id)).to be_present
      end

      it "deletes a part of archived combos only" do
        part = create(:product)
        create(:product, :combo, :inactive, components: [ [ part, 2 ] ])

        expect(part.destroy).to be_truthy
      end
    end

    describe "archive guard" do
      it "refuses to archive a part of an active combo" do
        part = create(:product)
        combo = create(:product, :combo, components: [ [ part, 2 ] ])

        expect(part.update(active: false)).to be(false)
        expect(part.errors[:base]).to include("Forma parte de #{combo.sku}; archivar esos combos primero.")
        expect(part.reload).to be_active
      end

      it "archives a part of archived combos only" do
        part = create(:product)
        create(:product, :combo, :inactive, components: [ [ part, 2 ] ])

        expect(part.update(active: false)).to be(true)
      end

      it "lets other edits through on a part of an active combo" do
        part = create(:product)
        create(:product, :combo, components: [ [ part, 2 ] ])

        expect(part.update(name: "Otro nombre")).to be(true)
      end

      it "archives a combo itself" do
        combo = create(:product, :combo)

        expect(combo.update(active: false)).to be(true)
      end
    end
  end
end
