# frozen_string_literal: true

class PaymentPolicy < ApplicationPolicy
  def index?
    user.caja? || user.admin?  # Caja y admin ven pagos
  end

  def show?
    user.caja? || user.admin?
  end

  def create?
    user.caja? || user.admin?  # Caja y admin registran pagos
  end

  def new?
    create?
  end

  def update?
    false  # No se editan pagos
  end

  def destroy?
    false  # No se eliminan pagos
  end
end
