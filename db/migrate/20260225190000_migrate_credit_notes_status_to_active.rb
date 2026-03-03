class MigrateCreditNotesStatusToActive < ActiveRecord::Migration[7.2]
  def up
    # The CreditNote enum was simplified from { pending, applied, cancelled }
    # to { active, cancelled }. Convert all legacy values to the new ones.
    execute "UPDATE credit_notes SET status = 'active' WHERE status IN ('pending', 'applied')"
  end

  def down
    # No safe rollback: we cannot distinguish which 'active' notes were originally
    # 'pending' vs 'applied'. Acceptable since this only affects development data.
    raise ActiveRecord::IrreversibleMigration
  end
end
