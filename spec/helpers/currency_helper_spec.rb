# frozen_string_literal: true

require "rails_helper"

RSpec.describe CurrencyHelper, type: :helper do
  describe "#format_contact_phone" do
    it "formats 10 digits as '11 5555-1234'" do
      expect(helper.format_contact_phone("1155551234")).to eq("11 5555-1234")
    end

    it "normalizes already-spaced input to the chosen format" do
      expect(helper.format_contact_phone("11 5555 1234")).to eq("11 5555-1234")
    end

    it "formats 8 digits as '5555-1234'" do
      expect(helper.format_contact_phone("55551234")).to eq("5555-1234")
    end

    it "returns empty string for blank input" do
      expect(helper.format_contact_phone("")).to eq("")
    end

    it "returns empty string for nil input" do
      expect(helper.format_contact_phone(nil)).to eq("")
    end

    it "returns the digits unbroken for an unusual length" do
      expect(helper.format_contact_phone("541155551234")).to eq("541155551234")
    end
  end
end
