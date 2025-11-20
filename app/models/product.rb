class Product < ApplicationRecord
  has_many :stock_movements, dependent: :destroy

  # Stock cacheado: current_stock es una columna en products
  # SOLO se debe modificar desde services de inventario usando recalculate_current_stock!
  # NUNCA editar directamente desde controllers o vistas
  def recalculate_current_stock!
    update!(current_stock: stock_movements.sum(:quantity))
  end

  def low_stock?
    current_stock.to_i < 20
  end
end
