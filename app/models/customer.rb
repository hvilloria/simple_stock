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

  # Scopes
  scope :with_credit_account, -> { where(has_credit_account: true) }
  scope :retail, -> { where(customer_type: "retail") }
  scope :workshops, -> { where(customer_type: "workshop") }
  scope :mechanics, -> { where(customer_type: "mechanic") }
  scope :stores, -> { where(customer_type: "store") }

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
end
