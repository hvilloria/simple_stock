# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Application timezone" do
  it "runs in Buenos Aires time" do
    expect(Time.zone.name).to eq("America/Argentina/Buenos_Aires")
  end

  it "resolves Date.current to the local business day near midnight UTC" do
    # 2026-08-04 01:30 UTC is still 2026-08-03 22:30 in Buenos Aires.
    travel_to(Time.utc(2026, 8, 4, 1, 30)) do
      expect(Date.current).to eq(Date.new(2026, 8, 3))
    end
  end
end
