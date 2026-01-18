require 'rails_helper'

RSpec.describe Inventory::SyncFromCsv do
  let!(:stock_location) { create(:stock_location) }
  let(:csv_file) { Tempfile.new([ 'products', '.csv' ]) }
  let(:file_path) { csv_file.path }

  # Helper para crear archivo CSV de prueba
  def write_csv(rows)
    CSV.open(csv_file.path, 'w', encoding: 'UTF-8') do |csv|
      # Headers del CSV (mismos que products_inventory.csv)
      csv << [ 'ID del artículo', 'Nombre del artículo', 'Compatibilidad', 'Precio Lista ( U$D)',
              'Precio Venta (ARS)', 'Stock', 'Estado', 'Origen', 'Pasillo', 'Notas' ]
      rows.each { |row| csv << row }
    end
  end

  after do
    # Clean up CSV and log files
    csv_file.close
    csv_file.unlink
    Dir.glob(Rails.root.join('log', 'inventory_sync_*.log')).each do |log|
      File.delete(log)
    end
  end

  describe '.call' do
    context 'with valid CSV data' do
      before do
        write_csv([
          [ '91503-SZ3-003-IMP', 'Grampa de paragolpe', 'Todos', '$0.13', '$1,300.00', '799', '', 'TAI', '', '' ]
        ])
      end

      it 'creates new product' do
        expect {
          described_class.call(file_path: file_path)
        }.to change(Product, :count).by(1)
      end

      it 'creates stock movement' do
        expect {
          described_class.call(file_path: file_path)
        }.to change(StockMovement, :count).by(1)
      end

      it 'returns success result' do
        result = described_class.call(file_path: file_path)

        expect(result.success?).to be true
        expect(result.record[:stats]).to include(
          created: 1,
          updated: 0,
          errors: 0,
          movements: 1
        )
      end

      it 'creates log file' do
        result = described_class.call(file_path: file_path)
        log_path = result.record[:log_path]

        expect(File.exist?(log_path)).to be true
        expect(File.read(log_path)).to include('INVENTORY SYNC FROM CSV')
      end

      it 'removes -IMP suffix from SKU' do
        described_class.call(file_path: file_path)

        product = Product.find_by(sku: '91503-SZ3-003')
        expect(product).to be_present
        expect(product.sku).not_to include('-IMP')
      end

      it 'sets correct product attributes' do
        described_class.call(file_path: file_path)

        product = Product.find_by(sku: '91503-SZ3-003')

        expect(product.name).to eq('Grampa de paragolpe')
        expect(product.product_type).to eq('aftermarket')
        expect(product.origin).to eq('taiwan')
        expect(product.brand).to be_nil
        expect(product.category).to be_nil
        expect(product.active).to be true
        expect(product.cost_unit).to eq(0.13)
        expect(product.cost_currency).to eq('USD')
        expect(product.price_unit).to eq(1300)
      end

      it 'creates initial stock movement' do
        described_class.call(file_path: file_path)

        product = Product.find_by(sku: '91503-SZ3-003')
        movement = product.stock_movements.last

        expect(movement.movement_type).to eq('adjustment')
        expect(movement.note).to include('Initial stock from CSV import')
        expect(movement.quantity).to eq(799)
      end

      it 'sets correct stock after creation' do
        described_class.call(file_path: file_path)

        product = Product.find_by(sku: '91503-SZ3-003')
        expect(product.current_stock).to eq(799)
      end

      it 'parses currency formatted values correctly' do
        described_class.call(file_path: file_path)

        product = Product.find_by(sku: '91503-SZ3-003')
        expect(product.cost_unit).to eq(0.13)   # From "$0.13"
        expect(product.price_unit).to eq(1300.0) # From "$1,300.00"
      end
    end

    context 'with existing product' do
      let!(:existing_product) do
        product = create(:product,
          sku: '91503-SZ3-003',
          product_type: 'aftermarket',
          origin: 'taiwan',
          price_unit: 1000,
          current_stock: 0
        )
        # Crear movimiento inicial
        create(:stock_movement,
          product: product,
          stock_location: stock_location,
          quantity: 100,
          movement_type: 'adjustment',
          note: 'Initial stock'
        )
        product.reload
        product
      end

      before do
        write_csv([
          [ '91503-SZ3-003-IMP', 'Grampa de paragolpe', 'Todos', '$0.13', '$1,300.00', '799', '', 'TAI', '', '' ]
        ])
      end

      it 'does not create duplicate product' do
        expect {
          described_class.call(file_path: file_path)
        }.not_to change(Product, :count)
      end

      it 'updates price' do
        described_class.call(file_path: file_path)

        expect(existing_product.reload.price_unit).to eq(1300)
      end

      it 'adjusts stock correctly' do
        described_class.call(file_path: file_path)

        expect(existing_product.reload.current_stock).to eq(799)
      end

      it 'creates adjustment movement with correct quantity' do
        initial_count = existing_product.stock_movements.count

        described_class.call(file_path: file_path)

        expect(existing_product.stock_movements.count).to eq(initial_count + 1)
        movement = existing_product.stock_movements.last
        expect(movement.movement_type).to eq('adjustment')
        expect(movement.quantity).to eq(699) # 799 - 100
        expect(movement.note).to include('Stock adjustment from CSV import')
      end

      it 'records update in stats' do
        result = described_class.call(file_path: file_path)

        expect(result.record[:stats][:updated]).to eq(1)
      end

      context 'when only price changes' do
        before do
          # Ajustar el stock a 799
          create(:stock_movement,
            product: existing_product,
            stock_location: stock_location,
            quantity: 699,
            movement_type: 'adjustment',
            note: 'Stock adjustment to 799'
          )
          existing_product.recalculate_current_stock!
          existing_product.reload
        end

        it 'updates price without stock movement' do
          initial_movements = existing_product.reload.stock_movements.count

          expect {
            described_class.call(file_path: file_path)
          }.not_to change { existing_product.stock_movements.count }

          expect(existing_product.reload.price_unit).to eq(1300)
        end

        it 'records update in stats' do
          result = described_class.call(file_path: file_path)

          expect(result.record[:stats][:updated]).to eq(1)
        end
      end

      context 'when nothing changes' do
        before do
          # Ajustar el stock a 799 y precio a 1300
          existing_product.update!(price_unit: 1300)
          create(:stock_movement,
            product: existing_product,
            stock_location: stock_location,
            quantity: 699,
            movement_type: 'adjustment',
            note: 'Stock adjustment to 799'
          )
          existing_product.recalculate_current_stock!
          existing_product.reload
        end

        it 'skips the product' do
          result = described_class.call(file_path: file_path)

          expect(result.record[:stats][:skipped]).to eq(1)
        end

        it 'does not create stock movement' do
          expect {
            described_class.call(file_path: file_path)
          }.not_to change(StockMovement, :count)
        end
      end
    end

    context 'with invalid data' do
      it 'rejects negative stock' do
        write_csv([
          [ '91503-SZ3-003-IMP', 'Grampa de paragolpe', 'Todos', '$0.13', '$1,300.00', '-10', '', 'TAI', '', '' ]
        ])

        result = described_class.call(file_path: file_path)

        expect(result.success?).to be false
        expect(result.errors).to include(match(/Stock cannot be negative/))
      end

      it 'accepts zero price' do
        write_csv([
          [ '91503-SZ3-003-IMP', 'Grampa de paragolpe', 'Todos', '$0.13', '$0.00', '100', '', 'TAI', '', '' ]
        ])

        result = described_class.call(file_path: file_path)

        expect(result.success?).to be true
        product = Product.find_by(sku: '91503-SZ3-003')
        expect(product.price_unit).to eq(0.0)
      end

      it 'silently skips rows with missing SKU' do
        write_csv([
          [ '', 'Grampa de paragolpe', 'Todos', '$0.13', '$1,300.00', '100', '', 'TAI', '', '' ]
        ])

        result = described_class.call(file_path: file_path)

        expect(result.success?).to be true
        expect(result.record[:stats][:skipped]).to eq(1)
      end

      it 'silently skips rows with missing name' do
        write_csv([
          [ '91503-SZ3-003-IMP', '', 'Todos', '$0.13', '$1,300.00', '100', '', 'TAI', '', '' ]
        ])

        result = described_class.call(file_path: file_path)

        expect(result.success?).to be true
        expect(result.record[:stats][:skipped]).to eq(1)
      end

      it 'silently skips completely empty rows' do
        write_csv([
          [ '', '', '', '', '', '', '', '', '', '' ]
        ])

        result = described_class.call(file_path: file_path)

        expect(result.success?).to be true
        expect(result.record[:stats][:skipped]).to eq(1)
      end
    end

    context 'with origin mapping' do
      it 'maps JAP to japan' do
        write_csv([
          [ '91503-SZ3-003-IMP', 'Producto', 'Todos', '$0.13', '$1,300.00', '100', '', 'JAP', '', '' ]
        ])

        described_class.call(file_path: file_path)

        product = Product.find_by(sku: '91503-SZ3-003')
        expect(product.origin).to eq('japan')
      end

      it 'maps TAI to taiwan' do
        write_csv([
          [ '91503-SZ3-003-IMP', 'Producto', 'Todos', '$0.13', '$1,300.00', '100', '', 'TAI', '', '' ]
        ])

        described_class.call(file_path: file_path)

        product = Product.find_by(sku: '91503-SZ3-003')
        expect(product.origin).to eq('taiwan')
      end

      it 'maps CHI to china' do
        write_csv([
          [ '91503-SZ3-003-IMP', 'Producto', 'Todos', '$0.13', '$1,300.00', '100', '', 'CHI', '', '' ]
        ])

        described_class.call(file_path: file_path)

        product = Product.find_by(sku: '91503-SZ3-003')
        expect(product.origin).to eq('china')
      end

      it 'handles unknown origin gracefully' do
        write_csv([
          [ '91503-SZ3-003-IMP', 'Producto', 'Todos', '$0.13', '$1,300.00', '100', '', 'USA', '', '' ]
        ])

        result = described_class.call(file_path: file_path)

        # Origin es opcional ahora, así que debería tener éxito
        expect(result.success?).to be true
        product = Product.find_by(sku: '91503-SZ3-003')
        expect(product.origin).to be_nil
      end

      it 'handles blank origin' do
        write_csv([
          [ '91503-SZ3-003-IMP', 'Producto', 'Todos', '$0.13', '$1,300.00', '100', '', '', '', '' ]
        ])

        result = described_class.call(file_path: file_path)

        expect(result.success?).to be true
        product = Product.find_by(sku: '91503-SZ3-003')
        expect(product.origin).to be_nil
      end
    end

    context 'with multiple products' do
      before do
        write_csv([
          [ '91503-SZ3-003-IMP', 'Grampa de paragolpe', 'Todos', '$0.13', '$1,300.00', '799', '', 'TAI', '', '' ],
          [ '12342-P2F-A01-IMP', 'Sello de bujia', 'Varios', '$0.94', '$4,500.00', '160', '', 'JAP', '', '' ],
          [ '88888-XXX-999-IMP', 'Producto inválido', 'Ninguno', '$0.50', '$0.00', '50', '', 'CHI', '', '' ]
        ])
      end

      it 'creates all valid products' do
        expect {
          described_class.call(file_path: file_path)
        }.to change(Product, :count).by(3) # Todos son válidos (precio 0 permitido)
      end

      it 'tracks all stats correctly' do
        result = described_class.call(file_path: file_path)

        expect(result.record[:stats][:created]).to eq(3)
        expect(result.record[:stats][:errors]).to eq(0)
        expect(result.record[:stats][:movements]).to eq(3)
      end
    end

    context 'when CSV file does not exist' do
      it 'returns error result' do
        result = described_class.call(file_path: '/non/existent/file.csv')

        expect(result.success?).to be false
        expect(result.errors).not_to be_empty
      end
    end

    context 'with zero stock in CSV' do
      before do
        write_csv([
          [ '91503-SZ3-003-IMP', 'Producto sin stock', 'Todos', '$0.13', '$1,300.00', '0', '', 'TAI', '', '' ]
        ])
      end

      it 'creates product without stock movement' do
        expect {
          described_class.call(file_path: file_path)
        }.to change(Product, :count).by(1)
         .and change(StockMovement, :count).by(0) # No movement para stock 0
      end

      it 'creates product with zero stock' do
        described_class.call(file_path: file_path)

        product = Product.find_by(sku: '91503-SZ3-003')
        expect(product.current_stock).to eq(0)
      end
    end

    context 'with edge cases in CSV formatting' do
      it 'handles prices without currency symbol' do
        write_csv([
          [ '91503-SZ3-003-IMP', 'Producto', 'Todos', '0.13', '1300', '100', '', 'TAI', '', '' ]
        ])

        result = described_class.call(file_path: file_path)

        expect(result.success?).to be true
        product = Product.find_by(sku: '91503-SZ3-003')
        expect(product.cost_unit).to eq(0.13)
        expect(product.price_unit).to eq(1300.0)
      end

      it 'handles stock with commas' do
        write_csv([
          [ '91503-SZ3-003-IMP', 'Producto', 'Todos', '$0.13', '$1,300.00', '1,500', '', 'TAI', '', '' ]
        ])

        result = described_class.call(file_path: file_path)

        expect(result.success?).to be true
        product = Product.find_by(sku: '91503-SZ3-003')
        expect(product.current_stock).to eq(1500)
      end
    end
  end
end
