# frozen_string_literal: true

class PurchasePolicy < ApplicationPolicy
  def index?
    user.admin?  # Solo admin ve compras
  end

  def show?
    user.admin?
  end

  def create?
    user.admin?  # Solo admin crea compras
  end

  def new?
    create?
  end

  def update?
    false  # No se editan compras
  end

  def destroy?
    false  # No se eliminan compras
  end
end

