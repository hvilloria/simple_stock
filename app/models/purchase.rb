class Purchase < ApplicationRecord
  # Associations
  belongs_to :supplier
  has_many :purchase_items, dependent: :destroy
  has_many :products, through: :purchase_items
  has_many :stock_movements, as: :reference, dependent: :nullify

  # Enums - Expandir estados
  enum :status, {
    pending: "pending",     # Factura pendiente de pago (modo simple)
    paid: "paid",          # Factura pagada (modo simple)
    confirmed: "confirmed", # Compra confirmada (modo completo)
    cancelled: "cancelled"  # Cancelada
  }, suffix: true

  # === VALIDACIONES COMUNES ===
  validates :currency, inclusion: { in: %w[USD ARS] }
  validates :exchange_rate, presence: true, if: :usd_currency?
  validates :exchange_rate, numericality: { greater_than: 0 }, allow_nil: true
  validates :purchase_date, presence: true
  validates :supplier_id, presence: true

  # === VALIDACIONES MODO SIMPLE (has_items: false) ===
  validates :invoice_number, presence: true, unless: :has_items?
  validates :due_date, presence: true, unless: :has_items?
  validates :amount, presence: true, unless: :has_items?
  validates :amount, numericality: { greater_than: 0 }, if: -> { !has_items? && amount.present? }

  # === VALIDACIONES MODO COMPLETO (has_items: true) ===
  # Validar purchase_items solo después de crear el purchase (no durante create)
  validates :purchase_items, presence: true, if: -> { has_items? && !new_record? }, on: :update

  # === SCOPES ===
  scope :simple_mode, -> { where(has_items: false) }
  scope :full_mode, -> { where(has_items: true) }
  scope :pending_payment, -> { where(status: "pending") }
  scope :paid_purchases, -> { where(status: "paid") }
  scope :overdue, -> { simple_mode.where(status: "pending").where("due_date < ?", Date.today) }
  scope :due_soon, -> { simple_mode.where(status: "pending").where("due_date <= ?", 7.days.from_now.to_date) }
  scope :by_due_date, -> { order(due_date: :asc) }

  # Nuevos scopes para métricas
  scope :due_today, -> { simple_mode.where(status: "pending").where(due_date: Date.current) }
  scope :due_this_week, -> {
    start_of_week = Date.current.beginning_of_week(:monday)
    end_of_week = Date.current.end_of_week(:monday)
    simple_mode.where(status: "pending").where(due_date: start_of_week..end_of_week)
  }

  # Filtro por proveedor (acepta nil para "todos")
  scope :for_supplier, ->(supplier) { where(supplier_id: supplier.id) if supplier.present? }

  # Búsqueda por número de factura (case-insensitive, partial match)
  scope :search_invoice, ->(query) { where("invoice_number ILIKE ?", "%#{query}%") if query.present? }

  # Ordenado por prioridad: 1) pending primero, 2) vencimiento más cercano
  scope :priority_order, -> {
    order(
      Arel.sql("CASE WHEN status = 'pending' THEN 0 ELSE 1 END"),
      Arel.sql("CASE WHEN due_date IS NULL THEN 1 ELSE 0 END"),
      "due_date ASC"
    )
  }

  # === MÉTODOS DE CLASE (para métricas) ===

  # Calcula el total pendiente en ARS, opcionalmente filtrado por proveedor
  # @param supplier [Supplier, nil] Proveedor para filtrar, o nil para todos
  # @return [Float] Total en ARS
  def self.total_pending_amount_ars(supplier: nil)
    scope = simple_mode.pending_payment
    scope = scope.for_supplier(supplier) if supplier
    scope.sum { |p| p.total_amount_ars }
  end

  # === MÉTODOS MODO SIMPLE ===

  def simple_mode?
    !has_items?
  end

  def full_mode?
    has_items?
  end

  # Total unificado (funciona para ambos modos)
  def total_amount
    if has_items?
      calculate_total  # Suma de items
    else
      amount  # Monto directo
    end
  end

  # Total en ARS (funciona para ambos modos)
  def total_amount_ars
    if currency == "USD"
      total_amount * (exchange_rate || 0)
    else
      total_amount || 0
    end
  end

  def overdue?
    pending_status? && due_date && due_date < Date.today
  end

  def days_until_due
    return nil unless due_date
    (due_date - Date.today).to_i
  end

  def mark_as_paid!(payment_date = Date.today)
    raise "Cannot mark as paid: not in simple mode" unless simple_mode?
    raise "Cannot mark as paid: already paid" if paid_status?

    update!(status: "paid", paid_at: payment_date)
  end

  # === MÉTODOS MODO COMPLETO (existentes) ===

  # Calculate total cost from purchase items
  def calculate_total
    return amount unless has_items?
    purchase_items.sum { |item| item.quantity * item.unit_cost }
  end

  # Calculate total cost in ARS
  def calculate_total_ars
    if currency == "USD"
      calculate_total * exchange_rate
    else
      calculate_total
    end
  end

  private

  def usd_currency?
    currency == "USD"
  end
end
