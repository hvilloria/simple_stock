class Supplier < ApplicationRecord
  # Associations
  has_many :purchases, dependent: :restrict_with_error

  # Validations
  validates :name, presence: true
end
