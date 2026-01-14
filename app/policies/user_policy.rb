# frozen_string_literal: true

class UserPolicy < ApplicationPolicy
  def index?
    user.admin?  # Solo admin ve usuarios
  end

  def show?
    user.admin?
  end

  def create?
    user.admin?  # Solo admin crea usuarios
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
    user.admin? && record != user  # Admin puede eliminar, pero no a sí mismo
  end
end

