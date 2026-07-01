# frozen_string_literal: true

class PaymentPolicy < ApplicationPolicy
  def index?
    user.caja? || user.admin?  # Caja and admin view payments
  end

  def show?
    user.caja? || user.admin?
  end

  def create?
    user.caja? || user.admin?  # Caja and admin register payments
  end

  def new?
    create?
  end

  def update?
    false  # Payments are not edited
  end

  def destroy?
    false  # Payments are not deleted
  end
end
