-- Pareto cut: how few products account for most of the sales frequency.
-- Columns: ranking | oem | nombre | veces_vendido | tipo | precio | pct_acumulado
--
-- pct_acumulado is the running share of total sale events, so the first row
-- where it crosses 80 marks the cut-off: everything above is the core catalogue.

WITH sales AS (
  SELECT p.id, p.sku, p.name, p.product_type, p.price_unit,
         COUNT(DISTINCT o.id) AS veces_vendido
  FROM order_items oi
  JOIN orders   o ON o.id = oi.order_id
  JOIN products p ON p.id = oi.product_id
  WHERE o.status <> 'cancelled'
    AND p.deleted_at IS NULL
  GROUP BY p.id
),
ranked AS (
  SELECT s.*,
         ROW_NUMBER() OVER (ORDER BY veces_vendido DESC, name)  AS ranking,
         SUM(veces_vendido) OVER ()                             AS total_ventas,
         SUM(veces_vendido) OVER (ORDER BY veces_vendido DESC, name
                                  ROWS UNBOUNDED PRECEDING)     AS acumulado
  FROM sales s
)
SELECT ranking,
       sku            AS oem,
       name           AS nombre,
       veces_vendido,
       product_type   AS tipo,
       price_unit     AS precio,
       ROUND(100.0 * acumulado / total_ventas, 2) AS pct_acumulado
FROM ranked
ORDER BY ranking;
