class Customer < ApplicationRecord
  # Associations
  has_many :orders, dependent: :nullify
  has_many :payments, dependent: :destroy

  # Enums
  enum :customer_type, {
    retail: "retail",
    workshop: "workshop",
    mechanic: "mechanic",
    store: "store"
  }, suffix: true

  # Validations
  validates :name, presence: true
  validates :customer_type, presence: true
  validate :retail_cannot_have_credit_account

  # Scopes
  scope :with_credit_account, -> { where(has_credit_account: true) }
  scope :retail, -> { where(customer_type: "retail") }
  scope :workshops, -> { where(customer_type: "workshop") }
  scope :mechanics, -> { where(customer_type: "mechanic") }
  scope :stores, -> { where(customer_type: "store") }
  scope :with_outstanding_balance, -> {
    with_credit_account.where(
      "( SELECT COALESCE(SUM(o.total_amount), 0)
         FROM orders o
         WHERE o.customer_id = customers.id
           AND o.order_type = 'credit'
           AND o.status = 'confirmed' )
       >
       ( SELECT COALESCE(SUM(pa.amount), 0)
         FROM payment_allocations pa
         JOIN orders o ON pa.order_id = o.id
         WHERE o.customer_id = customers.id
           AND o.order_type = 'credit'
           AND o.status = 'confirmed' )"
    )
  }

  # Retorna el cliente genérico para ventas de mostrador (contado)
  # Según FLUJOS.md sección 1: cliente genérico para consumidores finales
  def self.mostrador
    find_or_create_by!(name: "Cliente Mostrador") do |c|
      c.customer_type = "retail"
      c.has_credit_account = false
    end
  end

  # Calculate current balance for customers with credit account.
  # Only payments allocated to credit orders count against the balance —
  # payments for immediate sales do not affect credit debt.
  def current_balance
    return 0 unless has_credit_account?

    credit_owed = orders
                    .where(order_type: "credit", status: "confirmed")
                    .sum(:total_amount)

    credit_paid = PaymentAllocation
                    .joins(:order)
                    .where(orders: { customer_id: id, order_type: "credit", status: "confirmed" })
                    .sum(:amount)

    credit_owed - credit_paid
  end

  def last_payment_date
    payments.maximum(:payment_date)
  end

  def days_without_paying
    return nil if last_payment_date.nil?

    (Date.today - last_payment_date).to_i
  end

  private

  def retail_cannot_have_credit_account
    return unless retail_customer_type?

    if has_credit_account?
      errors.add(:has_credit_account, "no puede estar habilitada para clientes minoristas")
    end
  end
end
