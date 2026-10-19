class VoidPaymentsReversedByCancellation < ActiveRecord::Migration[7.2]
  def up
    execute <<~SQL
      UPDATE payments
      SET status = 'voided',
          voided_at = reversal.created_at,
          voided_by_id = reversal.user_id,
          void_reason = 'Venta anulada',
          updated_at = NOW()
      FROM cash_movements reversal
      WHERE reversal.source_payment_id = payments.id
        AND reversal.amount < 0
        AND payments.status = 'active'
        AND NOT EXISTS (SELECT 1 FROM payment_allocations pa WHERE pa.payment_id = payments.id)
    SQL
  end

  def down; end
end
