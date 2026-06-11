# frozen_string_literal: true

# Pundit policy for the payments-on-account surface. The "record" is an Order
# (no separate model is introduced).
class PaymentOnAccountPolicy < ApplicationPolicy
  def index?
    user.vendedor? || user.caja? || user.admin?
  end

  def show?
    index?
  end

  def deliver?
    (user.vendedor? || user.admin?) && record.on_account_order_type?
  end

  def collect?
    (user.caja? || user.admin?) && record.on_account_order_type? && !record.cancelled_status?
  end
end
