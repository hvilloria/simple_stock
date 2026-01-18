require 'rails_helper'

RSpec.describe PaymentPolicy do
  subject { described_class.new(user, payment) }

  let(:payment) { build(:payment) }

  context 'for a vendedor' do
    let(:user) { build(:user, role: "vendedor") }

    it 'forbids index' do
      expect(subject.index?).to be false
    end

    it 'forbids create' do
      expect(subject.create?).to be false
    end
  end

  context 'for caja' do
    let(:user) { build(:user, role: "caja") }

    it 'permits index' do
      expect(subject.index?).to be true
    end

    it 'permits show' do
      expect(subject.show?).to be true
    end

    it 'permits create' do
      expect(subject.create?).to be true
    end
  end

  context 'for an admin' do
    let(:user) { build(:user, role: "admin") }

    it 'permits index' do
      expect(subject.index?).to be true
    end

    it 'permits create' do
      expect(subject.create?).to be true
    end
  end
end
