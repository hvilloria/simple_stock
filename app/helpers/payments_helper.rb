# frozen_string_literal: true

module PaymentsHelper
  def payment_title(payment)
    "Cobro · #{Payment.method_label(payment.payment_method)} · #{number_ar(payment.amount)}"
  end

  def payment_subtitle(payment)
    collector = payment.original_cash_movement&.user
    [
      payment.payment_date.strftime("%d/%m/%Y"),
      payment.customer.name,
      ("cobrado por #{collector.name}" if collector)
    ].compact.join(" · ")
  end

  # How far a collection lowered the debt of the notes it covered.
  def payment_debt_lowered(payment)
    payment.shown_allocations.sum { |a| a.amount + a.discount_amount - a.overpaid_amount }
  end

  def void_confirm_message(cascade)
    total = number_ar(cascade.total)
    cascade.payments.one? ? "¿Anular el cobro por $ #{total}?" : "¿Anular #{cascade.payments.size} cobros por $ #{total}?"
  end

  def payment_order_label(order)
    [ Order.type_label(order.order_type), (order.contact_name if order.on_account_order_type?) ]
      .compact.join(" — ")
  end

  def payment_movement_status(movement)
    state =
      if movement.reversal? then "Reversión"
      elsif movement.sealed? then "Día cerrado"
      else "Día abierto"
      end
    "#{CashMovement.account_label(movement.account)} · #{state}"
  end

  # Nothing is preselected: the operator has to pick the method on purpose.
  def payment_method_options_with_prompt
    tag.option("Seleccionar medio", value: "", disabled: true, selected: true) +
      options_for_select(Payment.method_options)
  end

  # The cash discount a collection carried, as one of the allowed percents; nil when none.
  def payment_allocation_discount_percent(allocation)
    return nil unless allocation.discount_amount.positive?

    covered = allocation.try(:covered_amount) ||
              allocation.amount + allocation.discount_amount - allocation.overpaid_amount
    percent = allocation.discount_amount * 100 / covered
    Payments::CollectOnAccount::ALLOWED_DISCOUNTS.select(&:positive?).min_by { |d| (d - percent).abs }
  end

  def payment_notes(payment)
    payment.shown_allocations.map { |a| a.order.paper_number }.compact.join(", ")
  end

  def payment_types(payment)
    payment.shown_allocations.map { |a| Order.type_label(a.order.order_type) }.uniq.join(", ")
  end

  # An on-account operation is known by its contact, not by the counter customer.
  def payment_contact(payment)
    payment.shown_allocations.map(&:order).find(&:on_account_order_type?)&.contact_name.presence ||
      payment.customer.name
  end
end
