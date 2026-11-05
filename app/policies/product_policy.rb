# frozen_string_literal: true

class ProductPolicy < ApplicationPolicy
  def index?
    true  # Everyone can view products
  end

  def show?
    true
  end

  def create?
    user.admin? || user.vendedor?
  end

  def new?
    create?
  end

  def update?
    return user.admin? if combo?

    user.admin? || user.vendedor?  # Admin and vendedor edit products; caja does not
  end

  def edit?
    update?
  end

  def destroy?
    user.admin?  # Only admin deletes products
  end

  def adjust_stock?
    user.admin?  # Only admin adjusts stock manually
  end

  def search?
    true  # Everyone can search products
  end

  def create_combo?
    user.admin?
  end

  def archive?
    user.admin? && combo?
  end

  private

  def combo?
    record.is_a?(Product) && record.combo?
  end
end
