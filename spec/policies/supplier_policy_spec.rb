require "rails_helper"

RSpec.describe SupplierPolicy do
  subject { described_class.new(user, supplier) }
  
  let(:supplier) { build(:supplier) }

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

    it "permits update" do
      expect(subject.update?).to be true
    end
    
    context "when supplier has no purchases" do
      before { allow(supplier).to receive_message_chain(:purchases, :none?).and_return(true) }
      
      it "permits destroy" do
        expect(subject.destroy?).to be true
      end
    end
    
    context "when supplier has purchases" do
      before { allow(supplier).to receive_message_chain(:purchases, :none?).and_return(false) }
      
      it "forbids destroy" do
        expect(subject.destroy?).to be false
      end
    end
  end

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
  end
end
