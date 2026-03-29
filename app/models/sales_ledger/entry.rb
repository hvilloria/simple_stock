# frozen_string_literal: true

module SalesLedger
  class Entry < ApplicationRecord
    self.table_name = "sales_ledger_entries"

    PAYMENT_METHODS = %w[cash bank mercado_pago].freeze

    belongs_to :sales_import, class_name: "SalesLedger::SalesImport"
    belongs_to :product
    belongs_to :seller_user, class_name: "User", optional: true

    validates :entry_fingerprint, presence: true, uniqueness: true
    validates :sale_date, presence: true
    validates :ticket_number, presence: true
    validates :oem_code, presence: true
    validates :product_name_snapshot, presence: true
    validates :quantity, presence: true,
                         numericality: { only_integer: true, greater_than: 0 }
    validates :unit_price, presence: true,
                           numericality: { greater_than: 0 }
    validates :total_amount, presence: true,
                             numericality: { greater_than: 0 }

    # New fields — nullable at DB level to preserve historical records,
    # validated for presence by the importer service before create.
    validates :payment_method, inclusion: { in: PAYMENT_METHODS }, allow_nil: true
    validates :ticket_total_amount, numericality: { greater_than: 0 }, allow_nil: true

    scope :for_date_range, ->(from, to) { where(sale_date: from..to) }
    scope :for_product, ->(product_id) { where(product_id: product_id) }
    scope :with_mismatch, -> { where(ticket_amount_mismatch: true) }
    scope :for_seller, ->(name) { where(seller_name: name) }
    scope :for_payment_method, ->(method) { where(payment_method: method) }
  end
end
