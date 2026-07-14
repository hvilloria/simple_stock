# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvoicePolicy do
  subject { described_class.new(user, invoice) }

  # Simple mode + pending: the state the UI actually operates on.
  let(:invoice) { build(:invoice, :simple_mode) }

  # Everything except #view_pending? is admin-only.
  shared_examples "a non-admin invoice user" do
    it "forbids index" do
      expect(subject.index?).to be false
    end

    it "forbids show" do
      expect(subject.show?).to be false
    end

    it "forbids create" do
      expect(subject.create?).to be false
    end

    it "forbids update" do
      expect(subject.update?).to be false
    end

    it "forbids mark_as_paid" do
      expect(subject.mark_as_paid?).to be false
    end

    it "forbids cancel" do
      expect(subject.cancel?).to be false
    end

    it "forbids mark_supplier_paid" do
      expect(subject.mark_supplier_paid?).to be false
    end

    it "permits view_pending" do
      expect(subject.view_pending?).to be true
    end
  end

  context "for a vendedor" do
    let(:user) { build(:user, role: "vendedor") }

    it_behaves_like "a non-admin invoice user"
  end

  context "for caja" do
    let(:user) { build(:user, role: "caja") }

    it_behaves_like "a non-admin invoice user"
  end

  context "for an admin" do
    let(:user) { build(:user, role: "admin") }

    it "permits index" do
      expect(subject.index?).to be true
    end

    it "permits show" do
      expect(subject.show?).to be true
    end

    it "permits create" do
      expect(subject.create?).to be true
    end

    it "permits new" do
      expect(subject.new?).to be true
    end

    it "permits view_pending" do
      expect(subject.view_pending?).to be true
    end

    it "permits mark_supplier_paid" do
      expect(subject.mark_supplier_paid?).to be true
    end

    it "permits update on a pending invoice" do
      expect(subject.update?).to be true
    end

    it "permits edit on a pending invoice" do
      expect(subject.edit?).to be true
    end

    it "permits mark_as_paid on a pending simple invoice" do
      expect(subject.mark_as_paid?).to be true
    end

    it "permits cancel on a pending invoice" do
      expect(subject.cancel?).to be true
    end

    it "forbids update on a paid invoice" do
      paid = build(:invoice, :paid)
      expect(described_class.new(user, paid).update?).to be false
    end

    it "forbids mark_as_paid on a paid invoice" do
      paid = build(:invoice, :paid)
      expect(described_class.new(user, paid).mark_as_paid?).to be false
    end

    it "forbids mark_as_paid on a full-mode invoice" do
      full = build(:invoice, :full_mode, status: "pending")
      expect(described_class.new(user, full).mark_as_paid?).to be false
    end

    it "forbids cancel on a cancelled invoice" do
      cancelled = build(:invoice, :simple_mode, status: "cancelled")
      expect(described_class.new(user, cancelled).cancel?).to be false
    end
  end
end
