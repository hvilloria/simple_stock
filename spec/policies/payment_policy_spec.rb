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

  describe "#show? and #update?" do
    it "lets caja and admin see and invoice a payment" do
      %i[caja admin].each do |role|
        policy = described_class.new(build(:user, role), payment)

        expect(policy.show?).to be(true)
        expect(policy.update?).to be(true)
      end
    end

    it "keeps the seller out" do
      policy = described_class.new(build(:user, :vendedor), payment)

      expect(policy.show?).to be(false)
      expect(policy.update?).to be(false)
    end
  end

  describe "#change_method?" do
    it "lets caja and admin change a payment's method" do
      %i[caja admin].each do |role|
        expect(described_class.new(build(:user, role), payment).change_method?).to be(true)
      end
    end

    it "keeps the seller out" do
      expect(described_class.new(build(:user, :vendedor), payment).change_method?).to be(false)
    end
  end
end
