# frozen_string_literal: true

class InvoicePolicy < ApplicationPolicy
  def index?
    user.admin?
  end

  def show?
    user.admin?
  end

  def create?
    user.admin?
  end

  def new?
    create?
  end

  def update?
    user.admin? && record.pending_status?
  end

  def edit?
    update?
  end

  def mark_as_paid?
    user.admin? && record.simple_mode? && record.pending_status?
  end

  def cancel?
    user.admin? && record.pending_status?
  end

  def view_pending?
    user.present?
  end

  def mark_supplier_paid?
    user.admin?
  end
end
