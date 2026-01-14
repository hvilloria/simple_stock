# frozen_string_literal: true

class DashboardPolicy < ApplicationPolicy
  def index?
    true  # Todos los usuarios autenticados pueden ver el dashboard
  end
end

