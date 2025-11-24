class Product < ApplicationRecord
  # Associations
  has_many :stock_movements, dependent: :destroy

  # current_stock es un campo cacheado que se actualiza automáticamente
  # vía callbacks en StockMovement. NO actualizar manualmente.
  #
  # cost_unit representa el COSTO PROMEDIO PONDERADO del inventario
  # Se recalcula automáticamente al confirmar cada compra
  # NO es el "último costo" sino el promedio de todas las compras
  # cost_currency: moneda del costo promedio (típicamente 'USD')
  # Se actualiza automáticamente vía recalculate_average_cost!
  # NO actualizar manualmente desde controllers/vistas
  #
  # Según FLUJOS.md sección 8:
  # - product_type: 'oem' (original) o 'aftermarket' (alternativo)
  # - origin: país de fabricación (japan, china, taiwan, etc.)
  # - cost_currency: 'USD' o 'ARS' - indica en qué moneda está cost_unit

  # Constants
  CATEGORIES = %w[frenos motor suspension transmision electrico carroceria filtros lubricantes].freeze
  ORIGINS = %w[japan china taiwan usa germany korea brazil india].freeze
  PRODUCT_TYPES = %w[oem aftermarket].freeze

  # Validations
  validates :sku, presence: true, uniqueness: true
  validates :name, presence: true
  validates :price_unit, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :cost_unit, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :cost_currency, inclusion: { in: %w[USD ARS] }
  validates :origin, inclusion: { in: ORIGINS, allow_blank: true }
  validates :origin, presence: true, if: :aftermarket?
  validates :product_type, inclusion: { in: PRODUCT_TYPES, allow_blank: true }
  validates :category, inclusion: { in: CATEGORIES, allow_blank: true }

  # Scopes
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :with_low_stock, -> { where("current_stock < ?", 5) }
  scope :by_category, ->(cat) { where(category: cat) if cat.present? }
  scope :by_origin, ->(origin) { where(origin: origin) if origin.present? }
  scope :by_product_type, ->(type) { where(product_type: type) if type.present? }
  scope :by_status, lambda { |status|
    return active if status.blank?

    case status.to_s.downcase
    when "active" then active
    when "inactive" then inactive
    else active # default to active for invalid values
    end
  }
  scope :oem, -> { where(product_type: "oem") }
  scope :aftermarket, -> { where(product_type: "aftermarket") }
  scope :search, lambda { |query|
    where("sku ILIKE ? OR name ILIKE ?",
          "%#{query}%", "%#{query}%") if query.present?
  }

  # Stock cacheado: current_stock es una columna en products
  # SOLO se debe modificar desde services de inventario usando recalculate_current_stock!
  # NUNCA editar directamente desde controllers o vistas
  def recalculate_current_stock!
    update!(current_stock: stock_movements.sum(:quantity))
  end

  # Recalcula el costo promedio ponderado basado en TODAS las compras confirmadas
  # Convierte todo a USD para uniformidad en el cálculo
  # Se llama automáticamente desde Purchasing::CreatePurchase y Purchasing::CancelPurchase
  def recalculate_average_cost!
    # Obtener TODAS las compras confirmadas de este producto
    purchase_items = PurchaseItem.joins(:purchase)
                                  .where(product: self)
                                  .where(purchases: { status: "confirmed" })

    return if purchase_items.empty?

    # Calcular costo promedio ponderado en USD
    # (convertir todo a USD para uniformidad)
    total_cost_usd = 0.0
    total_quantity = 0

    purchase_items.find_each do |item|
      if item.purchase.currency == "USD"
        total_cost_usd += item.unit_cost * item.quantity
      else
        # Si es ARS, convertir a USD usando el exchange_rate inverso
        # (esto es aproximado, en producción se podría mejorar)
        cost_in_usd = item.unit_cost / (item.purchase.exchange_rate || 1200)
        total_cost_usd += cost_in_usd * item.quantity
      end

      total_quantity += item.quantity
    end

    if total_quantity > 0
      average_cost = (total_cost_usd / total_quantity).round(2)
      update_columns(
        cost_unit: average_cost,
        cost_currency: "USD"
      )
    end
  end

  # Alias para claridad semántica
  # cost_unit representa el COSTO PROMEDIO PONDERADO del inventario
  # Se recalcula automáticamente al confirmar cada compra
  # NO es el "último costo" sino el promedio de todas las compras
  alias_attribute :average_cost, :cost_unit

  def low_stock?
    current_stock.to_i < 5
  end

  # Convierte el costo promedio ponderado a ARS usando el tipo de cambio actual
  # Si cost_currency ya es ARS, retorna cost_unit directamente
  def cost_in_ars(exchange_rate = nil)
    return 0 if cost_unit.nil?
    return cost_unit if cost_currency == "ARS"

    rate = exchange_rate || 1000  # TODO: usar ExchangeRate.current cuando exista
    cost_unit * rate
  end

  # Calcula el margen de ganancia en ARS usando el costo promedio ponderado
  def margin(exchange_rate = nil)
    return 0 if price_unit.nil?
    price_unit - cost_in_ars(exchange_rate)
  end

  # Calcula el porcentaje de margen basado en el costo promedio ponderado
  def margin_percentage(exchange_rate = nil)
    cost = cost_in_ars(exchange_rate)
    return 0 if cost.zero? || price_unit.nil?
    ((price_unit - cost) / cost * 100).round(2)
  end

  def oem?
    product_type == "oem"
  end

  def aftermarket?
    product_type == "aftermarket"
  end
end
