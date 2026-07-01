class Product < ApplicationRecord
  # Associations
  has_many :stock_movements, dependent: :destroy

  # === SKU AND VARIANTS ===
  # sku represents the OEM CODE of the part (e.g.: original Honda code)
  # IT MAY REPEAT across multiple variants of the same part
  #
  # VARIANTS are distinguished by the unique combination of:
  #   - sku (common OEM code)
  #   - product_type ('oem' or 'aftermarket')
  #   - brand (manufacturer brand)
  #   - origin (country of manufacture)
  #
  # Example: The same OEM "12345-111-111" may have:
  #   - Variant 1: OEM Honda from Japan
  #   - Variant 2: Aftermarket Marca1 from China
  #   - Variant 3: Aftermarket Marca2 from China
  #   - Variant 4: Aftermarket Marca3 from India
  #
  # Each variant is a separate record with its own:
  #   - product_id (unique)
  #   - current_stock (independent)
  #   - cost_unit (independent average cost)
  #   - price_unit (independent sale price)
  #
  # === STOCK AND COSTS ===
  # current_stock is a cached field that updates automatically
  # via callbacks in StockMovement. DO NOT update manually.
  #
  # cost_unit represents the WEIGHTED AVERAGE COST of the inventory
  # It is recalculated automatically when each purchase is confirmed
  # It is NOT the "last cost" but the average of all purchases
  # cost_currency: currency of the average cost (typically 'USD')
  # It is updated automatically via recalculate_average_cost!
  # DO NOT update manually from controllers/views

  # Constants
  CATEGORIES = %w[frenos motor suspension transmision electrico carroceria filtros lubricantes].freeze
  ORIGINS = %w[japan china taiwan usa germany korea brazil india thailand canada].freeze
  PRODUCT_TYPES = %w[oem aftermarket].freeze

  # Physical location format in the warehouse
  # [aisle: 1-9][side: I/D][position: 0-9][level: 0-9]
  # Example: "2D31" = Aisle 2, Right, position 3, level 1
  LOCATION_FORMAT = /\A[1-9][ID][0-9][0-9]\z/

  # Validations
  # SKU is the OEM code, it may repeat across variants.
  # A variant's identity is: sku + product_type + origin + brand.
  # Uniqueness is enforced ONLY when `origin` is present, to allow
  # progressive loading (origin first, brand refined later) and so that
  # importers can create products with origin/brand as nil without colliding.
  # The DB index (index_products_on_variant_uniqueness) stays lenient
  # (NULLS DISTINCT): it is a backstop for complete rows; the model is the real enforcer.
  validates :sku, presence: true
  validates :sku, uniqueness: { scope: [ :product_type, :origin, :brand ] },
                  if: -> { origin.present? }
  validates :name, presence: true
  validates :price_unit, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :cost_unit, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :cost_currency, inclusion: { in: %w[USD ARS] }
  validates :origin, inclusion: { in: ORIGINS, allow_blank: true }
  # validates :origin, presence: true, if: :aftermarket? - Relaxed to allow excel imports with tickets
  validates :product_type, inclusion: { in: PRODUCT_TYPES, allow_blank: true }
  validates :category, inclusion: { in: CATEGORIES, allow_blank: true }
  validates :location_code, format: {
    with: LOCATION_FORMAT,
    message: "debe tener el formato NPnn (ej: 2D31 = Pasillo 2, Derecho, posición 3, nivel 1)",
    allow_blank: true
  }

  # Normalization
  # The SKU (OEM code) is ALWAYS stored in uppercase, whether it comes from the form,
  # the import, or the console. It goes in before_validation so that uniqueness and
  # the other validations run on the already-normalized value.
  before_validation :normalize_sku

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
    where("sku ILIKE ? OR name ILIKE ? OR brand ILIKE ?",
          "%#{query}%", "%#{query}%", "%#{query}%") if query.present?
  }
  scope :at_location, ->(code) { where(location_code: code) if code.present? }
  scope :sorted_by, lambda { |sort_column, direction|
    # Default ordering
    return order(:name) if sort_column.blank?

    # Validate allowed columns to prevent SQL injection
    allowed_columns = %w[sku name brand category current_stock price_unit]
    column = allowed_columns.include?(sort_column.to_s) ? sort_column : "name"

    # Validate direction
    dir = %w[asc desc].include?(direction.to_s.downcase) ? direction.downcase : "asc"

    order("#{column} #{dir}")
  }

  # Cached stock: current_stock is a column in products
  # It must ONLY be modified from inventory services using recalculate_current_stock!
  # NEVER edit directly from controllers or views
  def recalculate_current_stock!
    update!(current_stock: stock_movements.sum(:quantity))
  end

  # Recalculates the weighted average cost based on ALL confirmed purchases
  # Converts everything to USD for uniformity in the calculation
  # It is called automatically from Purchasing::CreateInvoice and Purchasing::CancelInvoice
  def recalculate_average_cost!
    # Get ALL confirmed purchases of this product
    invoice_items = InvoiceItem.joins(:invoice)
                                .where(product: self)
                                .where(invoices: { status: "confirmed" })

    return if invoice_items.empty?

    # Calculate weighted average cost in USD
    # (convert everything to USD for uniformity)
    total_cost_usd = 0.0
    total_quantity = 0

    invoice_items.find_each do |item|
      if item.invoice.currency == "USD"
        total_cost_usd += item.unit_cost * item.quantity
      else
        # If it is ARS, convert to USD using the inverse exchange_rate
        # (this is approximate, in production it could be improved)
        cost_in_usd = item.unit_cost / (item.invoice.exchange_rate || 1200)
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

  # Alias for semantic clarity
  # cost_unit represents the WEIGHTED AVERAGE COST of the inventory
  # It is recalculated automatically when each purchase is confirmed
  # It is NOT the "last cost" but the average of all purchases
  alias_attribute :average_cost, :cost_unit

  def low_stock?
    current_stock.to_i < 5
  end

  # Converts the weighted average cost to ARS using the current exchange rate
  # If cost_currency is already ARS, returns cost_unit directly
  def cost_in_ars(exchange_rate = nil)
    return 0 if cost_unit.nil?
    return cost_unit if cost_currency == "ARS"

    rate = exchange_rate || 1000  # TODO: use ExchangeRate.current when it exists
    cost_unit * rate
  end

  # Calculates the profit margin in ARS using the weighted average cost
  def margin(exchange_rate = nil)
    return 0 if price_unit.nil?
    price_unit - cost_in_ars(exchange_rate)
  end

  # Calculates the margin percentage based on the weighted average cost
  def margin_percentage(exchange_rate = nil)
    cost = cost_in_ars(exchange_rate)
    return 0 if cost.zero? || price_unit.nil?
    ((price_unit - cost) / cost * 100).round(2)
  end

  # Converts the location code to a readable format
  # Example: "2D31" → "Pasillo 2, lado derecho, posición 3, nivel 1"
  def location_human
    return "Sin ubicación asignada" if location_code.blank?

    pasillo = location_code[0]
    lado = location_code[1] == "I" ? "izquierdo" : "derecho"
    posicion = location_code[2]
    nivel = location_code[3]

    "Pasillo #{pasillo}, lado #{lado}, posición #{posicion}, nivel #{nivel}"
  end

  def oem?
    product_type == "oem"
  end

  def aftermarket?
    product_type == "aftermarket"
  end

  private

  def normalize_sku
    self.sku = sku.strip.upcase if sku.present?
  end
end
