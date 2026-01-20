# GENTE DEL SOL - CONTEXTO COMPLETO DEL PROYECTO

> **Para Claude Code CLI:** Usar `@CONTEXT.md` al inicio de cada sesión para cargar todo el contexto del proyecto.

---

## 📋 INFORMACIÓN GENERAL

**Proyecto:** Sistema de Gestión Gente del Sol  
**Tipo:** Sistema interno para negocio de repuestos Honda en CABA, Argentina  
**Stack:** Ruby on Rails 8, PostgreSQL, Hotwire (Turbo + Stimulus), HAML, TailwindCSS, Devise, Pundit

---

## 🔥 CONVENCIONES CRÍTICAS - NUNCA VIOLAR

1. **Código en inglés** (modelos, controllers, métodos, variables)
2. **UI en español** (vistas, textos para usuarios, mensajes)
3. **Services con Result pattern** para lógica de negocio compleja
4. **HAML únicamente** para vistas (nunca ERB)
5. **TailwindCSS únicamente** según docs/UI_DESIGN_SPEC.md (no CSS custom)
6. **Controllers delgados** - lógica en Services o Modelos
7. **Pundit** para toda autorización (`authorize` en cada acción)

---

## 📚 ARCHIVOS DE DOCUMENTACIÓN DE REFERENCIA

Si necesitás más detalle sobre algo específico, consultar:

- **docs/FLUJOS.md** → Reglas de negocio detalladas, flujos operativos
- **docs/DEVELOPMENT_GUIDE.md** → Arquitectura del sistema, patterns establecidos
- **docs/CODE_PATTERNS.md** → Convenciones de código, estilo
- **docs/UI_DESIGN_SPEC.md** → Sistema de diseño UI/UX, componentes visuales

---

## 🏗️ ARQUITECTURA Y PATTERNS ESTABLECIDOS

### Services (Result Pattern)

**Ubicación:** `app/services/[namespace]/[action].rb`

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
**Ubicación:** `app/controllers/web/[resource]_controller.rb`

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
      
      # Marcar notas de crédito asociadas como aplicadas
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

**Ubicación:** `app/policies/[resource]_policy.rb`

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

**Convenciones:**
- Usar HAML únicamente
- TailwindCSS según UI_DESIGN_SPEC.md
- Colores: slate como base, emerald para success, amber para warning, red para error
- NO usar rojo corporativo (#DC3545) en botones (solo en logo)

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

## 🗂️ MÓDULOS PRINCIPALES DEL SISTEMA

### 1. Invoices (Facturas de Proveedores)

**Modelo:** `Invoice`  
**Controller:** `Web::InvoicesController`  
**Services:** `Invoices::CreateSimpleInvoice`, `Invoices::MarkAsPaid`  
**Rutas:** `/web/invoices`, `/web/invoices/:id`, `/web/invoices/pending`

**Estados:**
- `pending`: Pendiente de pago
- `paid`: Pagada
- `confirmed`: Confirmada (modo completo - futuro)
- `cancelled`: Cancelada

**Modos:**
- **Simple** (actual): Solo monto total, sin detalle de productos (`has_items: false`)
- **Full** (futuro): Con productos detallados (`has_items: true`)

**Campos principales:**
```ruby
# Básicos
supplier_id, invoice_number, amount, currency, exchange_rate
purchase_date, due_date, status, paid_at, notes

# Descuento por pronto pago
early_payment_due_date, early_payment_discount_percentage, paid_with_discount

# Modo
has_items  # false = simple, true = full
```

**Scopes importantes:**
```ruby
Invoice.simple_mode              # Facturas sin detalle
Invoice.pending_payment          # Pendientes de pago
Invoice.due_this_week           # Vencen esta semana (lun-vie)
Invoice.due_next_week           # Vencen próxima semana
Invoice.overdue                 # Vencidas
Invoice.for_supplier(supplier)  # De un proveedor específico
```

**Métodos clave:**
```ruby
invoice.total_amount_ars                    # Monto en ARS (convierte si es USD)
invoice.amount_with_discount                # Monto con descuento aplicado
invoice.eligible_for_discount?(date)        # ¿Puede usar descuento en esta fecha?
invoice.mark_as_paid!(date, apply_discount: bool)
```

### 2. Credit Notes (Notas de Crédito)

**Modelo:** `CreditNote`  
**Controller:** `Web::CreditNotesController`  
**Rutas:** `/web/credit_notes`, `/web/credit_notes/:id`

**Propósito:** Registrar créditos a favor que dan los proveedores (por devoluciones, errores, etc.)

**Estados:**
- `pending`: Disponible para usar (crédito activo)
- `applied`: Ya consumida/aplicada
- `cancelled`: Anulada

**Campos principales:**
```ruby
supplier_id, invoice_id (opcional), credit_note_number
amount, currency, exchange_rate, issue_date
status, applied_at, notes
```

**Flujos:**

**Caso A - NC asociada a factura:**
1. Usuario crea NC vinculada a Invoice específica
2. NC hereda moneda/tipo de cambio de la factura
3. NC queda en status `pending`
4. Al marcar factura como pagada → NC automáticamente a `applied`

**Caso B - NC huérfana (sin factura):**
1. Usuario crea NC sin factura asociada (crédito general)
2. Default: ARS
3. NC queda en status `pending`
4. Usuario entra a Show de NC → botón "Marcar como Aplicada" (con modal de confirmación)
5. NC cambia a `applied` manualmente

**Scopes importantes:**
```ruby
CreditNote.available           # Solo pending (crédito disponible)
CreditNote.for_supplier(s)     # De un proveedor específico
```

### 3. Suppliers (Proveedores)

**Modelo:** `Supplier`  
**Controller:** `Web::SuppliersController`

**Campos principales:**
```ruby
# Básicos
name, email, phone, cuit, bank_alias, bank_account

# Plazos de pago
payment_term_days              # Plazo normal (ej: 30)
early_payment_days             # Días para pago anticipado (ej: 15)
early_payment_discount_percentage  # % descuento (ej: 5.0)
```

**Relaciones:**
```ruby
has_many :invoices
has_many :credit_notes
```

**Métodos:**
```ruby
supplier.has_early_payment_discount?  # ¿Tiene descuento configurado?
supplier.total_pending_amount         # Deuda total pendiente
supplier.total_credit_notes_amount    # Crédito total disponible
supplier.current_balance              # Balance neto (deuda - crédito)
```

**Proveedores principales (seeds):**
- IPC (30 días plazo)
- Yokomitsu (15 días)
- Goicochea (30 días normal, 5% descuento si paga en 15 días)
- Lorraine (10 días)
- Taiwan Auto Supply (45 días)

### 4. Products (Productos)

**Modelo:** `Product`  
**Campos:** SKU, name, price, stock, origin (OEM Japan, OEM USA, Aftermarket)  
**Cantidad:** ~1600 productos Honda cargados desde Excel

### 5. Orders (Ventas)

**Modelo:** `Order`  
**Modo actual:** "from_paper" (desde talonarios)  
**Relaciones:** belongs_to :customer

### 6. Customers (Clientes)

**Modelo:** `Customer`  
**Estado:** Index básico, asociados a ventas

---

## 🎯 FEATURE EN DESARROLLO ACTIVO: PAGOS ANTICIPADOS CON DESCUENTO

### Problema a Resolver

Algunos proveedores ofrecen descuentos por pago anticipado:
- Ejemplo: "30 días plazo normal, pero 5% descuento si pagás en 15 días"

**Escenario concreto:**
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

### Implementación

**Campos nuevos:**

Suppliers:
- `early_payment_days` (integer)
- `early_payment_discount_percentage` (decimal 5,2)

Invoices:
- `early_payment_due_date` (date)
- `early_payment_discount_percentage` (decimal 5,2)
- `paid_with_discount` (boolean)

**Herencia automática:**
- Al crear Invoice → hereda `early_payment_days` y `early_payment_discount_percentage` del Supplier
- Pero son editables manualmente en el formulario

**Lógica de "adelanto":**
```ruby
def should_advance_payment?
  return false unless early_payment_due_date.present?
  return false if early_payment_due_date <= Date.current
  
  natural_payment_thursday = payment_thursday_for_date(early_payment_due_date)
  early_payment_due_date < natural_payment_thursday
end
```

**Vista "Pagos Pendientes":**
Separa en dos secciones:
1. **Pagos Anticipados** (fondo verde/emerald) → Facturas con descuento que "adelantamos"
2. **Pagos Regulares** → Facturas que vencen esta semana normalmente

**Modal de pago:**
Al marcar como pagada, pregunta:
- ○ Pagar monto completo (ARS 500.000)
- ● Pagar con descuento (ARS 475.000) ⭐ - Ahorro: ARS 25.000

Validación: Si `payment_date > early_payment_due_date` → no permite descuento

---

## 🛠️ HELPERS Y CONCERNS DISPONIBLES

### CurrencyParser (Concern)

**Ubicación:** `app/controllers/concerns/currency_parser.rb`

**Uso:**
```ruby
include CurrencyParser

parse_amount("1.500.000,50")  # → 1500000.50
parse_amount("1500.00")       # → 1500.0
```

**Función:** Convierte formato argentino (punto = miles, coma = decimales) a float

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

## 📋 SIDEBAR NAVIGATION (Estructura Actual)

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

## 🎨 DISEÑO UI - REGLAS DE ORO

### Colores (TailwindCSS)

**Paleta base:**
- `slate-700` → Botones primarios
- `slate-50/100/200` → Backgrounds, borders
- `white` → Cards, fondos principales

**Colores semánticos:**
- `emerald-100/emerald-800` → Success, disponible, crédito
- `amber-100/amber-800` → Warning, pendiente
- `red-100/red-800` → Error, cancelado
- `slate-100/slate-700` → Neutral, aplicado

**NUNCA USAR:**
- Rojo (#DC3545) para botones → Solo para logo
- Gradientes en cards grandes → Solo en iconos pequeños

### Componentes Comunes

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

- Usar múltiplos de 4: `p-4`, `p-6`, `gap-4`, `gap-6`
- Border radius: `rounded-lg` (8px), `rounded-xl` (12px), `rounded-2xl` (16px)

---

## ⚙️ COMANDOS ÚTILES

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

# Sync inventory desde Excel
rails inventory:sync_from_excel['path/to/file.xlsx']
```

---

## 📖 GLOSARIO DE TÉRMINOS

- **Invoice:** Factura de proveedor (antes se llamaba "Purchase")
- **Credit Note (NC):** Nota de crédito a favor
- **Order:** Venta a cliente
- **Supplier:** Proveedor
- **Customer:** Cliente
- **Simple Mode:** Factura sin detalle de productos
- **Full Mode:** Factura con productos (futuro)
- **Early Payment:** Pago anticipado con descuento
- **Applied:** Estado de NC ya consumida
- **Pending:** Pendiente (facturas a pagar, créditos disponibles)

---

## 🔥 REGLAS DE ORO - NUNCA VIOLAR

1. **SIEMPRE** consultar docs/FLUJOS.md antes de implementar lógica de negocio
2. **SIEMPRE** seguir patterns establecidos (Services, Result, etc)
3. **SIEMPRE** código en inglés, UI en español
4. **SIEMPRE** HAML para vistas (nunca ERB)
5. **SIEMPRE** TailwindCSS según UI_DESIGN_SPEC.md (no CSS custom)
6. **SIEMPRE** Services para lógica compleja
7. **SIEMPRE** Pundit para autorización
8. **SIEMPRE** validaciones en modelos (no en controllers)
9. **NUNCA** usar rojo en botones (solo slate-700)
10. **NUNCA** inventar nuevos patterns - usar los establecidos

---

## 🎯 AL RECIBIR UNA TAREA

**Checklist:**
1. ✅ Leer el doc relevante si hace falta más detalle (FLUJOS.md, UI_DESIGN_SPEC.md, etc)
2. ✅ Seguir patterns establecidos (Services, Controllers, Models)
3. ✅ Mantener diseño consistente (TailwindCSS según spec)
4. ✅ Código en inglés, UI en español
5. ✅ Services para lógica compleja
6. ✅ Pundit para autorización
7. ✅ HAML para vistas

---

**Versión del contexto:** 2.0  
**Última actualización:** 2026-01-19