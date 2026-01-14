# frozen_string_literal: true

class OrderPolicy < ApplicationPolicy
  def index?
    true  # Todos pueden ver ventas
  end

  def show?
    true  # Todos pueden ver detalle de venta
  end

  def create?
    user.vendedor? || user.admin?  # Solo vendedores y admin
  end

  def new?
    create?
  end

  def cancel?
    user.admin?  # Solo admin puede cancelar
  end

  def update?
    false  # No se permite editar ventas
  end

  def destroy?
    false  # No se permite eliminar ventas
  end
end

