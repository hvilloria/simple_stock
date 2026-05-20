# Order Summary Payment Breakdown — Design Spec

**Date:** 2026-05-19
**Feature:** polish for `feat_07-payment-method-on-all-sales` (same branch, bundled into the same commit)

## Context

`feat_07-payment-method-on-all-sales` introduced a multi-row payment block in the new order form (`web/orders/new`). The "Resumen de Venta" card on the right side, however, still only shows the order total — it doesn't communicate how much of that total is being collected at the moment of sale vs. how much will be added to the customer's credit balance.

Concretely: a credit sale of $193.940 with no upfront payment shows "Total $193.940" in the resumen, with no indication that the customer is actually paying $0 right now and the full amount will become outstanding debt. The "Información de Pago" sub-section only echoes the order type (e.g. "Cuenta Corriente — A crédito") and channel, not the dollar split.

## Scope

### In scope

1. Add a two-row payment breakdown below the big "Total" number in the resumen card:
   - **Cobrás ahora**: sum of all amounts in the multi-row payment block.
   - **A cuenta corriente**: order total − cobrás ahora.
2. The breakdown is rendered **only for credit orders**. Immediate orders keep the resumen unchanged — by validation, the payment sum must equal the total, so the breakdown adds no information.
3. The breakdown updates live as the user adds/removes payment rows or changes product items, via the existing `order-form` Stimulus controller.
4. Color treatment for the two amounts:
   - "Cobrás ahora": green (`text-green-700`) when > $0; gray (`text-gray-500`) when $0.
   - "A cuenta corriente": amber (`text-amber-700`) when > $0; gray (`text-gray-500`) when $0.

### Out of scope

- No changes to the payment input section on the left card (already done in feat_07).
- No changes to the "Información de Pago" sub-section of the resumen (the order-type/channel rows stay as-is).
- No changes to the order index, show, customer pages, or any other view.
- No backend / service / spec changes — this is a view + Stimulus update only.
- No changes to existing immediate-order behavior or validation.

---

## Architecture

Pure view + Stimulus change. No new targets in the model layer, no new params, no new request specs.

### Files to modify

- `app/views/web/orders/new.html.haml` — add the two-row breakdown block inside the "Resumen de Venta" card.
- `app/javascript/controllers/order_form_controller.js` — extend `updatePaymentTotal` (already exists) to also update the new resumen rows, and toggle visibility based on order type.

### Files unchanged

- `app/services/sales/create_order.rb`
- `app/controllers/web/orders_controller.rb`
- All specs.

---

## UI changes

### `new.html.haml` — add a new block inside Card 2 (Resumen de Venta)

The current structure (lines ~104-138):

```haml
.bg-white.border.border-slate-200.rounded-lg.p-6.lg:sticky.lg:top-24.md:row-span-2
  %h3.text-lg.font-semibold.text-gray-900.mb-6 Resumen de Venta

  -# Total principal (calculado dinámicamente)
  .text-center.mb-6
    %p.text-sm.text-gray-500.mb-2 Total
    %p.text-4xl.font-bold.text-gray-900{ data: { order_form_target: "total" } } $0

  -# Items + cantidad block (sin cambios)
  .border-t.border-gray-200.py-4.space-y-3
    ...

  -# Información de Pago (sin cambios)
  .border-t.border-gray-200.py-4
    ...
```

The new breakdown block sits **between the big Total and the Items/Cantidad block**:

```haml
-# Desglose de pago (solo visible en venta a crédito)
.border-t.border-gray-200.py-4.hidden{ data: { order_form_target: "summaryBreakdown" } }
  .space-y-2
    .flex.justify-between.text-sm
      %span.text-gray-600 Cobrás ahora
      %span.font-semibold{ data: { order_form_target: "summaryPaidNow" } } $0
    .flex.justify-between.text-sm
      %span.text-gray-600 A cuenta corriente
      %span.font-semibold{ data: { order_form_target: "summaryOutstanding" } } $0
```

The container has `hidden` by default — Stimulus removes/adds it based on order type.

### `order_form_controller.js` — extend existing methods

**New targets in the targets array:**
- `summaryBreakdown`
- `summaryPaidNow`
- `summaryOutstanding`

**`applyPaymentMode(orderType)`** — extend the existing method (already updates the title/subtitle/badge of the payment section in Card 1). Add at the end:

```javascript
if (this.hasSummaryBreakdownTarget) {
  if (orderType === "credit") {
    this.summaryBreakdownTarget.classList.remove("hidden")
  } else {
    this.summaryBreakdownTarget.classList.add("hidden")
  }
}
```

**`updatePaymentTotal()`** — extend the existing method (already computes `declared` from `paymentAmountTargets` and updates the payment-status banner in Card 1). Add at the end, after the existing block:

```javascript
if (this.hasSummaryPaidNowTarget) {
  const paidNow = declared
  this.summaryPaidNowTarget.textContent = `$${this.formatCurrency(paidNow)}`
  this.summaryPaidNowTarget.classList.remove("text-green-700", "text-gray-500")
  this.summaryPaidNowTarget.classList.add(paidNow > 0 ? "text-green-700" : "text-gray-500")
}

if (this.hasSummaryOutstandingTarget) {
  const outstanding = Math.max(0, total - declared)
  this.summaryOutstandingTarget.textContent = `$${this.formatCurrency(outstanding)}`
  this.summaryOutstandingTarget.classList.remove("text-amber-700", "text-gray-500")
  this.summaryOutstandingTarget.classList.add(outstanding > 0 ? "text-amber-700" : "text-gray-500")
}
```

The `Math.max(0, ...)` clamp guarantees the outstanding amount never renders negative if the user momentarily types a payment sum greater than the total — the form already blocks submit in that case (red banner in Card 1), so the resumen just shows $0 outstanding instead of a negative number that would confuse.

---

## Behavior summary

| Scenario | Resumen shows |
| --- | --- |
| Immediate sale, products totalling $X | Total $X (unchanged) |
| Credit sale, no items | Total $0; breakdown visible with both rows at $0 (gray) |
| Credit sale, total $X, $0 cobro | Total $X; Cobrás ahora $0 (gray); A cuenta corriente $X (amber) |
| Credit sale, total $X, partial cobro $Y | Total $X; Cobrás ahora $Y (green); A cuenta corriente $X-Y (amber) |
| Credit sale, total $X, full cobro $X | Total $X; Cobrás ahora $X (green); A cuenta corriente $0 (gray) |
| Order type switches credit → immediate | breakdown hides immediately, no other reset |
| Order type switches immediate → credit | breakdown reveals immediately with current declared/outstanding values |

---

## Testing

No automated tests. The change is presentation-only and the underlying logic (validation, payment creation) is already covered by feat_07's specs.

Manual smoke test additions (extends Task 11 of the feat_07 plan):
- Switch to credit, no upfront → "Cobrás ahora $0" (gray) / "A cuenta corriente $total" (amber)
- Type partial cobro → "Cobrás ahora $Y" (green) / "A cuenta corriente $total-Y" (amber)
- Type full cobro → "Cobrás ahora $X" (green) / "A cuenta corriente $0" (gray)
- Type cobro > total → submit disabled (existing behavior); "A cuenta corriente" clamped to $0
- Switch to immediate → breakdown disappears
- Switch back to credit → breakdown reappears with the latest values

---

## Why this lives in feat_07

This is the natural completion of the multi-payment UI shipped in feat_07. The new payment block on the left card creates dollar information that the resumen card on the right currently ignores. Bundling into the existing uncommitted work keeps the feature coherent ("payment method on all sales" — and the resumen reflects it) and avoids a tiny standalone branch/commit for a 30-line tweak.
