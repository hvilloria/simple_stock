# UI_DESIGN_SPEC.md

**Especificación de Diseño UI/UX - Sistema de Gestión de Repuestos**

Sistema interno moderno con diseño visual premium para Gente del Sol.

**Stack:** Rails 7 + Hotwire + HAML + TailwindCSS

**Filosofía de Diseño:** Dashboard moderno con gradientes, cards coloridos, y experiencia visual premium, manteniendo la identidad de marca de Gente del Sol.

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

- **Moderno y Visual:** Uso de gradientes y colores vibrantes
- **Premium pero Funcional:** Estética atractiva sin sacrificar usabilidad
- **Identidad de Marca:** Mantener el rojo corporativo de Gente del Sol
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

### 2.1. Colores Principales (Gente del Sol)

```javascript
// config/tailwind.config.js
colors: {
  primary: {
    DEFAULT: '#DC3545',
    dark: '#C02E3C',
    light: '#FDE8EA',
    50: '#FEF5F5',
  },
}
```

### 2.2. Colores para Dashboard (Vibrantes)

```javascript
colors: {
  // Teal/Cyan - Para ventas y métricas positivas
  teal: {
    DEFAULT: '#14B8A6',
    dark: '#0F766E',
    light: '#99F6E4',
  },
  
  // Coral/Naranja - Para alertas y warnings
  coral: {
    DEFAULT: '#FB923C',
    dark: '#EA580C',
    light: '#FED7AA',
  },
  
  // Púrpura - Para métricas secundarias
  purple: {
    DEFAULT: '#A855F7',
    dark: '#7C3AED',
    light: '#E9D5FF',
  },
  
  // Azul - Para información
  blue: {
    DEFAULT: '#3B82F6',
    dark: '#1E40AF',
    light: '#DBEAFE',
  },
}
```

### 2.3. Gradientes CSS

```css
/* application.tailwind.css */

.gradient-teal {
  background: linear-gradient(135deg, #5EEAD4 0%, #14B8A6 100%);
}

.gradient-coral {
  background: linear-gradient(135deg, #FCA5A5 0%, #FB923C 50%, #F87171 100%);
}

.gradient-purple {
  background: linear-gradient(135deg, #C084FC 0%, #A855F7 100%);
}

.gradient-blue {
  background: linear-gradient(135deg, #93C5FD 0%, #3B82F6 100%);
}

.gradient-primary {
  background: linear-gradient(135deg, #F87171 0%, #DC3545 100%);
}
```

### 2.4. Sombras Premium

```javascript
// tailwind.config.js
boxShadow: {
  'soft': '0 2px 15px -3px rgba(0, 0, 0, 0.07)',
  'card': '0 4px 6px -1px rgba(0, 0, 0, 0.1)',
  'card-hover': '0 10px 15px -3px rgba(0, 0, 0, 0.1)',
  'premium': '0 20px 25px -5px rgba(0, 0, 0, 0.1)',
  'glow-teal': '0 0 20px rgba(20, 184, 166, 0.3)',
  'glow-primary': '0 0 20px rgba(220, 53, 69, 0.3)',
}
```

---

## 3. COMPONENTES PRINCIPALES

### 3.1. Metric Card (Card con Gradiente)

**Descripción:** Card destacada con gradiente de fondo, usada para mostrar métricas importantes.

**Características:**
- Gradiente de fondo
- Ícono en círculo con fondo semi-transparente
- Título, valor grande, y cambio porcentual
- Texto blanco sobre gradiente

**Uso en código:**

```haml
-# Ejemplo de uso
.relative.overflow-hidden.rounded-2xl.shadow-card.hover:shadow-card-hover.transition-all
  -# Gradiente de fondo
  .absolute.inset-0.gradient-teal
  
  -# Contenido
  .relative.p-6.text-white
    .flex.items-start.justify-between.mb-4
      .flex-1
        %p.text-sm.font-medium.text-white.opacity-90.mb-1 Ventas de Hoy
        %h3.text-3xl.font-bold $45,200
      
      .w-12.h-12.bg-white.bg-opacity-20.rounded-xl.flex.items-center.justify-center.text-2xl
        💰
    
    .flex.items-center.gap-2.text-sm
      %span ↗
      %span +12%
      %span.opacity-75 vs ayer
```

**Variantes de color:**
- `.gradient-teal` - Para ventas y métricas positivas
- `.gradient-coral` - Para alertas y stock bajo
- `.gradient-purple` - Para cuentas por cobrar
- `.gradient-blue` - Para compras
- `.gradient-primary` - Para métricas principales

### 3.2. Premium Card (Card Blanca Elevada)

**Descripción:** Card blanca con sombra suave, para contenido general.

**Características:**
- Fondo blanco
- Sombra suave que aumenta en hover
- Border radius grande (16px)
- Header opcional con borde de color

**Uso en código:**

```haml
.bg-white.rounded-2xl.shadow-soft.hover:shadow-premium.transition-all
  -# Header opcional con línea de color
  .h-1.gradient-teal.rounded-t-2xl
  
  -# Header con título
  .px-6.py-4.border-b.border-gray-100
    .flex.items-center.justify-between
      %h3.text-lg.font-semibold.text-gray-900 Ventas Recientes
      = link_to "Ver todas →", orders_path, class: "text-sm text-primary hover:text-primary-dark"
  
  -# Contenido
  .p-6
    -# Tu contenido aquí
```

### 3.3. Botones Modernos

**Botón Primario con Gradiente:**

```haml
= link_to new_order_path, class: "inline-flex items-center gap-2 px-5 py-2.5 gradient-teal text-white font-medium rounded-xl shadow-soft hover:shadow-glow-teal transition-all" do
  %span +
  %span Nueva Venta
```

**Botón Secundario:**

```haml
= link_to products_path, class: "inline-flex items-center gap-2 px-5 py-2.5 bg-white text-gray-700 font-medium border border-gray-200 rounded-xl shadow-soft hover:shadow-card transition-all" do
  %span Ver Productos
```

**Clases CSS helper:**

```css
.btn-primary {
  @apply inline-flex items-center gap-2 px-5 py-2.5;
  @apply bg-primary hover:bg-primary-dark text-white font-medium;
  @apply rounded-xl shadow-soft hover:shadow-card transition-all;
}

.btn-gradient-teal {
  @apply inline-flex items-center gap-2 px-5 py-2.5;
  @apply gradient-teal text-white font-medium;
  @apply rounded-xl shadow-soft hover:shadow-glow-teal transition-all;
}

.btn-secondary {
  @apply inline-flex items-center gap-2 px-5 py-2.5;
  @apply bg-white text-gray-700 font-medium border border-gray-200;
  @apply rounded-xl shadow-soft hover:shadow-card transition-all;
}
```

### 3.4. Badges Modernos

**Con gradiente:**

```haml
%span.inline-flex.items-center.gap-1.px-3.py-1.rounded-full.text-xs.font-medium.gradient-teal.text-white.shadow-sm
  %span ✓
  %span Activo
```

**Colores sólidos:**

```haml
-# Success
%span.inline-flex.px-3.py-1.rounded-full.text-xs.font-medium.bg-green-100.text-green-800
  Activo

-# Warning
%span.inline-flex.px-3.py-1.rounded-full.text-xs.font-medium.bg-yellow-100.text-yellow-800
  Stock Bajo

-# Error
%span.inline-flex.px-3.py-1.rounded-full.text-xs.font-medium.bg-red-100.text-red-800
  Cancelado
```

### 3.5. Inputs Modernos

```haml
-# Input simple
= f.text_field :name, 
              class: "w-full px-4 py-3 border border-gray-200 rounded-xl focus:ring-2 focus:ring-primary focus:border-transparent transition-all",
              placeholder: "Nombre del producto"

-# Input con ícono
.relative
  .absolute.left-4.top-1/2.-translate-y-1/2.text-gray-400
    🔍
  %input.w-full.pl-11.pr-4.py-3.border.border-gray-200.rounded-xl{
    type: "text",
    placeholder: "Buscar productos..."
  }
```

**Clase CSS helper:**

```css
.input-modern {
  @apply w-full px-4 py-3 bg-white border border-gray-200 rounded-xl;
  @apply focus:outline-none focus:ring-2 focus:ring-primary focus:border-transparent;
  @apply transition-all;
}
```

### 3.6. Tablas Modernas

```haml
.bg-white.rounded-2xl.shadow-soft.overflow-hidden
  %table.min-w-full
    %thead.bg-gray-50
      %tr
        %th.px-6.py-4.text-left.text-xs.font-semibold.text-gray-600.uppercase Código
        %th.px-6.py-4.text-left.text-xs.font-semibold.text-gray-600.uppercase Nombre
        %th.px-6.py-4.text-right.text-xs.font-semibold.text-gray-600.uppercase Precio
    
    %tbody.divide-y.divide-gray-100
      %tr.hover:bg-gray-50.transition-colors.cursor-pointer
        %td.px-6.py-4.font-mono.font-semibold HDC001
        %td.px-6.py-4 Disco de Freno
        %td.px-6.py-4.text-right.font-bold $4,500
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

### 4.2. Sidebar Moderna

**Características:**
- Fondo con gradiente oscuro
- Logo con gradiente en círculo
- Items de navegación con hover suave
- Usuario al final con avatar

```haml
%aside.w-64.bg-gradient-to-b.from-slate-900.to-slate-800.text-white.flex.flex-col.shadow-premium
  -# Logo
  .px-6.py-8
    .flex.items-center.gap-3
      .w-12.h-12.rounded-2xl.gradient-primary.flex.items-center.justify-center.shadow-glow-primary
        %span.font-bold.text-xl GS
      
      .flex-1
        %h1.font-bold.text-lg Gente del Sol
        %p.text-xs.text-gray-400 Sistema de Gestión
  
  -# Navegación
  %nav.flex-1.px-4.py-6.space-y-2
    = link_to dashboard_path, class: "flex items-center gap-3 px-3 py-3 rounded-xl text-sm font-medium bg-white bg-opacity-10 text-white" do
      %span 📊
      %span Dashboard
    
    = link_to products_path, class: "flex items-center gap-3 px-3 py-3 rounded-xl text-sm font-medium text-gray-300 hover:bg-white hover:bg-opacity-5 transition-all" do
      %span 📦
      %span Productos
  
  -# Usuario
  .px-4.py-6.border-t.border-white.border-opacity-10
    .flex.items-center.gap-3
      .w-10.h-10.rounded-full.gradient-teal.flex.items-center.justify-center.text-white.font-bold
        A
      .flex-1
        %p.text-sm.font-medium Alfredo
        %p.text-xs.text-gray-400 Admin
```

### 4.3. Header Moderno

```haml
%header.bg-white.border-b.border-gray-100.shadow-soft.sticky.top-0.z-40.px-6.py-4
  .flex.items-center.justify-between
    -# Título
    %h2.text-xl.font-bold.text-gray-900 Dashboard
    
    -# Acciones
    .flex.items-center.gap-3
      -# Búsqueda
      .relative
        .absolute.left-4.top-1/2.-translate-y-1/2.text-gray-400 🔍
        %input.w-64.pl-11.pr-4.py-2.border.border-gray-200.rounded-xl{placeholder: "Buscar..."}
      
      -# Notificaciones
      %button.w-10.h-10.flex.items-center.justify-center.bg-white.border.border-gray-200.rounded-xl.relative
        🔔
        .absolute.top-0.right-0.w-2.h-2.bg-primary.rounded-full
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

**4 Metric Cards con gradientes:**
- Ventas de Hoy (gradient-teal)
- Stock Bajo (gradient-coral)
- Cuentas por Cobrar (gradient-purple)
- Compras del Mes (gradient-blue)

### 5.2. Listado de Productos

**Características:**
- Búsqueda con ícono
- Filtros por categoría y estado
- Cards de producto con hover effect
- Stock badge con color
- Menú de acciones

```haml
-# Cada producto como card
.flex.items-center.gap-6.p-6.hover:bg-gray-50.transition-all.cursor-pointer
  -# Ícono de categoría
  .w-16.h-16.rounded-xl.gradient-teal.flex.items-center.justify-center.text-2xl
    📦
  
  -# Info
  .flex-1
    %p.font-mono.text-xs.text-gray-500 HDC001
    %h3.font-semibold.text-gray-900 Disco de Freno Delantero
    .flex.gap-2.mt-2
      %span.text-xs.text-gray-600 Honda
      %span.px-2.py-1.bg-gray-100.text-gray-700.rounded-full.text-xs Frenos
  
  -# Stock
  .text-center
    %p.text-xs.text-gray-500 Stock
    %span.inline-flex.px-3.py-2.bg-green-100.text-green-700.rounded-xl.font-bold ✓ 12
  
  -# Precio
  .text-right
    %p.text-xs.text-gray-500 Precio
    %p.text-xl.font-bold $4,500
```

### 5.3. Nueva Venta

**Layout 2 columnas:**
- Izquierda (2/3): Formulario (Info + Productos)
- Derecha (1/3): Resumen sticky

**Características:**
- Tipo de venta como radio cards visuales
- Autocomplete para buscar productos
- Resumen con total grande
- Botón deshabilitado si no hay items

---

## 6. ESTADOS Y FEEDBACK

### 6.1. Loading

**Skeleton:**

```haml
.animate-pulse
  .h-4.bg-gray-200.rounded.mb-2
  .h-4.bg-gray-200.rounded.w-3/4
```

### 6.2. Empty State

```haml
.text-center.py-16
  .text-6xl.mb-4 📦
  %h3.text-xl.font-bold.text-gray-900.mb-2 No hay productos
  %p.text-gray-600.mb-6 Comenzá agregando tu primer producto
  = link_to new_product_path, class: "btn-gradient-teal" do
    + Crear Producto
```

### 6.3. Toast

```haml
-# Éxito
.fixed.top-6.right-6.bg-white.rounded-2xl.shadow-premium.p-4.flex.gap-3.border-l-4.border-green-500
  .w-10.h-10.rounded-xl.gradient-teal.flex.items-center.justify-center.text-white ✓
  .flex-1
    %h4.font-semibold Éxito
    %p.text-sm.text-gray-600 Producto guardado correctamente
```

---

## 7. RESPONSIVE DESIGN

### 7.1. Breakpoints

```
sm: 640px - Mobile grande
md: 768px - Tablet
lg: 1024px - Desktop
xl: 1280px - Desktop grande
```

### 7.2. Grid Adaptativo

```haml
-# 4 columnas en desktop, 2 en tablet, 1 en móvil
.grid.grid-cols-1.md:grid-cols-2.lg:grid-cols-4.gap-6
```

### 7.3. Sidebar Responsiva

```haml
-# Desktop: visible
-# Mobile: drawer
.w-64.bg-slate-900.hidden.lg:flex
```

---

## 8. GUÍAS DE IMPLEMENTACIÓN

### 8.1. Checklist

- [ ] Actualizar `tailwind.config.js` con colores y sombras
- [ ] Agregar clases de gradientes a `application.tailwind.css`
- [ ] Crear sidebar con gradiente oscuro
- [ ] Crear header sticky con búsqueda
- [ ] Implementar 4 metric cards en dashboard
- [ ] Estilizar tablas y formularios
- [ ] Agregar toasts y modales

### 8.2. Uso con Cursor

```
@docs/UI_DESIGN_SPEC.md

Crear el dashboard con las 4 metric cards usando gradientes
```

---

**Versión:** 2.0 - Modern Premium Design  
**Última actualización:** Noviembre 2025