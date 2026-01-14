# frozen_string_literal: true

class ProductPolicy < ApplicationPolicy
  def index?
    true  # Todos pueden ver productos
  end

  def show?
    true
  end

  def create?
    user.admin?  # Solo admin crea productos
  end

  def new?
    create?
  end

  def update?
    user.admin?  # Solo admin edita productos
  end

  def edit?
    update?
  end

  def destroy?
    user.admin?  # Solo admin elimina productos
  end

  def adjust_stock?
    user.admin?  # Solo admin ajusta stock manualmente
  end

  def search?
    true  # Todos pueden buscar productos
  end
end

