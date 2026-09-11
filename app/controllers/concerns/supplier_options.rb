# frozen_string_literal: true

# The supplier list the cash live row offers, shared by every screen that
# renders that row. Plucked rather than loaded: the select only needs a label
# and an id.
module SupplierOptions
  extend ActiveSupport::Concern

  private

  def supplier_options
    Supplier.alphabetical.pluck(:name, :id)
  end
end
