# UI_DESIGN_SPEC.md

**Especificación de Diseño UI/UX - Sistema de Gestión de Repuestos**

Sistema interno moderno con diseño limpio y profesional para Gente del Sol.

**Stack:** Rails 7 + Hotwire + HAML + TailwindCSS

**Filosofía de Diseño:** Dashboard empresarial minimalista con esquema de colores neutro (grises), inspirado en herramientas B2B modernas. Identidad de marca (rojo corporativo) presente solo en el logo. Prioridad en usabilidad, claridad y estética profesional.

---

## Tabla de Contenidos

1. [Sistema de Diseño](#1-sistema-de-diseño)
2. [Paleta de Colores](#2-paleta-de-colores)
3. [Componentes Principales](#3-componentes-principales)
4. [Layout del Sistema](#4-layout-del-sistema)
5. [Pantallas Clave](#5-pantallas-clave)
6. [Estados y Feedback](#6-estados-y-feedback)
7. [Responsive Design](#7-responsive-design)
8. [Guías de Implementación](#8-guías-de-implementación)

---

## 1. SISTEMA DE DISEÑO

### 1.1. Principios de Diseño

- **Limpio y Minimalista:** Interfaz despejada con espacio en blanco generoso
- **Profesional:** Estética sobria y confiable para uso empresarial diario
- **Esquema Neutro:** Paleta de grises como base, sin colores vibrantes dominantes
- **Identidad Sutil:** Rojo corporativo (#DC3545) solo en logo, resto en grises
- **Funcional:** Prioridad absoluta en usabilidad y claridad sobre decoración
- **Responsive:** Funciona perfectamente en desktop, tablet y móvil

### 1.2. Tipografía

```
Familia: Inter (sistema por defecto de Tailwind)

Tamaños:
- text-xs: 12px - Timestamps, badges pequeños
- text-sm: 14px - Textos secundarios, labels
- text-base: 16px - Texto normal
- text-lg: 18px - Subtítulos
- text-xl: 20px - Títulos de sección
- text-2xl: 24px - Títulos principales
- text-3xl: 30px - Headers
- text-4xl: 36px - Números grandes en métricas

Pesos:
- font-normal: 400
- font-medium: 500
- font-semibold: 600
- font-bold: 700
```

### 1.3. Espaciado y Bordes

```
Espaciado (múltiplos de 4px):
- p-4: 16px
- p-6: 24px
- gap-4: 16px
- gap-6: 24px

Border Radius:
- rounded-lg: 8px (inputs, badges)
- rounded-xl: 12px (botones, cards pequeñas)
- rounded-2xl: 16px (cards grandes)
- rounded-3xl: 24px (modales)
- rounded-full: 9999px (avatares, pills)
```

---

## 2. PALETA DE COLORES

### 2.1. Filosofía de Color

**Esquema Neutro Empresarial:**
- Base en grises (slate) para toda la interfaz
- Sin colores vibrantes dominantes
- Rojo corporativo SOLO en logo
- Colores semánticos sutiles para estados

### 2.2. Colores Principales (Grises Slate)

```javascript
// config/tailwind.config.js
colors: {
  // Usar escala SLATE de Tailwind (más fría y profesional que gray)
  // Esta será la base de TODO el sistema
  
  slate: {
    50: '#F8FAFC',   // Backgrounds muy claros, sidebar
    100: '#F1F5F9',  // Backgrounds alternos
    200: '#E2E8F0',  // Borders suaves
    300: '#CBD5E1',  // Borders, dividers
    400: '#94A3B8',  // Texto placeholder, íconos secundarios
    500: '#64748B',  // Texto secundario
    600: '#475569',  // Texto normal
    700: '#334155',  // Botones primarios, texto importante
    800: '#1E293B',  // Headers, texto muy importante
    900: '#0F172A',  // Texto máximo contraste
  },
  
  // Rojo Corporativo (Gente del Sol) - SOLO para logo
  brand: {
    DEFAULT: '#DC3545',
    dark: '#C02E3C',
  },
}
```

### 2.3. Colores Semánticos (Sutiles, estilo Stampede)

```javascript
colors: {
  // Success (verde) - Para confirmados, activos, recibidos
  success: {
    DEFAULT: '#10B981',  // emerald-500
    bg: '#D1FAE5',       // emerald-100
    text: '#065F46',     // emerald-800
  },
  
  // Pending (azul) - Para pendientes, en proceso
  pending: {
    DEFAULT: '#3B82F6',  // blue-500
    bg: '#DBEAFE',       // blue-100
    text: '#1E40AF',     // blue-800
  },
  
  // Warning (amarillo) - Para alertas, stock bajo
  warning: {
    DEFAULT: '#F59E0B',  // amber-500
    bg: '#FEF3C7',       // amber-100
    text: '#92400E',     // amber-800
  },
  
  // Error/Rejected (rojo) - Para cancelados, rechazados
  error: {
    DEFAULT: '#EF4444',  // red-500
    bg: '#FEE2E2',       // red-100
    text: '#991B1B',     // red-800
  },
  
  // Neutral (gris) - Para inactivos, cancelados
  neutral: {
    DEFAULT: '#6B7280',  // gray-500
    bg: '#F3F4F6',       // gray-100
    text: '#374151',     // gray-700
  },
}
```

### 2.4. Sombras (Sutiles y Minimalistas)

```javascript
// tailwind.config.js
boxShadow: {
  // Sombras MUY sutiles, casi imperceptibles
  'sm': '0 1px 2px 0 rgba(0, 0, 0, 0.05)',           // Borders elevados
  'DEFAULT': '0 1px 3px 0 rgba(0, 0, 0, 0.1)',       // Cards base
  'md': '0 2px 4px -1px rgba(0, 0, 0, 0.06)',        // Dropdowns, modales
  'lg': '0 4px 6px -1px rgba(0, 0, 0, 0.08)',        // Sidebar, headers sticky
  
  // NO usar sombras grandes o "premium" - diseño plano
}
```

---

## 3. COMPONENTES PRINCIPALES

### 3.1. Metric Card (Card Limpia con Ícono)

**Descripción:** Card blanca minimalista con ícono colorido, usada para mostrar métricas importantes en el dashboard.

**Características:**
- Fondo blanco con sombra suave
- Ícono en círculo con fondo de color claro (NO gradiente en el fondo de la card)
- Título, valor grande, y cambio porcentual
- Hover effect sutil

**Uso en código:**

```haml
-# Metric Card - Ventas de Hoy
.bg-white.rounded-2xl.shadow-soft.hover:shadow-card.transition-all.p-6
  .flex.items-start.justify-between.mb-4
    .flex-1
      %p.text-sm.font-medium.text-gray-600.mb-1 Ventas de Hoy
      %h3.text-3xl.font-bold.text-gray-900 $45,200
    
    -# Ícono con fondo de color claro
    .w-12.h-12.bg-gray-100.rounded-xl.flex.items-center.justify-center.text-2xl
      💰
  
  .flex.items-center.gap-2.text-sm
    %span.text-green-600 ↗
    %span.text-green-600.font-medium +12%
    %span.text-gray-500 vs ayer
```

**Variantes de color para íconos (fondos claros):**

```haml
-# Ventas (neutral/gris)
.w-12.h-12.bg-gray-100.rounded-xl.flex.items-center.justify-center.text-2xl
  💰

-# Stock Bajo (amarillo claro)
.w-12.h-12.bg-warning-50.rounded-xl.flex.items-center.justify-center.text-2xl
  ⚠️

-# Cuentas por Cobrar (azul claro)
.w-12.h-12.bg-info-50.rounded-xl.flex.items-center.justify-center.text-2xl
  📋

-# Compras (gris claro)
.w-12.h-12.bg-gray-100.rounded-xl.flex.items-center.justify-center.text-2xl
  📥
```

### 3.2. Card Estándar (Card Blanca)

**Descripción:** Card blanca con sombra suave, para contenido general.

**Características:**
- Fondo blanco
- Sombra suave que aumenta en hover
- Border radius grande (16px)
- Header opcional con borde inferior

**Uso en código:**

```haml
.bg-white.rounded-2xl.shadow-soft.hover:shadow-card.transition-all
  -# Header con título
  .px-6.py-4.border-b.border-gray-100
    .flex.items-center.justify-between
      %h3.text-lg.font-semibold.text-gray-900 Ventas Recientes
      = link_to "Ver todas →", orders_path, class: "text-sm text-primary hover:text-primary-dark transition-colors"
  
  -# Contenido
  .p-6
    -# Tu contenido aquí
```

### 3.3. Botones (Estilo Stampede)

**Botón Primario (Gris Oscuro - Slate 700):**

```haml
= link_to new_order_path, class: "inline-flex items-center justify-center gap-2 px-4 py-2.5 bg-slate-700 hover:bg-slate-800 text-white text-sm font-medium rounded-lg shadow-sm transition-colors" do
  %span +
  %span Create PO
```

**Botón Secundario (Outline Gris):**

```haml
= link_to products_path, class: "inline-flex items-center justify-center gap-2 px-4 py-2.5 bg-white text-slate-700 text-sm font-medium border border-slate-300 rounded-lg hover:bg-slate-50 transition-colors" do
  %span Ver Productos
```

**Botón Terciario (Ghost/Text):**

```haml
= link_to "#", class: "inline-flex items-center justify-center gap-2 px-3 py-2 text-slate-600 text-sm font-medium hover:text-slate-900 hover:bg-slate-100 rounded-lg transition-colors" do
  %span Cancelar
```

**Botón Destructivo (Rojo para acciones críticas):**

```haml
= button_to cancel_order_path(@order), method: :post, class: "inline-flex items-center justify-center gap-2 px-4 py-2.5 bg-red-600 hover:bg-red-700 text-white text-sm font-medium rounded-lg shadow-sm transition-colors" do
  %span Anular
```

**Botón Ícono (Acciones en tabla):**

```haml
%button.w-8.h-8.flex.items-center.justify-center.text-slate-400.hover:text-slate-600.hover:bg-slate-100.rounded-lg.transition-colors{type: "button"}
  %span ⋮
```

**Clases CSS helper:**

```css
/* application.tailwind.css */

.btn-primary {
  @apply inline-flex items-center justify-center gap-2 px-4 py-2.5;
  @apply bg-slate-700 hover:bg-slate-800 text-white text-sm font-medium;
  @apply rounded-lg shadow-sm transition-colors;
}

.btn-secondary {
  @apply inline-flex items-center justify-center gap-2 px-4 py-2.5;
  @apply bg-white text-slate-700 text-sm font-medium border border-slate-300;
  @apply rounded-lg hover:bg-slate-50 transition-colors;
}

.btn-ghost {
  @apply inline-flex items-center justify-center gap-2 px-3 py-2;
  @apply text-slate-600 text-sm font-medium hover:text-slate-900 hover:bg-slate-100;
  @apply rounded-lg transition-colors;
}

.btn-danger {
  @apply inline-flex items-center justify-center gap-2 px-4 py-2.5;
  @apply bg-red-600 hover:bg-red-700 text-white text-sm font-medium;
  @apply rounded-lg shadow-sm transition-colors;
}

.btn-icon {
  @apply w-8 h-8 flex items-center justify-center;
  @apply text-slate-400 hover:text-slate-600 hover:bg-slate-100;
  @apply rounded-lg transition-colors;
}
```

### 3.4. Badges (Estilo Stampede)

**Estados de órdenes/registros:**

```haml
-# Received / Confirmado / Activo (verde)
%span.inline-flex.items-center.px-2.5.py-1.rounded-md.text-xs.font-medium.bg-emerald-100.text-emerald-800
  Received

-# Pending / En Proceso (azul)
%span.inline-flex.items-center.px-2.5.py-1.rounded-md.text-xs.font-medium.bg-blue-100.text-blue-800
  Pending

-# Waiting for Approval (azul claro)
%span.inline-flex.items-center.px-2.5.py-1.rounded-md.text-xs.font-medium.bg-blue-50.text-blue-700
  Waiting for Approval

-# Rejected / Cancelado (rojo)
%span.inline-flex.items-center.px-2.5.py-1.rounded-md.text-xs.font-medium.bg-red-100.text-red-800
  Rejected

-# Canceled / Anulado (gris)
%span.inline-flex.items-center.px-2.5.py-1.rounded-md.text-xs.font-medium.bg-slate-100.text-slate-700
  Canceled

-# Warning / Stock Bajo (amarillo)
%span.inline-flex.items-center.px-2.5.py-1.rounded-md.text-xs.font-medium.bg-amber-100.text-amber-800
  Stock Bajo
```

**Badges con ícono (sin emojis, más profesional):**

```haml
-# Success con dot
%span.inline-flex.items-center.gap-1.5.px-2.5.py-1.rounded-md.text-xs.font-medium.bg-emerald-100.text-emerald-800
  %span.w-1.5.h-1.5.rounded-full.bg-emerald-500
  Activo

-# Pending con dot
%span.inline-flex.items-center.gap-1.5.px-2.5.py-1.rounded-md.text-xs.font-medium.bg-blue-100.text-blue-800
  %span.w-1.5.h-1.5.rounded-full.bg-blue-500
  Pendiente
```

**Badge contador (notificaciones):**

```haml
-# Pequeño contador rojo
%span.inline-flex.items-center.justify-center.min-w-[20px].h-5.px-1.5.rounded-full.text-xs.font-semibold.bg-red-500.text-white
  12
```

### 3.5. Inputs Modernos

```haml
-# Input simple
= f.text_field :name, 
              class: "w-full px-4 py-3 border border-gray-300 rounded-xl focus:ring-2 focus:ring-primary focus:border-transparent transition-all",
              placeholder: "Nombre del producto"

-# Input con ícono
.relative
  .absolute.left-4.top-1/2.-translate-y-1/2.text-gray-400
    🔍
  %input.w-full.pl-11.pr-4.py-3.border.border-gray-300.rounded-xl.focus:ring-2.focus:ring-primary.focus:border-transparent.transition-all{
    type: "text",
    placeholder: "Buscar productos..."
  }

-# Input con error
= f.text_field :sku,
              class: "w-full px-4 py-3 border border-red-300 rounded-xl focus:ring-2 focus:ring-red-500 focus:border-transparent transition-all"
- if @product.errors[:sku].any?
  %p.text-sm.text-red-600.mt-1= @product.errors[:sku].first
```

**Clase CSS helper:**

```css
.input-modern {
  @apply w-full px-4 py-3 bg-white border border-gray-300 rounded-xl;
  @apply focus:outline-none focus:ring-2 focus:ring-primary focus:border-transparent;
  @apply transition-all placeholder:text-gray-400;
}

.input-error {
  @apply w-full px-4 py-3 bg-white border border-red-300 rounded-xl;
  @apply focus:outline-none focus:ring-2 focus:ring-red-500 focus:border-transparent;
  @apply transition-all;
}
```

### 3.6. Tablas (Estilo Stampede - Limpias y Minimalistas)

```haml
.bg-white.border.border-slate-200.rounded-lg.overflow-hidden
  %table.min-w-full.divide-y.divide-slate-200
    %thead.bg-slate-50
      %tr
        -# Checkbox para selección múltiple
        %th.w-12.px-4.py-3
          %input.w-4.h-4.rounded.border-slate-300.text-slate-700.focus:ring-slate-500{type: "checkbox"}
        
        -# Headers con sorting
        %th.px-4.py-3.text-left.text-xs.font-medium.text-slate-500.uppercase.tracking-wider
          .flex.items-center.gap-1.5
            %span CREATE DATE
            %button.text-slate-400.hover:text-slate-600{type: "button"}
              ↕
        
        %th.px-4.py-3.text-left.text-xs.font-medium.text-slate-500.uppercase.tracking-wider
          BRAND
        
        %th.px-4.py-3.text-left.text-xs.font-medium.text-slate-500.uppercase.tracking-wider
          WAREHOUSE
        
        %th.px-4.py-3.text-left.text-xs.font-medium.text-slate-500.uppercase.tracking-wider
          ORDER
        
        %th.px-4.py-3.text-left.text-xs.font-medium.text-slate-500.uppercase.tracking-wider
          STATUS
        
        %th.px-4.py-3.text-left.text-xs.font-medium.text-slate-500.uppercase.tracking-wider
          EXP.DELIVERY
        
        %th.w-20.px-4.py-3.text-right.text-xs.font-medium.text-slate-500.uppercase
          ACTION
    
    %tbody.divide-y.divide-slate-100.bg-white
      %tr.hover:bg-slate-50.transition-colors
        -# Checkbox
        %td.px-4.py-3
          %input.w-4.h-4.rounded.border-slate-300.text-slate-700.focus:ring-slate-500{type: "checkbox"}
        
        -# Fecha
        %td.px-4.py-3.whitespace-nowrap
          %p.text-sm.text-slate-900 2022-10-28
          %p.text-xs.text-slate-500 04:51 PM
        
        -# Brand
        %td.px-4.py-3.whitespace-nowrap
          %span.text-sm.text-slate-700 Alvarado Street Bakery
        
        -# Warehouse
        %td.px-4.py-3.whitespace-nowrap
          %span.text-sm.text-slate-700 TOP Warehouse
        
        -# Order
        %td.px-4.py-3.whitespace-nowrap
          %span.text-sm.font-medium.text-slate-900 PO-22-000055
        
        -# Status (badge)
        %td.px-4.py-3.whitespace-nowrap
          %span.inline-flex.px-2.5.py-1.rounded-md.text-xs.font-medium.bg-blue-100.text-blue-800
            Pending
        
        -# Expected Delivery
        %td.px-4.py-3.whitespace-nowrap
          %span.text-sm.text-slate-700 12-05-2022
        
        -# Action (menú de 3 puntos)
        %td.px-4.py-3.text-right
          %button.w-8.h-8.flex.items-center.justify-center.text-slate-400.hover:text-slate-600.hover:bg-slate-100.rounded-lg.transition-colors{type: "button"}
            ⋮
```

### 3.7. Íconos de Categoría (con gradiente decorativo)

**Para usar en listados de productos, etc.:**

```haml
-# Ícono con gradiente rojo
.w-12.h-12.rounded-xl.icon-gradient-red.flex.items-center.justify-center.text-white.text-xl.shadow-sm
  🔧

-# Ícono con gradiente verde
.w-12.h-12.rounded-xl.icon-gradient-green.flex.items-center.justify-center.text-white.text-xl.shadow-sm
  ✓

-# Ícono con gradiente gris (neutral)
.w-12.h-12.rounded-xl.icon-gradient-gray.flex.items-center.justify-center.text-white.text-xl.shadow-sm
  📦
```

---

## 4. LAYOUT DEL SISTEMA

### 4.1. Estructura General

```
┌─────────────────────────────────────────┐
│ Sidebar (fixed) │ Main Content          │
│                 │ ┌───────────────────┐ │
│                 │ │ Header (sticky)   │ │
│                 │ ├───────────────────┤ │
│                 │ │                   │ │
│                 │ │ Page Content      │ │
│                 │ │                   │ │
│                 │ └───────────────────┘ │
└─────────────────────────────────────────┘
```

### 4.2. Sidebar (Estilo Stampede - Claro y Minimalista)

**Características:**
- Fondo blanco/gris muy claro (slate-50)
- Logo con fondo rojo corporativo (único uso del rojo)
- Items de navegación en gris con íconos simples
- Hover sutil en gris claro
- Sin emojis, usar SVG o iconos de texto

```haml
%aside.w-64.bg-white.border-r.border-slate-200.flex.flex-col.h-screen.fixed.left-0.top-0
  -# Logo con colapser
  .flex.items-center.justify-between.px-6.py-4.border-b.border-slate-200
    = link_to root_path, class: "flex items-center gap-3" do
      -# Logo con fondo rojo (único uso del color corporativo)
      .w-10.h-10.rounded-lg.bg-brand.flex.items-center.justify-center.shadow-sm
        %span.font-bold.text-lg.text-white GS
      
      %div
        %h1.font-bold.text-base.text-slate-900 Gente del Sol
        %p.text-xs.text-slate-500 Sistema de Gestión
    
    -# Botón collapse (opcional)
    %button.w-6.h-6.flex.items-center.justify-center.text-slate-400.hover:text-slate-600.transition-colors{type: "button"}
      ‹
  
  -# Navegación
  %nav.flex-1.px-3.py-4.space-y-1
    = link_to web_dashboard_path, class: "flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium text-slate-700 bg-slate-100" do
      %svg.w-5.h-5{viewBox: "0 0 20 20", fill: "currentColor"}
        %path{d: "M3 4a1 1 0 011-1h12a1 1 0 011 1v2a1 1 0 01-1 1H4a1 1 0 01-1-1V4zM3 10a1 1 0 011-1h6a1 1 0 011 1v6a1 1 0 01-1 1H4a1 1 0 01-1-1v-6zM14 9a1 1 0 00-1 1v6a1 1 0 001 1h2a1 1 0 001-1v-6a1 1 0 00-1-1h-2z"}
      %span Dashboard
    
    = link_to web_products_path, class: "flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium text-slate-600 hover:text-slate-900 hover:bg-slate-50 transition-colors" do
      %svg.w-5.h-5{viewBox: "0 0 20 20", fill: "currentColor"}
        %path{d: "M3 1a1 1 0 000 2h1.22l.305 1.222a.997.997 0 00.01.042l1.358 5.43-.893.892C3.74 11.846 4.632 14 6.414 14H15a1 1 0 000-2H6.414l1-1H14a1 1 0 00.894-.553l3-6A1 1 0 0017 3H6.28l-.31-1.243A1 1 0 005 1H3zM16 16.5a1.5 1.5 0 11-3 0 1.5 1.5 0 013 0zM6.5 18a1.5 1.5 0 100-3 1.5 1.5 0 000 3z"}
      %span Productos
    
    = link_to web_orders_path, class: "flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium text-slate-600 hover:text-slate-900 hover:bg-slate-50 transition-colors" do
      %svg.w-5.h-5{viewBox: "0 0 20 20", fill: "currentColor"}
        %path{d: "M3 1a1 1 0 000 2h1.22l.305 1.222a.997.997 0 00.01.042l1.358 5.43-.893.892C3.74 11.846 4.632 14 6.414 14H15a1 1 0 000-2H6.414l1-1H14a1 1 0 00.894-.553l3-6A1 1 0 0017 3H6.28l-.31-1.243A1 1 0 005 1H3zM16 16.5a1.5 1.5 0 11-3 0 1.5 1.5 0 013 0zM6.5 18a1.5 1.5 0 100-3 1.5 1.5 0 000 3z"}
      %span Ventas
    
    = link_to web_customers_path, class: "flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium text-slate-600 hover:text-slate-900 hover:bg-slate-50 transition-colors" do
      %svg.w-5.h-5{viewBox: "0 0 20 20", fill: "currentColor"}
        %path{d: "M9 6a3 3 0 11-6 0 3 3 0 016 0zM17 6a3 3 0 11-6 0 3 3 0 016 0zM12.93 17c.046-.327.07-.66.07-1a6.97 6.97 0 00-1.5-4.33A5 5 0 0119 16v1h-6.07zM6 11a5 5 0 015 5v1H1v-1a5 5 0 015-5z"}
      %span Clientes
    
    = link_to web_purchases_path, class: "flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium text-slate-600 hover:text-slate-900 hover:bg-slate-50 transition-colors" do
      %svg.w-5.h-5{viewBox: "0 0 20 20", fill: "currentColor"}
        %path{"fill-rule": "evenodd", d: "M10 2a4 4 0 00-4 4v1H5a1 1 0 00-.994.89l-1 9A1 1 0 004 18h12a1 1 0 00.994-1.11l-1-9A1 1 0 0015 7h-1V6a4 4 0 00-4-4zm2 5V6a2 2 0 10-4 0v1h4zm-6 3a1 1 0 112 0 1 1 0 01-2 0zm7-1a1 1 0 100 2 1 1 0 000-2z", "clip-rule": "evenodd"}
      %span Compras
  
  -# Usuario (sin sección especial, parte de navegación)
  .px-3.py-4.border-t.border-slate-200
    .flex.items-center.gap-3.px-3.py-2
      .w-8.h-8.rounded-full.bg-slate-200.flex.items-center.justify-center.text-slate-600.text-sm.font-semibold
        A
      .flex-1.min-w-0
        %p.text-sm.font-medium.text-slate-700.truncate Alfredo
        %p.text-xs.text-slate-500 Admin
    
  -# Theme toggle (Light/Dark) al final
  .px-6.py-3.border-t.border-slate-200
    .flex.items-center.gap-2.text-xs.text-slate-500
      %button.flex.items-center.gap-1.5.hover:text-slate-700{type: "button"}
        ☀
        %span Light
```

### 4.3. Header (Con Breadcrumbs estilo Stampede)

```haml
%header.bg-white.border-b.border-slate-200.sticky.top-0.z-40.px-6.py-3
  .flex.items-center.justify-between
    -# Breadcrumbs + Título
    %div
      -# Breadcrumbs
      %nav.flex.items-center.gap-2.text-xs.text-slate-500.mb-1
        = link_to "Stampede", root_path, class: "hover:text-slate-700"
        %span >
        = link_to "Inventory", inventory_path, class: "hover:text-slate-700"
        %span >
        %span.text-slate-900.font-medium Purchase Orders
      
      -# Título de página
      .flex.items-center.gap-3
        %svg.w-6.h-6.text-slate-700{viewBox: "0 0 20 20", fill: "currentColor"}
          %path{d: "M3 1a1 1 0 000 2h1.22l.305 1.222a.997.997 0 00.01.042l1.358 5.43-.893.892C3.74 11.846 4.632 14 6.414 14H15a1 1 0 000-2H6.414l1-1H14a1 1 0 00.894-.553l3-6A1 1 0 0017 3H6.28l-.31-1.243A1 1 0 005 1H3z"}
        %h1.text-xl.font-semibold.text-slate-900= yield :page_title
    
    -# Acciones de usuario
    .flex.items-center.gap-3
      -# Notificaciones
      %button.relative.w-9.h-9.flex.items-center.justify-center.text-slate-500.hover:text-slate-700.hover:bg-slate-100.rounded-lg.transition-colors{
        type: "button"
      }
        %svg.w-5.h-5{viewBox: "0 0 20 20", fill: "currentColor"}
          %path{d: "M10 2a6 6 0 00-6 6v3.586l-.707.707A1 1 0 004 14h12a1 1 0 00.707-1.707L16 11.586V8a6 6 0 00-6-6zM10 18a3 3 0 01-3-3h6a3 3 0 01-3 3z"}
        -# Badge contador
        %span.absolute.top-1.right-1.w-2.h-2.bg-red-500.rounded-full.ring-2.ring-white
      
      -# Avatar + Dropdown
      .flex.items-center.gap-3
        .flex.items-center.gap-2.cursor-pointer.hover:bg-slate-50.px-2.py-1.5.rounded-lg.transition-colors
          .w-8.h-8.rounded-full.bg-slate-800.flex.items-center.justify-center
            %span.text-white.text-sm.font-semibold AD
          %div
            %p.text-sm.font-medium.text-slate-900 Adam Driver
            %p.text-xs.text-slate-500 Fleet Manager
        
        -# Menú hamburguesa (más opciones)
        %button.w-9.h-9.flex.items-center.justify-center.text-slate-500.hover:text-slate-700.hover:bg-slate-100.rounded-lg.transition-colors{type: "button"}
          %span ⋮
```

### 4.4. Main Content Area

```haml
-# En el layout principal
.flex.min-h-screen.bg-gray-50
  = render "layouts/sidebar"
  
  .flex-1.ml-64
    = render "layouts/header"
    
    %main.p-6
      -# Flash messages
      - if flash[:notice]
        .mb-6
          = render "shared/flash", type: "success", message: flash[:notice]
      - if flash[:alert]
        .mb-6
          = render "shared/flash", type: "error", message: flash[:alert]
      
      -# Page content
      = yield
```

---

## 5. PANTALLAS CLAVE

### 5.1. Dashboard

**Estructura:**

```
┌─────────────────────────────────────────┐
│ Saludo + Botón Nueva Venta              │
├─────────────────────────────────────────┤
│ ┌────┐ ┌────┐ ┌────┐ ┌────┐           │
│ │💰  │ │⚠️  │ │📋  │ │📥  │  Metrics  │
│ └────┘ └────┘ └────┘ └────┘           │
├─────────────────────────────────────────┤
│ ┌──────────────┐ ┌─────────────┐      │
│ │Ventas        │ │Stock Crítico│      │
│ │Recientes     │ │             │      │
│ └──────────────┘ └─────────────┘      │
└─────────────────────────────────────────┘
```

**4 Metric Cards (estilo minimalista):**

```haml
-# Header con saludo y acción principal
.flex.items-center.justify-between.mb-8
  %div
    %h1.text-3xl.font-bold.text-gray-900 ¡Hola, Alfredo!
    %p.text-gray-600.mt-1 Resumen de hoy
  
  = link_to new_order_path, class: "btn-primary" do
    %span +
    %span Nueva Venta

-# Grid de métricas
.grid.grid-cols-1.md:grid-cols-2.lg:grid-cols-4.gap-6.mb-8
  
  -# Ventas de Hoy (gris claro)
  .bg-white.rounded-2xl.shadow-soft.hover:shadow-card.transition-all.p-6
    .flex.items-start.justify-between.mb-4
      .flex-1
        %p.text-sm.font-medium.text-gray-600.mb-1 Ventas de Hoy
        %h3.text-3xl.font-bold.text-gray-900 $45,200
      .w-12.h-12.bg-gray-100.rounded-xl.flex.items-center.justify-center.text-2xl
        💰
    .flex.items-center.gap-2.text-sm
      %span.text-success ↗
      %span.text-success.font-medium +12%
      %span.text-gray-500 vs ayer
  
  -# Stock Bajo (amarillo claro)
  .bg-white.rounded-2xl.shadow-soft.hover:shadow-card.transition-all.p-6
    .flex.items-start.justify-between.mb-4
      .flex-1
        %p.text-sm.font-medium.text-gray-600.mb-1 Stock Bajo
        %h3.text-3xl.font-bold.text-gray-900 8
      .w-12.h-12.bg-warning-50.rounded-xl.flex.items-center.justify-center.text-2xl
        ⚠️
    .flex.items-center.gap-2.text-sm
      %span.text-warning ⚠
      %span.text-warning.font-medium Requiere atención
  
  -# Cuentas por Cobrar (azul claro)
  .bg-white.rounded-2xl.shadow-soft.hover:shadow-card.transition-all.p-6
    .flex.items-start.justify-between.mb-4
      .flex-1
        %p.text-sm.font-medium.text-gray-600.mb-1 Por Cobrar
        %h3.text-3xl.font-bold.text-gray-900 $127,400
      .w-12.h-12.bg-info-50.rounded-xl.flex.items-center.justify-center.text-2xl
        📋
    .flex.items-center.gap-2.text-sm
      %span.text-gray-500 12 clientes
  
  -# Compras del Mes (gris claro)
  .bg-white.rounded-2xl.shadow-soft.hover:shadow-card.transition-all.p-6
    .flex.items-start.justify-between.mb-4
      .flex-1
        %p.text-sm.font-medium.text-gray-600.mb-1 Compras del Mes
        %h3.text-3xl.font-bold.text-gray-900 $82,500
      .w-12.h-12.bg-gray-100.rounded-xl.flex.items-center.justify-center.text-2xl
        📥
    .flex.items-center.gap-2.text-sm
      %span.text-gray-500 5 compras

-# Grid de contenido secundario
.grid.grid-cols-1.lg:grid-cols-2.gap-6
  -# Ventas recientes
  .bg-white.rounded-2xl.shadow-soft
    .px-6.py-4.border-b.border-gray-100
      .flex.items-center.justify-between
        %h3.text-lg.font-semibold.text-gray-900 Ventas Recientes
        = link_to "Ver todas →", orders_path, class: "text-sm text-primary hover:text-primary-dark"
    .p-6
      -# Lista de ventas...
  
  -# Productos con stock crítico
  .bg-white.rounded-2xl.shadow-soft
    .px-6.py-4.border-b.border-gray-100
      .flex.items-center.justify-between
        %h3.text-lg.font-semibold.text-gray-900 Stock Crítico
        = link_to "Ver todos →", products_path(low_stock: true), class: "text-sm text-primary hover:text-primary-dark"
    .p-6
      -# Lista de productos...
```

### 5.2. Listado de Productos

**Características:**
- Búsqueda con filtros
- Cards de producto con hover effect
- Stock badge con color semántico
- Acciones inline

```haml
-# Header
.flex.items-center.justify-between.mb-6
  %h1.text-3xl.font-bold.text-gray-900 Productos
  = link_to new_product_path, class: "btn-primary" do
    %span +
    %span Nuevo Producto

-# Filtros y búsqueda
.bg-white.rounded-2xl.shadow-soft.p-6.mb-6
  .flex.flex-col.md:flex-row.gap-4
    -# Búsqueda
    .flex-1
      .relative
        .absolute.left-4.top-1/2.-translate-y-1/2.text-gray-400
          🔍
        %input.w-full.pl-11.pr-4.py-3.border.border-gray-300.rounded-xl.focus:ring-2.focus:ring-primary{
          type: "text",
          placeholder: "Buscar por SKU, nombre o marca...",
          name: "q"
        }
    
    -# Filtro por categoría
    = select_tag :category, 
                 options_for_select([["Todas las categorías", ""]] + Product::CATEGORIES.map { |c| [c.titleize, c] }),
                 class: "px-4 py-3 border border-gray-300 rounded-xl focus:ring-2 focus:ring-primary"
    
    -# Filtro por tipo
    = select_tag :product_type,
                 options_for_select([["Todos los tipos", ""], ["OEM", "oem"], ["Aftermarket", "aftermarket"]]),
                 class: "px-4 py-3 border border-gray-300 rounded-xl focus:ring-2 focus:ring-primary"

-# Lista de productos
.bg-white.rounded-2xl.shadow-soft.divide-y.divide-gray-100
  - @products.each do |product|
    .flex.items-center.gap-6.p-6.hover:bg-gray-50.transition-all.cursor-pointer
      
      -# Ícono de categoría con gradiente decorativo
      .w-16.h-16.rounded-xl.icon-gradient-gray.flex.items-center.justify-center.text-white.text-2xl.shadow-sm
        📦
      
      -# Info del producto
      .flex-1
        .flex.items-center.gap-3.mb-2
          %p.font-mono.text-sm.font-semibold.text-gray-900= product.sku
          - if product.oem?
            %span.px-2.py-1.bg-gray-100.text-gray-700.rounded-lg.text-xs.font-medium OEM
          - elsif product.aftermarket?
            %span.px-2.py-1.bg-blue-50.text-blue-700.rounded-lg.text-xs.font-medium Aftermarket
        
        %h3.font-semibold.text-gray-900.mb-2= product.name
        
        .flex.gap-3.text-sm.text-gray-600
          %span= product.brand
          - if product.category
            %span •
            %span= product.category.titleize
          - if product.origin
            %span •
            %span= "🌍 #{product.origin.titleize}"
      
      -# Stock
      .text-center
        %p.text-xs.text-gray-500.mb-2 Stock
        - if product.current_stock > 10
          %span.inline-flex.px-3.py-2.bg-success-light.text-success-dark.rounded-xl.font-bold.text-sm
            ✓
            = product.current_stock
        - elsif product.current_stock > 0
          %span.inline-flex.px-3.py-2.bg-warning-light.text-warning-dark.rounded-xl.font-bold.text-sm
            ⚠
            = product.current_stock
        - else
          %span.inline-flex.px-3.py-2.bg-red-100.text-red-800.rounded-xl.font-bold.text-sm
            ✕ 0
      
      -# Precio
      .text-right
        %p.text-xs.text-gray-500.mb-2 Precio
        %p.text-xl.font-bold.text-gray-900= number_to_currency(product.price_unit)
      
      -# Acciones
      .flex.gap-2
        = link_to edit_product_path(product), class: "w-10 h-10 flex items-center justify-center border border-gray-300 rounded-xl hover:bg-gray-50 transition-colors" do
          ✏️
        = link_to product_path(product), class: "w-10 h-10 flex items-center justify-center border border-gray-300 rounded-xl hover:bg-gray-50 transition-colors" do
          👁️
```

### 5.3. Nueva Venta

**Layout 2 columnas:**
- Izquierda (2/3): Formulario (cliente + productos)
- Derecha (1/3): Resumen sticky

```haml
.grid.grid-cols-1.lg:grid-cols-3.gap-6
  
  -# Columna izquierda: Formulario
  .lg:col-span-2
    = form_with model: @order, url: orders_path, local: true do |f|
      
      -# Información del cliente
      .bg-white.rounded-2xl.shadow-soft.p-6.mb-6
        %h3.text-lg.font-semibold.text-gray-900.mb-4 Cliente
        
        -# Tipo de venta (radio buttons visuales)
        .mb-6
          %label.block.text-sm.font-medium.text-gray-700.mb-3 Tipo de Venta
          .grid.grid-cols-2.gap-4
            %label.relative.flex.items-center.p-4.border-2.border-gray-200.rounded-xl.cursor-pointer.hover:border-primary.transition-colors
              = f.radio_button :order_type, "cash", class: "sr-only peer"
              .w-full.flex.items-center.gap-3
                .w-5.h-5.rounded-full.border-2.border-gray-300.peer-checked:border-primary.peer-checked:bg-primary.transition-colors
                %div
                  %p.font-medium.text-gray-900 Contado
                  %p.text-xs.text-gray-500 Pago inmediato
            
            %label.relative.flex.items-center.p-4.border-2.border-gray-200.rounded-xl.cursor-pointer.hover:border-primary.transition-colors
              = f.radio_button :order_type, "credit", class: "sr-only peer"
              .w-full.flex.items-center.gap-3
                .w-5.h-5.rounded-full.border-2.border-gray-300.peer-checked:border-primary.peer-checked:bg-primary.transition-colors
                %div
                  %p.font-medium.text-gray-900 Cuenta Corriente
                  %p.text-xs.text-gray-500 A crédito
        
        -# Selector de cliente
        .mb-4
          = f.label :customer_id, "Cliente", class: "block text-sm font-medium text-gray-700 mb-2"
          = f.select :customer_id, 
                     options_for_select(@customers.map { |c| [c.name, c.id] }),
                     { include_blank: "Seleccionar cliente" },
                     class: "input-modern"
        
        -# Canal (opcional)
        = f.label :channel, "Canal de Venta", class: "block text-sm font-medium text-gray-700 mb-2"
        = f.select :channel,
                   options_for_select([["Mostrador", "counter"], ["WhatsApp", "whatsapp"], ["Mercado Libre", "mercadolibre"]]),
                   { include_blank: "Seleccionar canal" },
                   class: "input-modern"
      
      -# Productos
      .bg-white.rounded-2xl.shadow-soft.p-6
        .flex.items-center.justify-between.mb-4
          %h3.text-lg.font-semibold.text-gray-900 Productos
          %button.btn-secondary{type: "button", data: {action: "click->order-form#addItem"}}
            %span +
            %span Agregar Producto
        
        -# Lista de productos seleccionados
        #order-items
          -# Se llenan dinámicamente con Stimulus
  
  -# Columna derecha: Resumen
  .lg:col-span-1
    .bg-white.rounded-2xl.shadow-soft.p-6.sticky.top-24
      %h3.text-lg.font-semibold.text-gray-900.mb-6 Resumen
      
      .space-y-3.mb-6
        .flex.justify-between.text-sm
          %span.text-gray-600 Subtotal
          %span.font-medium.text-gray-900 $0.00
        
        .flex.justify-between.text-sm
          %span.text-gray-600 Items
          %span.font-medium.text-gray-900 0
      
      .border-t.border-gray-200.pt-4.mb-6
        .flex.justify-between
          %span.text-base.font-semibold.text-gray-900 Total
          %span.text-2xl.font-bold.text-gray-900 $0.00
      
      = f.submit "Crear Venta", class: "btn-primary w-full", disabled: true
```

---

## 6. ESTADOS Y FEEDBACK

### 6.1. Loading States

**Skeleton para cards:**

```haml
.animate-pulse.bg-white.rounded-2xl.shadow-soft.p-6
  .flex.items-center.gap-4
    .w-12.h-12.bg-gray-200.rounded-xl
    .flex-1
      .h-4.bg-gray-200.rounded.mb-2
      .h-4.bg-gray-200.rounded.w-3/4
```

**Spinner inline:**

```haml
.inline-flex.items-center.gap-2.text-gray-600
  %svg.animate-spin.h-5.w-5{viewBox: "0 0 24 24"}
    %circle.opacity-25{cx: "12", cy: "12", r: "10", stroke: "currentColor", "stroke-width": "4", fill: "none"}
    %path.opacity-75{fill: "currentColor", d: "M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"}
  %span Cargando...
```

### 6.2. Empty States

```haml
.bg-white.rounded-2xl.shadow-soft.p-16.text-center
  .inline-flex.w-20.h-20.rounded-full.bg-gray-100.items-center.justify-center.text-4xl.mb-4
    📦
  %h3.text-xl.font-bold.text-gray-900.mb-2 No hay productos
  %p.text-gray-600.mb-6 Comenzá agregando tu primer producto al inventario
  = link_to new_product_path, class: "btn-primary" do
    %span +
    %span Crear Producto
```

### 6.3. Flash Messages / Toasts

**Componente reutilizable:**

```haml
-# app/views/shared/_flash.html.haml
- type_classes = {
    success: "border-success bg-success-50 text-success-dark",
    error: "border-primary bg-primary-50 text-primary-dark",
    warning: "border-warning bg-warning-50 text-warning-dark",
    info: "border-info bg-info-50 text-info-dark"
  }

.rounded-xl.border-l-4.p-4.shadow-soft.flex.gap-3.items-start{class: type_classes[type.to_sym]}
  -# Ícono
  - if type.to_sym == :success
    .w-10.h-10.rounded-xl.bg-success.flex.items-center.justify-center.text-white.flex-shrink-0
      ✓
  - elsif type.to_sym == :error
    .w-10.h-10.rounded-xl.bg-primary.flex.items-center.justify-center.text-white.flex-shrink-0
      ✕
  - elsif type.to_sym == :warning
    .w-10.h-10.rounded-xl.bg-warning.flex.items-center.justify-center.text-white.flex-shrink-0
      ⚠
  - else
    .w-10.h-10.rounded-xl.bg-info.flex.items-center.justify-center.text-white.flex-shrink-0
      ℹ
  
  -# Mensaje
  .flex-1
    - if type.to_sym == :success
      %h4.font-semibold.mb-1 Éxito
    - elsif type.to_sym == :error
      %h4.font-semibold.mb-1 Error
    - elsif type.to_sym == :warning
      %h4.font-semibold.mb-1 Atención
    - else
      %h4.font-semibold.mb-1 Información
    
    %p.text-sm= message
```

**Uso:**

```haml
- if flash[:notice]
  .mb-6
    = render "shared/flash", type: "success", message: flash[:notice]

- if flash[:alert]
  .mb-6
    = render "shared/flash", type: "error", message: flash[:alert]
```

### 6.4. Modales

```haml
-# Modal base con Stimulus
%div{data: {controller: "modal", action: "keydown@window->modal#closeOnEscape"}}
  -# Overlay
  .fixed.inset-0.bg-gray-900.bg-opacity-50.z-50.hidden{data: {modal_target: "overlay"}}
  
  -# Modal
  .fixed.inset-0.z-50.overflow-y-auto.hidden{data: {modal_target: "container"}}
    .flex.items-center.justify-center.min-h-screen.p-4
      .bg-white.rounded-3xl.shadow-premium.max-w-lg.w-full.p-6
        -# Header
        .flex.items-center.justify-between.mb-6
          %h3.text-xl.font-bold.text-gray-900 Título del Modal
          %button.w-8.h-8.flex.items-center.justify-center.text-gray-400.hover:text-gray-600.transition-colors{
            type: "button",
            data: {action: "click->modal#close"}
          }
            ✕
        
        -# Body
        .mb-6
          %p.text-gray-600 Contenido del modal...
        
        -# Footer con acciones
        .flex.gap-3.justify-end
          %button.btn-ghost{type: "button", data: {action: "click->modal#close"}}
            Cancelar
          %button.btn-primary{type: "submit"}
            Confirmar
```

---

## 7. RESPONSIVE DESIGN

### 7.1. Breakpoints

```
sm: 640px - Mobile grande
md: 768px - Tablet
lg: 1024px - Desktop
xl: 1280px - Desktop grande
2xl: 1536px - Desktop extra grande
```

### 7.2. Grid Adaptativo

```haml
-# 4 columnas en desktop, 2 en tablet, 1 en móvil
.grid.grid-cols-1.md:grid-cols-2.lg:grid-cols-4.gap-6

-# 3 columnas con ajuste proporcional
.grid.grid-cols-1.md:grid-cols-2.lg:grid-cols-3.gap-6

-# Layout de detalle: 2/3 y 1/3
.grid.grid-cols-1.lg:grid-cols-3.gap-6
  .lg:col-span-2
    -# Contenido principal
  .lg:col-span-1
    -# Sidebar
```

### 7.3. Sidebar Responsiva

```haml
-# Sidebar en desktop
%aside.w-64.bg-slate-900.text-white.flex.flex-col.shadow-premium.h-screen.fixed.left-0.top-0.hidden.lg:flex
  -# Contenido del sidebar

-# Botón de menú móvil (en header)
%button.lg:hidden.w-10.h-10.flex.items-center.justify-center.border.border-gray-300.rounded-xl{
  type: "button",
  data: {action: "click->sidebar#toggle"}
}
  ☰
```

### 7.4. Utilidades Responsive Comunes

```haml
-# Ocultar en móvil, mostrar en desktop
.hidden.lg:block

-# Mostrar en móvil, ocultar en desktop
.block.lg:hidden

-# Stack vertical en móvil, horizontal en desktop
.flex.flex-col.lg:flex-row

-# Texto responsive
.text-2xl.lg:text-3xl

-# Padding responsive
.p-4.lg:p-6

-# Grid responsive con gap
.grid.grid-cols-1.md:grid-cols-2.lg:grid-cols-3.gap-4.lg:gap-6
```

---

## 8. GUÍAS DE IMPLEMENTACIÓN

### 8.1. Checklist de Implementación

**Configuración inicial:**
- [ ] Actualizar `tailwind.config.js` con colores y sombras personalizadas
- [ ] Agregar clases de gradientes para íconos en `application.tailwind.css`
- [ ] Configurar layout base con sidebar y header
- [ ] Crear partials reutilizables en `app/views/shared/`

**Componentes base:**
- [ ] Implementar sistema de flash messages
- [ ] Crear partial para metric cards
- [ ] Crear partial para cards estándar
- [ ] Implementar clases helper de botones
- [ ] Implementar clases helper de inputs

**Vistas principales:**
- [ ] Dashboard con métricas
- [ ] Listado de productos con filtros
- [ ] Formulario de nuevo producto
- [ ] Formulario de nueva venta
- [ ] Listado de ventas
- [ ] Detalle de cliente con saldo

**Interactividad:**
- [ ] Stimulus controller para búsqueda con debounce
- [ ] Stimulus controller para modales
- [ ] Stimulus controller para formulario de venta dinámico
- [ ] Turbo Frames para actualización parcial

### 8.2. Estructura de Archivos CSS

```css
/* app/assets/stylesheets/application.tailwind.css */

@tailwind base;
@tailwind components;
@tailwind utilities;

/* === Gradientes para íconos === */
@layer utilities {
  .icon-gradient-red {
    background: linear-gradient(135deg, #F87171 0%, #DC3545 100%);
  }
  
  .icon-gradient-green {
    background: linear-gradient(135deg, #6EE7B7 0%, #10B981 100%);
  }
  
  .icon-gradient-yellow {
    background: linear-gradient(135deg, #FCD34D 0%, #F59E0B 100%);
  }
  
  .icon-gradient-blue {
    background: linear-gradient(135deg, #93C5FD 0%, #3B82F6 100%);
  }
  
  .icon-gradient-gray {
    background: linear-gradient(135deg, #E5E7EB 0%, #9CA3AF 100%);
  }
}

/* === Componentes reutilizables === */
@layer components {
  /* Botones */
  .btn-primary {
    @apply inline-flex items-center justify-center gap-2 px-5 py-2.5;
    @apply bg-primary hover:bg-primary-dark text-white font-medium;
    @apply rounded-xl shadow-soft hover:shadow-card transition-all;
  }
  
  .btn-secondary {
    @apply inline-flex items-center justify-center gap-2 px-5 py-2.5;
    @apply bg-white text-gray-700 font-medium border border-gray-300;
    @apply rounded-xl hover:bg-gray-50 transition-all;
  }
  
  .btn-ghost {
    @apply inline-flex items-center justify-center gap-2 px-5 py-2.5;
    @apply text-gray-700 font-medium hover:bg-gray-100;
    @apply rounded-xl transition-all;
  }
  
  .btn-danger {
    @apply inline-flex items-center justify-center gap-2 px-5 py-2.5;
    @apply bg-red-600 hover:bg-red-700 text-white font-medium;
    @apply rounded-xl shadow-soft transition-all;
  }
  
  /* Inputs */
  .input-modern {
    @apply w-full px-4 py-3 bg-white border border-gray-300 rounded-xl;
    @apply focus:outline-none focus:ring-2 focus:ring-primary focus:border-transparent;
    @apply transition-all placeholder:text-gray-400;
  }
  
  .input-error {
    @apply w-full px-4 py-3 bg-white border border-red-300 rounded-xl;
    @apply focus:outline-none focus:ring-2 focus:ring-red-500 focus:border-transparent;
    @apply transition-all;
  }
  
  /* Cards */
  .card {
    @apply bg-white rounded-2xl shadow-soft hover:shadow-card transition-all;
  }
  
  .card-header {
    @apply px-6 py-4 border-b border-gray-100;
  }
  
  .card-body {
    @apply p-6;
  }
}
```

### 8.3. Uso con Cursor/Claude

Para generar código consistente con este diseño, usar el siguiente contexto:

```
@docs/UI_DESIGN_SPEC.md

Crear [pantalla/componente] siguiendo el diseño minimalista con:
- Rojo primary (#DC3545) para acciones principales
- Colores semánticos (verde, amarillo) para estados
- Cards blancas con sombra suave
- Sin gradientes en backgrounds grandes
- Tipografía Inter
```

**Ejemplos de prompts efectivos:**

```
@docs/UI_DESIGN_SPEC.md
Crear el dashboard con las 4 metric cards (ventas, stock bajo, por cobrar, compras)
```

```
@docs/UI_DESIGN_SPEC.md
Crear el listado de productos con búsqueda, filtros y cards de producto
```

```
@docs/UI_DESIGN_SPEC.md
Crear formulario de nueva venta con selección de cliente y productos dinámicos
```

### 8.4. Testing Visual

**Checklist de verificación:**
- [ ] Colores coinciden con la paleta definida
- [ ] Espaciados son consistentes (múltiplos de 4px)
- [ ] Border radius son consistentes
- [ ] Hover states funcionan en todos los botones/links
- [ ] Focus states son visibles en inputs
- [ ] Responsive funciona en mobile/tablet/desktop
- [ ] Sidebar es accesible en móvil
- [ ] Flash messages se ven correctamente
- [ ] Loading states son claros

---

**Versión:** 3.0 - Clean Professional Design  
**Última actualización:** Noviembre 2025

---

## Notas para Desarrolladores

### Diferencias clave vs versión anterior:

1. **Colores:** Paleta simplificada, rojo como único acento vibrante
2. **Gradientes:** Solo para íconos pequeños, NO para cards o botones grandes
3. **Metric Cards:** Fondo blanco con íconos en círculos de color claro
4. **Botones:** Primario rojo sólido, secundario outline, sin gradientes
5. **Estilo general:** Minimalista y profesional, no saturado de colores

### Principios de uso de color:

- **Rojo primary:** Botones principales, enlaces importantes, alertas críticas
- **Verde:** Estados de éxito, confirmaciones, stock alto
- **Amarillo:** Warnings, stock bajo, atención necesaria
- **Azul:** Información neutral, badges informativos
- **Gris:** Base de la interfaz, texto, bordes, backgrounds neutros

### Cuándo usar gradientes:

✅ **SÍ usar gradientes:**
- Íconos pequeños decorativos (12x12, 16x16px)
- Avatares de usuario
- Badges especiales (muy ocasionalmente)

❌ **NO usar gradientes:**
- Botones principales
- Cards grandes
- Backgrounds de secciones
- Headers

---

**¿Preguntas o aclaraciones?** Consultar al equipo de diseño o revisar ejemplos en el código existente.