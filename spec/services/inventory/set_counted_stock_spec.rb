# frozen_string_literal: true

require "rails_helper"

RSpec.describe Inventory::SetCountedStock do
  let!(:location) { create(:stock_location) }
  let(:admin)     { create(:user, :admin) }
  let(:filter)    { create(:product, name: "Filtro de aceite", current_stock: 0) }
  let(:plug)      { create(:product, name: "Bujía iridium", current_stock: 0) }

  def stock!(product, quantity)
    create(:stock_movement, product: product, stock_location: location, quantity: quantity, movement_type: "purchase")
    product.recalculate_current_stock!
  end

  def call(lines, note: "Conteo de fin de mes")
    described_class.call(user: admin, note: note, lines: lines)
  end

  it "raises and lowers stock to the counted numbers" do
    stock!(filter, 12)
    stock!(plug, 0)

    result = call([ { product_id: filter.id, counted: "9" }, { product_id: plug.id, counted: "4" } ])

    expect(result.success?).to be true
    expect(filter.reload.current_stock).to eq(9)
    expect(plug.reload.current_stock).to eq(4)
    expect(result.record.map(&:quantity)).to contain_exactly(-3, 4)
  end

  it "writes adjustments that name the admin and the reason, with no reference" do
    stock!(filter, 5)

    movement = call([ { product_id: filter.id, counted: "2" } ]).record.first

    expect(movement.movement_type).to eq("adjustment")
    expect(movement.user).to eq(admin)
    expect(movement.note).to eq("Conteo de fin de mes")
    expect(movement.reference).to be_nil
    expect(movement.stock_location).to eq(location)
  end

  it "takes a product down to zero" do
    stock!(filter, 7)

    expect(call([ { product_id: filter.id, counted: "0" } ]).success?).to be true
    expect(filter.reload.current_stock).to eq(0)
  end

  it "writes nothing for a line that already matches" do
    stock!(filter, 5)
    stock!(plug, 1)

    result = call([ { product_id: filter.id, counted: "5" }, { product_id: plug.id, counted: "3" } ])

    expect(result.record.size).to eq(1)
    expect(filter.stock_movements.where(movement_type: "adjustment")).to be_empty
  end

  it "fails when no line changes anything" do
    stock!(filter, 5)

    result = nil
    expect { result = call([ { product_id: filter.id, counted: "5" } ]) }.not_to change(StockMovement, :count)
    expect(result.errors).to eq([ "No hay cambios de stock para guardar" ])
  end

  it "takes the difference against the stock at save time" do
    stock!(filter, 10)
    sold = false
    allow(Product).to receive(:lock).and_wrap_original do |original, *args|
      unless sold
        sold = true
        create(:stock_movement, product: filter, stock_location: location, quantity: -3, movement_type: "sale")
        filter.recalculate_current_stock!
      end
      original.call(*args)
    end

    result = call([ { product_id: filter.id, counted: "5" } ])

    expect(result.record.first.quantity).to eq(-2)
    expect(filter.reload.current_stock).to eq(5)
  end

  it "accepts spaces around the number" do
    stock!(filter, 1)

    expect(call([ { product_id: filter.id, counted: " 7 " } ]).success?).to be true
    expect(filter.reload.current_stock).to eq(7)
  end

  it "adjusts an inactive product" do
    filter.update!(active: false)
    stock!(filter, 1)

    expect(call([ { product_id: filter.id, counted: "3" } ]).success?).to be true
  end

  it "lands on the count when the cached stock reads higher than the movements" do
    filter.update_column(:current_stock, 10)

    result = call([ { product_id: filter.id, counted: "7" } ])

    expect(result.record.first.quantity).to eq(7)
    expect(filter.reload.current_stock).to eq(7)
  end

  it "lands on the count when the cached stock reads lower than the movements" do
    stock!(filter, 10)
    filter.update_column(:current_stock, 3)

    result = call([ { product_id: filter.id, counted: "0" } ])

    expect(result.record.first.quantity).to eq(-10)
    expect(filter.reload.current_stock).to eq(0)
  end

  describe "refusals" do
    before { stock!(filter, 5) }

    def refused(lines, note: "Conteo de fin de mes")
      result = nil
      expect { result = call(lines, note: note) }.not_to change(StockMovement, :count)
      expect(filter.reload.current_stock).to eq(5)
      result.errors
    end

    it "requires a reason" do
      expect(refused([ { product_id: filter.id, counted: "2" } ], note: "   ")).to eq([ "El motivo es obligatorio" ])
    end

    it "requires at least one line" do
      expect(refused([])).to eq([ "Agregá al menos un producto" ])
    end

    it "refuses a blank count" do
      expect(refused([ { product_id: filter.id, counted: "" } ]))
        .to eq([ "El stock real de Filtro de aceite debe ser un número entero mayor o igual a 0" ])
    end

    it "refuses a count that is not a whole number" do
      %w[3,5 3.5 abc].each do |raw|
        expect(refused([ { product_id: filter.id, counted: raw } ]))
          .to eq([ "El stock real de Filtro de aceite debe ser un número entero mayor o igual a 0" ])
      end
    end

    it "refuses a negative count" do
      expect(refused([ { product_id: filter.id, counted: "-1" } ]))
        .to eq([ "El stock real de Filtro de aceite debe ser un número entero mayor o igual a 0" ])
    end

    it "refuses a count too large to store" do
      expect(refused([ { product_id: filter.id, counted: "3000000000" } ]))
        .to eq([ "El stock real de Filtro de aceite es demasiado grande" ])
    end

    it "refuses the same product twice" do
      expect(refused([ { product_id: filter.id, counted: "2" }, { product_id: filter.id.to_s, counted: "3" } ]))
        .to eq([ "Filtro de aceite está repetido" ])
    end

    it "refuses a deleted product" do
      gone = create(:product, name: "Correa", current_stock: 0)
      gone.destroy

      expect(refused([ { product_id: gone.id, counted: "2" } ])).to eq([ "Producto no encontrado" ])
    end

    it "refuses a line without a product" do
      expect(refused([ { product_id: "", counted: "2" } ])).to eq([ "Producto no encontrado" ])
    end

    it "refuses the same product written two ways" do
      expect(refused([ { product_id: filter.id.to_s, counted: "2" }, { product_id: " #{filter.id}", counted: "3" } ]))
        .to eq([ "Filtro de aceite está repetido" ])
    end

    it "refuses a product id with trailing garbage" do
      expect(refused([ { product_id: "#{filter.id}abc", counted: "2" } ])).to eq([ "Producto no encontrado" ])
    end

    it "refuses several lines without a product" do
      expect(refused([ { product_id: "", counted: "2" }, { product_id: "", counted: "3" } ]))
        .to eq([ "Producto no encontrado" ])
    end

    it "asks to retry when another stock movement deadlocks the save" do
      allow(Inventory::AdjustStock).to receive(:call).and_raise(ActiveRecord::Deadlocked)

      expect(refused([ { product_id: filter.id, counted: "2" } ]))
        .to eq([ "Otro movimiento de stock se guardó al mismo tiempo. Probá guardar el ajuste de nuevo." ])
    end

    it "rolls every line back when one movement fails" do
      stock!(plug, 1)
      allow(Inventory::AdjustStock).to receive(:call).and_call_original
      allow(Inventory::AdjustStock).to receive(:call).with(hash_including(product: plug))
        .and_return(Result.new(success?: false, record: nil, errors: [ "Error adjusting stock" ]))

      errors = refused([ { product_id: filter.id, counted: "2" }, { product_id: plug.id, counted: "4" } ])

      expect(errors).to eq([ "Error adjusting stock" ])
      expect(plug.reload.current_stock).to eq(1)
    end
  end
end
