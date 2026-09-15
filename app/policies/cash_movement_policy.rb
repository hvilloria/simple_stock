# frozen_string_literal: true

class CashMovementPolicy < ApplicationPolicy
  # Categories the drawer zone offers. partner and opening_balance are not the
  # cashier's to load, and internal_transfer is written as a pair by
  # Cash::RecordTransfer, never one leg at a time.
  DRAWER_CATEGORIES = %w[sale suppliers fixed_expense].freeze

  # Categories the arca zone offers. No sale: a sale is always a drawer-zone
  # row, whatever arca its channel reaches.
  ARCA_CATEGORIES = %w[suppliers fixed_expense].freeze

  # partner marks only what a partner keeps; what he then pays with that money
  # is recorded under its own real category.
  ADMIN_ARCA_CATEGORIES = %w[partner].freeze

  # The list depends on the user, so it is a method and not a constant. The
  # views and the controller both read it: neither keeps its own idea of what
  # a role may load.
  def categories_for(zone)
    return DRAWER_CATEGORIES unless zone == :arca

    user.admin? ? ARCA_CATEGORIES + ADMIN_ARCA_CATEGORIES : ARCA_CATEGORIES
  end

  # Not the wrong zone but not hers: a forged partner row is refused as a
  # permission failure, the way any other action she lacks is.
  def forbidden_category?(category)
    ADMIN_ARCA_CATEGORIES.include?(category) && !user.admin?
  end

  # The module is admin-only for now: the cashier's access is deferred, not
  # cancelled. Everything else here derives from this gate, so re-opening it to
  # her is this line and the Scope below.
  def index?
    user.admin?
  end

  def create?
    index?
  end

  # The balance report is the owner's reading of the whole operation, not the
  # cashier's: she works a day at a time and never sees accumulated balances.
  def balance_report?
    user.admin?
  end

  # The history is the drill-down of the balance report, so the two screens are
  # one permission: whoever may read the figures may read the rows behind them.
  def movement_history?
    balance_report?
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
      return scope.all if user.admin?

      scope.none
    end
  end
end
