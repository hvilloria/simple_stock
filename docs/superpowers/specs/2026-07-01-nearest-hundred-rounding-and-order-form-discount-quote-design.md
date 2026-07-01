# feat_19 — Nearest-100 discount rounding + cash-discount quote on the order form

**Date:** 2026-07-01
**Branch/scope:** `feat_19` (commits `feat(feat_19): …`; `feat_18` = product edit, already merged)

## Summary

Two related changes to how cash discounts behave:

1. **Rounding rule (everywhere):** replace the current *ceil-to-100* (always round up) rule for discounted cash amounts with **round-to-nearest-100, ties rounding down** (remainder 1–50 → down, 51–99 → up). This changes the amount caja actually charges and can now round **down** in the customer's favour.
2. **Cash-discount quote on `web/orders/new`:** add a JS-only discount suggestion so the salesperson can quote a cash price. Nothing is submitted; caja still applies the real discount at collection (current behaviour unchanged).

A third, forced consequence: the `web/orders/show` "Redondeo" line must handle a **negative** rounding, since rounding can now go down.

## Motivation

The sales team's real-world rule is round-to-nearest-100 with a 51 threshold on the tens, not always-up. Example: a $24.500 product with 10% off = $22.050 → **$22.000** (not $22.100); $22.051 → **$22.100**. Salespeople also want to quote the cash-discount price to the customer at the counter, while the actual discount is still set by caja at collection time.

## Part A — Rounding rule (replace everywhere)

**Rule:** round the discounted cash amount to the nearest multiple of 100; a remainder of exactly 50 rounds **down**. So 1–50 → down, 51–99 → up.

- `22.050 → 22.000`
- `22.051 → 22.100`
- `639.697,5 → 639.700` (unchanged from the ceil example — remainder 97,5 > 50)
- exact multiples of 100 are unchanged.

### Backend

- **`app/services/payments/cash_rounding.rb`** — replace `round_up_to_hundred` with `round_to_nearest_hundred(amount)`:

  ```ruby
  def round_to_nearest_hundred(amount)
    (amount.to_d / 100).round(0, :half_down) * 100
  end
  ```

  BigDecimal, half-down at ties, always returns an Integer. Update the module doc examples.

- **`app/services/payments/collect_sale_note.rb`** (~line 92) and **`app/services/payments/collect_on_account.rb`** (~line 106): call `round_to_nearest_hundred`. Update comments that say "ceil-to-hundred" → "nearest-hundred".
- **`app/controllers/web/payments_on_account/payments_controller.rb`** (~line 18): the inline `(cash_raw / 100.0).ceil * 100` becomes the nearest-100 rule (mirror the helper's math).

### Frontend

Four Stimulus/JS spots currently inline `Math.ceil(x/100)*100`. Extract a single shared helper and import it in all of them to remove the 4-copy drift.

- **New:** `app/javascript/helpers/cash_rounding.js`

  ```js
  // Round to nearest multiple of 100; ties (exactly .50) round DOWN.
  export function roundToNearestHundred(amount) {
    const v = amount / 100
    const floor = Math.floor(v)
    return (v - floor > 0.5 ? floor + 1 : floor) * 100
  }
  ```

  `v - floor > 0.5` is strict, so exactly `.50` falls to `floor` (down), matching the backend `:half_down`.

- Import and use it in: `sale_note_payment_controller.js`, `on_account_payment_controller.js`, `payment_allocation_controller.js` (replacing each `Math.ceil(...)*100`), and `order_form_controller.js` (Part B).

## Part B — Cash-discount quote on `web/orders/new`

Purely a salesperson quote. **Nothing is submitted; the backend is untouched.** The order is still created with `source: from_paper` and no discount; caja sets the real discount later via `Payments::CollectSaleNote`.

### UI (`app/views/web/orders/new.html.haml`, "Resumen de Venta" panel)

- A **"Descuento sugerido (contado)"** dropdown with options `0 / 5 / 10 %`.
- A **"Total con descuento"** line showing `roundToNearestHundred(total × (1 − d/100))`.
- A small note: *"El descuento final lo aplica caja al cobrar."*
- The whole block is **visible only when order_type = Contado (immediate)**.

Follows `UI_DESIGN_SPEC` — slate base, no new accent colours.

### Behaviour (`app/javascript/controllers/order_form_controller.js`)

- New targets: `discountSection`, `discountSelect`, `suggestedTotal`.
- New action `updateDiscountSuggestion` on the select's `change`.
- Recompute the suggested total inside `updateSummary` (so it tracks item/price/quantity edits).
- In `updateOrderType`: show `discountSection` only for `immediate`; when leaving `immediate`, hide it and reset the select to `0` (and clear the suggested line).
- No hidden inputs added; `updateSubmitButton` is unchanged; the submitted params are byte-for-byte identical to today.

## Part C — Show-view rounding line (forced consequence)

`Order#rounding_amount` = `total_amount − (original_total_amount − discount_amount)` already returns a **signed** value; no model change. But `app/views/web/orders/show.html.haml` (two spots, ~line 171 and ~line 305) renders the "Redondeo" line only `if @order.rounding_amount.positive?` with a hard-coded `+`. Under nearest-100 rounding the value can be negative.

- Render the line whenever `rounding_amount != 0` (both the items-table row and the summary row).
- Show a **sign-aware** amount: `+50` when positive, `−50` when negative (reuse `currency_ar`, prefix by sign).
- This keeps the reconciliation `Subtotal − Discount + Rounding = Total` correct in both directions.

## Testing

- **`spec/services/payments/cash_rounding_spec.rb`** (or wherever the helper is specced): boundary table — `…49 → down`, `…50 → down`, `…51 → up`, exact multiples unchanged, `639.697,5 → 639.700`, the `24.500 × 0,90 = 22.050 → 22.000` case.
- **`CollectSaleNote` / `CollectOnAccount` specs:** update expectations to nearest-100. Some fixtures that previously rounded up now round down. Re-verify the `on_account` hard guard `cash_to_collect ≤ outstanding_balance` still holds (rounding down only relaxes it; rounding up at 51–99 is still bounded — keep the existing "use a nominal discount ≥ 100" note where relevant).
- **`Order#rounding_amount` + show view:** add a case where rounding is negative, assert the "−" line renders and `Subtotal − Discount + Rounding = Total` reconciles.
- **Part B is JS-only UI.** Submission is identical to today, so no request-spec changes. Sanity-check manually: show/hide by order type, reset-to-0 on leaving Contado, and the suggested-total math against the new rounding.

## Out of scope

- No change to the caja discount cap (stays `0 / 5 / 10`).
- No persistence of the order-form suggested discount.
- Credit per-item discounts (`Payments::AllocatePayment`) are unaffected — they don't use the hundred-rounding.

## Commit plan (one logical change per commit; scope `feat_19`)

1. `feat(feat_19): round discounted cash to nearest hundred` — helper rename + backend callers + shared JS helper + the 3 collection JS spots + specs.
2. `feat(feat_19): suggest cash discount on the new-order form` — HAML + `order_form_controller.js`.
3. `fix(feat_19): show signed rounding on order detail` — show-view sign-aware Redondeo line + spec.

(Exact split adjustable.)
