# frozen_string_literal: true

module SalesLedger
  class SalesImport < ApplicationRecord
    STATUSES = %w[pending processing completed failed].freeze

    has_many :entries,
             class_name: "SalesLedger::Entry",
             foreign_key: :sales_import_id,
             dependent: :destroy

    validates :source_filename, presence: true
    validates :status, inclusion: { in: STATUSES }

    scope :recent, -> { order(created_at: :desc) }
  end
end
