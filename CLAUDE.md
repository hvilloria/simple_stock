# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Rails 7.2 inventory and sales management system for a Honda auto parts shop (Gente del Sol) in Buenos Aires, Argentina. Single location business with products, stock tracking, sales (cash/credit), customers, payments, supplier invoices, and credit notes.

**Stack:** Rails 7.2, PostgreSQL, Hotwire (Turbo + Stimulus), HAML templates, TailwindCSS, Devise (auth), Pundit (authorization)

## Commands

```bash
# Run all tests
bundle exec rspec

# Run single test file
bundle exec rspec spec/models/invoice_spec.rb

# Run tests matching pattern
bundle exec rspec -e "early payment"

# Lint and auto-fix
bundle exec rubocop -A

# Security scan
bundle exec brakeman -q

# Start server
bin/rails server

# Database
bin/rails db:migrate
bin/rails db:setup  # create + migrate + seed
```

## Architecture

### Service Pattern (Required for Business Logic)

All business logic goes in services under `app/services/[domain]/[action].rb`. Services must:
- Implement `.call(**params)` class method
- Return `Result` struct: `Result.new(success?: bool, record: object, errors: array)`
- Wrap operations in `ActiveRecord::Base.transaction`
- Validate params before modifying data via `validate_params` private method
- Capture exceptions and return Result (never raise to controller)

```ruby
module Sales
  class CreateOrder
    def self.call(**params)
      new(**params).call
    end

    def call
      validate_params
      ActiveRecord::Base.transaction do
        # logic
        Result.new(success?: true, record: @order, errors: [])
      end
    rescue ValidationError => e
      Result.new(success?: false, record: nil, errors: [e.message])
    end
  end
end
```

### Controllers (Thin)

Controllers only handle HTTP: receive params, call services, render/redirect based on Result.

```ruby
def create
  result = Sales::CreateOrder.call(customer: @customer, items: items)
  if result.success?
    redirect_to result.record, notice: "Venta creada"
  else
    flash.now[:alert] = result.errors.join(", ")
    render :new, status: :unprocessable_entity
  end
end
```

### Stock Management (Critical Rule)

- **NEVER** update `current_stock` directly from controllers/views
- All stock changes must create `StockMovement` records
- `current_stock` is a cache updated via callbacks from StockMovement
- Source of truth: `stock_movements.sum(:quantity)`

### Key Directories

- `app/services/` - Business logic (sales/, invoices/, inventory/, payments/)
- `app/controllers/web/` - All controllers namespaced under Web
- `app/views/web/` - HAML templates (no ERB)
- `app/policies/` - Pundit authorization policies
- `docs/` - Project documentation (FLUJOS.md, CODE_PATTERNS.md, DEVELOPMENT_GUIDE.md, UI_DESIGN_SPEC.md)

### Models

- `Product` - Inventory items with SKU, cost (USD/ARS), price, current_stock
- `Order` - Sales (order_type: 'cash' or 'credit')
- `OrderItem` - Order line items
- `StockMovement` - Polymorphic reference to Orders/Invoices, tracks all stock changes
- `Customer` - Clients (has_credit_account enables credit purchases)
- `Payment` - Customer payments
- `Invoice` - Supplier purchases (simple_mode or full_mode with items)
- `Supplier` - Vendors with optional early payment discount terms
- `CreditNote` - Supplier credit notes

## Testing

- RSpec with shoulda-matchers for model validations
- FactoryBot for test data with traits
- Test organization: `spec/{models,services,controllers,requests}/`

```ruby
# Model spec
it { is_expected.to validate_presence_of(:sku) }

# Service spec
result = Sales::CreateOrder.call(customer: customer, items: items)
expect(result.success?).to be true
```

## Language Convention

- **Code**: English (classes, methods, variables, database columns)
- **UI text**: Spanish (flash messages, form labels, user-facing content)
- **Tests**: English descriptions

## Documentation

Read these docs in `docs/` before implementing features:
- `FLUJOS.md` - Business workflows and rules
- `CODE_PATTERNS.md` - Code examples and patterns
- `DEVELOPMENT_GUIDE.md` - Architecture reference
- `UI_DESIGN_SPEC.md` - Design system (TailwindCSS classes, color palette)
