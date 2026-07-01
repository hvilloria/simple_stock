# frozen_string_literal: true

class CustomerPolicy < ApplicationPolicy
  def index?
    true  # Todos ven clientes
  end

  def debtors?
    index?
  end

  def show?
    true
  end

  def create?
    user.admin?  || user.vendedor?
  end

  def new?
    create?
  end

  def update?
    user.admin?
  end

  def edit?
    update?
  end

  def destroy?
    false  # No se eliminan clientes
  end
end
