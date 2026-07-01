# frozen_string_literal: true

class OrderPolicy < ApplicationPolicy
  def index?
    true  # Everyone can view sales
  end

  def show?
    true  # Everyone can view sale detail
  end

  def create?
    user.vendedor? || user.admin?  # Only vendedores and admin
  end

  def new?
    create?
  end

  def cancel?
    user.admin?  # Only admin can cancel
  end

  def cancel_pending?
    record.pending_status? && (user.vendedor? || user.caja? || user.admin?)
  end

  def update?
    false  # Editing sales is not allowed
  end

  def destroy?
    false  # Deleting sales is not allowed
  end
end
