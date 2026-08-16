-- ============================================================================
-- Reporte de ventas por canal — simple_stock
-- Ejecutar en DBeaver contra PROD. Todas las queries son de solo lectura.
--
-- Convenciones usadas en todo el archivo:
--   * status <> 'cancelled'  -> excluye anuladas (equivale al scope Order.active)
--   * sale_date              -> fecha real de la venta (NO created_at)
--   * original_total_amount  -> total bruto, = SUM(quantity * unit_price)
--   * total_amount           -> total realmente cobrado (ya con descuento aplicado
--                               y redondeado al cien mas cercano cuando hubo descuento)
--   * channel                -> 'counter' | 'whatsapp' | 'mercadolibre' | NULL
-- ============================================================================


-- ============================================================================
-- BLOQUE 0 — SANIDAD DE DATOS
-- Correr esto PRIMERO. Define que tan lejos se puede llegar con el resto.
-- ============================================================================

-- 0.1 — Cobertura del campo channel: cuanto del historial esta etiquetado
SELECT
  CASE WHEN channel IS NULL THEN 'SIN canal' ELSE 'CON canal' END AS cobertura,
  COUNT(*)                   AS ventas,
  MIN(sale_date)             AS desde,
  MAX(sale_date)             AS hasta,
  SUM(total_amount)          AS monto_cobrado
FROM orders
WHERE status <> 'cancelled'
GROUP BY 1
ORDER BY 1;


-- 0.2 — Volumen diario con canal: para ver cuantos dias reales de muestra hay
SELECT
  sale_date,
  COUNT(*)                                              AS ventas,
  COUNT(*) FILTER (WHERE channel = 'counter')           AS mostrador,
  COUNT(*) FILTER (WHERE channel = 'whatsapp')          AS whatsapp,
  COUNT(*) FILTER (WHERE channel = 'mercadolibre')      AS mercadolibre,
  COUNT(*) FILTER (WHERE channel IS NULL)               AS sin_canal
FROM orders
WHERE status <> 'cancelled'
GROUP BY sale_date
ORDER BY sale_date DESC
LIMIT 60;


-- 0.3 — Split por status y source: define si 'pending' cuenta como venta
--       y cuanto del historial entro por papel (from_paper), que suele venir
--       sin canal y a veces sin precios.
SELECT
  status,
  source,
  COALESCE(channel, '(sin canal)') AS canal,
  COUNT(*)                         AS ventas,
  SUM(total_amount)                AS monto_cobrado
FROM orders
GROUP BY status, source, COALESCE(channel, '(sin canal)')
ORDER BY status, source, ventas DESC;


-- 0.4 — Lineas sin precio (modo sales-lite: unit_price NULL se trata como 0).
--       Estas lineas aportan UNIDADES pero no aportan MONTO: si el numero es
--       alto, el ranking por monto queda sesgado y hay que mirar unidades.
SELECT
  COUNT(*)                                                        AS lineas_totales,
  COUNT(*) FILTER (WHERE oi.unit_price IS NULL)                   AS lineas_sin_precio,
  COUNT(DISTINCT oi.order_id) FILTER (WHERE oi.unit_price IS NULL) AS ordenes_afectadas,
  ROUND(100.0 * COUNT(*) FILTER (WHERE oi.unit_price IS NULL) / NULLIF(COUNT(*), 0), 2) AS pct_sin_precio
FROM order_items oi
JOIN orders o ON o.id = oi.order_id
WHERE o.status <> 'cancelled';


-- ============================================================================
-- BLOQUE 1 — VENTAS POR CANAL
-- ============================================================================

-- 1.1 — Resumen por canal (solo ventas etiquetadas)
SELECT
  channel                                                             AS canal,
  COUNT(*)                                                            AS ventas,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                  AS pct_ventas,
  SUM(original_total_amount)                                          AS monto_bruto,
  SUM(total_amount)                                                   AS monto_cobrado,
  ROUND(100.0 * SUM(total_amount) / SUM(SUM(total_amount)) OVER (), 1) AS pct_ingresos,
  ROUND(AVG(total_amount), 2)                                         AS ticket_promedio,
  SUM(original_total_amount) - SUM(total_amount)                      AS descuentos
FROM orders
WHERE status <> 'cancelled'
  AND channel IS NOT NULL
GROUP BY channel
ORDER BY monto_cobrado DESC;


-- 1.2 — Mismo resumen pero por mes, para ver evolucion del mix
SELECT
  DATE_TRUNC('month', sale_date)::date AS mes,
  channel                              AS canal,
  COUNT(*)                             AS ventas,
  SUM(total_amount)                    AS monto_cobrado
FROM orders
WHERE status <> 'cancelled'
  AND channel IS NOT NULL
GROUP BY 1, 2
ORDER BY mes DESC, monto_cobrado DESC;


-- ============================================================================
-- BLOQUE 2 — PRODUCTOS POR CANAL
--
-- Nota sobre el monto por producto: order_items.discount_percent es metadata de
-- display; el monto canonico cobrado vive en orders.total_amount. Por eso el
-- monto por linea se PRORRATEA:
--     neto_linea = (qty * unit_price) / original_total_amount * total_amount
-- Asi la suma de los netos por producto cierra contra el ingreso real del canal.
-- ============================================================================

-- Vista base reutilizable por las queries de este bloque
-- (en DBeaver: ejecutar el bloque WITH + SELECT completo como una sola sentencia)

-- 2.1 — Todos los productos vendidos, por canal
WITH lineas AS (
  SELECT
    o.channel,
    oi.product_id,
    oi.quantity,
    COALESCE(oi.unit_price, 0) * oi.quantity AS bruto_linea,
    CASE
      WHEN o.original_total_amount > 0
        THEN COALESCE(oi.unit_price, 0) * oi.quantity
             / o.original_total_amount * o.total_amount
      ELSE 0
    END AS neto_linea
  FROM order_items oi
  JOIN orders o ON o.id = oi.order_id
  WHERE o.status <> 'cancelled'
    AND o.channel IS NOT NULL
)
SELECT
  l.channel                        AS canal,
  p.sku,
  p.name                           AS producto,
  p.brand                          AS marca,
  SUM(l.quantity)                  AS unidades,
  COUNT(*)                         AS lineas,
  ROUND(SUM(l.neto_linea), 2)      AS monto_cobrado,
  ROUND(SUM(l.bruto_linea), 2)     AS monto_bruto
FROM lineas l
JOIN products p ON p.id = l.product_id   -- sin filtrar deleted_at: ventas viejas
                                         -- pueden referenciar productos borrados
GROUP BY l.channel, p.id, p.sku, p.name, p.brand
ORDER BY l.channel, unidades DESC;


-- 2.2 — Top 15 productos DE CADA canal (por unidades)
WITH lineas AS (
  SELECT
    o.channel,
    oi.product_id,
    oi.quantity,
    CASE
      WHEN o.original_total_amount > 0
        THEN COALESCE(oi.unit_price, 0) * oi.quantity
             / o.original_total_amount * o.total_amount
      ELSE 0
    END AS neto_linea
  FROM order_items oi
  JOIN orders o ON o.id = oi.order_id
  WHERE o.status <> 'cancelled'
    AND o.channel IS NOT NULL
),
agregado AS (
  SELECT
    l.channel,
    p.id AS product_id,
    p.sku,
    p.name  AS producto,
    p.brand AS marca,
    SUM(l.quantity)             AS unidades,
    ROUND(SUM(l.neto_linea), 2) AS monto_cobrado
  FROM lineas l
  JOIN products p ON p.id = l.product_id
  GROUP BY l.channel, p.id, p.sku, p.name, p.brand
)
SELECT
  r.channel AS canal,
  r.puesto,
  r.sku,
  r.producto,
  r.marca,
  r.unidades,
  r.monto_cobrado
FROM (
  SELECT
    a.*,
    ROW_NUMBER() OVER (PARTITION BY a.channel ORDER BY a.unidades DESC, a.monto_cobrado DESC) AS puesto
  FROM agregado a
) r
WHERE r.puesto <= 15
ORDER BY r.channel, r.puesto;


-- 2.3 — MATRIZ producto x canal (una fila por producto, una columna por canal).
--       Esta es la base para estimar el mix historico: muestra, para cada
--       producto, que reparto de canal tuvo en la ventana etiquetada.
WITH lineas AS (
  SELECT
    o.channel,
    oi.product_id,
    oi.quantity,
    CASE
      WHEN o.original_total_amount > 0
        THEN COALESCE(oi.unit_price, 0) * oi.quantity
             / o.original_total_amount * o.total_amount
      ELSE 0
    END AS neto_linea
  FROM order_items oi
  JOIN orders o ON o.id = oi.order_id
  WHERE o.status <> 'cancelled'
    AND o.channel IS NOT NULL
)
SELECT
  p.sku,
  p.name  AS producto,
  p.brand AS marca,
  SUM(l.quantity)                                                  AS unidades_total,
  SUM(l.quantity) FILTER (WHERE l.channel = 'counter')             AS u_mostrador,
  SUM(l.quantity) FILTER (WHERE l.channel = 'whatsapp')            AS u_whatsapp,
  SUM(l.quantity) FILTER (WHERE l.channel = 'mercadolibre')        AS u_mercadolibre,
  ROUND(100.0 * COALESCE(SUM(l.quantity) FILTER (WHERE l.channel = 'counter'), 0)
        / NULLIF(SUM(l.quantity), 0), 1)                           AS pct_mostrador,
  ROUND(100.0 * COALESCE(SUM(l.quantity) FILTER (WHERE l.channel = 'whatsapp'), 0)
        / NULLIF(SUM(l.quantity), 0), 1)                           AS pct_whatsapp,
  ROUND(100.0 * COALESCE(SUM(l.quantity) FILTER (WHERE l.channel = 'mercadolibre'), 0)
        / NULLIF(SUM(l.quantity), 0), 1)                           AS pct_mercadolibre,
  ROUND(SUM(l.neto_linea), 2)                                      AS monto_total
FROM lineas l
JOIN products p ON p.id = l.product_id
GROUP BY p.id, p.sku, p.name, p.brand
ORDER BY unidades_total DESC;
