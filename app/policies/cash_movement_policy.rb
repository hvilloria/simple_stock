# frozen_string_literal: true

class CashMovementPolicy < ApplicationPolicy
  # Categories the drawer zone offers. partner and opening_balance are not the
  # cashier's to load, and internal_transfer is written as a pair by
  # Cash::RecordTransfer, never one leg at a time.
  DRAWER_CATEGORIES = %w[sale suppliers fixed_expense].freeze

  def index?
    user.caja? || user.admin?
  end

  def create?
    index?
  end

  def update?
    index? && !record.sealed?
  end

  def destroy?
    update?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.all if user.caja? || user.admin?

      scope.none
    end
  end
end
