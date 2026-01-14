class User < ApplicationRecord
  # Devise modules (solo authenticatable y trackable)
  devise :database_authenticatable, :trackable

  # Enums
  enum role: {
    vendedor: "vendedor",
    caja: "caja",
    admin: "admin"
  }, _suffix: true

  # Validations
  validates :email, presence: true, uniqueness: true
  validates :name, presence: true
  validates :role, presence: true, inclusion: { in: roles.keys }

  # Role helpers
  def vendedor?
    role == "vendedor"
  end

  def caja?
    role == "caja"
  end

  def admin?
    role == "admin"
  end
end
