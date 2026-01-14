require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:role) }
    
    it 'validates uniqueness of email' do
      create(:user, email: 'test@example.com')
      user = build(:user, email: 'test@example.com')
      expect(user).not_to be_valid
      expect(user.errors[:email]).to include('has already been taken')
    end
  end

  describe 'enums' do
    it 'defines role enum' do
      expect(User.roles).to eq({ "vendedor" => "vendedor", "caja" => "caja", "admin" => "admin" })
    end
  end

  describe 'role helpers' do
    it 'vendedor? returns true for vendedor role' do
      user = build(:user, role: "vendedor")
      expect(user.vendedor?).to be true
      expect(user.caja?).to be false
      expect(user.admin?).to be false
    end

    it 'caja? returns true for caja role' do
      user = build(:user, role: "caja")
      expect(user.caja?).to be true
      expect(user.vendedor?).to be false
      expect(user.admin?).to be false
    end

    it 'admin? returns true for admin role' do
      user = build(:user, role: "admin")
      expect(user.admin?).to be true
      expect(user.vendedor?).to be false
      expect(user.caja?).to be false
    end
  end
end
