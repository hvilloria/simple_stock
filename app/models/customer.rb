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
    with_credit_account
      .where(
        "( SELECT COALESCE(SUM(o.total_amount), 0)
           FROM orders o
           WHERE o.customer_id = customers.id
             AND o.order_type = 'credit'
             AND o.status = 'confirmed' )
         >
         ( SELECT COALESCE(SUM(p.amount), 0)
           FROM payments p
           WHERE p.customer_id = customers.id )"
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

  # Calculate current balance for customers with credit account
  def current_balance
    return 0 unless has_credit_account?

    total_credit_sales = orders
                          .where(order_type: "credit")
                          .where.not(status: "cancelled")
                          .sum(:total_amount)

    total_payments = payments.sum(:amount) rescue 0  # rescue because Payment might not exist yet

    total_credit_sales - total_payments
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
