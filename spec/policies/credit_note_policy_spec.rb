# frozen_string_literal: true

require "rails_helper"

RSpec.describe CreditNotePolicy do
  subject { described_class.new(user, credit_note) }

  let(:credit_note) { build(:credit_note) }

  # Every action except destroy is `user.present?`.
  shared_examples "an authenticated credit-note user" do
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

    it "permits update" do
      expect(subject.update?).to be true
    end

    it "permits edit" do
      expect(subject.edit?).to be true
    end
  end

  context "for a vendedor" do
    let(:user) { build(:user, role: "vendedor") }

    it_behaves_like "an authenticated credit-note user"

    it "forbids destroy" do
      expect(subject.destroy?).to be false
    end
  end

  context "for caja" do
    let(:user) { build(:user, role: "caja") }

    it_behaves_like "an authenticated credit-note user"

    it "forbids destroy" do
      expect(subject.destroy?).to be false
    end
  end

  context "for an admin" do
    let(:user) { build(:user, role: "admin") }

    it_behaves_like "an authenticated credit-note user"

    it "permits destroy" do
      expect(subject.destroy?).to be true
    end
  end
end
