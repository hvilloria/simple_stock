# frozen_string_literal: true

require "rails_helper"

# Minimal system spec for the part of compensation no request spec can see: the
# supplier select the channel shows, and — the half that matters — disables
# everywhere else, so a supplier never rides along on an ordinary sale. The
# money side is checked here only as the figure the screen shows: a compensation
# reaches no arca, so the amount to wrap must not move. Everything else
# (refusals, the balance report, the history filter) is covered by the request
# specs — see spec/requests/web/cash/movements_spec.rb.

RSpec.describe "Caja - compensación", type: :system do
  include Warden::Test::Helpers

  let(:admin)         { create(:user, :admin) }
  let(:business_date) { Date.new(2026, 8, 3) }
  let(:day_path)      { "/web/cash/days/#{business_date}" }

  let!(:supplier) { create(:supplier, name: "Cromosol") }

  # A cash sale so the amount to wrap is a real number and not zero.
  let!(:cash_sale) { create(:cash_movement, business_date: business_date, amount: 299_700) }

  before do
    driven_by :selenium_chrome_headless, screen_size: [ 1400, 900 ]
    login_as(admin, scope: :user)
  end

  after { Warden.test_reset! }

  it "shows the supplier only on a compensation sale and disables it everywhere else" do
    visit day_path

    within("#drawer-live-row") do
      expect(page).to have_select("supplier_id", visible: :hidden, disabled: true)

      select "Compensación", from: "channel"
      expect(page).to have_select("supplier_id", visible: :visible, disabled: false)

      select "Efectivo", from: "channel"
      expect(page).to have_select("supplier_id", visible: :hidden, disabled: true)

      select "Compensación", from: "channel"
      expect(page).to have_select("supplier_id", visible: :visible, disabled: false)

      # Not a sale at all: the channel goes, and the supplier with it.
      select "Proveedores", from: "category"
      expect(page).to have_select("channel", visible: :hidden, disabled: true)
      expect(page).to have_select("supplier_id", visible: :hidden, disabled: true)
    end
  end

  it "records the compensation with its supplier and leaves the amount to wrap where it was" do
    visit day_path

    amount_before = amount_to_wrap
    expect(amount_before).to eq("299.700,00")

    within("#drawer-live-row") do
      fill_in "description", with: "Compensación Cromosol"
      select "Venta", from: "category"
      select "Compensación", from: "channel"
      select "Cromosol", from: "supplier_id"
      fill_in "amount", with: "661188"
      click_button "Guardar"
    end

    expect(page).to have_css("#drawer-rows tr", count: 2)
    row = find("#drawer-rows tr", text: "Compensación Cromosol")
    expect(row).to have_content("Compensación")
    expect(row).to have_content("661.188,00")

    expect(page).to have_css("#sales-by-channel", text: "661.188,00")
    expect(amount_to_wrap).to eq(amount_before)

    movement = CashMovement.find_by(description: "Compensación Cromosol")
    expect(movement.supplier).to eq(supplier)
    expect(movement.account).to be_nil
  end

  it "saves an ordinary sale with no supplier when the channel moves away from compensation" do
    visit day_path

    within("#drawer-live-row") do
      fill_in "description", with: "Venta mostrador"
      select "Venta", from: "category"
      select "Compensación", from: "channel"
      select "Cromosol", from: "supplier_id"
      select "Efectivo", from: "channel"
      expect(page).to have_select("supplier_id", visible: :hidden, disabled: true)

      fill_in "amount", with: "1500"
      click_button "Guardar"
    end

    expect(page).to have_css("#drawer-rows tr", count: 2)

    movement = CashMovement.find_by(description: "Venta mostrador")
    expect(movement.supplier).to be_nil
    expect(movement.channel).to eq("cash")
    expect(amount_to_wrap).to eq("301.200,00")
  end

  # The figure lives in the footer of the sales panel, next to its own label.
  def amount_to_wrap
    find("#sales-by-channel")
      .find(:xpath, ".//span[normalize-space()='Monto a fajar']/following-sibling::span")
      .text
  end
end
