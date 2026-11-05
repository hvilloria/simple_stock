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
      expect(subject.create?).to be true
    end

    it 'permits update' do
      expect(subject.update?).to be true
    end

    it 'permits edit' do
      expect(subject.edit?).to be true
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

  context 'for a caja' do
    let(:user) { build(:user, role: "caja") }

    it 'forbids update' do
      expect(subject.update?).to be false
    end

    it 'forbids edit' do
      expect(subject.edit?).to be false
    end

    it 'forbids create' do
      expect(subject.create?).to be false
    end
  end

  describe "#view_cost?" do
    it "lets only an admin see product costs" do
      expect(described_class.new(build(:user, :admin), product).view_cost?).to be true
      expect(described_class.new(build(:user, role: "vendedor"), product).view_cost?).to be false
      expect(described_class.new(build(:user, role: "caja"), product).view_cost?).to be false
    end
  end

  describe "combos" do
    let(:combo) { build(:product, combo: true) }

    it "lets only an admin edit a combo" do
      expect(described_class.new(build(:user, :admin), combo).update?).to be true
      expect(described_class.new(build(:user, role: "vendedor"), combo).update?).to be false
      expect(described_class.new(build(:user, role: "vendedor"), combo).edit?).to be false
      expect(described_class.new(build(:user, role: "caja"), combo).update?).to be false
    end

    it "still lets a vendedor edit a regular product" do
      expect(described_class.new(build(:user, role: "vendedor"), build(:product)).update?).to be true
    end

    it "lets only an admin create a combo" do
      expect(described_class.new(build(:user, :admin), Product.new).create_combo?).to be true
      expect(described_class.new(build(:user, role: "vendedor"), Product.new).create_combo?).to be false
      expect(described_class.new(build(:user, role: "caja"), Product.new).create_combo?).to be false
    end

    it "lets only an admin archive, and only a combo" do
      expect(described_class.new(build(:user, :admin), combo).archive?).to be true
      expect(described_class.new(build(:user, :admin), build(:product)).archive?).to be false
      expect(described_class.new(build(:user, role: "vendedor"), combo).archive?).to be false
    end
  end
end
