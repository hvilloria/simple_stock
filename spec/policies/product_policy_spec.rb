require 'rails_helper'

RSpec.describe ProductPolicy do
  subject { described_class.new(user, product) }

  let(:product) { build(:product) }

  context 'for a vendedor' do
    let(:user) { build(:user, role: "vendedor") }

    it 'permits index' do
      expect(subject.index?).to be true
    end

    it 'permits show' do
      expect(subject.show?).to be true
    end

    it 'forbids create' do
      expect(subject.create?).to be false
    end

    it 'forbids update' do
      expect(subject.update?).to be false
    end

    it 'forbids destroy' do
      expect(subject.destroy?).to be false
    end

    it 'forbids adjust_stock' do
      expect(subject.adjust_stock?).to be false
    end

    it 'permits search' do
      expect(subject.search?).to be true
    end
  end

  context 'for an admin' do
    let(:user) { build(:user, role: "admin") }

    it 'permits index' do
      expect(subject.index?).to be true
    end

    it 'permits show' do
      expect(subject.show?).to be true
    end

    it 'permits create' do
      expect(subject.create?).to be true
    end

    it 'permits update' do
      expect(subject.update?).to be true
    end

    it 'permits destroy' do
      expect(subject.destroy?).to be true
    end

    it 'permits adjust_stock' do
      expect(subject.adjust_stock?).to be true
    end
  end
end
