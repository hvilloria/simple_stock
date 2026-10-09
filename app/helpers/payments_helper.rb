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

  def payment_back_date(payment)
    payment.original_cash_movement&.business_date || payment.payment_date
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

  # The cash discount a collection carried, as a whole percentage; nil when none.
  def payment_allocation_discount_percent(allocation)
    return nil unless allocation.discount_amount.positive?

    (allocation.discount_amount * 100 / (allocation.amount + allocation.discount_amount)).round
  end
end
