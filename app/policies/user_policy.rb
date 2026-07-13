# frozen_string_literal: true

class UserPolicy < ApplicationPolicy
  def index?
    user.admin?  # Only admin views users
  end

  def show?
    user.admin?
  end

  def create?
    user.admin?  # Only admin creates users
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
    user.admin? && record != user  # Admin can delete, but not themselves
  end
end
