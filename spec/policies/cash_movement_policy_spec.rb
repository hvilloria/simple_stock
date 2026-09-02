# frozen_string_literal: true

require "rails_helper"

RSpec.describe CashMovementPolicy do
  let(:cashier) { build(:user, role: "caja") }
  let(:admin)   { build(:user, role: "admin") }
  let(:seller)  { build(:user, role: "vendedor") }

  describe "#index? and #create?" do
    it "permits the cashier and the admin, and forbids the seller" do
      expect(described_class.new(cashier, CashMovement).index?).to be(true)
      expect(described_class.new(admin, CashMovement).index?).to be(true)
      expect(described_class.new(seller, CashMovement).index?).to be(false)

      expect(described_class.new(cashier, CashMovement).create?).to be(true)
      expect(described_class.new(admin, CashMovement).create?).to be(true)
      expect(described_class.new(seller, CashMovement).create?).to be(false)
    end
  end

  describe "#update? and #destroy?" do
    let(:open_movement) { build(:cash_movement) }

    it "permits the cashier and the admin on an open movement, and forbids the seller" do
      expect(described_class.new(cashier, open_movement).update?).to be(true)
      expect(described_class.new(admin, open_movement).update?).to be(true)
      expect(described_class.new(seller, open_movement).update?).to be(false)

      expect(described_class.new(cashier, open_movement).destroy?).to be(true)
      expect(described_class.new(admin, open_movement).destroy?).to be(true)
      expect(described_class.new(seller, open_movement).destroy?).to be(false)
    end

    it "refuses a movement born from a collection" do
      automatic = create(:cash_movement, :from_collection)

      expect(described_class.new(cashier, automatic).update?).to be(false)
      expect(described_class.new(admin, automatic).update?).to be(false)
      expect(described_class.new(cashier, automatic).destroy?).to be(false)
      expect(described_class.new(admin, automatic).destroy?).to be(false)
    end

    it "refuses a movement sealed by a closing" do
      sealed = create(:cash_movement, :sealed)

      expect(described_class.new(cashier, sealed).update?).to be(false)
      expect(described_class.new(admin, sealed).update?).to be(false)
      expect(described_class.new(cashier, sealed).destroy?).to be(false)
      expect(described_class.new(admin, sealed).destroy?).to be(false)
    end

    it "refuses one leg of a transfer" do
      leg = create(:cash_movement, :transfer_leg)

      expect(described_class.new(cashier, leg).update?).to be(false)
      expect(described_class.new(admin, leg).update?).to be(false)
      expect(described_class.new(cashier, leg).destroy?).to be(false)
      expect(described_class.new(admin, leg).destroy?).to be(false)
    end
  end

  describe "Scope" do
    it "gives the cashier and the admin every movement" do
      movement = create(:cash_movement)

      expect(described_class::Scope.new(cashier, CashMovement).resolve).to include(movement)
      expect(described_class::Scope.new(admin, CashMovement).resolve).to include(movement)
    end

    it "gives the seller nothing" do
      create(:cash_movement)

      expect(described_class::Scope.new(seller, CashMovement).resolve).to be_empty
    end
  end
end
