# frozen_string_literal: true

require "rails_helper"

# Minimal system spec for the Stimulus-dependent behavior of the cash day
# screen: the live row that reappears empty and focused after a save, and the
# channel/subcategory selects the category shows or hides. Everything else
# (authorization, refusals, accounts) is covered by the request spec — see
# spec/requests/web/cash/movements_spec.rb.

RSpec.describe "Caja - fila viva del día", type: :system do
  include Warden::Test::Helpers

  let(:admin)         { create(:user, :admin) }
  let(:business_date) { Date.new(2026, 8, 3) }
  let(:day_path)      { "/web/cash/days/#{business_date}" }

  before do
    driven_by :selenium_chrome_headless, screen_size: [ 1400, 900 ]
    login_as(admin, scope: :user)
  end

  after { Warden.test_reset! }

  it "appends the saved row and leaves an empty live row focused" do
    visit day_path

    within("#drawer-live-row") do
      fill_in "description", with: "Venta mostrador"
      select "Venta", from: "category"
      select "Efectivo", from: "channel"
      fill_in "amount", with: "1500"
      click_button "Guardar"
    end

    expect(page).to have_css("#drawer-rows tr", count: 1)
    expect(page).to have_css("#drawer-rows tr", text: "Venta mostrador")
    expect(page).to have_css("#drawer-rows tr", text: "1.500,00")

    within("#drawer-live-row") do
      expect(page).to have_field("description", with: "")
      expect(page).to have_field("amount", with: "")
    end
    expect(page.evaluate_script("document.activeElement.id")).to eq("description")
  end

  it "appends an arca row to the arca zone and leaves its live row focused" do
    visit day_path

    within("#arca-live-row") do
      fill_in "description", with: "Cromosol"
      select "Proveedores", from: "category"
      select "Banco", from: "account"
      fill_in "amount", with: "153951"
      click_button "Guardar"
    end

    expect(page).to have_css("#arca-rows tr", count: 1)
    expect(page).to have_css("#arca-rows tr", text: "Cromosol")
    expect(page).to have_css("#arca-rows tr", text: "Banco")
    expect(page).to have_css("#drawer-rows tr", count: 0)

    expect(page.evaluate_script("document.activeElement.id")).to eq("arca-description")
  end

  it "leaves the caret in the drawer zone on load" do
    visit day_path

    expect(page.evaluate_script("document.activeElement.id")).to eq("description")
  end

  it "shows the channel only on a sale and the subcategory only on a fixed expense" do
    visit day_path

    within("#drawer-live-row") do
      expect(page).to have_select("channel", visible: :visible)
      expect(page).to have_select("subcategory", visible: :hidden, disabled: true)

      select "Proveedores", from: "category"
      expect(page).to have_select("channel", visible: :hidden, disabled: true)
      expect(page).to have_select("subcategory", visible: :hidden, disabled: true)

      select "Gastos fijos", from: "category"
      expect(page).to have_select("channel", visible: :hidden, disabled: true)
      expect(page).to have_select("subcategory", visible: :visible)

      select "Venta", from: "category"
      expect(page).to have_select("channel", visible: :visible)
      expect(page).to have_select("subcategory", visible: :hidden, disabled: true)
    end
  end

  it "formats the amount in Argentine format when the field loses focus" do
    visit day_path

    within("#drawer-live-row") do
      fill_in "amount", with: "324700"
      find_field("description").click

      expect(page).to have_field("amount", with: "324.700,00")
    end
  end

  it "refuses an amount that is not a number and writes no row" do
    visit day_path

    within("#drawer-live-row") do
      fill_in "description", with: "Monto ilegible"
      fill_in "amount", with: "abc"
      click_button "Guardar"
    end

    expect(page).to have_content("El monto no es un número.")
    expect(page).to have_css("#drawer-rows tr", count: 0)
    expect(CashMovement.count).to eq(0)
  end
end
