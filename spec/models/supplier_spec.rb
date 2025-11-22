require "rails_helper"

RSpec.describe Supplier, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:purchases).dependent(:restrict_with_error) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
  end
end
