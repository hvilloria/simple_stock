# frozen_string_literal: true

module CashHelper
  ENTRY_GLYPHS = { in: "↓", out: "↑", move: "⇄" }.freeze
  ENTRY_GLYPH_CLASSES = { in: "text-emerald-600", out: "text-red-600", move: "text-slate-400" }.freeze
  CASH_PILES = CashMovement::REPORTING_GROUPS.fetch("efectivo")
  PAYMENT_METHODS = %w[cash bank mercado_pago usd].freeze
  SALE_GROUP_TEXT_CLASSES = { "efectivo" => "text-emerald-600", "mercado_pago" => "text-sky-500", "banco" => "text-blue-800" }.freeze
  SALE_GROUP_FILL_CLASSES = { "efectivo" => "bg-emerald-500", "mercado_pago" => "bg-sky-400", "banco" => "bg-blue-800" }.freeze
  SALE_GROUP_HINTS = { "banco" => "Tarjeta · QR · Transferencia" }.freeze
  MONTH_NAMES =%w[enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre].freeze

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

  def cash_sale_group_text_class(group) = SALE_GROUP_TEXT_CLASSES.fetch(group)
  def cash_sale_group_fill_class(group) = SALE_GROUP_FILL_CLASSES.fetch(group)
  def cash_sale_group_hint(group) = SALE_GROUP_HINTS[group]

  def cash_month_name(month)
    MONTH_NAMES.fetch(month.month - 1)
  end

  # The dashboard's month travels as YYYY-MM; there is no next link past the
  # current month.
  def cash_month_param(month)
    month.strftime("%Y-%m")
  end

  def cash_next_month(month)
    month.next_month unless month >= Date.current.beginning_of_month
  end

  def cash_month_figure(amount, usd: false)
    currency_ar_int(amount, unit: usd ? "US$ " : "$ ")
  end

  # With no description written, the rubro is the only name the expense has.
  def cash_fixed_expense_title(movement)
    movement.description.presence || CashMovement.subcategory_label(movement.subcategory)
  end

  def cash_fixed_expense_rubro(movement)
    CashMovement.subcategory_label(movement.subcategory) if movement.description.present?
  end

  def cash_fixed_expense_amount(movement)
    cash_month_figure(movement.amount.abs, usd: movement.account == "usd")
  end

  # The invoice cell of a cash row. nil means the collection is still unbilled.
  def cash_entry_invoice(movement)
    payment = movement.source_payment
    return "—" if payment.nil? || movement.reversal? || payment.reversal_movement.present?
    return nil unless payment.billed?
    return "S/F" if payment.none_invoice_type?

    "#{payment.invoice_type.upcase} · #{payment.invoice_number}"
  end

  def cash_entry_link(movement)
    return nil unless movement.automatic?

    target = if movement.source_payment_id
      web_payment_path(movement.source_payment_id)
    elsif movement.paid_invoices.size == 1
      web_invoice_path(movement.paid_invoices.first)
    end
    return nil if target.nil?

    "if (!event.target.closest('a, button, form')) window.location='#{target}'"
  end

  # "Pago <supplier> — <numbers>" with each number linking to its invoice. The
  # numbers are typed by users, so link_to escapes them.
  def cash_paid_invoices_description(movement)
    invoices = movement.paid_invoices.sort_by(&:id)
    links = invoices.map { |invoice| link_to(invoice.invoice_number, web_invoice_path(invoice), class: "underline hover:text-slate-600") }

    safe_join([ "Pago #{invoices.first.supplier.name} — ", safe_join(links, ", ") ])
  end

  # A fixed expense reads as what it is (Impuestos), not as its broad category.
  def cash_category_label(movement)
    if movement.fixed_expense_category? && movement.subcategory.present?
      CashMovement.subcategory_label(movement.subcategory)
    else
      CashMovement.category_label(movement.category)
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
