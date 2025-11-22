# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payments::RegisterPayment do
  let(:customer_with_credit) { create(:customer, has_credit_account: true) }
  let(:customer_without_credit) { create(:customer, has_credit_account: false) }

  describe ".call" do
    context "with valid params" do
      it "creates payment successfully" do
        result = described_class.call(
          customer: customer_with_credit,
          amount: 5000,
          payment_method: "cash"
        )

        expect(result.success?).to be true
        expect(result.record).to be_a(Payment)
        expect(result.record.amount).to eq(5000)
      end

      it "reduces customer balance" do
        # Crear venta a crédito
        create(:order,
               customer: customer_with_credit,
               order_type: "credit",
               status: "confirmed",
               total_amount: 10000)

        expect(customer_with_credit.current_balance).to eq(10000)

        described_class.call(
          customer: customer_with_credit,
          amount: 3000,
          payment_method: "cash"
        )

        expect(customer_with_credit.reload.current_balance).to eq(7000)
      end

      it "accepts different payment methods" do
        %w[cash transfer check card].each do |method|
          result = described_class.call(
            customer: customer_with_credit,
            amount: 1000,
            payment_method: method
          )

          expect(result.success?).to be true
          expect(result.record.payment_method).to eq(method)
        end
      end

      it "accepts custom payment date" do
        custom_date = 3.days.ago.to_date

        result = described_class.call(
          customer: customer_with_credit,
          amount: 1000,
          payment_method: "cash",
          payment_date: custom_date
        )

        expect(result.record.payment_date).to eq(custom_date)
      end

      it "uses today as default payment date" do
        result = described_class.call(
          customer: customer_with_credit,
          amount: 1000,
          payment_method: "cash"
        )

        expect(result.record.payment_date).to eq(Date.today)
      end

      it "accepts notes" do
        result = described_class.call(
          customer: customer_with_credit,
          amount: 1000,
          payment_method: "transfer",
          notes: "Transferencia #123456"
        )

        expect(result.record.notes).to eq("Transferencia #123456")
      end

      it "allows payment larger than current balance" do
        # Create credit order
        create(:order,
               customer: customer_with_credit,
               order_type: "credit",
               status: "confirmed",
               total_amount: 5000)

        # Pay more than balance
        result = described_class.call(
          customer: customer_with_credit,
          amount: 7000,
          payment_method: "cash"
        )

        expect(result.success?).to be true
        expect(customer_with_credit.reload.current_balance).to eq(-2000)
      end
    end

    context "with invalid params" do
      it "fails for customer without credit account" do
        result = described_class.call(
          customer: customer_without_credit,
          amount: 1000,
          payment_method: "cash"
        )

        expect(result.success?).to be false
        expect(result.errors).to include(/does not have credit account/)
      end

      it "fails with zero amount" do
        result = described_class.call(
          customer: customer_with_credit,
          amount: 0,
          payment_method: "cash"
        )

        expect(result.success?).to be false
        expect(result.errors).to include(/greater than zero/)
      end

      it "fails with negative amount" do
        result = described_class.call(
          customer: customer_with_credit,
          amount: -1000,
          payment_method: "cash"
        )

        expect(result.success?).to be false
        expect(result.errors).to include(/greater than zero/)
      end

      it "fails with invalid payment method" do
        result = described_class.call(
          customer: customer_with_credit,
          amount: 1000,
          payment_method: "bitcoin"
        )

        expect(result.success?).to be false
        expect(result.errors).to include(/Invalid payment method/)
      end

      it "fails without customer" do
        result = described_class.call(
          customer: nil,
          amount: 1000,
          payment_method: "cash"
        )

        expect(result.success?).to be false
        expect(result.errors).to include(/Customer is required/)
      end
    end

    context "when transaction fails" do
      it "does not create payment" do
        allow_any_instance_of(Payment).to receive(:save!).and_raise(StandardError, "DB error")

        expect do
          described_class.call(
            customer: customer_with_credit,
            amount: 1000,
            payment_method: "cash"
          )
        end.not_to change(Payment, :count)
      end

      it "returns error result" do
        allow_any_instance_of(Payment).to receive(:save!).and_raise(StandardError, "DB error")

        result = described_class.call(
          customer: customer_with_credit,
          amount: 1000,
          payment_method: "cash"
        )

        expect(result.success?).to be false
        expect(result.errors).not_to be_empty
      end
    end
  end
end
