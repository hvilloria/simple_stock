require 'rails_helper'

RSpec.describe Product, type: :model do
  describe 'associations' do
    it { is_expected.to have_many(:stock_movements).dependent(:destroy) }
  end

  describe 'validations' do
    subject { build(:product) }

    it { is_expected.to validate_presence_of(:sku) }
    it { is_expected.to validate_uniqueness_of(:sku) }
    it { is_expected.to validate_presence_of(:name) }

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

      it 'allows blank origin' do
        product = build(:product, origin: nil)
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
        product = build(:product, product_type: 'aftermarket')
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

  describe '#recalculate_average_cost!' do
    let(:product) { create(:product) }
    let(:supplier) { create(:supplier) }

    context 'with single purchase in USD' do
      it 'sets cost to purchase unit cost' do
        purchase = create(:purchase, supplier: supplier, currency: 'USD', exchange_rate: 1200)
        create(:purchase_item, purchase: purchase, product: product, quantity: 10, unit_cost: 50)

        product.recalculate_average_cost!

        expect(product.reload.cost_unit).to eq(50.0)
        expect(product.cost_currency).to eq('USD')
      end
    end

    context 'with multiple purchases at different prices' do
      it 'calculates weighted average cost' do
        purchase1 = create(:purchase, supplier: supplier, currency: 'USD', exchange_rate: 1200)
        create(:purchase_item, purchase: purchase1, product: product, quantity: 5, unit_cost: 10)

        purchase2 = create(:purchase, supplier: supplier, currency: 'USD', exchange_rate: 1200)
        create(:purchase_item, purchase: purchase2, product: product, quantity: 5, unit_cost: 20)

        product.recalculate_average_cost!

        # (5 × $10 + 5 × $20) / 10 = $15
        expect(product.reload.cost_unit).to eq(15.0)
        expect(product.cost_currency).to eq('USD')
      end
    end

    context 'with purchases in different currencies' do
      it 'converts ARS to USD for averaging' do
        purchase_usd = create(:purchase, supplier: supplier, currency: 'USD', exchange_rate: 1200)
        create(:purchase_item, purchase: purchase_usd, product: product, quantity: 5, unit_cost: 10)

        purchase_ars = create(:purchase, supplier: supplier, currency: 'ARS', exchange_rate: 1200)
        create(:purchase_item, purchase: purchase_ars, product: product, quantity: 5, unit_cost: 12000)

        product.recalculate_average_cost!

        # purchase_ars: 12000 ARS / 1200 = 10 USD
        # (5 × $10 + 5 × $10) / 10 = $10
        expect(product.reload.cost_unit).to eq(10.0)
        expect(product.cost_currency).to eq('USD')
      end
    end

    context 'with cancelled purchases' do
      it 'ignores cancelled purchases' do
        purchase1 = create(:purchase, supplier: supplier, status: 'confirmed')
        create(:purchase_item, purchase: purchase1, product: product, quantity: 10, unit_cost: 10)

        purchase2 = create(:purchase, supplier: supplier, status: 'cancelled')
        create(:purchase_item, purchase: purchase2, product: product, quantity: 10, unit_cost: 50)

        product.recalculate_average_cost!

        # Solo cuenta purchase1
        expect(product.reload.cost_unit).to eq(10.0)
      end
    end

    context 'with no purchases' do
      it 'does not change cost' do
        original_cost = product.cost_unit
        product.recalculate_average_cost!
        expect(product.reload.cost_unit).to eq(original_cost)
      end
    end

    context 'with complex mixed scenario' do
      it 'calculates correct weighted average' do
        # Purchase 1: 5 units @ $10 USD
        purchase1 = create(:purchase, supplier: supplier, currency: 'USD', exchange_rate: 1200)
        create(:purchase_item, purchase: purchase1, product: product, quantity: 5, unit_cost: 10)

        # Purchase 2: 10 units @ $20 USD
        purchase2 = create(:purchase, supplier: supplier, currency: 'USD', exchange_rate: 1300)
        create(:purchase_item, purchase: purchase2, product: product, quantity: 10, unit_cost: 20)

        # Purchase 3: 5 units @ 15000 ARS (exchange_rate 1500 → 10 USD)
        purchase3 = create(:purchase, supplier: supplier, currency: 'ARS', exchange_rate: 1500)
        create(:purchase_item, purchase: purchase3, product: product, quantity: 5, unit_cost: 15000)

        product.recalculate_average_cost!

        # Total: (5 × $10) + (10 × $20) + (5 × $10) = $50 + $200 + $50 = $300
        # Quantity: 5 + 10 + 5 = 20
        # Average: $300 / 20 = $15
        expect(product.reload.cost_unit).to eq(15.0)
        expect(product.cost_currency).to eq('USD')
      end
    end
  end

  describe '#average_cost' do
    it 'is an alias for cost_unit' do
      product = create(:product, cost_unit: 50.0)
      expect(product.average_cost).to eq(product.cost_unit)
      expect(product.average_cost).to eq(50.0)
    end
  end
end
