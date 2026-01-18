# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payment, type: :model do
  describe "associations" do
    it { should belong_to(:customer) }
  end

  describe "validations" do
    it { should validate_presence_of(:amount) }
    it { should validate_numericality_of(:amount).is_greater_than(0) }
    it { should validate_presence_of(:payment_method) }
    it { should validate_inclusion_of(:payment_method).in_array(Payment::PAYMENT_METHODS) }
    it { should validate_presence_of(:payment_date) }

    describe "customer_must_have_credit_account" do
      let(:customer_with_credit) { create(:customer, has_credit_account: true) }
      let(:customer_without_credit) { create(:customer, has_credit_account: false) }

      it "is valid when customer has credit account" do
        payment = build(:payment, customer: customer_with_credit)
        expect(payment).to be_valid
      end

      it "is invalid when customer does not have credit account" do
        payment = build(:payment, customer: customer_without_credit)
        expect(payment).not_to be_valid
        expect(payment.errors[:customer]).to include("must have credit account enabled")
      end
    end
  end

  describe "scopes" do
    let(:customer1) { create(:customer, has_credit_account: true) }
    let(:customer2) { create(:customer, has_credit_account: true) }
    let!(:payment1) { create(:payment, customer: customer1, payment_date: 3.days.ago) }
    let!(:payment2) { create(:payment, customer: customer2, payment_date: 1.day.ago) }
    let!(:payment3) { create(:payment, customer: customer1, payment_date: Date.today) }

    describe ".by_customer" do
      it "returns payments for specified customer" do
        expect(Payment.by_customer(customer1)).to contain_exactly(payment1, payment3)
      end
    end

    describe ".recent" do
      it "orders payments by payment_date desc, then created_at desc" do
        expect(Payment.recent).to eq([ payment3, payment2, payment1 ])
      end
    end
  end

  describe "factory" do
    it "has a valid default factory" do
      expect(create(:payment)).to be_valid
    end

    it "has a :transfer trait" do
      payment = create(:payment, :transfer)
      expect(payment.payment_method).to eq("transfer")
    end

    it "has a :check trait" do
      payment = create(:payment, :check)
      expect(payment.payment_method).to eq("check")
    end

    it "has a :card trait" do
      payment = create(:payment, :card)
      expect(payment.payment_method).to eq("card")
    end
  end
end
