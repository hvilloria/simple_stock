require "rails_helper"

RSpec.describe StockMovement, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:product) }
    it { is_expected.to belong_to(:stock_location) }
    it { is_expected.to belong_to(:reference).optional }
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:movement_type).with_values(purchase: "purchase", sale: "sale", adjustment: "adjustment").backed_by_column_of_type(:string).with_suffix }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:quantity) }
    it { is_expected.to validate_presence_of(:movement_type) }
    it { is_expected.to validate_presence_of(:stock_location) }

    context "when reference_id is present" do
      it "validates reference_type is Order or Invoice" do
        order = create(:order)
        movement = build(:stock_movement, reference_id: order.id, reference_type: "Order")
        expect(movement).to be_valid

        purchase = create(:invoice)
        movement = build(:stock_movement, reference_id: purchase.id, reference_type: "Invoice")
        expect(movement).to be_valid

        movement = build(:stock_movement, reference_id: 1, reference_type: "InvalidType")
        expect(movement).not_to be_valid
        expect(movement.errors[:reference_type]).to be_present
      end
    end

    context "when reference_id is nil" do
      it "allows any reference_type" do
        movement = build(:stock_movement, reference: nil)
        expect(movement).to be_valid
      end
    end
  end

  describe "polymorphic association" do
    it "can associate with an Order" do
      order = create(:order)
      movement = create(:stock_movement, reference: order)

      expect(movement.reference).to eq(order)
      expect(movement.reference_type).to eq("Order")
      expect(movement.reference_id).to eq(order.id)
    end

    it "can associate with an Invoice" do
      purchase = create(:invoice)
      movement = create(:stock_movement, reference: purchase)

      expect(movement.reference).to eq(purchase)
      expect(movement.reference_type).to eq("Invoice")
      expect(movement.reference_id).to eq(purchase.id)
    end

    it "can have nil reference" do
      movement = create(:stock_movement, reference: nil)

      expect(movement.reference).to be_nil
      expect(movement.reference_type).to be_nil
      expect(movement.reference_id).to be_nil
    end
  end

  describe "#inbound?" do
    it "returns true for positive quantities" do
      movement = build(:stock_movement, quantity: 10)
      expect(movement.inbound?).to be true
    end

    it "returns false for negative quantities" do
      movement = build(:stock_movement, quantity: -5)
      expect(movement.inbound?).to be false
    end
  end

  describe "#outbound?" do
    it "returns true for negative quantities" do
      movement = build(:stock_movement, quantity: -5)
      expect(movement.outbound?).to be true
    end

    it "returns false for positive quantities" do
      movement = build(:stock_movement, quantity: 10)
      expect(movement.outbound?).to be false
    end
  end
end
