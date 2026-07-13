# frozen_string_literal: true

class DashboardPolicy < ApplicationPolicy
  def index?
    true  # All authenticated users can view the dashboard
  end
end
