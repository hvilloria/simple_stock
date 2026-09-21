-- Most-sold products by sale frequency (how many distinct sales include the product).
-- Columns: oem | nombre | veces_vendido | tipo | precio
--
-- Notes:
--   * Grouped by product variant (sku + product_type + brand + origin), so the
--     price column belongs to that exact variant.
--   * Cancelled orders are excluded; soft-deleted products are excluded.
--   * Optional date window: uncomment the purchase-window predicate below.

SELECT
  p.sku                       AS oem,
  p.name                      AS nombre,
  COUNT(DISTINCT o.id)        AS veces_vendido,
  p.product_type              AS tipo,
  p.price_unit                AS precio
FROM order_items oi
JOIN orders   o ON o.id = oi.order_id
JOIN products p ON p.id = oi.product_id
WHERE o.status <> 'cancelled'
  AND p.deleted_at IS NULL
  -- AND o.sale_date >= DATE '2025-01-01'
  -- AND o.sale_date <  DATE '2026-01-01'
GROUP BY p.id, p.sku, p.name, p.product_type, p.price_unit
ORDER BY veces_vendido DESC, p.name ASC;
