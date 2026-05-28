# frozen_string_literal: true

# Pundit policy for the cashier sale-notes surface. The "record" is an Order
# (we don't introduce a separate model).
class SaleNotePolicy < ApplicationPolicy
  def index?
    user.caja? || user.admin?
  end

  def collect?
    (user.caja? || user.admin?) && record.immediate_order_type? && record.pending_status?
  end

  def cancel?
    record.pending_status? && (user.vendedor? || user.caja? || user.admin?)
  end
end
