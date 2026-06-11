# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentOnAccountPolicy do
  subject { described_class.new(user, order) }

  let(:order) { build(:order, :on_account) }

  context "vendedor" do
    let(:user) { build(:user, role: "vendedor") }

    it "permits index" do
      expect(subject.index?).to be true
    end

    it "permits show" do
      expect(subject.show?).to be true
    end

    it "permits deliver" do
      expect(subject.deliver?).to be true
    end

    it "forbids collect" do
      expect(subject.collect?).to be false
    end
  end

  context "caja" do
    let(:user) { build(:user, role: "caja") }

    it "permits index" do
      expect(subject.index?).to be true
    end

    it "permits show" do
      expect(subject.show?).to be true
    end

    it "permits collect on a non-cancelled on_account order" do
      expect(subject.collect?).to be true
    end

    it "forbids deliver" do
      expect(subject.deliver?).to be false
    end

    it "forbids collect on a cancelled order" do
      cancelled_order = build(:order, :on_account, :cancelled)
      expect(described_class.new(user, cancelled_order).collect?).to be false
    end
  end

  context "admin" do
    let(:user) { build(:user, role: "admin") }

    it "permits index" do
      expect(subject.index?).to be true
    end

    it "permits show" do
      expect(subject.show?).to be true
    end

    it "permits deliver" do
      expect(subject.deliver?).to be true
    end

    it "permits collect on a non-cancelled on_account order" do
      expect(subject.collect?).to be true
    end

    it "forbids collect on a cancelled order" do
      cancelled_order = build(:order, :on_account, :cancelled)
      expect(described_class.new(user, cancelled_order).collect?).to be false
    end
  end
end
