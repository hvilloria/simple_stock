# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payment, type: :model do
  describe "associations" do
    it { should belong_to(:customer) }
    it { should have_many(:allocations).class_name("PaymentAllocation") }
    it { should have_many(:orders).through(:allocations) }
  end

  describe "validations" do
    it { should validate_presence_of(:amount) }
    it { should validate_numericality_of(:amount).is_greater_than(0) }
    it { should validate_presence_of(:payment_method) }
    it { should validate_inclusion_of(:payment_method).in_array(Payment::PAYMENT_METHODS) }
    it { should validate_presence_of(:payment_date) }

    context "for a customer without a credit account (retail / mostrador)" do
      let(:retail) { create(:customer, customer_type: "retail", has_credit_account: false) }

      it "is persisted successfully" do
        expect {
          create(:payment, customer: retail, amount: 100, payment_method: "cash", payment_date: Date.current)
        }.to change(Payment, :count).by(1)
      end
    end
  end

  describe "scopes" do
    let(:customer1) { create(:customer, customer_type: "workshop", has_credit_account: true) }
    let(:customer2) { create(:customer, customer_type: "workshop", has_credit_account: true) }
    let!(:payment1) { create(:payment, customer: customer1, payment_date: 3.days.ago) }
    let!(:payment2) { create(:payment, customer: customer2, payment_date: 1.day.ago) }
    let!(:payment3) { create(:payment, customer: customer1, payment_date: Date.current) }

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

    it "has a :bank_qr trait" do
      expect(create(:payment, :bank_qr).payment_method).to eq("bank_qr")
    end

    it "has a :bank_card trait" do
      expect(create(:payment, :bank_card).payment_method).to eq("bank_card")
    end

    it "has a :bank_transfer trait" do
      expect(create(:payment, :bank_transfer).payment_method).to eq("bank_transfer")
    end

    it "has a :mercado_pago trait" do
      expect(create(:payment, :mercado_pago).payment_method).to eq("mercado_pago")
    end
  end

  describe "payment method catalog" do
    it "defines exactly the five official methods" do
      expect(Payment::PAYMENT_METHODS).to eq(%w[cash bank_qr bank_card bank_transfer mercado_pago])
    end

    it "keeps 'cash' as the discount anchor key" do
      expect(Payment::PAYMENT_METHODS).to include("cash")
    end

    describe ".method_label" do
      it "returns the human label for a known key" do
        expect(Payment.method_label("bank_card")).to eq("Banco Tarjeta")
        expect(Payment.method_label("mercado_pago")).to eq("Mercado Pago")
      end

      it "humanizes an unknown key as a fallback" do
        expect(Payment.method_label("foo_bar")).to eq("Foo bar")
      end
    end

    describe ".method_options" do
      it "returns [label, key] pairs in catalog order for selects" do
        expect(Payment.method_options).to eq([
          [ "Efectivo", "cash" ],
          [ "Banco QR", "bank_qr" ],
          [ "Banco Tarjeta", "bank_card" ],
          [ "Banco Transferencia", "bank_transfer" ],
          [ "Mercado Pago", "mercado_pago" ]
        ])
      end
    end
  end
end
