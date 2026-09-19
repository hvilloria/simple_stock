# frozen_string_literal: true

module CashHelper
  ENTRY_GLYPHS = { in: "↓", out: "↑", move: "⇄" }.freeze
  ENTRY_GLYPH_CLASSES = { in: "text-emerald-600", out: "text-red-600", move: "text-slate-400" }.freeze
  INVOICE_TYPE_LABELS = { "a" => "A", "b" => "B" }.freeze
  CASH_PILES = CashMovement::REPORTING_GROUPS.fetch("efectivo")
  PAYMENT_METHODS = %w[cash bank mercado_pago usd].freeze

  def cash_entry_glyph(entry)
    ENTRY_GLYPHS.fetch(entry.kind)
  end

  def cash_entry_glyph_class(entry)
    ENTRY_GLYPH_CLASSES.fetch(entry.kind)
  end

  # The server stored the sign; an outflow shows it, a transfer shows only
  # how much moved.
  def cash_entry_amount(entry)
    case entry.kind
    when :move then number_ar(entry.amount)
    when :out  then "−#{number_ar(entry.movement.amount.abs)}"
    else number_ar(entry.movement.amount)
    end
  end

  def cash_holding_amount(row)
    currency_ar(row.amount, unit: row.usd? ? "US$ " : "$ ")
  end

  def cash_entry_notes(movement)
    return [] if movement.source_payment.nil?

    movement.source_payment.orders.sort_by(&:paper_number).map do |order|
      [ order.paper_number, INVOICE_TYPE_LABELS[order.invoice_type] ].compact.join(" · ")
    end
  end

  def cash_pile?(account)
    CASH_PILES.include?(account)
  end

  def cash_channel_options
    CashMovement::CHANNEL_LABELS.map do |key, label|
      [ key == "compensation" ? "Compensación — no entra plata" : label, key ]
    end
  end

  def cash_method_options
    PAYMENT_METHODS.map { |key| [ key == "cash" ? "Efectivo" : CashMovement.account_label(key), key ] }
  end

  def cash_pile_options
    CASH_PILES.map { |key| [ CashMovement.account_label(key), key ] }
  end

  def cash_outflow_kind_options(partner:)
    options = [ [ "Proveedor", "suppliers" ] ]
    options += CashMovement::SUBCATEGORY_LABELS.map { |key, label| [ label, "fixed_expense:#{key}" ] }
    options << [ "Retiro de socio", "partner" ] if partner
    options
  end

  # What the entry form starts on: a movement's stored answers when editing,
  # the first option of the mode otherwise. The account splits into the two
  # questions the form asks, method and pile.
  def cash_entry_fields(movement: nil, mode: "out")
    return cash_entry_defaults(mode) if movement.nil?

    account = movement.account
    {
      mode: movement.inflow? ? "in" : "out",
      kind: [ movement.category, movement.subcategory ].compact.join(":"),
      category: movement.category,
      subcategory: movement.subcategory,
      direction: movement.partner_category? ? movement.partner_direction : nil,
      account: movement.sale_category? ? nil : account,
      method: cash_pile?(account) || account.nil? ? "cash" : account,
      pile: cash_pile?(account) ? account : "drawer",
      channel: movement.channel || "cash",
      supplier_id: movement.supplier_id,
      description: movement.description,
      amount: number_ar(movement.amount.abs)
    }
  end

  private

  def cash_entry_defaults(mode)
    inflow = mode == "in"
    {
      mode: mode,
      kind: inflow ? "sale" : "suppliers",
      category: inflow ? "sale" : "suppliers",
      subcategory: nil,
      direction: nil,
      account: inflow ? nil : "drawer",
      method: "cash",
      pile: "drawer",
      channel: "cash",
      supplier_id: nil,
      description: nil,
      amount: nil
    }
  end
end
