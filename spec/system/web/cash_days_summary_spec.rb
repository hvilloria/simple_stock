# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Caja - resumen de días", type: :system do
  include Warden::Test::Helpers

  let(:admin)    { create(:user, :admin) }
  let(:past_day) { Date.current - 3 }

  before do
    driven_by :selenium_chrome_headless, screen_size: [ 1400, 900 ]
    login_as(admin, scope: :user)
    create(:cash_movement, business_date: past_day, amount: 45_000)
  end

  it "goes from today's day to the summary and into a past day" do
    visit "/web/cash/days/#{Date.current}"
    click_link "Resumen de días"

    expect(page).to have_css("h1", text: "Resumen de días")
    find("tbody tr", text: past_day.strftime("%d/%m/%Y")).find("td", text: "45.000").click

    expect(page).to have_current_path("/web/cash/days/#{past_day}")
    expect(page).to have_css("h1", text: past_day.strftime("%d/%m/%Y"))
  end
end
