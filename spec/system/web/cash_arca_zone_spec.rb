# frozen_string_literal: true

require "rails_helper"

# Minimal system spec for the parts of the arca zone a request spec cannot see:
# which of the two live rows takes the caret, the selects the category shows or
# hides in the arca row, the row a drawer-arca expense moves to (R-6), and the
# transfer form previewing two rows before it writes them. Everything else
# (authorization, refusals, signs, accounts) is covered by the request specs —
# see spec/requests/web/cash/movements_spec.rb and
# spec/requests/web/cash/transfers_spec.rb.

RSpec.describe "Caja - zona de arcas", type: :system do
  include Warden::Test::Helpers

  let(:cashier)       { create(:user, :caja) }
  let(:admin)         { create(:user, :admin) }
  let(:business_date) { Date.new(2026, 8, 3) }
  let(:day_path)      { "/web/cash/days/#{business_date}" }

  # A cash sale so the amount to wrap is a real number and R-6 has something to
  # move.
  let!(:cash_sale) { create(:cash_movement, business_date: business_date, amount: 299_700) }

  before do
    driven_by :selenium_chrome_headless, screen_size: [ 1400, 900 ]
  end

  after { Warden.test_reset! }

  context "as a cashier" do
    before { login_as(cashier, scope: :user) }

    it "leaves the caret in the drawer row only, with the arca row waiting" do
      visit day_path

      expect(page).to have_css("#description:focus")
      expect(page).to have_no_css("#arca-description:focus")
    end

    it "appends the arca row and hands the caret to a fresh empty arca row" do
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
      expect(page).to have_css("#arca-rows tr", text: "153.951,00")
      expect(page).to have_css("#drawer-rows tr", count: 1)

      expect(page).to have_css("#arca-description:focus")
      within("#arca-live-row") do
        expect(page).to have_field("description", with: "")
        expect(page).to have_field("amount", with: "")
      end
    end

    it "shows the subcategory only on a fixed expense and offers no partner category" do
      visit day_path

      within("#arca-live-row") do
        expect(page).to have_select("subcategory", visible: :hidden, disabled: true)

        select "Gastos fijos", from: "category"
        expect(page).to have_select("subcategory", visible: :visible)

        select "Proveedores", from: "category"
        expect(page).to have_select("subcategory", visible: :hidden, disabled: true)
      end

      expect(page).to have_css("#arca-category option", text: "Proveedores")
      expect(page).to have_no_css("#arca-category option", text: "Socio")
      expect(page).to have_no_css("#arca-direction", visible: :all)
    end

    # R-6: the zone a row lands in is the arca it names, not the form it was
    # typed into. Loading an expense against the drawer from the arca zone puts
    # it in the drawer table and takes it out of the amount to wrap.
    it "sends an expense loaded against the drawer to the drawer zone and moves the amount to wrap" do
      visit day_path

      expect(page).to have_css("#sales-by-channel", text: "299.700,00")

      within("#arca-live-row") do
        fill_in "description", with: "Bolsas"
        select "Proveedores", from: "category"
        select "Caja del día", from: "account"
        fill_in "amount", with: "25000"
        click_button "Guardar"
      end

      expect(page).to have_css("#drawer-rows tr", count: 2)
      expect(page).to have_css("#drawer-rows tr", text: "Bolsas")
      expect(page).to have_css("#arca-rows tr", count: 0)
      expect(page).to have_css("#sales-by-channel", text: "274.700,00")

      expect(page).to have_css("#arca-description:focus")
    end

    it "previews two rows and drops the preview when a field changes afterwards" do
      visit day_path

      open_transfer_panel

      within("#transfer-panel") do
        select "Mercado Pago", from: "from"
        select "Banco", from: "to"
        fill_in "amount", with: "50000"
        fill_in "description", with: "Retiro de Mercado Pago"
        click_button "Ver los movimientos"

        expect(page).to have_css("#transfer-preview tbody tr", count: 2)
        expect(page).to have_css("#transfer-preview tbody tr", text: "Mercado Pago")
        expect(page).to have_css("#transfer-preview tbody tr", text: "Banco")
        expect(page).to have_button("Confirmar")

        fill_in "description", with: "Otra cosa"
        expect(page).to have_no_css("#transfer-preview tbody tr")
        expect(page).to have_no_button("Confirmar")
      end
    end

    it "writes both legs into the arca zone with the transfer marker" do
      visit day_path

      open_transfer_panel

      within("#transfer-panel") do
        select "Mercado Pago", from: "from"
        select "Banco", from: "to"
        fill_in "amount", with: "50000"
        fill_in "description", with: "Retiro de Mercado Pago"
        click_button "Ver los movimientos"

        expect(page).to have_css("#transfer-preview tbody tr", count: 2)
        click_button "Confirmar"
      end

      expect(page).to have_css("#arca-rows tr", count: 2)
      expect(page).to have_css("#drawer-rows tr", count: 1)
      expect(page).to have_css("#sales-by-channel", text: "299.700,00")

      page.all("#arca-rows tr").each do |row|
        expect(row).to have_content("Entre arcas")
        expect(row).to have_content("50.000,00")
      end
    end

    it "puts each leg in the zone its arca belongs to" do
      visit day_path

      open_transfer_panel

      within("#transfer-panel") do
        select "Caja del día", from: "from"
        select "Banco", from: "to"
        fill_in "amount", with: "80000"
        fill_in "description", with: "Depósito del día"
        click_button "Ver los movimientos"

        expect(page).to have_css("#transfer-preview tbody tr", count: 2)
        click_button "Confirmar"
      end

      expect(page).to have_css("#drawer-rows tr", count: 2)
      expect(page).to have_css("#arca-rows tr", count: 1)
      expect(find("#drawer-rows tr", text: "Depósito del día")).to have_content("Entre arcas")
      expect(find("#arca-rows tr", text: "Depósito del día")).to have_content("Entre arcas")
      expect(page).to have_css("#sales-by-channel", text: "219.700,00")
    end
  end

  context "as an admin" do
    before { login_as(admin, scope: :user) }

    it "shows the direction only on a partner movement" do
      visit day_path

      within("#arca-live-row") do
        expect(page).to have_select("direction", visible: :hidden, disabled: true)

        select "Socio", from: "category"
        expect(page).to have_select("direction", visible: :visible)
        expect(page).to have_select("subcategory", visible: :hidden, disabled: true)

        select "Proveedores", from: "category"
        expect(page).to have_select("direction", visible: :hidden, disabled: true)
      end
    end

    it "records a partner withdrawal as an outflow of the arca it names" do
      visit day_path

      within("#arca-live-row") do
        fill_in "description", with: "Retiro del socio"
        select "Socio", from: "category"
        select "Caja grande", from: "account"
        select "Retiro", from: "direction"
        fill_in "amount", with: "100000"
        click_button "Guardar"
      end

      expect(page).to have_css("#arca-rows tr", count: 1)
      row = find("#arca-rows tr", text: "Retiro del socio")
      expect(row).to have_content("Caja grande")
      expect(row).to have_content("100.000,00")
      expect(CashMovement.find_by(description: "Retiro del socio").amount).to eq(-100_000)
    end
  end

  def open_transfer_panel
    click_button "Movimiento entre arcas"
    expect(page).to have_select("from", visible: :visible)
  end
end
