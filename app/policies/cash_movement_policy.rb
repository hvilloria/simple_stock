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

  # An automatic row is undone through Cash::ReversePayment, never edited here:
  # correcting it would make the two modules disagree about the same money.
  # A transfer leg cannot be corrected alone either: it was written as one half
  # of a pair, and editing only one leg would leave the arcas disagreeing about
  # the same money.
  def update?
    index? && !record.sealed? && !record.automatic? && !record.transfer?
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
