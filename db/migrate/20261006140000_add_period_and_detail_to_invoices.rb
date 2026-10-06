# frozen_string_literal: true

class AddPeriodAndDetailToInvoices < ActiveRecord::Migration[7.2]
  def change
    add_column :invoices, :period, :date
    add_column :invoices, :detail, :string
  end
end
