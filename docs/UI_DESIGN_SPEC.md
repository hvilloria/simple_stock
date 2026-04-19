# UI_DESIGN_SPEC.md

## Purpose

This document defines the **UI rules and visual standards** for this project.

It should help builders and reviewers produce interfaces that are:
- clean
- consistent
- professional
- easy to maintain

It is **not** a full screen-by-screen spec.
It should stay stable and compact.

---

## Product Context

Internal business application for auto parts management.
The UI should feel:
- professional
- operational
- clear
- efficient for daily use

Avoid flashy marketing-style design.
Prefer sober B2B interfaces.

---

## Design Principles

- Prefer clarity over decoration
- Prefer consistency over novelty
- Use whitespace generously
- Keep interfaces visually quiet
- Make important actions obvious
- Keep information dense enough for operational use, but never cluttered

---

## Stack Assumptions

- Rails 7+
- HAML
- TailwindCSS
- Hotwire (Turbo + Stimulus)

---

## Visual Direction

### General Style

- Neutral, professional, B2B look
- Slate / gray as the primary visual base
- Corporate red is an accent color, not the whole interface
- White cards on soft neutral backgrounds
- Subtle borders and subtle shadows
- Rounded corners, but not exaggerated

### Avoid

- Loud gradients on large surfaces
- Highly saturated UI
- Multiple competing accent colors
- Fancy effects that reduce clarity
- Inconsistent component styles from page to page

---

## Color System

### Primary Base

Use **slate** tones as the main UI foundation.

Recommended Tailwind scale:
- `slate-50` → page backgrounds / soft sections
- `slate-100` → alternate backgrounds
- `slate-200` → subtle borders
- `slate-300` → dividers
- `slate-500` → secondary text
- `slate-700` → primary action surfaces / important text
- `slate-900` → strong headings

### Brand Accent

Use corporate red sparingly.

Recommended usage:
- brand/logo
- destructive actions
- occasional high-priority actions only when justified

Do **not** make the whole UI red.

### Semantic Colors

Use semantic colors only for meaning:

- **Success** → confirmed, active, completed
- **Warning** → low stock, attention needed
- **Error** → cancelled, destructive, invalid
- **Info / Pending** → neutral process states

These colors should support the UI, not dominate it.

---

## Typography

Use the default Tailwind / system stack (Inter if available).

Recommended scale:
- `text-xs` → helper text, timestamps, badges
- `text-sm` → labels, secondary info
- `text-base` → normal content
- `text-lg` → section headers
- `text-xl` → page sub-headings
- `text-2xl` → page headings
- `text-3xl` → important page titles / dashboard metrics

Recommended weights:
- `font-medium` for labels and UI emphasis
- `font-semibold` for headings
- `font-bold` only for key numbers or page titles

Avoid overusing very large text.

---

## Spacing and Shape

### Spacing

Use consistent spacing based on Tailwind defaults.
Common spacing:
- `p-4`
- `p-6`
- `gap-4`
- `gap-6`
- `mb-4`
- `mb-6`

### Border Radius

Preferred radius:
- `rounded-lg` → simple controls
- `rounded-xl` → buttons, inputs, smaller cards
- `rounded-2xl` → main cards / containers

Avoid excessive rounding unless there is a clear reason.

---

## Shadows and Borders

Use shadows sparingly.

Preferred style:
- light border first
- soft shadow second

Recommended feel:
- subtle elevation
- no heavy floating effects

If a card already has a border and good spacing, shadow can be minimal.

---

## Core Components

### Cards

Cards are the main layout container.

Use cards for:
- forms
- dashboard sections
- lists
- summaries
- side panels

Card style:
- white background
- subtle border or subtle shadow
- `rounded-2xl`
- consistent padding

### Buttons

Keep button styles limited and consistent.

#### Primary Button
Use for the main action on the screen.

Style direction:
- dark slate background
- white text
- medium emphasis

#### Secondary Button
Use for standard non-primary actions.

Style direction:
- white background
- slate text
- border

#### Ghost Button
Use for low-emphasis actions.

Style direction:
- text only / very light hover background

#### Danger Button
Use for destructive actions only.

Style direction:
- red background
- white text

Do not create many button variants without need.

### Inputs

Inputs should be simple and readable.

Style direction:
- white background
- subtle border
- clear focus ring
- comfortable padding
- no heavy decoration

### Badges

Use badges for compact status indicators.

Examples:
- confirmed
- pending
- cancelled
- low stock
- OEM / aftermarket

Badges should be small, readable, and semantically colored.

### Tables

Tables should be clean and operational.

Rules:
- strong alignment
- readable headers
- enough row height
- subtle hover on rows
- avoid noisy borders
- use badges inside tables when useful

### Empty States

Empty states should be clear and practical.

Include:
- short title
- short explanation
- primary next action if relevant

Avoid cute or overly decorative empty states.

### Flash Messages

Flash messages should be compact and easy to scan.

Support:
- success
- error
- warning
- info

---

## Layout Rules

### App Layout

Preferred structure:
- left sidebar for main navigation
- top header for page title and local actions
- main content area with consistent padding

### Sidebar

Sidebar should feel stable and quiet.

Rules:
- light neutral background
- subtle active state
- simple icons
- strong readability

### Header

Header should include:
- page title
- optional breadcrumbs when helpful
- page-level actions

Do not overload the header.

### Content Area

Main content should use:
- cards
- grids
- clear sections
- consistent spacing

Avoid long unstructured pages.

---

## Forms

Forms should be optimized for operational speed.

Rules:
- clear grouping
- labels always visible
- errors shown near fields when possible
- main submit action easy to find
- secondary actions visually quieter

For complex forms:
- split into logical sections
- keep summaries visible when useful
- use sticky side summary only if it truly helps

---

## Dashboard Rules

Dashboards should show:
- important metrics first
- operational alerts second
- recent activity third

Avoid visual overload.

Metric cards should:
- be easy to scan
- use restrained color
- emphasize the value, not decoration

---

## Responsive Rules

Design for desktop first, but keep layouts responsive.

Recommended behavior:
- desktop: multi-column layouts
- tablet: simplified grid
- mobile: single column where needed

For mobile:
- sidebar becomes collapsible
- tables may require simplified presentation
- forms should stack vertically

Do not force desktop density into mobile.

---

## UI Implementation Rules

When building UI in this project:

- Use HAML
- Use Tailwind utility classes or small shared component classes
- Reuse existing partials before creating new ones
- Keep styling consistent with existing screens
- Keep logic out of views
- Use Stimulus only for small interaction behavior
- Prefer simple Turbo flows over custom JavaScript when possible

---

## Consistency Rules

Before introducing a new component or style:

1. Check whether a similar pattern already exists
2. Reuse the existing pattern if possible
3. Only create a new variant if there is a clear reason

Do not create visual inconsistency through one-off styling.

---

## Anti-Patterns

Avoid:
- red as the dominant page color
- large gradients on buttons or cards
- excessive shadows
- emoji-heavy interfaces
- multiple competing button styles
- business logic inside views
- inconsistent spacing and border radius
- overly decorative dashboards

---

## Review Checklist

When reviewing UI work, check:

- Is it visually consistent with the rest of the app?
- Is the main action obvious?
- Is the hierarchy clear?
- Is spacing consistent?
- Are semantic colors used correctly?
- Is the interface still calm and professional?
- Is there unnecessary visual complexity?

---

## Final Rule

When in doubt:

> choose the clearest and most consistent UI, not the most visually impressive one.
