# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserPolicy do
  subject { described_class.new(user, record) }

  let(:record) { build(:user, role: "vendedor") }

  context "for a vendedor" do
    let(:user) { build(:user, role: "vendedor") }

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

    it "forbids destroy" do
      expect(subject.destroy?).to be false
    end
  end

  context "for caja" do
    let(:user) { build(:user, role: "caja") }

    it "forbids index" do
      expect(subject.index?).to be false
    end

    it "forbids create" do
      expect(subject.create?).to be false
    end

    it "forbids destroy" do
      expect(subject.destroy?).to be false
    end
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

    it "permits update" do
      expect(subject.update?).to be true
    end

    it "permits edit" do
      expect(subject.edit?).to be true
    end

    it "permits destroy on another user" do
      expect(subject.destroy?).to be true
    end

    it "forbids destroy on themselves" do
      expect(described_class.new(user, user).destroy?).to be false
    end
  end
end
