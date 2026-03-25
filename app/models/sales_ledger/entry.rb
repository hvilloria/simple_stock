# frozen_string_literal: true

module SalesLedger
  class Entry < ApplicationRecord
    self.table_name = "sales_ledger_entries"

    belongs_to :sales_import, class_name: "SalesLedger::SalesImport"
    belongs_to :product

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

    scope :for_date_range, ->(from, to) { where(sale_date: from..to) }
    scope :for_product, ->(product_id) { where(product_id: product_id) }
  end
end
