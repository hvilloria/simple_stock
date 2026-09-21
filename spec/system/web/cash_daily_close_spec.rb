# frozen_string_literal: true

require "rails_helper"

# Minimal system spec for the parts of the closing flow a request spec cannot
# see: the modal rendered over the day, the note field the closing-form
# controller reveals only once the count differs, the live "A envolver" figure,
# and the day view re-rendered read-only after the close. Everything else
# (authorization, refusals, amount parsing) is covered by the request spec —
# see spec/requests/web/cash/closings_spec.rb.

RSpec.describe "Caja - cierre del día", type: :system do
  include Warden::Test::Helpers

  let(:admin)         { create(:user, :admin) }
  let(:business_date) { Date.new(2026, 8, 3) }
  let(:day_path)      { "/web/cash/days/#{business_date}" }

  # 311.700 in cash minus a 13.000 expense: the drawer is expected to hold
  # 298.700 and the modal has a real number to check against.
  let!(:cash_sale) { create(:cash_movement, business_date: business_date, amount: 311_700) }
  let!(:expense)   { create(:cash_movement, :store_expense, business_date: business_date) }

  def note_wrapper(visible:)
    find("[data-closing-form-target='note']", visible: visible)
  end

  def open_modal
    visit day_path
    click_link "Cerrar el día"
    expect(page).to have_field("counted_cash")
  end

  def clear_counted
    find_field("counted_cash").send_keys([ :control, "a" ], :backspace)
  end

  before do
    driven_by :selenium_chrome_headless, screen_size: [ 1400, 900 ]
    login_as(admin, scope: :user)
  end

  after { Warden.test_reset! }

  it "opens the modal over the day and shows the expected amount" do
    open_modal

    expect(page).to have_content("Cerrar el día 03/08/2026")
    expect(page).to have_content("Esperado en el cajón")
    expect(page).to have_css("section", text: "298.700,00")
    expect(page).to have_content("El día tiene 2 movimientos.")
    # The day itself is still on the page, behind the modal.
    expect(page).to have_css("#day-entries tr", count: 2)
    expect(page).to have_css("#day-entry-form", visible: :all)
  end

  it "reveals the note only while the count differs from the expectation" do
    open_modal

    expect(note_wrapper(visible: :hidden)).not_to be_visible

    fill_in "counted_cash", with: "298700"
    expect(page).to have_css("[data-closing-form-target='note']", visible: :hidden)

    fill_in "counted_cash", with: "290000"
    expect(page).to have_css("[data-closing-form-target='note']", visible: :visible)

    # An empty field differs from the expectation numerically but is not a
    # discrepancy, so clearing it has to hide the note again.
    clear_counted
    expect(page).to have_css("[data-closing-form-target='note']", visible: :hidden)
  end

  it "updates the amount to wrap as the count is typed" do
    open_modal

    wrap = "[data-closing-form-target='wrapAmount']"
    expect(page).to have_css(wrap, text: "298.700,00")

    fill_in "counted_cash", with: "290000"
    expect(page).to have_css(wrap, text: "290.000,00")

    clear_counted
    expect(page).to have_css(wrap, text: "298.700,00")
  end

  it "writes the discrepancy and the transfer leg onto the day when the count differs" do
    open_modal

    fill_in "counted_cash", with: "290000"
    fill_in "note", with: "Faltó vuelto de la mañana"
    click_button "Cerrar día"

    expect(page).to have_content("Día cerrado.")
    # The sale, the expense, the discrepancy, and the closing transfer folded
    # into one row.
    expect(page).to have_css("#day-entries tr", count: 4)
    expect(page).to have_css("#day-entries tr", text: "Faltó vuelto de la mañana")
    expect(page).to have_css("#day-entries tr", text: "8.700,00")

    transfer = find("#day-entries tr", text: "Cierre de caja del día")
    expect(transfer).to have_content("Caja del día → Caja grande")
    expect(transfer).to have_content("290.000,00")

    expect(page).to have_css("#sales-by-channel", text: "0,00")
  end

  it "leaves the day read-only after the close" do
    open_modal

    fill_in "counted_cash", with: "298700"
    click_button "Cerrar día"

    expect(page).to have_content("Día cerrado — solo lectura")
    expect(page).to have_no_field("description")
    expect(page).to have_no_button("Guardar")
    expect(page).to have_no_link("Editar")
    expect(page).to have_no_button("Eliminar")
    expect(page).to have_no_link("Cerrar el día")
  end
end
