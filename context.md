# GENTE DEL SOL - COMPLETE PROJECT CONTEXT

> **For Claude Code CLI:** Use `@CONTEXT.md` at the start of each session to load the full project context.

---

## 📋 GENERAL INFORMATION

**Project:** Gente del Sol Management System  
**Type:** Internal system for a Honda spare parts business in CABA, Argentina  
**Stack:** Ruby on Rails 8, PostgreSQL, Hotwire (Turbo + Stimulus), HAML, TailwindCSS, Devise, Pundit

---

## 🔥 CRITICAL CONVENTIONS - NEVER VIOLATE

1. **Code in English** (models, controllers, methods, variables)
2. **UI in Spanish** (views, user-facing text, messages)
3. **Services with the Result pattern** for complex business logic
4. **HAML only** for views (never ERB)
5. **TailwindCSS only** according to docs/UI_DESIGN_SPEC.md (no custom CSS)
6. **Thin controllers** - logic in Services or Models
7. **Pundit** for all authorization (`authorize` in every action)

---

## 📚 REFERENCE DOCUMENTATION FILES

If you need more detail on something specific, consult:

- **docs/FLUJOS.md** → Detailed business rules, operational flows
- **docs/DEVELOPMENT_GUIDE.md** → System architecture, established patterns
- **docs/CODE_PATTERNS.md** → Code conventions, style
- **docs/UI_DESIGN_SPEC.md** → UI/UX design system, visual components

---

## 🏗️ ARCHITECTURE AND ESTABLISHED PATTERNS

### Services (Result Pattern)

**Location:** `app/services/[namespace]/[action].rb`

**Template:**
```ruby
module Invoices
  class CreateSimpleInvoice
    def initialize(supplier:, invoice_number:, amount:, currency:, exchange_rate:, purchase_date:, due_date:, notes:)
      @supplier = supplier
      @invoice_number = invoice_number
      @amount = amount
      @currency = currency
      @exchange_rate = exchange_rate
      @purchase_date = purchase_date
      @due_date = due_date
      @notes = notes
    end
    
    def call
      validate_params
      
      invoice = Invoice.create!(
        supplier: @supplier,
        invoice_number: @invoice_number,
        amount: @amount,
        currency: @currency,
        exchange_rate: @exchange_rate,
        purchase_date: @purchase_date,
        due_date: @due_date,
        notes: @notes,
        status: "pending",
        has_items: false
      )
      
      Result.success(record: invoice)
    rescue ActiveRecord::RecordInvalid => e
      Result.failure(errors: [e.message])
    rescue => e
      Result.failure(errors: [e.message])
    end
    
    private
    
    def validate_params
      raise "Supplier is required" if @supplier.blank?
      raise "Invoice number is required" if @invoice_number.blank?
      raise "Amount must be positive" if @amount.nil? || @amount <= 0
      raise "Exchange rate required for USD" if @currency == "USD" && @exchange_rate.nil?
    end
  end
end
```

**Result Class:**
```ruby
# app/services/result.rb
class Result
  attr_reader :record, :errors, :message
  
  def self.success(record: nil, message: nil)
    new(success: true, record: record, message: message)
  end
  
  def self.failure(errors: [])
    new(success: false, errors: errors)
  end
  
  def initialize(success:, record: nil, errors: [], message: nil)
    @success = success
    @record = record
    @errors = errors
    @message = message
  end
  
  def success?
    @success
  end
  
  def failure?
    !@success
  end
end
```

### Controllers (Thin Controllers)

**Namespace:** `Web::`  
**Location:** `app/controllers/web/[resource]_controller.rb`

**Template:**
```ruby
module Web
  class InvoicesController < ApplicationController
    include CurrencyParser  # Para parsear formato argentino (1.500.000,50 → 1500000.50)
    
    before_action :load_invoice, only: [:show, :edit, :update, :mark_as_paid, :cancel]
    before_action :load_suppliers, only: [:new, :create, :edit, :update]
    
    def index
      authorize Invoice
      
      @selected_supplier = Supplier.find_by(id: params[:supplier_id]) if params[:supplier_id].present?
      
      @invoices = Invoice.simple_mode
                        .includes(:supplier)
                        .for_supplier(@selected_supplier)
                        .search_invoice(params[:invoice_search])
                        .priority_order
                        .limit(50)
      
      # Métricas
      @total_pending_amount = Invoice.simple_mode.pending_payment.sum { |i| i.total_amount_ars }
      @total_credit_amount = CreditNote.available.sum { |cn| cn.total_amount_ars }
      @net_balance = @total_pending_amount - @total_credit_amount
    end
    
    def create
      authorize Invoice, :create?
      
      result = Invoices::CreateSimpleInvoice.call(
        supplier: find_supplier,
        invoice_number: params[:invoice_number],
        amount: parse_amount(params[:amount]),
        currency: params[:currency] || "USD",
        exchange_rate: parse_exchange_rate(params[:exchange_rate], params[:currency]),
        purchase_date: parse_date(params[:purchase_date]),
        due_date: parse_date(params[:due_date]),
        notes: params[:notes]
      )
      
      if result.success?
        redirect_to web_invoice_path(result.record), notice: "Factura registrada exitosamente."
      else
        flash.now[:alert] = result.errors.join(", ")
        @invoice = Invoice.new
        load_suppliers
        render :new, status: :unprocessable_entity
      end
    end
    
    private
    
    def load_invoice
      @invoice = Invoice.find(params[:id])
    end
    
    def load_suppliers
      @suppliers = Supplier.alphabetical
    end
    
    def find_supplier
      Supplier.find(params[:supplier_id])
    end
    
    def parse_date(date_string)
      return Date.today if date_string.blank?
      Date.parse(date_string)
    rescue ArgumentError
      Date.today
    end
    
    def parse_exchange_rate(rate_string, currency)
      return nil if currency == "ARS"
      return nil if rate_string.blank?
      parse_amount(rate_string)
    end
  end
end
```

### Models (Validations + Scopes + Methods)

**Template:**
```ruby
class Invoice < ApplicationRecord
  # === ASSOCIATIONS ===
  belongs_to :supplier
  has_many :invoice_items, dependent: :destroy
  has_many :products, through: :invoice_items
  has_many :credit_notes, dependent: :restrict_with_error
  has_many :stock_movements, as: :reference, dependent: :nullify
  
  # === ENUMS ===
  enum :status, {
    pending: "pending",
    paid: "paid",
    confirmed: "confirmed",
    cancelled: "cancelled"
  }, suffix: true
  
  # === VALIDATIONS ===
  validates :supplier_id, presence: true
  validates :invoice_number, presence: true, uniqueness: true
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :currency, inclusion: { in: %w[USD ARS] }
  validates :exchange_rate, presence: true, if: :usd_currency?
  validates :exchange_rate, numericality: { greater_than: 0 }, allow_nil: true
  validates :purchase_date, presence: true
  validates :due_date, presence: true
  
  # === SCOPES ===
  scope :simple_mode, -> { where(has_items: false) }
  scope :full_mode, -> { where(has_items: true) }
  scope :pending_payment, -> { where(status: "pending") }
  scope :paid_invoices, -> { where(status: "paid") }
  scope :overdue, -> { simple_mode.where(status: "pending").where("due_date < ?", Date.today) }
  scope :due_this_week, -> {
    start_of_week = Date.current.beginning_of_week(:monday)
    end_of_week = Date.current.end_of_week(:monday)
    simple_mode.where(status: "pending").where(due_date: start_of_week..end_of_week)
  }
  scope :for_supplier, ->(supplier) { where(supplier_id: supplier.id) if supplier.present? }
  scope :search_invoice, ->(query) { where("invoice_number ILIKE ?", "%#{query}%") if query.present? }
  scope :priority_order, -> {
    order(
      Arel.sql("CASE WHEN status = 'pending' THEN 0 ELSE 1 END"),
      Arel.sql("CASE WHEN due_date IS NULL THEN 1 ELSE 0 END"),
      "due_date ASC"
    )
  }
  
  # === CALLBACKS ===
  before_validation :set_early_payment_terms, on: :create, if: -> { supplier.present? && purchase_date.present? }
  
  # === INSTANCE METHODS ===
  def simple_mode?
    !has_items?
  end
  
  def full_mode?
    has_items?
  end
  
  def total_amount
    has_items? ? calculate_total : amount
  end
  
  def total_amount_ars
    currency == "USD" ? total_amount * (exchange_rate || 0) : (total_amount || 0)
  end
  
  def overdue?
    pending_status? && due_date && due_date < Date.today
  end
  
  def days_until_due
    return nil unless due_date
    (due_date - Date.today).to_i
  end
  
  def mark_as_paid!(payment_date = Date.today, apply_discount: false)
    raise "Cannot mark as paid: not in simple mode" unless simple_mode?
    raise "Cannot mark as paid: already paid" if paid_status?
    
    transaction do
      update!(
        status: "paid",
        paid_at: payment_date,
        paid_with_discount: apply_discount
      )
      
      # Mark associated credit notes as applied
      credit_notes.pending_status.update_all(
        status: "applied",
        applied_at: payment_date
      )
    end
  end
  
  # Early payment discount methods
  def amount_with_discount
    return amount unless early_payment_discount_percentage.present?
    amount * (1 - (early_payment_discount_percentage / 100.0))
  end
  
  def amount_with_discount_ars
    currency == "USD" ? amount_with_discount * (exchange_rate || 0) : amount_with_discount
  end
  
  def eligible_for_discount?(payment_date = Date.current)
    return false unless early_payment_due_date.present?
    payment_date <= early_payment_due_date
  end
  
  def potential_savings
    return 0 unless early_payment_due_date.present?
    amount - amount_with_discount
  end
  
  def potential_savings_ars
    currency == "USD" ? potential_savings * (exchange_rate || 0) : potential_savings
  end
  
  private
  
  def usd_currency?
    currency == "USD"
  end
  
  def set_early_payment_terms
    return unless supplier.has_early_payment_discount?
    
    self.early_payment_due_date = purchase_date + supplier.early_payment_days.days
    self.early_payment_discount_percentage = supplier.early_payment_discount_percentage
  end
  
  def calculate_total
    return amount unless has_items?
    invoice_items.sum { |item| item.quantity * item.unit_cost }
  end
end
```

### Policies (Pundit)

**Location:** `app/policies/[resource]_policy.rb`

**Template:**
```ruby
class InvoicePolicy < ApplicationPolicy
  def index?
    user.present?
  end
  
  def show?
    user.present?
  end
  
  def create?
    user.present?
  end
  
  def update?
    user.present? && record.pending_status?
  end
  
  def destroy?
    user.admin?
  end
  
  def mark_as_paid?
    user.present? && record.pending_status?
  end
end
```

### Views (HAML + TailwindCSS)

**Conventions:**
- Use HAML only
- TailwindCSS according to UI_DESIGN_SPEC.md
- Colors: slate as the base, emerald for success, amber for warning, red for error
- DO NOT use corporate red (#DC3545) on buttons (only on the logo)

**Metric Card:**
```haml
.bg-white.border.border-slate-200.rounded-lg.shadow-sm.hover:shadow-md.transition-all.p-6
  .flex.items-start.justify-between.mb-4
    .flex-1
      %p.text-sm.font-medium.text-gray-600.mb-1 Deuda Total Pendiente
      %h3.text-3xl.font-bold.text-gray-900
        = number_to_currency(@total_pending, unit: "ARS ", precision: 0, delimiter: ".", separator: ",")
    
    .w-12.h-12.bg-gray-100.rounded-xl.flex.items-center.justify-center.text-2xl
      💰
  
  .text-sm.text-gray-500
    %span.font-medium.text-gray-700 10
    %span facturas pendientes
```

**Primary Button:**
```haml
= link_to new_web_invoice_path, class: "inline-flex items-center justify-center gap-2 px-4 py-2.5 bg-slate-700 hover:bg-slate-800 text-white text-sm font-medium rounded-lg shadow-sm transition-colors" do
  %span +
  %span Nueva Factura
```

**Badge:**
```haml
-# Success
%span.inline-flex.items-center.px-2.5.py-1.rounded-md.text-xs.font-medium.bg-emerald-100.text-emerald-800
  Disponible

-# Warning
%span.inline-flex.items-center.px-2.5.py-1.rounded-md.text-xs.font-medium.bg-amber-100.text-amber-800
  Pendiente

-# Error
%span.inline-flex.items-center.px-2.5.py-1.rounded-md.text-xs.font-medium.bg-red-100.text-red-800
  Cancelada

-# Neutral
%span.inline-flex.items-center.px-2.5.py-1.rounded-md.text-xs.font-medium.bg-slate-100.text-slate-700
  Aplicada
```

---

## 🗂️ MAIN SYSTEM MODULES

### 1. Invoices (Supplier Invoices)

**Model:** `Invoice`  
**Controller:** `Web::InvoicesController`  
**Services:** `Invoices::CreateSimpleInvoice`, `Invoices::MarkAsPaid`  
**Routes:** `/web/invoices`, `/web/invoices/:id`, `/web/invoices/pending`

**Statuses:**
- `pending`: Pending payment
- `paid`: Paid
- `confirmed`: Confirmed (full mode - future)
- `cancelled`: Cancelled

**Modes:**
- **Simple** (current): Total amount only, without product detail (`has_items: false`)
- **Full** (future): With detailed products (`has_items: true`)

**Main fields:**
```ruby
# Básicos
supplier_id, invoice_number, amount, currency, exchange_rate
purchase_date, due_date, status, paid_at, notes

# Descuento por pronto pago
early_payment_due_date, early_payment_discount_percentage, paid_with_discount

# Modo
has_items  # false = simple, true = full
```

**Important scopes:**
```ruby
Invoice.simple_mode              # Facturas sin detalle
Invoice.pending_payment          # Pendientes de pago
Invoice.due_this_week           # Vencen esta semana (lun-vie)
Invoice.due_next_week           # Vencen próxima semana
Invoice.overdue                 # Vencidas
Invoice.for_supplier(supplier)  # De un proveedor específico
```

**Key methods:**
```ruby
invoice.total_amount_ars                    # Amount in ARS (converts if USD)
invoice.amount_with_discount                # Amount with discount applied
invoice.eligible_for_discount?(date)        # Can it use a discount on this date?
invoice.mark_as_paid!(date, apply_discount: bool)
```

### 2. Credit Notes (Credit Notes)

**Model:** `CreditNote`  
**Controller:** `Web::CreditNotesController`  
**Routes:** `/web/credit_notes`, `/web/credit_notes/:id`

**Purpose:** Record credits in the business's favor granted by suppliers (for returns, errors, etc.)

**Statuses:**
- `pending`: Available to use (active credit)
- `applied`: Already consumed/applied
- `cancelled`: Voided

**Main fields:**
```ruby
supplier_id, invoice_id (opcional), credit_note_number
amount, currency, exchange_rate, issue_date
status, applied_at, notes
```

**Flows:**

**Case A - Credit note linked to an invoice:**
1. The user creates a credit note linked to a specific Invoice
2. The credit note inherits the currency/exchange rate from the invoice
3. The credit note stays in status `pending`
4. When the invoice is marked as paid → the credit note automatically goes to `applied`

**Case B - Orphan credit note (without an invoice):**
1. The user creates a credit note without an associated invoice (general credit)
2. Default: ARS
3. The credit note stays in status `pending`
4. The user enters the credit note's Show page → "Marcar como Aplicada" button (with a confirmation modal)
5. The credit note changes to `applied` manually

**Important scopes:**
```ruby
CreditNote.available           # Solo pending (crédito disponible)
CreditNote.for_supplier(s)     # De un proveedor específico
```

### 3. Suppliers (Suppliers)

**Model:** `Supplier`  
**Controller:** `Web::SuppliersController`

**Main fields:**
```ruby
# Básicos
name, email, phone, cuit, bank_alias, bank_account

# Payment terms
payment_term_days              # Normal term (e.g. 30)
early_payment_days             # Days for early payment (e.g. 15)
early_payment_discount_percentage  # % discount (e.g. 5.0)
```

**Relationships:**
```ruby
has_many :invoices
has_many :credit_notes
```

**Methods:**
```ruby
supplier.has_early_payment_discount?  # Has a discount configured?
supplier.total_pending_amount         # Total pending debt
supplier.total_credit_notes_amount    # Crédito total disponible
supplier.current_balance              # Balance neto (deuda - crédito)
```

**Main suppliers (seeds):**
- IPC (30-day term)
- Yokomitsu (15 days)
- Goicochea (30 days normal, 5% discount if paid within 15 days)
- Lorraine (10 days)
- Taiwan Auto Supply (45 days)

### 4. Products (Products)

**Model:** `Product`  
**Fields:** SKU, name, price, stock, origin (OEM Japan, OEM USA, Aftermarket)  
**Quantity:** ~1600 Honda products loaded from Excel

### 5. Orders (Sales)

**Model:** `Order`  
**Current mode:** "from_paper" (from receipt books)  
**Relationships:** belongs_to :customer

### 6. Customers (Customers)

**Model:** `Customer`  
**Status:** Basic index, associated with sales

---

## 🎯 FEATURE IN ACTIVE DEVELOPMENT: EARLY PAYMENTS WITH DISCOUNT

### Problem to Solve

Some suppliers offer discounts for early payment:
- Example: "30-day normal term, but 5% discount if you pay within 15 days"

**Concrete scenario:**
```
Factura de Goicochea emitida 12/01:
- Vencimiento normal: 11/02 (30 días) → monto: ARS 500.000
- Vencimiento con descuento: 27/01 (15 días) → monto: ARS 475.000 (5% off)

Problema:
- Vence con descuento: 27/01 (viernes de próxima semana)
- Jueves de pago de esa semana: 29/01
- 27/01 < 29/01 ✅ → Si esperamos al 29/01, perdemos el descuento

Solución:
- Mostrar en "Pagos Anticipados" de esta semana (pagar el 22/01)
- Capturar el 5% de descuento
- Ahorro: ARS 25.000
```

### Implementation

**New fields:**

Suppliers:
- `early_payment_days` (integer)
- `early_payment_discount_percentage` (decimal 5,2)

Invoices:
- `early_payment_due_date` (date)
- `early_payment_discount_percentage` (decimal 5,2)
- `paid_with_discount` (boolean)

**Automatic inheritance:**
- When creating an Invoice → it inherits `early_payment_days` and `early_payment_discount_percentage` from the Supplier
- But they are manually editable in the form

**"Advance" logic:**
```ruby
def should_advance_payment?
  return false unless early_payment_due_date.present?
  return false if early_payment_due_date <= Date.current
  
  natural_payment_thursday = payment_thursday_for_date(early_payment_due_date)
  early_payment_due_date < natural_payment_thursday
end
```

**"Pending Payments" view:**
Splits into two sections:
1. **Early Payments** (green/emerald background) → Invoices with discount that we "advance"
2. **Regular Payments** → Invoices that fall due this week normally

**Payment modal:**
When marking as paid, it asks:
- ○ Pay full amount (ARS 500.000)
- ● Pay with discount (ARS 475.000) ⭐ - Savings: ARS 25.000

Validation: If `payment_date > early_payment_due_date` → discount is not allowed

---

## 🛠️ AVAILABLE HELPERS AND CONCERNS

### CurrencyParser (Concern)

**Location:** `app/controllers/concerns/currency_parser.rb`

**Usage:**
```ruby
include CurrencyParser

parse_amount("1.500.000,50")  # → 1500000.50
parse_amount("1500.00")       # → 1500.0
```

**Function:** Converts Argentine format (dot = thousands, comma = decimals) to float

### View Helpers

```ruby
# Formatear moneda estilo argentino
number_to_currency(1500000, unit: "ARS ", precision: 0, delimiter: ".", separator: ",")
# → "ARS 1.500.000"

# Helper custom (si existe)
currency_ar_int(1500000)
# → "ARS 1.500.000"
```

---

## 📋 SIDEBAR NAVIGATION (Current Structure)

```
📊 Dashboard
📦 Productos
🛒 Ventas
👥 Clientes
📥 Facturación ▼ (desplegable)
   ├─ 📄 Facturas (/web/invoices)
   ├─ 💳 Notas de Crédito (/web/credit_notes)
   └─ 💸 Pagos Pendientes (/web/invoices/pending)
🏢 Proveedores
```

---

## 🎨 UI DESIGN - GOLDEN RULES

### Colors (TailwindCSS)

**Base palette:**
- `slate-700` → Primary buttons
- `slate-50/100/200` → Backgrounds, borders
- `white` → Cards, main backgrounds

**Semantic colors:**
- `emerald-100/emerald-800` → Success, available, credit
- `amber-100/amber-800` → Warning, pending
- `red-100/red-800` → Error, cancelled
- `slate-100/slate-700` → Neutral, applied

**NEVER USE:**
- Red (#DC3545) for buttons → Only for the logo
- Gradients on large cards → Only on small icons

### Common Components

**Card:**
```css
.bg-white.border.border-slate-200.rounded-lg.p-6
```

**Button Primary:**
```css
.bg-slate-700.hover:bg-slate-800.text-white.text-sm.font-medium.rounded-lg
```

**Button Secondary:**
```css
.bg-white.border.border-slate-300.text-slate-700.rounded-lg
```

**Input:**
```css
.border.border-slate-300.rounded-xl.focus:ring-2.focus:ring-slate-500
```

### Spacing

- Use multiples of 4: `p-4`, `p-6`, `gap-4`, `gap-6`
- Border radius: `rounded-lg` (8px), `rounded-xl` (12px), `rounded-2xl` (16px)

---

## ⚙️ USEFUL COMMANDS

```bash
# Database
rails db:migrate
rails db:seed
rails db:reset  # ⚠️ BORRA TODO

# Console
rails c

# Tests
rspec
rspec spec/models/invoice_spec.rb

# Sync inventory from Excel
rails inventory:sync_from_excel['path/to/file.xlsx']
```

---

## 📖 GLOSSARY OF TERMS

- **Invoice:** Supplier invoice (previously called "Purchase")
- **Credit Note (NC):** Credit note in the business's favor
- **Order:** Sale to a customer
- **Supplier:** Supplier
- **Customer:** Customer
- **Simple Mode:** Invoice without product detail
- **Full Mode:** Invoice with products (future)
- **Early Payment:** Early payment with discount
- **Applied:** Status of a credit note already consumed
- **Pending:** Pending (invoices to pay, credits available)

---

## 🔥 GOLDEN RULES - NEVER VIOLATE

1. **ALWAYS** consult docs/FLUJOS.md before implementing business logic
2. **ALWAYS** follow established patterns (Services, Result, etc.)
3. **ALWAYS** code in English, UI in Spanish
4. **ALWAYS** HAML for views (never ERB)
5. **ALWAYS** TailwindCSS according to UI_DESIGN_SPEC.md (no custom CSS)
6. **ALWAYS** Services for complex logic
7. **ALWAYS** Pundit for authorization
8. **ALWAYS** validations in models (not in controllers)
9. **NEVER** use red on buttons (only slate-700)
10. **NEVER** invent new patterns - use the established ones

---

## 🎯 WHEN RECEIVING A TASK

**Checklist:**
1. ✅ Read the relevant doc if more detail is needed (FLUJOS.md, UI_DESIGN_SPEC.md, etc.)
2. ✅ Follow established patterns (Services, Controllers, Models)
3. ✅ Keep the design consistent (TailwindCSS according to spec)
4. ✅ Code in English, UI in Spanish
5. ✅ Services for complex logic
6. ✅ Pundit for authorization
7. ✅ HAML for views

---

**Context version:** 2.0  
**Last updated:** 2026-01-19
