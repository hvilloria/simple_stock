class Order < ApplicationRecord
  # Associations
  belongs_to :customer, optional: true
  has_many :order_items, dependent: :destroy
  has_many :products, through: :order_items
  has_many :payment_allocations, dependent: :destroy
  has_many :payments, through: :payment_allocations
  has_many :stock_movements, as: :reference, dependent: :nullify

  # Nested attributes
  accepts_nested_attributes_for :order_items, allow_destroy: true, reject_if: :all_blank

  # Enums
  enum :status, {
    confirmed: "confirmed",
    cancelled: "cancelled"
  }, suffix: true

  enum :order_type, {
    immediate: "immediate",
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
  validates :paper_number, presence: true, if: :from_paper?
  validate :credit_order_requires_credit_account
  validates :original_total_amount,
            presence: true,
            numericality: { greater_than_or_equal_to: 0 }
  validate :original_total_at_least_current_total

  # Scopes
  scope :immediate, -> { where(order_type: "immediate") }
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

  # Monto pendiente de cobrar para esta orden específica.
  # Solo considera pagos directamente vinculados via order_id.
  # Los pagos sueltos del cliente (sin order_id) no se descontan aquí.
  def outstanding_balance
    return 0 unless credit_order_type?
    return 0 if cancelled_status?

    total_amount - payment_allocations.sum(:amount)
  end

  def from_paper?
    source == "from_paper"
  end

  def live?
    source == "live"
  end

  def calculate_total!
    update!(total_amount: order_items.sum("quantity * unit_price"))
  end

  def discount_amount
    return 0 if original_total_amount.nil? || total_amount.nil?
    original_total_amount - total_amount
  end

  # Assumes all items share the same discount_percent (true for feat_08 immediate sales).
  # Revisit this helper in feat_09 when credit orders introduce per-item discounts.
  def discount_percent_display
    order_items.first&.discount_percent.to_i
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

  def original_total_at_least_current_total
    return if original_total_amount.nil? || total_amount.nil?
    if original_total_amount < total_amount
      errors.add(:original_total_amount, "no puede ser menor al total actual")
    end
  end
end
