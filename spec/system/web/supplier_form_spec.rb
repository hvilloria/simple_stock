# frozen_string_literal: true

require "rails_helper"

# Bank details and payment terms are optional cards, offered only to suppliers
# that bill Proveedor or Servicios. The server-side rule lives in the model and
# request specs.
RSpec.describe "Formulario de proveedor", type: :system do
  include Warden::Test::Helpers

  let(:admin) { create(:user, role: "admin") }

  before do
    driven_by :selenium_chrome_headless, screen_size: [ 1400, 900 ]
    login_as(admin, scope: :user)
  end

  describe "new supplier" do
    before { visit "/web/suppliers/new" }

    it "offers both optional cards as links, collapsed" do
      expect(page).to have_button("+ Agregar datos bancarios")
      expect(page).to have_button("+ Agregar condiciones de pago")
      expect(page).to have_no_field("Alias CBU")
      expect(page).to have_no_field("Plazo de Pago (días)")
    end

    it "reveals a card when its link is clicked" do
      click_button "+ Agregar condiciones de pago"

      expect(page).to have_field("Plazo de Pago (días)")
      expect(page).to have_no_button("+ Agregar condiciones de pago")
      expect(page).to have_button("+ Agregar datos bancarios")
      expect(page).to have_no_field("Alias CBU")
    end

    it "collapses a card and clears its fields with Quitar" do
      click_button "+ Agregar datos bancarios"
      fill_in "Alias CBU", with: "MI.ALIAS"
      within("fieldset", text: "Información Bancaria") { click_button "Quitar" }

      expect(page).to have_no_field("Alias CBU")
      expect(page).to have_button("+ Agregar datos bancarios")

      click_button "+ Agregar datos bancarios"
      expect(page).to have_field("Alias CBU", with: "")
    end

    it "hides links and cards when only taxes or social charges are billed" do
      click_button "+ Agregar condiciones de pago"

      uncheck "supplier_expense_types_supplier"
      check "supplier_expense_types_taxes"

      expect(page).to have_no_button("+ Agregar datos bancarios")
      expect(page).to have_no_button("+ Agregar condiciones de pago")
      expect(page).to have_no_field("Plazo de Pago (días)")

      check "supplier_expense_types_utilities"
      expect(page).to have_button("+ Agregar datos bancarios")
    end

    it "saves a tax authority billing only taxes" do
      fill_in "Nombre del Proveedor *", with: "AFIP"
      uncheck "supplier_expense_types_supplier"
      check "supplier_expense_types_taxes"
      click_button "Guardar Proveedor"

      expect(page).to have_text("Proveedor creado exitosamente")
      expect(Supplier.find_by!(name: "AFIP").expense_types).to eq([ "taxes" ])
    end

    it "does not submit a payment term typed before switching to taxes only" do
      fill_in "Nombre del Proveedor *", with: "AFIP"
      click_button "+ Agregar condiciones de pago"
      fill_in "Plazo de Pago (días)", with: "30"
      uncheck "supplier_expense_types_supplier"
      check "supplier_expense_types_taxes"
      click_button "Guardar Proveedor"

      expect(page).to have_text("Proveedor creado exitosamente")
      expect(Supplier.find_by!(name: "AFIP").payment_term_days).to be_nil
    end
  end

  describe "edit supplier" do
    it "starts with the bank card open when it holds values" do
      supplier = create(:supplier, bank_alias: "MI.ALIAS.CBU")
      visit "/web/suppliers/#{supplier.id}/edit"

      expect(page).to have_field("Alias CBU", with: "MI.ALIAS.CBU")
      expect(page).to have_no_button("+ Agregar datos bancarios")
      expect(page).to have_button("+ Agregar condiciones de pago")
      expect(page).to have_no_field("Plazo de Pago (días)")
    end

    it "starts with the terms card open when it holds values" do
      supplier = create(:supplier, payment_term_days: 30)
      visit "/web/suppliers/#{supplier.id}/edit"

      expect(page).to have_field("Plazo de Pago (días)", with: "30")
      expect(page).to have_no_button("+ Agregar condiciones de pago")
    end

    it "saves a supplier with terms that switches to taxes only, dropping the terms" do
      supplier = create(:supplier, payment_term_days: 30)
      visit "/web/suppliers/#{supplier.id}/edit"

      uncheck "supplier_expense_types_supplier"
      check "supplier_expense_types_taxes"
      click_button "Actualizar Proveedor"

      expect(page).to have_text("Proveedor actualizado exitosamente")
      supplier.reload
      expect(supplier.expense_types).to eq([ "taxes" ])
      expect(supplier.payment_term_days).to be_nil
    end

    it "keeps a card with submitted values open after a failed submit" do
      supplier = create(:supplier)
      visit "/web/suppliers/#{supplier.id}/edit"
      click_button "+ Agregar condiciones de pago"
      fill_in "Días para pago anticipado", with: "10"
      click_button "Actualizar Proveedor"

      expect(page).to have_text("impidió actualizar el proveedor")
      expect(page).to have_field("Días para pago anticipado", with: "10")
    end
  end
end
