# Caja del día, dirección primero — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the day screen's two zones and category-first live rows with one list and one entry row that starts by asking whether it is an entrada, a salida or a transferencia

**Architecture:** A UI rewrite of the day screen over an unchanged data model and an almost unchanged server. The entry row posts the same parameters the controllers accept today; Stimulus translates the operator's answers into them. The two zones stop being two tables — `Cash::DayQuery` gains one ordered list of entries in which a transfer's two legs fold into one line.

**Tech Stack:** Rails 7.2, HAML, Turbo Streams, Stimulus, TailwindCSS, RSpec (request + system specs via Selenium in Docker).

**Spec:** this plan carries its own design, in the section below. The visual reference is option B of the mockup page (https://claude.ai/artifact/WJZ7fihb5CgGgw5emqFwff), chosen by the owner. Background: `docs/CASH_MODULE_DESIGN.md` §7.1, §8.1, R-6.

**Branch:** `feat-33_cash-compensation` — this closes an implementation gap in the cash module rather than opening new work. Commit scope `feat_33`.

---

## Why this is changing

The owner found the current screen confusing, and the reasons are specific:

- **The direction is hidden.** The first dropdown asks for an accounting category — "Venta / Proveedores / Gastos fijos". An operator first thinks *did money come in or go out?*, and nothing on the row answers that. The Excel it replaced answered it with two columns, Entrada and Salida.
- **The fields change meaning and sit under the wrong headers.** The category dropdown sits under the column headed "Canal" in one table and "Arca" in the other. The second dropdown is a channel for a sale and a subcategory for a fixed expense.
- **The day is split in two tables.** The drawer zone and the arca zone exist so the night's count knows which rows are the drawer's. That is accounting leaking into the screen; the Excel was one list.
- **The arca zone defaults to the drawer.** Its subtitle says "lo que no salió del cajón" and its arca select starts on "Caja del día". A row saved without touching it is counted against the drawer and jumps to the other table.
- **Moving money is unreadable.** A button at the foot of the second table opens a separate form with a preview, and the result is two unrelated-looking rows with a badge.

---

## Design decisions — review these before execution

These are decisions option B left open. Each has a recommendation; execution assumes them unless the owner changes one.

**D1. The row opens on the question, not on a text field.** The mode control (↓ Entrada · ↑ Salida · ⇄ Transferencia — the Excel's own words, no first person) is the first stop of the entry row and holds the focus on page load and after every save. While focus is on it, `E`, `S`, `T` and the arrow keys switch mode; Tab moves into the fields. Bare letter keys are safe precisely because focus is on the control, not in a text field. **The mode sticks after saving**: loading five expenses in a row stays on Salida. On page load it starts on **Salida**, because since slice 1c almost every sale arrives by itself from a collection and what is typed by hand is mostly outflows.

**D2. "Qué es" is a field of the Salida row, and it is one flat list.** Proveedor · Alquiler · Sueldos · Cargas sociales · Impuestos · Servicios · Gastos de local · Retiro de socio (admin only). Each fixed-expense subcategory is its own option, so the separate subcategory select disappears and the row has one field fewer. It does not appear on an Entrada row for a sale — see D3.

**D11. Salida asks how it was paid, then — only for cash — from which pile.** The owner pointed out that the first draft asked "De dónde salió" with the arca names, which hides the method: "Caja del día" names a place, not a way of paying. The Excel's `Egresos` sheet records an outflow's **Canal** as the method — Efectivo, Banco, Mercado Pago or USD — and that is the question now. **Cómo se pagó** offers exactly those four; choosing **Efectivo** adds **De qué caja** — Caja del día (default), Caja grande, Remanente — because R-6 needs to know which cash pile, and only for cash does it vary. Every one of the six arcas is still reachable and the model does not change: Efectivo + Caja del día is `drawer`, Efectivo + Caja grande is `main_cash`, Efectivo + Remanente is `change_fund`, and Banco, Mercado Pago and USD are `bank`, `mercado_pago` and `usd`. Aporte de socio asks the same two questions, as **Cómo entró** and **De qué caja**.

**D3. Entrada, as a flow.** A sale typed by hand is: `E` · Descripción (optional) · Nota · Cómo pagó · Monto · Enter. **Compensación** is one of the "Cómo pagó" options, labelled "Compensación — no entra plata", because it is a sale; choosing it adds a **Proveedor** field, as today, and the row gets no drawer dot because no money reached a caja. **Aporte de socio** is the one entrada that is not a sale: for an admin, the Entrada row carries a **Qué es** field first, defaulting to Venta; choosing Aporte de socio swaps "Cómo pagó" for **Cómo entró** and, for cash, **De qué caja** (D11), because a contribution has no sale channel. For anyone without the partner category the field is not rendered — there would be one option. Retiro de socio is the same case the other way, in the Salida list (D2).

**D4. Transferencia has no preview.** Monto · De · A · Descripción (optional). The row already says what will happen, so the two-row preview, its `preview` action, route, views and specs are removed. The default is Caja grande → Banco, the everyday deposit.

**D5. One list, in load order.** Each row starts with a direction glyph and shows one signed amount. A transfer's two legs fold into **one** row, shown as "Mercado Pago → Banco" in the Caja column. A row whose money touches the drawer carries a small dot — the drawer's count is the sum of the dotted rows. For a transfer, the dot appears if either leg is the drawer. This is exactly R-6: the count is defined by the arca, never by the zone.

**D6. Labels do not change.** "Caja del día" stays the drawer's name in every select. It used to collide with the title of the first table; with one list that title is gone, and the name stops being ambiguous. No change to `ACCOUNT_LABELS`, so the reports are untouched.

**D7. The drawer-by-default bug disappears on its own.** Cash that left the till is the common case, so "De qué caja" defaulting to Caja del día is correct — and it is only asked once someone has said the payment was in cash. Nothing jumps tables either, because there is only one.

**D8. The server keeps deciding the sign.** Entrada / Salida only restricts which options the row offers. The amount's sign is still derived server-side from the category, plus `direction` for a partner movement, exactly as today. The screen never sends a sign.

**D10. The list says only what was written.** The first draft of B was too wordy, and the owner said so. No first person anywhere. No "Cobro de nota" filler: an automatic sale's description is blank, with the small "Automático" badge the screen already has. No category in muted text beside each row — the kind of expense lives in the form and in the reports. The invoice type rides on the note number, `3340 · A`. The payment column is called **Canal**, as in the Excel, and always states the method (D11); the cash pile appears after it only when it is cash that did not come from the till — `Efectivo · Caja grande`. A transfer's description is shown only if one was written.

**D9. Editing locks the direction.** "Editar" on a manual row replaces it with the entry form in edit mode, with its mode fixed. Turning an outflow into an inflow is a different fact, not a correction: delete and load again. Automatic rows, transfer legs and sealed rows stay uneditable through the policy, unchanged.

---

## Global Constraints

Every task's brief includes these.

- **No host Ruby.** Everything runs in Docker; the stack is up. Commands are `docker compose exec -T web …`, run in the FOREGROUND. Never launch a background job and idle. Run the full suite ONCE per task, at the end.
- **The module is admin-only for now** (`CashMovementPolicy#index?` is `user.admin?`). Specs that drive the day screen sign in an **admin**. Do not reopen it to `caja`.
- **`::Cash::Foo` with leading colons** anywhere under `Web::Cash::` — a bare `Cash` there resolves to `Web::Cash` and raises a NameError that reads like a missing file.
- **Turbo Streams** are a list of `turbo_stream.<verb> "<dom-id>"` calls and nothing else. Every target needs a stable id; a stream aimed at a missing id fails silently.
- **Partials take locals, never controller ivars.**
- **A field that does not apply is disabled as well as hidden** — hiding alone still submits it.
- **HAML drops an attribute whose value is `false`**; render a Stimulus boolean value as `x.to_s`.
- **`travel_to Date.new(...) { }` binds the block to `Date.new`**; use `do…end`.
- **The row asks `policy(movement).update?`** for its edit and delete affordances; never restate the policy's conditions in a view.
- **`Cash::AmountParser` is the only strict reading of an amount.** The form's amount goes through `CurrencyParser#decimal_string_from`, as today.
- **No change to models, services, the policies' rules or the database.** If a task seems to need one, stop and report it instead.
- UI copy in Spanish; code, comments and identifiers in English; comments minimal; HAML only; no queries or logic in views.
- **Do not `git commit` and do not stage.** The controller of the run commits after review.

---

## The parameter contract

This table is the load-bearing part of the plan: it is how the operator's answers become the parameters the server already accepts. `MovementsController` decides the zone by whether `account` is present, derives the sign from the category, and reads `direction` for a partner movement; none of that changes.

| Mode | Qué es | Cómo pagó / de dónde / a qué caja | Posts to | Parameters |
|---|---|---|---|---|
| Entrada | Venta | Cómo pagó = channel `X` | `POST /web/cash/movements` | `category=sale`, `channel=X`, no `account`; plus `supplier_id` when `X` is `compensation` |
| Entrada | Aporte de socio | Cómo entró + (for Efectivo) De qué caja → arca `Y` | `POST /web/cash/movements` | `category=partner`, `direction=contribution`, `account=Y` |
| Salida | Proveedor | Cómo se pagó + (for Efectivo) De qué caja → arca `Y` | `POST /web/cash/movements` | `category=suppliers`, `account=Y` |
| Salida | Alquiler · Sueldos · Cargas sociales · Impuestos · Servicios · Gastos de local | Cómo se pagó + (for Efectivo) De qué caja → arca `Y` | `POST /web/cash/movements` | `category=fixed_expense`, `subcategory=<key>`, `account=Y` |
| Salida | Retiro de socio | Cómo se pagó + (for Efectivo) De qué caja → arca `Y` | `POST /web/cash/movements` | `category=partner`, `direction=withdrawal`, `account=Y` |
| Transferencia | — | de `A` a `B` | `POST /web/cash/transfers` | `from=A`, `to=B`, `amount`, `description` |

Every row also posts `business_date`, `description` and `amount`.

**How method + pile become one `account`.** The two selects are UI only; the server still receives a single `account`. Cómo se pagó offers `cash`, `bank`, `mercado_pago`, `usd`; De qué caja offers `drawer`, `main_cash`, `change_fund` and is enabled only when the method is `cash`. The Stimulus controller writes the hidden `account` input: the pile when the method is `cash`, the method itself otherwise. The server renders that hidden input with the default — `drawer` — so a save works with no script, exactly as for `category`.

**How the "Qué es" select carries two values.** Its option values encode the pair as `category` or `category:subcategory` — `suppliers`, `fixed_expense:rent`, `partner`. The Stimulus controller writes the hidden `category`, `subcategory` and `direction` inputs whenever the mode or the select changes, and once on `connect()`. The hidden inputs are also rendered server-side with the default option's values, so a save works before any change event fires. If the script fails to run, `category` is empty and the server refuses the row: a safe failure, never a wrong row.

---

## File structure

**Created**
- `app/views/web/cash/days/_entries.html.haml` — the day's single list.
- `app/views/web/cash/entries/_entry.html.haml` — one displayed row: a movement or a folded transfer.
- `app/views/web/cash/entries/_form.html.haml` — the entry row, in new or edit mode.
- `app/javascript/controllers/cash_entry_controller.js` — mode switching, field visibility, the hidden-parameter translation, focus.
- `spec/system/web/cash_day_entry_spec.rb` — the browser spec for the new row, and the only layer that sees its JavaScript.

**Modified**
- `app/services/cash/day_query.rb` — gains `#entries`; loses the zone queries in the last task.
- `app/views/web/cash/days/_day.html.haml` — renders the list, the form and the panels.
- `app/views/web/cash/movements/{create,update,edit,destroy}.turbo_stream.haml` and `app/views/web/cash/transfers/create.turbo_stream.haml` — retargeted at the single list.
- `app/controllers/web/cash/movements_controller.rb`, `transfers_controller.rb` — drop the per-zone partial selection and the preview action.
- `config/routes.rb` — drops the transfer preview route.
- `spec/requests/web/cash/{days,movements,transfers,closings}_spec.rb` — retargeted DOM ids.
- `docs/CASH_MODULE_DESIGN.md` — §7.1 and §8.1 describe the new screen.

**Deleted** (last task, once nothing references them)
- `app/views/web/cash/days/_drawer_zone.html.haml`, `_arca_zone.html.haml`
- `app/views/web/cash/movements/_row`, `_arca_row`, `_live_row`, `_arca_live_row`, `_edit_row`, `_arca_edit_row`
- `app/views/web/cash/transfers/_panel`, `_preview`, `preview.turbo_stream`
- `app/javascript/controllers/cash_live_row_controller.js`, `cash_transfer_controller.js`
- `spec/system/web/cash_live_row_spec.rb`, `cash_arca_zone_spec.rb`, `cash_compensation_spec.rb` — superseded by the new system spec, which must cover everything they did.

---

### Task 1: `Cash::DayQuery#entries`

**Files:**
- Modify: `app/services/cash/day_query.rb`
- Test: `spec/services/cash/day_query_spec.rb`

**Interfaces:**
- Consumes: `CashMovement.on`, `#transfer?`, `transfer_group_id`, the existing `includes(source_payment: :orders)`.
- Produces: `Cash::DayQuery#entries` → an Array of `Cash::DayQuery::Entry`, a `Struct` with keyword init:
  - `kind` — `:in`, `:out` or `:move`
  - `movements` — Array of `CashMovement`; one element, or the two legs of a transfer ordered outflow leg first
  - `counts_in_drawer` — Boolean, true when any movement's `account` is `"drawer"`
  - and methods `#movement` (the first movement), `#from` / `#to` (the legs' accounts, for `:move` only) and `#amount` (the absolute amount, for `:move`)

What must be true:
- `kind` is `:move` for a transfer, otherwise `:in` when the amount is positive and `:out` when negative. It is read from the sign the server stored, never recomputed from the category.
- **Every movement of the day appears in exactly one entry**, and together the entries account for all of them. This is the property the zone partition spec protected; it carries over. Write it as one example over a day holding a cash sale, a card sale, a USD sale, a compensation sale, a till expense, a bundle expense, a supplier paid from the bank, a partner withdrawal and a transfer pair.
- A transfer's two legs fold into one `:move` entry; a transfer whose second leg is on another date cannot happen (both legs share `business_date`), so do not code for it.
- Entries are in load order (`created_at`, then `id`), and a folded transfer sits where its first leg does.
- Eager loading is preserved: reading every entry's paper numbers fires no extra query. Pin it with the `capture_sql` idiom already used in this spec file.
- Do not remove `#drawer_movements` or `#arca_movements` here; Task 4 does, once nothing uses them.

- [ ] **Step 1:** Write the partition, folding, ordering, kind and `counts_in_drawer` examples, plus the query-count example. Run `docker compose exec -T web bundle exec rspec spec/services/cash/day_query_spec.rb` and confirm they fail with `undefined method 'entries'`.
- [ ] **Step 2:** Implement `Entry` and `#entries`. Group by `transfer_group_id` in Ruby over the one relation already loaded; do not issue a query per transfer.
- [ ] **Step 3:** Run the file; all green. Break the folding on purpose (skip grouping), watch the partition example fail, restore.
- [ ] **Step 4:** Full suite once, rubocop.

---

### Task 2: The new screen — list, form and wiring

This project tests rendering through request specs and has no view specs, so the list and the form are built and wired to the day screen in one task and tested at the request layer. The browser behaviour comes in Task 3.

**Files:**
- Create: `app/views/web/cash/entries/_entry.html.haml`, `app/views/web/cash/entries/_form.html.haml`, `app/views/web/cash/days/_entries.html.haml`
- Modify: `app/views/web/cash/days/_day.html.haml`
- Modify: `app/views/web/cash/movements/{create,update,edit,destroy}.turbo_stream.haml`, `app/views/web/cash/transfers/create.turbo_stream.haml`
- Modify: `app/controllers/web/cash/movements_controller.rb`, `app/controllers/web/cash/transfers_controller.rb`
- Modify: `spec/requests/web/cash/{days,movements,transfers,closings}_spec.rb`

**Interfaces:**
- Consumes: `#entries` and `Entry` from Task 1; `CashMovement#paper_numbers`, `#automatic?`, `.channel_label`, `.account_label`, `.subcategory_label`; `CurrencyHelper#number_ar`; `policy(movement).update?`; `CashMovementPolicy#categories_for`; the suppliers list from the `SupplierOptions` concern; the parameter contract table above.
- Produces, for Task 3 and the streams:
  - partial `web/cash/entries/entry`, locals `entry:`, `editable:`, root `<tr id="entry_<first movement id>">`
  - partial `web/cash/entries/form`, locals `business_date:`, `suppliers:`, `error:`, optional `movement:` (present means edit mode); root id `day-entry-form` in new mode, `entry_<id>` in edit mode
  - DOM ids `#day-entries` (the list's tbody), `#day-entry-form`, `#entry_<id>`, and the existing `#sales-by-channel`
  - inside the form, the Stimulus identifier `cash-entry` and these targets for Task 3: `mode` (each mode button, with `data-mode="in|out|move"`), `group` (each mode's field group, with `data-mode`), `kind` (the Qué es select), `channel`, `method` (Cómo se pagó / Cómo entró), `pile` (De qué caja), `account` (hidden), `supplier`, `category`, `subcategory`, `direction` (the three hidden inputs)

**The list row** (D10). Columns: the direction glyph (↓ `:in`, ↑ `:out`, ⇄ `:move`) · **Descripción** — what was typed, blank for an automatic sale, which carries the existing "Automático" badge instead · **Nota** — the paper numbers stacked as today, each followed by its invoice type when there is one (`3340 · A`) · **Canal** — the method: the channel label for a sale ("Compensación · Cromosol" for a compensation); for anything else "Efectivo" when the arca is one of the three cash piles, followed by the pile in muted text unless it is the drawer (`Efectivo · Caja grande`), and the arca label for Banco, Mercado Pago and USD; "Mercado Pago → Banco" for a transfer · **Monto** — `−13.000` for an outflow, plain for an inflow, muted for a transfer · the **drawer dot** when `counts_in_drawer` · edit and delete when `editable && policy(entry.movement).update?`. No category text on the row and no first person anywhere. A transfer never offers edit or delete — the policy already refuses a transfer leg, and the row asks the policy rather than checking `kind`.

**The form, as rendered by the server.** The mode control first, then one field group per mode, each field with its own small label above it — "Descripción", "Nota", "Cómo pagó", "Proveedor", "Qué es", "Cómo se pagó", "Cómo entró", "De qué caja", "Monto", "De", "A" — never under a header that belongs to another field. The server renders Salida as the visible group and the other two hidden **and disabled**, and renders the hidden `category`, `subcategory` and `direction` inputs with Salió's default option, so a save works with no script at all. Retiro and Aporte de socio appear only when `categories_for` includes `partner`; without it, the Entrada row renders no Qué es field at all (D3). Transferencia's group posts to the transfers endpoint and the others to the movements endpoint — say in your report whether you switch one form's `action` or render two forms, and why. In edit mode the mode control is shown but locked, the fields are prefilled, and the form carries the row it replaces so "Cancelar" can restore it without a page load (Task 3 wires the button).

**The wiring.**
- `_day` renders the form above one list, with "Ventas por canal" and the amount to wrap on the right, as in mockup B. It stops rendering the two zone partials; do not delete them yet.
- A created row appends to `#day-entries` and the form is replaced by a fresh one. An update replaces `#entry_<id>`; a destroy removes it; a transfer appends **one** folded row. Every mutating stream repaints `#sales-by-channel`.
- In `MovementsController`, the per-zone rendering goes — `@zone` choosing a partial, `@zone_changed` choosing between replace and remove-plus-append — because there is one list. **Its validation stays**: `arca_submission?`, `zone_category?` and `partner_direction?` still enforce the parameter contract.
- The closing modal renders `_day` behind it; confirm it still does and that `Web::Cash::ClosingsController` still loads what the form needs.

**Specs** — retarget, never delete, and keep every paired presence/absence assertion paired:
- The day renders one row per entry: a sale, a supplier outflow, a fixed expense, a partner withdrawal and contribution, a compensation sale with its supplier, an automatic sale and a folded transfer, each with its glyph, signed amount, Canal text and dot — including a cash outflow from the till reading "Efectivo" and one from Caja grande reading "Efectivo · Caja grande" — and, paired with those, that no row contains "Cobro de nota", a category label, or "Moví".
- A transfer is one row, never two.
- The form renders the three groups with their labels, Salida visible and the others disabled, and the hidden inputs carrying the defaults.
- Posting each row of the parameter contract table stores the right `category`, `subcategory`, `channel`, `account`, sign and `supplier`, and the stream appends to `#day-entries`.
- Edit renders the form prefilled with the mode locked; update and destroy target `#entry_<id>`.
- The old ids — `drawer-rows`, `drawer-live-row`, `arca-rows`, `arca-live-row` — appear nowhere in the responses.

The partner options cannot be asserted absent for a cashier here: the module is closed to her, so she never reaches the screen. `spec/policies/cash_movement_policy_spec.rb` already covers `categories_for`; leave it at that.

- [ ] **Step 1:** Retarget and add the request specs; run `docker compose exec -T web bundle exec rspec spec/requests/web/cash` and confirm they fail against the old markup for the right reasons.
- [ ] **Step 2:** Build the two partials and `_entries`; rewire `_day`, the streams and the controllers.
- [ ] **Step 3:** Request specs green; full suite once; rubocop. The three old day-screen system specs fail here because their screen is gone — expected, Task 3 replaces them. Report exactly which examples fail and confirm every one targets the removed UI.

---

### Task 3: The row's behaviour, and its system spec

The mode switching, the field visibility, the parameter translation and the focus are JavaScript, and a system spec is the only layer that can see them — so they are one task.

**Files:**
- Create: `app/javascript/controllers/cash_entry_controller.js`
- Create: `spec/system/web/cash_day_entry_spec.rb`
- Delete: `spec/system/web/cash_live_row_spec.rb`, `cash_arca_zone_spec.rb`, `cash_compensation_spec.rb`

**Interfaces:**
- Consumes: the form's Stimulus identifier and targets from Task 2; the parameter contract table.
- Produces: nothing later tasks rely on.

What the controller does:
- The mode control holds the focus on connect and after every save. `E` / `S` / `T` and `←` / `→` switch mode while it has focus, and do nothing while a text field has focus.
- The last mode survives a save: the stream sends back a fresh form, so carry the mode the way the module already carries state across a stream — read how `cash_live_row_controller.js` receives its `autofocus` value, and remember the HAML landmine about `false` attributes.
- Switching mode shows that mode's group and **disables** the others. Inside a group, the supplier select shows only for Venta + Compensación, and switching away hides **and disables** it. Follow `cash_live_row_controller.js`: its `#show(field, visible)` and its flat visibility rules.
- The Qué es select's value is `category` or `category:subcategory`; on every change of mode or kind, write the hidden `category`, `subcategory` and `direction` inputs per the parameter contract — `direction` is `contribution` for Aporte de socio, `withdrawal` for Retiro de socio, and empty otherwise.
- The method select drives the pile select: De qué caja is shown and enabled only for `cash`, and the hidden `account` is written as described under "How method + pile become one `account`". In edit mode, method and pile are prefilled from the movement's arca.
- In edit mode, "Cancelar" restores the row the form carries without a request.

What the system spec covers, including everything the three deleted specs covered:
- The page opens with the focus on the mode control, on Salida.
- `E`, `S`, `T` switch mode while the control has focus; typing an `e` in the description does not.
- **Every row of the parameter contract table, end to end through the browser**: for each Qué es option in each mode, save a row and assert the stored `category`, `subcategory`, `channel`, `account`, sign and `supplier`. Table-drive it. This is the example that proves the translation, and it matters more than any other.
- A saved row appears with the right glyph and signed amount, and the form comes back empty on the same mode with the focus on the mode control.
- A Salida in Efectivo from Caja del día moves the amount to wrap; in Efectivo from Caja grande, or by Banco, it does not — R-6, visible.
- Choosing Banco hides and disables De qué caja; switching back to Efectivo shows it on Caja del día.
- Compensación reveals the supplier select; switching away hides and disables it, and a sale saved after switching away has no supplier.
- A Transferencia writes two legs and shows one row, "Mercado Pago → Banco".
- Editing prefills and locks the mode; "Cancelar" restores the row with no request.
- A closed day shows the list with no form and no edit affordances.

Follow `spec/system/web/cash_daily_close_spec.rb` for the setup, and remember that `fill_in with: ""` does not reliably fire `input` in chromedriver.

- [ ] **Step 1:** Write the system spec against the markup from Task 2; run it and confirm it fails on the missing controller.
- [ ] **Step 2:** Write `cash_entry_controller.js`.
- [ ] **Step 3:** Delete the three superseded system specs.
- [ ] **Step 4:** The new spec green three runs in a row; full suite once — now fully green; rubocop.

---

### Task 4: Remove what the new screen replaced, and update the design doc

**Files:**
- Delete everything listed under "Deleted" in the file structure that is still present.
- Modify: `config/routes.rb` (the transfer `preview` route), `app/controllers/web/cash/transfers_controller.rb` (the `preview` action and its dry run), `spec/requests/web/cash/transfers_spec.rb` (the preview examples).
- Modify: `app/services/cash/day_query.rb` and its spec — remove `#drawer_movements`, `#arca_movements` and their examples; the partition property now lives on `#entries`.
- Modify: `app/models/cash_movement.rb` — remove `#drawer_zone?` only if nothing references it any more; check, do not assume.
- Modify: `docs/CASH_MODULE_DESIGN.md` — rewrite §7.1 and §8.1 to describe one list and the direction-first row; keep R-6 as it is, since the count is still defined by the arca; record in §2 that the two-zone screen was built and replaced, and why.

What must be true:
- `grep` finds no reference to any removed partial, controller, route helper or method.
- The design doc no longer describes a screen that does not exist.

- [ ] **Step 1:** Delete, then `grep` for every removed name.
- [ ] **Step 2:** Update the design doc.
- [ ] **Step 3:** Full suite once, green; rubocop.

---

## Verification for the whole plan

```
docker compose exec -T web bundle exec rspec
docker compose exec -T web bundle exec rubocop
```

Then by hand, as admin, on a day with a few rows:

1. The page opens with the focus on the mode control, on Salida. Press `S`, Tab, type "Cromosol", pick Proveedor and, for Cómo se pagó, Banco; type an amount, Enter. The row appears with ↑ and a negative amount; the form is back on Salió with the focus on the mode control.
2. Load five expenses in a row without touching the mouse.
3. Press `E`, load a cash sale. It gets the drawer dot and the amount to wrap rises.
4. Press `T`, move $400.000 from Mercado Pago to Banco. One row, "Mercado Pago → Banco".
5. Edit an expense, change the amount, save; edit another and cancel — no page reload either time.
6. Close the day. The modal still shows the day behind it, and afterwards there is no form.

---

## Self-review

- **Coverage of the complaints:** direction first (D1, Tasks 2–3); fields under their own questions (Task 2); one list (D5, Tasks 1–2); the drawer-by-default bug (D7, by construction); moving money as a sentence (D4, Tasks 2–4).
- **Nothing on the server's rules changes** (D8): the sign, the zone validation, the policy and every service are untouched; Task 2 removes only rendering logic and Task 4 only the preview.
- **Every deleted spec's coverage is restated** in Task 3.
- **No new testing pattern:** rendering is tested by request specs and the JavaScript by a system spec, per the decision tree in `AGENTS.md`; the project has no view specs and this plan adds none.
- **Names used across tasks:** `Cash::DayQuery::Entry`, `#entries`, `kind`, `movements`, `counts_in_drawer`, `web/cash/entries/entry`, `web/cash/entries/form`, `#day-entries`, `#day-entry-form`, `#entry_<id>`, `cash_entry_controller.js` — the same in every task.
