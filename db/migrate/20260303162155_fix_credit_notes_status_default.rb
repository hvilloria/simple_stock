class FixCreditNotesStatusDefault < ActiveRecord::Migration[7.2]
  def change
    change_column_default :credit_notes, :status, from: "pending", to: "active"
  end
end
