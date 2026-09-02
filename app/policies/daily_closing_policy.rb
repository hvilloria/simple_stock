# frozen_string_literal: true

class DailyClosingPolicy < ApplicationPolicy
  def create?
    user.caja? || user.admin?
  end

  def new?
    create?
  end

  # R-10: a closing is never reopened, so there is no update and no destroy —
  # written out explicitly rather than left to ApplicationPolicy's default.
  def update?
    false
  end

  def destroy?
    false
  end
end
