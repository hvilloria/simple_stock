# frozen_string_literal: true

class CustomerPolicy < ApplicationPolicy
  def index?
    true  # Todos ven clientes
  end

  def show?
    true
  end

  def create?
    user.admin?  # Solo admin crea clientes
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
