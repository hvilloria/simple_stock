# frozen_string_literal: true

require "rails_helper"

RSpec.describe CashMovementPolicy do
  let(:cashier) { build(:user, role: "caja") }
  let(:admin)   { build(:user, role: "admin") }
  let(:seller)  { build(:user, role: "vendedor") }

  describe "#categories_for" do
    it "offers partner in the arca zone to the admin alone" do
      expect(described_class.new(admin, CashMovement).categories_for(:arca)).to include("partner")
      expect(described_class.new(cashier, CashMovement).categories_for(:arca)).not_to include("partner")
    end

    it "keeps the rest of the arca list the same for both" do
      expect(described_class.new(admin, CashMovement).categories_for(:arca)).to include("suppliers", "fixed_expense")
      expect(described_class.new(cashier, CashMovement).categories_for(:arca)).to contain_exactly("suppliers", "fixed_expense")
    end

    it "keeps partner out of the drawer zone for everyone" do
      expect(described_class.new(admin, CashMovement).categories_for(:drawer)).not_to include("partner")
      expect(described_class.new(cashier, CashMovement).categories_for(:drawer)).not_to include("partner")
    end
  end

  describe "#forbidden_category?" do
    it "reads partner from the cashier as a permission failure, not a wrong zone" do
      expect(described_class.new(cashier, CashMovement).forbidden_category?("partner")).to be(true)
      expect(described_class.new(admin, CashMovement).forbidden_category?("partner")).to be(false)
    end

    it "leaves the categories both roles share alone" do
      expect(described_class.new(cashier, CashMovement).forbidden_category?("suppliers")).to be(false)
      expect(described_class.new(cashier, CashMovement).forbidden_category?("internal_transfer")).to be(false)
    end
  end

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

  describe "#balance_report?" do
    it "is the admin's alone: the cashier never sees accumulated balances" do
      expect(described_class.new(admin, CashMovement).balance_report?).to be(true)
      expect(described_class.new(cashier, CashMovement).balance_report?).to be(false)
      expect(described_class.new(seller, CashMovement).balance_report?).to be(false)
    end
  end

  describe "#movement_history?" do
    it "is the admin's alone: the history is the report's drill-down" do
      expect(described_class.new(admin, CashMovement).movement_history?).to be(true)
      expect(described_class.new(cashier, CashMovement).movement_history?).to be(false)
      expect(described_class.new(seller, CashMovement).movement_history?).to be(false)
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
