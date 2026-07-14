# frozen_string_literal: true

require "rails_helper"

RSpec.describe DashboardPolicy do
  # The controller authorizes the :dashboard symbol, there is no record.
  subject { described_class.new(user, :dashboard) }

  context "for a vendedor" do
    let(:user) { build(:user, role: "vendedor") }

    it "permits index" do
      expect(subject.index?).to be true
    end
  end

  context "for caja" do
    let(:user) { build(:user, role: "caja") }

    it "permits index" do
      expect(subject.index?).to be true
    end
  end

  context "for an admin" do
    let(:user) { build(:user, role: "admin") }

    it "permits index" do
      expect(subject.index?).to be true
    end
  end
end
