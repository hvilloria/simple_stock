class Order < ApplicationRecord
  # Associations
  belongs_to :customer, optional: true
  has_many :order_items, dependent: :destroy
  has_many :products, through: :order_items
  has_many :stock_movements, as: :reference, dependent: :nullify

  # Nested attributes
  accepts_nested_attributes_for :order_items, allow_destroy: true, reject_if: :all_blank

  # Enums
  enum :status, {
    confirmed: "confirmed",
    cancelled: "cancelled"
  }, suffix: true

  enum :order_type, {
    cash: "cash",
    credit: "credit"
  }, suffix: true

  # Constants
  ALLOWED_CHANNELS = %w[counter whatsapp mercadolibre].freeze

  # Validations
  validates :order_type, presence: true
  validates :total_amount,
            numericality: { greater_than: 0 },
            unless: :from_paper?
  validates :total_amount,
            numericality: { greater_than_or_equal_to: 0 },
            if: :from_paper?
  validates :sale_date, presence: true
  validates :source, inclusion: { in: %w[live from_paper] }
  validates :channel, inclusion: { in: ALLOWED_CHANNELS, allow_nil: true }
  validate :credit_order_requires_credit_account

  # Scopes
  scope :cash, -> { where(order_type: "cash") }
  scope :credit, -> { where(order_type: "credit") }
  scope :active, -> { where.not(status: "cancelled") }
  scope :from_paper, -> { where(source: "from_paper") }
  scope :live, -> { where(source: "live") }
  scope :by_sale_date, ->(date) { where(sale_date: date) if date.present? }

  # === VENTAS-LITE MODE ===
  # source: Indica el origen de la venta
  #   - 'live': Venta registrada en tiempo real (precios confiables)
  #   - 'from_paper': Venta cargada desde talonario físico (precios aproximados/opcionales)
  #
  # sale_date: Fecha REAL de la venta (puede ser distinta a created_at si se carga con retraso)
  # paper_number: Número del talonario físico (para cruzar con registros en papel)
  #
  # Validación de total_amount:
  #   - Ventas 'live': total_amount DEBE ser > 0
  #   - Ventas 'from_paper': total_amount PUEDE ser >= 0 (incluso 0 si precios desconocidos)

  def from_paper?
    source == "from_paper"
  end

  def live?
    source == "live"
  end

  def calculate_total!
    update!(total_amount: order_items.sum("quantity * unit_price"))
  end

  def cancel!(reason: nil)
    result = Sales::CancelOrder.call(order: self, reason: reason)

    if result.success?
      result.record
    else
      raise StandardError, result.errors.join(", ")
    end
  end

  private

  # Valida que las ventas a crédito solo se hagan a clientes con cuenta corriente
  def credit_order_requires_credit_account
    return unless credit_order_type?
    return if customer.nil? # Ya se maneja con belongs_to optional

    unless customer.has_credit_account?
      errors.add(:base, "Credit orders require a customer with credit account enabled")
    end
  end
end
