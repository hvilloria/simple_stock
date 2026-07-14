# frozen_string_literal: true

require "rails_helper"

RSpec.describe SaleNotePolicy do
  subject { described_class.new(user, note) }

  # The record is an Order (immediate + pending is the collectable state).
  let(:note) { build(:order, :pending, order_type: "immediate") }

  context "for a vendedor" do
    let(:user) { build(:user, role: "vendedor") }

    it "forbids index" do
      expect(subject.index?).to be false
    end

    it "forbids collect" do
      expect(subject.collect?).to be false
    end

    it "permits cancel on a pending note" do
      expect(subject.cancel?).to be true
    end
  end

  context "for caja" do
    let(:user) { build(:user, role: "caja") }

    it "permits index" do
      expect(subject.index?).to be true
    end

    it "permits collect on a pending immediate note" do
      expect(subject.collect?).to be true
    end

    it "permits cancel on a pending note" do
      expect(subject.cancel?).to be true
    end

    it "forbids collect on a confirmed note" do
      confirmed = build(:order, order_type: "immediate", status: "confirmed")
      expect(described_class.new(user, confirmed).collect?).to be false
    end

    it "forbids collect on a non-immediate note" do
      on_account = build(:order, :on_account)
      expect(described_class.new(user, on_account).collect?).to be false
    end

    it "forbids cancel on a confirmed note" do
      confirmed = build(:order, order_type: "immediate", status: "confirmed")
      expect(described_class.new(user, confirmed).cancel?).to be false
    end
  end

  context "for an admin" do
    let(:user) { build(:user, role: "admin") }

    it "permits index" do
      expect(subject.index?).to be true
    end

    it "permits collect on a pending immediate note" do
      expect(subject.collect?).to be true
    end

    it "permits cancel on a pending note" do
      expect(subject.cancel?).to be true
    end
  end
end
