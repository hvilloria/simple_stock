# frozen_string_literal: true

require "rails_helper"

# System tests for the JS modal in /web/invoices/pending.
#
# Prerequisites:
#   - Google Chrome installed (uses :selenium_chrome_headless driver)
#
# What is tested here:
#   1. Invoice list in modal shows individual numbers, not a generic count
#   2. Credit notes render as checkboxes (not free-text number inputs)
#   3. Checking a NC recalculates "Neto a transferir" correctly
#   4. Unchecking restores the previous net total
#   5. When invoice is fully covered, remaining unchecked NCs get disabled
#   6. Unchecking re-enables the disabled NCs
#   7. Partial application badge appears when NC balance > remaining invoice amount
#   8. No credit notes section shown when supplier has no active NCs

RSpec.describe "Pending modal — credit note checkbox behavior", type: :system do
  include Warden::Test::Helpers

  let(:admin)    { create(:user, role: "admin") }
  let(:supplier) { create(:supplier, name: "Proveedor Modal Test") }

  before do
    driven_by :selenium_chrome_headless, screen_size: [ 1400, 900 ]
    login_as(admin, scope: :user)
  end

  after { Warden.test_reset! }

  # ── Helpers ────────────────────────────────────────────────────────

  def create_invoice(amount:, number:)
    create(:invoice, :simple_mode,
           supplier: supplier,
           amount: amount,
           currency: "ARS",
           invoice_number: number,
           due_date: Date.current.beginning_of_week(:monday),
           purchase_date: 30.days.ago.to_date)
  end

  def create_nc(amount:, number:)
    create(:credit_note,
           supplier: supplier,
           credit_note_number: number,
           amount: amount,
           currency: "ARS",
           issue_date: Date.current)
  end

  # Opens the payment modal for the test supplier.
  # Uses text-based navigation to find the supplier row, then clicks its Pagar button.
  # Waits for the supplier name to appear first — if it never does, the data-visibility
  # issue is diagnosed here rather than with a cryptic "button not found" message.
  def open_payment_modal
    visit pending_web_invoices_path
    page.driver.browser.manage.window.resize_to(1400, 900)
    expect(page).to have_text(supplier.name)
    find("tr.bg-slate-50", text: supplier.name).find("button").click
    expect(page).to have_css("#paymentModal", visible: true)
  end

  # Re-queries checkboxes on each call so state is always fresh after JS runs.
  def cn_checkboxes
    all("#creditNotesList input[type='checkbox']")
  end

  # ── 1. Invoice list ──────────────────────────────────────────────────

  describe "invoice list in modal" do
    before do
      create_invoice(amount: 340_000, number: "FAC-2025-001")
      create_invoice(amount: 490_000, number: "FAC-2025-002")
      open_payment_modal
    end

    it "displays each invoice number individually" do
      within "#modalInvoicesList" do
        expect(page).to have_text("FAC-2025-001")
        expect(page).to have_text("FAC-2025-002")
      end
    end

    it "does not show a generic count message" do
      within "#supplierInfo" do
        expect(page).not_to have_text("facturas — Total")
      end
    end
  end

  # ── 2. Checkboxes render ──────────────────────────────────────────────

  describe "credit note cards render as checkboxes" do
    before do
      create_invoice(amount: 100_000, number: "FAC-CB")
      create_nc(amount: 50_000, number: "NC-TEST-01")
      create_nc(amount: 60_000, number: "NC-TEST-02")
      open_payment_modal
    end

    it "renders one checkbox per credit note" do
      expect(cn_checkboxes.count).to eq(2)
    end

    it "all checkboxes start unchecked" do
      cn_checkboxes.each { |cb| expect(cb).not_to be_checked }
    end

    it "shows the NC number in each card" do
      within "#creditNotesList" do
        expect(page).to have_text("NC-TEST-01")
        expect(page).to have_text("NC-TEST-02")
      end
    end
  end

  # ── 3 & 4. Net recalculation on check / uncheck ──────────────────────

  describe "Scenario 1: invoice $100k, NC1=$50k, NC2=$60k" do
    before do
      create_invoice(amount: 100_000, number: "FAC-SC1")
      create_nc(amount: 50_000, number: "NC-SC1-A")
      create_nc(amount: 60_000, number: "NC-SC1-B")
      open_payment_modal
    end

    it "deducts NC1 from net when checked" do
      cn_checkboxes.first.click

      # $50k applied → net = $50k. have_css waits for JS to update the DOM.
      expect(page).to have_css("#modalCreditsApplied", text: /50/)
      expect(page).to have_css("#modalNetTotal", text: /50/)
    end

    it "restores net when NC1 is unchecked" do
      cn_checkboxes.first.click
      cn_checkboxes.first.click   # uncheck

      # Net should be back to $100k
      expect(page).to have_css("#modalCreditsApplied", text: /0/)
      expect(page).to have_css("#modalNetTotal", text: /100/)
    end

    it "NC2 remains enabled when invoice is not yet fully covered after NC1" do
      cn_checkboxes.first.click

      # $50k applied, $50k remaining → NC2 must still be enabled
      expect(page).not_to have_css("#creditNotesList input[type='checkbox'][disabled]")
    end

    it "net reaches 0 when both NCs are checked (NC2 effective = $50k, not $60k)" do
      cn_checkboxes.first.click   # NC1: $50k applied
      cn_checkboxes.last.click    # NC2: effective = min($60k, $50k remaining) = $50k

      expect(page).to have_css("#modalNetTotal", text: /\A\s*\$\s*0\s*\z/)
    end
  end

  # ── 5 & 6. Disable / re-enable logic ─────────────────────────────────

  describe "Scenario 2: invoice $100k, NC1=$100k, NC2=$100k — disable logic" do
    before do
      create_invoice(amount: 100_000, number: "FAC-SC2")
      create_nc(amount: 100_000, number: "NC-SC2-A")
      create_nc(amount: 100_000, number: "NC-SC2-B")
      open_payment_modal
    end

    it "disables NC2 when NC1 fully covers the invoice" do
      cn_checkboxes.first.click

      # JS sets cb.disabled = true when invoice is fully covered
      expect(page).to have_css("#creditNotesList input[type='checkbox'][disabled]")
    end

    it "the label of a disabled NC becomes visually muted" do
      cn_checkboxes.first.click

      # The label's style should include opacity (set by JS)
      label = find("#creditNotesList label:last-child")
      expect(label[:style]).to include("opacity")
    end

    it "re-enables NC2 when NC1 is unchecked" do
      cn_checkboxes.first.click     # NC2 disabled
      cn_checkboxes.first.click     # uncheck NC1 → NC2 should re-enable

      expect(page).not_to have_css("#creditNotesList input[type='checkbox'][disabled]")
    end

    it "restores full net when NC1 is unchecked" do
      cn_checkboxes.first.click
      cn_checkboxes.first.click   # uncheck

      expect(page).to have_css("#modalNetTotal", text: /100/)
    end
  end

  # ── 7. Partial application badge ──────────────────────────────────────

  describe "Scenario 3: partial application badge when NC exceeds remaining" do
    before do
      create_invoice(amount: 100_000, number: "FAC-SC3")
      create_nc(amount: 60_000, number: "NC-SC3-A")   # covers $60k fully
      create_nc(amount: 80_000, number: "NC-SC3-B")   # only $40k of $80k will apply
      open_payment_modal
    end

    it "shows a partial label for NC-SC3-B" do
      cn_checkboxes.first.click   # NC-SC3-A: $60k → $40k remaining
      cn_checkboxes.last.click    # NC-SC3-B: effective = $40k (not $80k)

      # At least one .cn-effective-label must be visible (not hidden by Tailwind)
      expect(page).to have_css("#creditNotesList .cn-effective-label", visible: true)
    end

    it "does not show a partial label for NC-SC3-A (applies fully)" do
      cn_checkboxes.first.click

      # The first NC applies fully ($60k) so its effective label must remain hidden
      first_label = find("#creditNotesList label:first-child")
      effective_el = first_label.find(".cn-effective-label", visible: :all)
      expect(effective_el[:class]).to include("hidden")
    end
  end

  # ── 8. No credit notes section when supplier has none ─────────────────

  describe "no credit notes available" do
    before do
      create_invoice(amount: 50_000, number: "FAC-NOCN")
      # No credit notes created for this supplier
      open_payment_modal
    end

    it "keeps the credit notes section hidden" do
      expect(page).not_to have_css("#creditNotesSection", visible: true)
    end

    it "still shows the invoice list" do
      within "#modalInvoicesList" do
        expect(page).to have_text("FAC-NOCN")
      end
    end
  end
end
