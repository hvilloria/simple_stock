# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#payment_method_label" do
    it "labels the five Payment methods" do
      expect(helper.payment_method_label("cash")).to eq("Efectivo")
      expect(helper.payment_method_label("bank_qr")).to eq("Banco QR")
      expect(helper.payment_method_label("bank_card")).to eq("Banco Tarjeta")
      expect(helper.payment_method_label("bank_transfer")).to eq("Banco Transferencia")
      expect(helper.payment_method_label("mercado_pago")).to eq("Mercado Pago")
    end

    it "still labels the ledger's 'bank' bucket" do
      expect(helper.payment_method_label("bank")).to eq("Banco")
    end

    it "humanizes unknown keys" do
      expect(helper.payment_method_label("foo")).to eq("Foo")
    end
  end

  describe "#payment_method_badge_class" do
    it "returns dark green for cash" do
      expect(helper.payment_method_badge_class("cash")).to eq("bg-green-900 text-white")
    end

    it "returns dark blue for every bank method and the ledger bucket" do
      %w[bank_qr bank_card bank_transfer bank].each do |method|
        expect(helper.payment_method_badge_class(method)).to eq("bg-blue-900 text-white")
      end
    end

    it "returns light blue for mercado_pago" do
      expect(helper.payment_method_badge_class("mercado_pago")).to eq("bg-sky-400 text-white")
    end

    it "falls back to slate for unknown keys" do
      expect(helper.payment_method_badge_class("foo")).to eq("bg-slate-100 text-slate-700")
    end
  end
end
